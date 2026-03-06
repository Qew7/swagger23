# frozen_string_literal: true

require "spec_helper"

# End-to-end tests driven by spec/fixtures/bookstore_swagger2.json —
# a single comprehensive Swagger 2.0 document that exercises every conversion
# path in the gem.  Tests are grouped by concern; each assertion targets one
# specific transformation rule rather than comparing the whole output JSON
# (which would be brittle to maintain).
RSpec.describe "Bookstore fixture – end-to-end conversion" do
  let(:swagger) do
    path = File.expand_path("../fixtures/bookstore_swagger2.json", __dir__)
    JSON.parse(File.read(path))
  end

  let(:result) { Swagger23.convert(swagger) }

  # ── Structural sanity ──────────────────────────────────────────────────────

  describe "openapi version" do
    it "sets openapi: 3.0.3" do
      expect(result["openapi"]).to eq("3.0.3")
    end

    it "removes the swagger 2.0 key" do
      expect(result).not_to have_key("swagger")
    end
  end

  # ── Info ──────────────────────────────────────────────────────────────────

  describe "info" do
    subject(:info) { result["info"] }

    it "preserves title and version"    do
      expect(info["title"]).to eq("Bookstore API")
      expect(info["version"]).to eq("2.1.0")
    end
    it "preserves contact"              do
      expect(info.dig("contact", "email")).to eq("api@example.com")
    end
    it "preserves license"              do
      expect(info.dig("license", "name")).to eq("MIT")
    end
    it "preserves termsOfService"       do
      expect(info["termsOfService"]).to include("tos")
    end
    it "passes through x- extensions"  do
      expect(info.dig("x-logo", "url")).to include("logo.png")
    end
  end

  # ── Servers ───────────────────────────────────────────────────────────────

  describe "servers" do
    subject(:servers) { result["servers"] }

    it "produces one server per scheme" do
      expect(servers.size).to eq(2)
    end

    it "builds correct HTTPS url" do
      expect(servers.map { |s| s["url"] }).to include("https://api.bookstore.io/v2")
    end

    it "builds correct HTTP url" do
      expect(servers.map { |s| s["url"] }).to include("http://api.bookstore.io/v2")
    end
  end

  # ── Top-level passthrough ─────────────────────────────────────────────────

  describe "top-level passthrough fields" do
    it "keeps tags"                   do
      expect(result["tags"].map { |t| t["name"] }).to contain_exactly("books", "authors")
    end
    it "keeps externalDocs"           do
      expect(result.dig("externalDocs", "url")).to include("docs.bookstore.io")
    end
    it "keeps top-level security"     do
      expect(result["security"]).to eq([{ "ApiKeyAuth" => [] }])
    end
    it "passes through x- extension" do
      expect(result["x-internal-version"]).to eq("42")
    end
  end

  # ── components/schemas ────────────────────────────────────────────────────

  describe "components/schemas" do
    subject(:schemas) { result.dig("components", "schemas") }

    it "includes all definitions" do
      expect(schemas.keys).to contain_exactly(
        "Book", "NewBook", "AuthorRef", "Author", "Error", "ValidationError"
      )
    end

    it "preserves required fields on Book" do
      expect(schemas.dig("Book", "required")).to contain_exactly("id", "title")
    end

    it "rewrites $ref inside Book.author" do
      expect(schemas.dig("Book", "properties", "author", "$ref"))
        .to eq("#/components/schemas/AuthorRef")
    end

    it "rewrites $ref inside allOf in NewBook" do
      all_of = schemas.dig("NewBook", "allOf")
      refs   = all_of.map { |item| item["$ref"] }.compact
      expect(refs).to include("#/components/schemas/Book")
    end

    it "rewrites nested $ref inside Author.books items" do
      expect(schemas.dig("Author", "properties", "books", "items", "$ref"))
        .to eq("#/components/schemas/Book")
    end

    it "rewrites $ref in allOf of ValidationError" do
      all_of_refs = schemas.dig("ValidationError", "allOf").map { |i| i["$ref"] }.compact
      expect(all_of_refs).to include("#/components/schemas/Error")
    end
  end

  # ── components/parameters ────────────────────────────────────────────────

  describe "components/parameters" do
    subject(:params) { result.dig("components", "parameters") }

    it "includes global parameters" do
      expect(params.keys).to contain_exactly("RequestId", "BookId")
    end

    it "moves type to schema on RequestId" do
      expect(params.dig("RequestId", "schema", "type")).to eq("string")
      expect(params["RequestId"]).not_to have_key("type")
    end

    it "preserves x- extension on RequestId" do
      expect(params.dig("RequestId", "x-custom")).to be true
    end

    it "moves type+format to schema on BookId" do
      schema = params.dig("BookId", "schema")
      expect(schema["type"]).to eq("integer")
      expect(schema["format"]).to eq("int64")
    end
  end

  # ── components/responses ─────────────────────────────────────────────────

  describe "components/responses" do
    subject(:responses) { result.dig("components", "responses") }

    it "includes global responses" do
      expect(responses.keys).to contain_exactly("NotFound", "UnprocessableEntity")
    end

    it "rewrites $ref in NotFound schema" do
      schema_ref = responses.dig("NotFound", "content", "application/json", "schema", "$ref")
      expect(schema_ref).to eq("#/components/schemas/Error")
    end

    it "preserves response headers on UnprocessableEntity" do
      expect(responses.dig("UnprocessableEntity", "headers", "X-Error-Code")).not_to be_nil
    end
  end

  # ── components/securitySchemes ───────────────────────────────────────────

  describe "components/securitySchemes" do
    subject(:schemes) { result.dig("components", "securitySchemes") }

    it "converts ApiKeyAuth" do
      expect(schemes.dig("ApiKeyAuth", "type")).to eq("apiKey")
      expect(schemes.dig("ApiKeyAuth", "name")).to eq("X-API-Key")
      expect(schemes.dig("ApiKeyAuth", "in")).to eq("header")
    end

    it "converts BasicAuth to http/basic" do
      expect(schemes.dig("BasicAuth", "type")).to eq("http")
      expect(schemes.dig("BasicAuth", "scheme")).to eq("basic")
    end

    it "converts OAuth2Implicit" do
      flow = schemes.dig("OAuth2Implicit", "flows", "implicit")
      expect(flow["authorizationUrl"]).to include("authorize")
      expect(flow["scopes"].keys).to contain_exactly("read:books", "write:books")
    end

    it "converts OAuth2Password" do
      flow = schemes.dig("OAuth2Password", "flows", "password")
      expect(flow["tokenUrl"]).to include("token")
    end

    it "converts OAuth2Application to clientCredentials" do
      expect(schemes.dig("OAuth2Application", "flows")).to have_key("clientCredentials")
      flow = schemes.dig("OAuth2Application", "flows", "clientCredentials")
      expect(flow["tokenUrl"]).to include("token")
    end

    it "converts OAuth2AccessCode to authorizationCode" do
      flow = schemes.dig("OAuth2AccessCode", "flows", "authorizationCode")
      expect(flow["authorizationUrl"]).to include("authorize")
      expect(flow["tokenUrl"]).to include("token")
    end
  end

  # ── paths – GET /books ───────────────────────────────────────────────────

  describe "GET /books" do
    subject(:op) { result.dig("paths", "/books", "get") }

    it "keeps tags, summary, operationId" do
      expect(op["tags"]).to eq(["books"])
      expect(op["summary"]).to eq("List books")
      expect(op["operationId"]).to eq("listBooks")
    end

    it "moves type to schema for plain query param" do
      q_param = op["parameters"].find { |p| p["name"] == "q" }
      expect(q_param.dig("schema", "type")).to eq("string")
      expect(q_param).not_to have_key("type")
    end

    it "converts collectionFormat: csv to style: form, explode: false" do
      tags_param = op["parameters"].find { |p| p["name"] == "tags" }
      schema     = tags_param["schema"]
      expect(schema["style"]).to eq("form")
      expect(schema["explode"]).to be false
      expect(schema).not_to have_key("collectionFormat")
    end

    it "converts collectionFormat: multi to style: form, explode: true" do
      status_param = op["parameters"].find { |p| p["name"] == "status" }
      schema       = status_param["schema"]
      expect(schema["style"]).to eq("form")
      expect(schema["explode"]).to be true
    end

    it "preserves minimum/maximum in schema" do
      page_param = op["parameters"].find { |p| p["name"] == "page" }
      expect(page_param.dig("schema", "minimum")).to eq(1)
      expect(page_param.dig("schema", "default")).to eq(1)
    end

    it "wraps response schema in content" do
      content = op.dig("responses", "200", "content", "application/json", "schema")
      expect(content["type"]).to eq("array")
      expect(content.dig("items", "$ref")).to eq("#/components/schemas/Book")
    end

    it "preserves response headers" do
      headers = op.dig("responses", "200", "headers")
      expect(headers.keys).to contain_exactly("X-Total-Count", "X-Page")
    end
  end

  # ── paths – Path-level parameters ────────────────────────────────────────

  describe "path-level parameters on /books" do
    subject(:path_params) { result.dig("paths", "/books", "parameters") }

    it "keeps path-level $ref parameter" do
      expect(path_params).not_to be_nil
      expect(path_params.first["$ref"]).to eq("#/components/parameters/RequestId")
    end
  end

  # ── paths – POST /books ──────────────────────────────────────────────────

  describe "POST /books" do
    subject(:op) { result.dig("paths", "/books", "post") }

    it "creates requestBody" do
      expect(op["requestBody"]).not_to be_nil
    end

    it "marks requestBody as required" do
      expect(op.dig("requestBody", "required")).to be true
    end

    it "sets description on requestBody" do
      expect(op.dig("requestBody", "description")).to eq("Book to create")
    end

    it "puts schema under application/json" do
      ref = op.dig("requestBody", "content", "application/json", "schema", "$ref")
      expect(ref).to eq("#/components/schemas/NewBook")
    end

    it "removes body parameter from parameters list" do
      expect(op["parameters"]).to be_nil
    end

    it "carries operation-level security" do
      expect(op["security"]).to eq([{ "OAuth2Implicit" => ["write:books"] }])
    end

    it "rewrites $ref in 422 response" do
      ref = op.dig("responses", "422", "$ref")
      expect(ref).to eq("#/components/responses/UnprocessableEntity")
    end
  end

  # ── paths – PUT /books/{bookId} ───────────────────────────────────────────

  describe "PUT /books/{bookId}" do
    subject(:op) { result.dig("paths", "/books/{bookId}", "put") }

    it "honours operation-level consumes for requestBody content keys" do
      content_keys = op.dig("requestBody", "content").keys
      expect(content_keys).to contain_exactly("application/json", "application/xml")
    end

    it "honours operation-level produces for response content keys" do
      content_keys = op.dig("responses", "200", "content").keys
      expect(content_keys).to contain_exactly("application/json", "application/xml")
    end

    it "passes through deprecated flag" do
      expect(op["deprecated"]).to be true
    end
  end

  # ── paths – DELETE /books/{bookId} ────────────────────────────────────────

  describe "DELETE /books/{bookId}" do
    subject(:op) { result.dig("paths", "/books/{bookId}", "delete") }

    it "passes through x- extension" do
      expect(op["x-idempotent"]).to be true
    end

    it "handles 204 response with no schema (no content key)" do
      expect(op.dig("responses", "204").key?("content")).to be false
    end
  end

  # ── paths – POST /books/{bookId}/cover (file upload) ─────────────────────

  describe "POST /books/{bookId}/cover" do
    subject(:op) { result.dig("paths", "/books/{bookId}/cover", "post") }

    it "creates multipart/form-data requestBody" do
      expect(op.dig("requestBody", "content").keys).to eq(["multipart/form-data"])
    end

    it "maps file formData param to string/binary" do
      cover = op.dig("requestBody", "content", "multipart/form-data",
                     "schema", "properties", "cover")
      expect(cover).to eq("type" => "string", "format" => "binary")
    end

    it "includes non-file formData param as string" do
      caption = op.dig("requestBody", "content", "multipart/form-data",
                       "schema", "properties", "caption")
      expect(caption["type"]).to eq("string")
    end

    it "marks required formData fields" do
      required = op.dig("requestBody", "content", "multipart/form-data", "schema", "required")
      expect(required).to eq(["cover"])
    end

    it "does not include $ref path param in requestBody" do
      properties = op.dig("requestBody", "content", "multipart/form-data",
                          "schema", "properties")
      expect(properties).not_to have_key("bookId")
    end

    it "keeps $ref path param in parameters list" do
      params = op["parameters"] || []
      expect(params.any? { |p| p["$ref"] }).to be true
    end
  end

  # ── paths – POST /authors (form-urlencoded) ───────────────────────────────

  describe "POST /authors" do
    subject(:op) { result.dig("paths", "/authors", "post") }

    it "creates application/x-www-form-urlencoded requestBody" do
      expect(op.dig("requestBody", "content").keys)
        .to eq(["application/x-www-form-urlencoded"])
    end

    it "includes all form fields as properties" do
      props = op.dig("requestBody", "content",
                     "application/x-www-form-urlencoded", "schema", "properties")
      expect(props.keys).to contain_exactly("name", "bio", "website")
    end

    it "marks required form fields" do
      required = op.dig("requestBody", "content",
                        "application/x-www-form-urlencoded", "schema", "required")
      expect(required).to eq(["name"])
    end
  end

  # ── paths – GET /authors/{authorId} ──────────────────────────────────────

  describe "GET /authors/{authorId}" do
    subject(:op) { result.dig("paths", "/authors/{authorId}", "get") }

    it "keeps inline path param" do
      param = op["parameters"].find { |p| p["name"] == "authorId" }
      expect(param["in"]).to eq("path")
      expect(param.dig("schema", "type")).to eq("integer")
    end

    it "keeps $ref param alongside inline param" do
      ref_param = op["parameters"].find { |p| p["$ref"] }
      expect(ref_param["$ref"]).to eq("#/components/parameters/RequestId")
    end
  end

  # ── No leftover Swagger 2.0 artefacts ────────────────────────────────────

  describe "no Swagger 2.0 artefacts remain in output" do
    let(:raw) { JSON.generate(result) }

    it "has no #/definitions/ refs" do
      expect(raw).not_to include("#/definitions/")
    end

    it "has no #/parameters/ refs (replaced by #/components/parameters/)" do
      expect(raw).not_to include('"$ref":"#/parameters/')
    end

    it "has no #/responses/ refs (replaced by #/components/responses/)" do
      expect(raw).not_to include('"$ref":"#/responses/')
    end

    it "has no #/securityDefinitions/ refs" do
      expect(raw).not_to include("#/securityDefinitions/")
    end

    it "has no top-level host key" do
      expect(result).not_to have_key("host")
    end

    it "has no top-level basePath key" do
      expect(result).not_to have_key("basePath")
    end

    it "has no top-level schemes key" do
      expect(result).not_to have_key("schemes")
    end

    it "has no top-level consumes key" do
      expect(result).not_to have_key("consumes")
    end

    it "has no top-level produces key" do
      expect(result).not_to have_key("produces")
    end

    it "has no top-level definitions key" do
      expect(result).not_to have_key("definitions")
    end

    it "has no top-level securityDefinitions key" do
      expect(result).not_to have_key("securityDefinitions")
    end

    it "does not mutate the original swagger fixture" do
      _ = result  # trigger conversion
      expect(swagger["swagger"]).to eq("2.0")
      expect(swagger).to have_key("definitions")
      expect(swagger).to have_key("securityDefinitions")
    end
  end
end

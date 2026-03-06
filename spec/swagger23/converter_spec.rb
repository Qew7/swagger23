# frozen_string_literal: true

require "spec_helper"

RSpec.describe Swagger23::Converter do
  # Minimal valid Swagger 2.0 document used as base for most tests
  let(:base_swagger) do
    {
      "swagger"  => "2.0",
      "info"     => { "title" => "Test API", "version" => "1.0" },
      "host"     => "api.example.com",
      "basePath" => "/v1",
      "schemes"  => ["https"],
      "paths"    => {}
    }
  end

  def convert(doc = base_swagger)
    described_class.new(doc).convert
  end

  # ---------------------------------------------------------------------------
  # Version & top-level fields
  # ---------------------------------------------------------------------------

  describe "top-level openapi field" do
    it "sets openapi to 3.0.3" do
      expect(convert["openapi"]).to eq("3.0.3")
    end

    it "does not include the swagger 2.0 version field" do
      expect(convert.key?("swagger")).to be false
    end
  end

  describe "validation" do
    it "raises InvalidSwaggerError when swagger version is not 2.0" do
      expect { convert("swagger" => "1.2", "info" => {}, "paths" => {}) }
        .to raise_error(Swagger23::InvalidSwaggerError, /2\.0/)
    end

    it "raises InvalidSwaggerError when swagger key is missing" do
      expect { convert("info" => {}, "paths" => {}) }
        .to raise_error(Swagger23::InvalidSwaggerError)
    end
  end

  # ---------------------------------------------------------------------------
  # Info
  # ---------------------------------------------------------------------------

  describe "info" do
    it "copies info as-is" do
      result = convert
      expect(result["info"]).to eq("title" => "Test API", "version" => "1.0")
    end

    it "passes through extensions in info" do
      doc = base_swagger.merge("info" => { "title" => "X", "version" => "1", "x-logo" => "logo.png" })
      expect(convert(doc)["info"]["x-logo"]).to eq("logo.png")
    end
  end

  # ---------------------------------------------------------------------------
  # Servers
  # ---------------------------------------------------------------------------

  describe "servers" do
    it "builds a server URL from host + basePath + schemes" do
      result = convert
      expect(result["servers"]).to eq([{ "url" => "https://api.example.com/v1" }])
    end

    it "creates multiple servers for multiple schemes" do
      doc = base_swagger.merge("schemes" => ["https", "http"])
      urls = convert(doc)["servers"].map { |s| s["url"] }
      expect(urls).to eq(["https://api.example.com/v1", "http://api.example.com/v1"])
    end

    it "uses a default URL when host/schemes are absent" do
      doc = { "swagger" => "2.0", "info" => { "title" => "T", "version" => "1" }, "paths" => {} }
      expect(convert(doc)["servers"].first["url"]).to match(%r{localhost})
    end
  end

  # ---------------------------------------------------------------------------
  # $ref rewriting
  # ---------------------------------------------------------------------------

  describe "$ref rewriting" do
    it "rewrites #/definitions/ to #/components/schemas/" do
      doc = base_swagger.merge(
        "paths" => {
          "/pets" => {
            "get" => {
              "responses" => {
                "200" => {
                  "description" => "ok",
                  "schema" => { "$ref" => "#/definitions/Pet" }
                }
              }
            }
          }
        },
        "definitions" => { "Pet" => { "type" => "object" } }
      )
      result = convert(doc)
      schema_ref = result.dig("paths", "/pets", "get", "responses", "200", "content",
                              "application/json", "schema", "$ref")
      expect(schema_ref).to eq("#/components/schemas/Pet")
    end

    it "rewrites #/securityDefinitions/ to #/components/securitySchemes/" do
      doc = base_swagger.merge(
        "security" => [{ "ApiKey" => [] }],
        "securityDefinitions" => {
          "ApiKey" => { "type" => "apiKey", "name" => "X-API-Key", "in" => "header" }
        }
      )
      result = convert(doc)
      # The rewrite applies at the components level too
      expect(result.dig("components", "securitySchemes", "ApiKey", "type")).to eq("apiKey")
    end
  end

  # ---------------------------------------------------------------------------
  # Components / definitions
  # ---------------------------------------------------------------------------

  describe "components/schemas" do
    it "moves definitions to components/schemas" do
      doc = base_swagger.merge("definitions" => { "Pet" => { "type" => "object" } })
      expect(convert(doc).dig("components", "schemas", "Pet")).to eq("type" => "object")
    end
  end

  # ---------------------------------------------------------------------------
  # Paths – parameter conversion
  # ---------------------------------------------------------------------------

  describe "parameter conversion" do
    context "with a body parameter" do
      let(:doc) do
        base_swagger.merge(
          "consumes" => ["application/json"],
          "produces" => ["application/json"],
          "paths" => {
            "/pets" => {
              "post" => {
                "parameters" => [
                  {
                    "in"          => "body",
                    "name"        => "body",
                    "required"    => true,
                    "schema"      => { "$ref" => "#/definitions/NewPet" }
                  }
                ],
                "responses" => { "201" => { "description" => "created" } }
              }
            }
          }
        )
      end

      it "creates a requestBody" do
        result = convert(doc)
        rb = result.dig("paths", "/pets", "post", "requestBody")
        expect(rb).not_to be_nil
      end

      it "puts the schema under the correct content-type" do
        result = convert(doc)
        schema = result.dig("paths", "/pets", "post", "requestBody",
                            "content", "application/json", "schema")
        expect(schema).to eq("$ref" => "#/components/schemas/NewPet")
      end

      it "does not include the body parameter in the parameters array" do
        result = convert(doc)
        params = result.dig("paths", "/pets", "post", "parameters")
        expect(params).to be_nil
      end

      it "copies required from body parameter" do
        result = convert(doc)
        expect(result.dig("paths", "/pets", "post", "requestBody", "required")).to be true
      end
    end

    context "with formData parameters" do
      let(:doc) do
        base_swagger.merge(
          "paths" => {
            "/upload" => {
              "post" => {
                "consumes" => ["multipart/form-data"],
                "parameters" => [
                  { "in" => "formData", "name" => "name", "type" => "string", "required" => true },
                  { "in" => "formData", "name" => "file", "type" => "file" }
                ],
                "responses" => { "200" => { "description" => "ok" } }
              }
            }
          }
        )
      end

      it "creates a multipart/form-data requestBody" do
        result = convert(doc)
        content = result.dig("paths", "/upload", "post", "requestBody", "content")
        expect(content.keys).to include("multipart/form-data")
      end

      it "maps file type to string/binary" do
        result = convert(doc)
        schema = result.dig("paths", "/upload", "post", "requestBody",
                            "content", "multipart/form-data", "schema")
        expect(schema.dig("properties", "file")).to eq("type" => "string", "format" => "binary")
      end

      it "collects required formData field names" do
        result = convert(doc)
        schema = result.dig("paths", "/upload", "post", "requestBody",
                            "content", "multipart/form-data", "schema")
        expect(schema["required"]).to eq(["name"])
      end
    end

    context "with regular query/path/header parameters" do
      let(:doc) do
        base_swagger.merge(
          "paths" => {
            "/pets/{id}" => {
              "get" => {
                "parameters" => [
                  { "in" => "path",  "name" => "id",     "required" => true, "type" => "integer" },
                  { "in" => "query", "name" => "expand", "type" => "string" }
                ],
                "responses" => { "200" => { "description" => "ok" } }
              }
            }
          }
        )
      end

      it "keeps path and query parameters" do
        result = convert(doc)
        params = result.dig("paths", "/pets/{id}", "get", "parameters")
        expect(params.map { |p| p["in"] }).to contain_exactly("path", "query")
      end

      it "moves type to schema" do
        result = convert(doc)
        params = result.dig("paths", "/pets/{id}", "get", "parameters")
        path_param = params.find { |p| p["name"] == "id" }
        expect(path_param.dig("schema", "type")).to eq("integer")
        expect(path_param.key?("type")).to be false
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Paths – response conversion
  # ---------------------------------------------------------------------------

  describe "response conversion" do
    let(:doc) do
      base_swagger.merge(
        "produces" => ["application/json"],
        "paths" => {
          "/pets" => {
            "get" => {
              "responses" => {
                "200" => {
                  "description" => "A list of pets",
                  "schema" => { "type" => "array", "items" => { "$ref" => "#/definitions/Pet" } }
                },
                "404" => { "description" => "Not found" }
              }
            }
          }
        }
      )
    end

    it "wraps schema in content with the produces mime type" do
      result = convert(doc)
      content = result.dig("paths", "/pets", "get", "responses", "200", "content")
      expect(content.keys).to eq(["application/json"])
    end

    it "preserves description" do
      result = convert(doc)
      expect(result.dig("paths", "/pets", "get", "responses", "200", "description"))
        .to eq("A list of pets")
    end

    it "leaves responses without a schema without a content key" do
      result = convert(doc)
      expect(result.dig("paths", "/pets", "get", "responses", "404").key?("content")).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Security definitions
  # ---------------------------------------------------------------------------

  describe "securityDefinitions conversion" do
    it "converts basic auth" do
      doc = base_swagger.merge(
        "securityDefinitions" => { "Basic" => { "type" => "basic" } }
      )
      scheme = convert(doc).dig("components", "securitySchemes", "Basic")
      expect(scheme).to eq("type" => "http", "scheme" => "basic")
    end

    it "converts apiKey" do
      doc = base_swagger.merge(
        "securityDefinitions" => {
          "ApiKey" => { "type" => "apiKey", "name" => "X-API-Key", "in" => "header" }
        }
      )
      scheme = convert(doc).dig("components", "securitySchemes", "ApiKey")
      expect(scheme["type"]).to eq("apiKey")
      expect(scheme["name"]).to eq("X-API-Key")
    end

    it "converts oauth2 implicit flow" do
      doc = base_swagger.merge(
        "securityDefinitions" => {
          "OAuth" => {
            "type"             => "oauth2",
            "flow"             => "implicit",
            "authorizationUrl" => "https://auth.example.com/oauth/authorize",
            "scopes"           => { "read:pets" => "read pets" }
          }
        }
      )
      scheme = convert(doc).dig("components", "securitySchemes", "OAuth")
      expect(scheme["type"]).to eq("oauth2")
      expect(scheme.dig("flows", "implicit", "authorizationUrl"))
        .to eq("https://auth.example.com/oauth/authorize")
      expect(scheme.dig("flows", "implicit", "scopes")).to eq("read:pets" => "read pets")
    end

    it "converts oauth2 accessCode to authorizationCode flow" do
      doc = base_swagger.merge(
        "securityDefinitions" => {
          "OAuth" => {
            "type"             => "oauth2",
            "flow"             => "accessCode",
            "authorizationUrl" => "https://auth.example.com/oauth/authorize",
            "tokenUrl"         => "https://auth.example.com/oauth/token",
            "scopes"           => {}
          }
        }
      )
      scheme = convert(doc).dig("components", "securitySchemes", "OAuth")
      expect(scheme.dig("flows", "authorizationCode", "tokenUrl"))
        .to eq("https://auth.example.com/oauth/token")
    end
  end

  # ---------------------------------------------------------------------------
  # Extensions passthrough
  # ---------------------------------------------------------------------------

  describe "x- extensions" do
    it "passes through top-level x- extensions" do
      doc = base_swagger.merge("x-internal" => true)
      expect(convert(doc)["x-internal"]).to be true
    end

    it "passes through operation-level x- extensions" do
      doc = base_swagger.merge(
        "paths" => {
          "/test" => {
            "get" => {
              "x-rate-limit" => 100,
              "responses"    => { "200" => { "description" => "ok" } }
            }
          }
        }
      )
      expect(convert(doc).dig("paths", "/test", "get", "x-rate-limit")).to eq(100)
    end
  end

  # ---------------------------------------------------------------------------
  # Module-level convenience API
  # ---------------------------------------------------------------------------

  describe "Swagger23.convert" do
    it "delegates to Converter#convert" do
      result = Swagger23.convert(base_swagger)
      expect(result["openapi"]).to eq("3.0.3")
    end
  end

  describe "Swagger23.convert_json" do
    it "accepts a JSON string and returns a JSON string" do
      json_in  = JSON.generate(base_swagger)
      json_out = Swagger23.convert_json(json_in)
      result   = JSON.parse(json_out)
      expect(result["openapi"]).to eq("3.0.3")
    end
  end

  # ---------------------------------------------------------------------------
  # collectionFormat → style / explode
  # ---------------------------------------------------------------------------

  describe "collectionFormat conversion" do
    def param_with_format(fmt)
      {
        "swagger" => "2.0",
        "info"    => { "title" => "T", "version" => "1" },
        "paths"   => {
          "/x" => {
            "get" => {
              "parameters" => [
                { "in" => "query", "name" => "ids", "type" => "array",
                  "items" => { "type" => "string" }, "collectionFormat" => fmt }
              ],
              "responses" => { "200" => { "description" => "ok" } }
            }
          }
        }
      }
    end

    {
      "csv"   => { "style" => "form",            "explode" => false },
      "multi" => { "style" => "form",            "explode" => true  },
      "ssv"   => { "style" => "spaceDelimited",  "explode" => nil   },
      "pipes" => { "style" => "pipeDelimited",   "explode" => nil   }
    }.each do |fmt, expected|
      it "maps collectionFormat '#{fmt}'" do
        result = convert(param_with_format(fmt))
        schema = result.dig("paths", "/x", "get", "parameters", 0, "schema")
        expect(schema["style"]).to eq(expected["style"])
        expect(schema["explode"]).to eq(expected["explode"]) unless expected["explode"].nil?
        expect(schema).not_to have_key("collectionFormat")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Operation-level fields passthrough
  # ---------------------------------------------------------------------------

  describe "operation-level fields" do
    let(:doc) do
      base_swagger.merge(
        "paths" => {
          "/items" => {
            "get" => {
              "summary"     => "List items",
              "description" => "Returns items",
              "operationId" => "listItems",
              "deprecated"  => true,
              "tags"        => ["items"],
              "externalDocs" => { "url" => "https://docs.example.com" },
              "responses"   => { "200" => { "description" => "ok" } }
            }
          }
        }
      )
    end

    it "preserves deprecated flag" do
      expect(convert(doc).dig("paths", "/items", "get", "deprecated")).to be true
    end

    it "preserves tags array" do
      expect(convert(doc).dig("paths", "/items", "get", "tags")).to eq(["items"])
    end

    it "preserves externalDocs" do
      expect(convert(doc).dig("paths", "/items", "get", "externalDocs", "url"))
        .to eq("https://docs.example.com")
    end

    it "preserves operationId" do
      expect(convert(doc).dig("paths", "/items", "get", "operationId")).to eq("listItems")
    end
  end

  # ---------------------------------------------------------------------------
  # Path-level parameters (shared across operations on the same path)
  # ---------------------------------------------------------------------------

  describe "path-level parameters" do
    let(:doc) do
      base_swagger.merge(
        "paths" => {
          "/items/{id}" => {
            "parameters" => [
              { "in" => "path", "name" => "id", "required" => true, "type" => "string" }
            ],
            "get"  => { "responses" => { "200" => { "description" => "ok" } } },
            "delete" => { "responses" => { "204" => { "description" => "gone" } } }
          }
        }
      )
    end

    it "keeps path-level parameters at path item level" do
      params = convert(doc).dig("paths", "/items/{id}", "parameters")
      expect(params).not_to be_nil
      expect(params.first["name"]).to eq("id")
    end

    it "moves type to schema in path-level parameter" do
      param = convert(doc).dig("paths", "/items/{id}", "parameters", 0)
      expect(param.dig("schema", "type")).to eq("string")
      expect(param).not_to have_key("type")
    end
  end

  # ---------------------------------------------------------------------------
  # $ref parameters at operation level (pass-through)
  # ---------------------------------------------------------------------------

  describe "$ref parameters" do
    let(:doc) do
      base_swagger.merge(
        "parameters" => {
          "Limit" => { "in" => "query", "name" => "limit", "type" => "integer" }
        },
        "paths" => {
          "/things" => {
            "get" => {
              "parameters" => [{ "$ref" => "#/parameters/Limit" }],
              "responses"  => { "200" => { "description" => "ok" } }
            }
          }
        }
      )
    end

    it "rewrites $ref in operation parameters to #/components/parameters/" do
      param = convert(doc).dig("paths", "/things", "get", "parameters", 0)
      expect(param["$ref"]).to eq("#/components/parameters/Limit")
    end
  end

  # ---------------------------------------------------------------------------
  # Response with headers
  # ---------------------------------------------------------------------------

  describe "response headers" do
    let(:doc) do
      base_swagger.merge(
        "produces" => ["application/json"],
        "paths"    => {
          "/things" => {
            "get" => {
              "responses" => {
                "200" => {
                  "description" => "ok",
                  "schema"  => { "type" => "object" },
                  "headers" => {
                    "X-RateLimit-Limit"     => { "type" => "integer", "description" => "Calls allowed" },
                    "X-RateLimit-Remaining" => { "type" => "integer" }
                  }
                }
              }
            }
          }
        }
      )
    end

    it "includes headers in converted response" do
      headers = convert(doc).dig("paths", "/things", "get", "responses", "200", "headers")
      expect(headers.keys).to contain_exactly("X-RateLimit-Limit", "X-RateLimit-Remaining")
    end

    it "preserves header description" do
      header = convert(doc).dig("paths", "/things", "get", "responses", "200",
                                "headers", "X-RateLimit-Limit")
      expect(header["description"]).to eq("Calls allowed")
    end
  end

  # ---------------------------------------------------------------------------
  # Global components/responses
  # ---------------------------------------------------------------------------

  describe "global responses in components" do
    let(:doc) do
      base_swagger.merge(
        "produces"  => ["application/json"],
        "responses" => {
          "NotFound" => {
            "description" => "Not found",
            "schema"      => { "$ref" => "#/definitions/Error" }
          }
        },
        "definitions" => { "Error" => { "type" => "object" } }
      )
    end

    it "moves global responses to components/responses" do
      expect(convert(doc).dig("components", "responses", "NotFound")).not_to be_nil
    end

    it "wraps schema in content in global response" do
      schema = convert(doc).dig("components", "responses", "NotFound",
                                "content", "application/json", "schema")
      expect(schema["$ref"]).to eq("#/components/schemas/Error")
    end
  end

  # ---------------------------------------------------------------------------
  # Empty / minimal document
  # ---------------------------------------------------------------------------

  describe "minimal document (no paths, no definitions)" do
    let(:doc) { { "swagger" => "2.0", "info" => { "title" => "T", "version" => "1" } } }

    it "converts without error" do
      expect { convert(doc) }.not_to raise_error
    end

    it "produces an empty paths object" do
      expect(convert(doc)["paths"]).to eq({})
    end

    it "omits components when there is nothing to put in it" do
      expect(convert(doc)).not_to have_key("components")
    end
  end
end

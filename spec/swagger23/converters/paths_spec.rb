# frozen_string_literal: true

require "spec_helper"

RSpec.describe Swagger23::Converters::Paths do
  # Helpers for calling module methods directly (all are public self. methods)
  def convert_param(param)
    described_class.convert_parameter(param)
  end

  def build_body_rb(body_param, consumes = ["application/json"])
    described_class.build_request_body_from_body_param(body_param, consumes)
  end

  def build_form_rb(params, consumes = [])
    described_class.build_request_body_from_form_params(params, consumes)
  end

  def convert_resp(response, produces = ["application/json"])
    described_class.convert_response(response, produces)
  end

  # ---------------------------------------------------------------------------
  # convert_parameter
  # ---------------------------------------------------------------------------

  describe ".convert_parameter" do
    it "passes a $ref parameter through unchanged" do
      ref = { "$ref" => "#/components/parameters/Limit" }
      expect(convert_param(ref)).to eq(ref)
    end

    it "preserves description" do
      param = { "in" => "query", "name" => "q", "type" => "string", "description" => "Full-text search" }
      expect(convert_param(param)["description"]).to eq("Full-text search")
    end

    it "preserves required: false (explicit)" do
      param = { "in" => "query", "name" => "q", "type" => "string", "required" => false }
      expect(convert_param(param)["required"]).to be false
    end

    it "preserves deprecated flag on parameter" do
      param = { "in" => "query", "name" => "legacy", "type" => "string", "deprecated" => true }
      expect(convert_param(param)["deprecated"]).to be true
    end

    it "preserves allowEmptyValue on query parameters" do
      param = { "in" => "query", "name" => "q", "type" => "string", "allowEmptyValue" => true }
      expect(convert_param(param)["allowEmptyValue"]).to be true
    end

    it "preserves allowEmptyValue: false as well" do
      param = { "in" => "query", "name" => "q", "type" => "string", "allowEmptyValue" => false }
      expect(convert_param(param)["allowEmptyValue"]).to be false
    end

    it "moves type to schema" do
      result = convert_param("in" => "query", "name" => "page", "type" => "integer")
      expect(result.dig("schema", "type")).to eq("integer")
      expect(result).not_to have_key("type")
    end

    it "moves format to schema alongside type" do
      result = convert_param("in" => "path", "name" => "id", "type" => "integer", "format" => "int64")
      expect(result.dig("schema", "type")).to eq("integer")
      expect(result.dig("schema", "format")).to eq("int64")
      expect(result).not_to have_key("format")
    end

    it "moves default to schema" do
      result = convert_param("in" => "query", "name" => "limit", "type" => "integer", "default" => 20)
      expect(result.dig("schema", "default")).to eq(20)
    end

    it "moves enum to schema" do
      result = convert_param("in" => "query", "name" => "sort", "type" => "string",
                             "enum" => %w[asc desc])
      expect(result.dig("schema", "enum")).to eq(%w[asc desc])
    end

    it "moves minimum and maximum to schema" do
      result = convert_param("in" => "query", "name" => "page", "type" => "integer",
                             "minimum" => 1, "maximum" => 500)
      expect(result.dig("schema", "minimum")).to eq(1)
      expect(result.dig("schema", "maximum")).to eq(500)
    end

    it "moves minLength and maxLength to schema" do
      result = convert_param("in" => "query", "name" => "slug", "type" => "string",
                             "minLength" => 3, "maxLength" => 64)
      expect(result.dig("schema", "minLength")).to eq(3)
      expect(result.dig("schema", "maxLength")).to eq(64)
    end

    it "moves pattern to schema" do
      result = convert_param("in" => "query", "name" => "code", "type" => "string",
                             "pattern" => "^[A-Z]{3}$")
      expect(result.dig("schema", "pattern")).to eq("^[A-Z]{3}$")
    end

    it "moves uniqueItems to schema" do
      result = convert_param("in" => "query", "name" => "ids", "type" => "array",
                             "items" => { "type" => "integer" }, "uniqueItems" => true)
      expect(result.dig("schema", "uniqueItems")).to be true
    end

    it "preserves x- extensions at the parameter level" do
      result = convert_param("in" => "query", "name" => "q", "type" => "string",
                             "x-example" => "hello", "x-deprecated-in" => "v2")
      expect(result["x-example"]).to eq("hello")
      expect(result["x-deprecated-in"]).to eq("v2")
    end

    it "forces required: true for path parameters even when absent in source" do
      expect(convert_param("in" => "path", "name" => "id", "type" => "string")["required"])
        .to be true
    end

    it "does not add required to query parameters" do
      expect(convert_param("in" => "query", "name" => "q", "type" => "string"))
        .not_to have_key("required")
    end

    it "returns nil schema when the parameter has no type-like fields" do
      result = convert_param("in" => "query", "name" => "q")
      expect(result["schema"]).to be_nil
    end

    context "collectionFormat → style / explode" do
      it "maps tsv to tabDelimited style" do
        result = convert_param("in" => "query", "name" => "ids", "type" => "array",
                               "items" => { "type" => "string" }, "collectionFormat" => "tsv")
        schema = result["schema"]
        expect(schema["style"]).to eq("tabDelimited")
        expect(schema).not_to have_key("collectionFormat")
      end

      it "maps csv to style: form, explode: false" do
        schema = convert_param("in" => "query", "name" => "ids", "type" => "array",
                               "items" => { "type" => "string" }, "collectionFormat" => "csv")["schema"]
        expect(schema["style"]).to eq("form")
        expect(schema["explode"]).to be false
      end

      it "maps multi to style: form, explode: true" do
        schema = convert_param("in" => "query", "name" => "ids", "type" => "array",
                               "items" => { "type" => "string" }, "collectionFormat" => "multi")["schema"]
        expect(schema["style"]).to eq("form")
        expect(schema["explode"]).to be true
      end
    end
  end

  # ---------------------------------------------------------------------------
  # build_request_body_from_body_param
  # ---------------------------------------------------------------------------

  describe ".build_request_body_from_body_param" do
    it "creates one content entry per mime in consumes" do
      rb = build_body_rb(
        { "in" => "body", "name" => "b", "schema" => { "type" => "object" } },
        ["application/json", "application/xml"]
      )
      expect(rb["content"].keys).to contain_exactly("application/json", "application/xml")
    end

    it "places the schema under each content mime" do
      rb = build_body_rb({ "in" => "body", "name" => "b", "schema" => { "type" => "string" } })
      expect(rb.dig("content", "application/json", "schema", "type")).to eq("string")
    end

    it "carries description from the body parameter" do
      rb = build_body_rb({ "in" => "body", "name" => "b",
                           "description" => "Payload", "schema" => {} })
      expect(rb["description"]).to eq("Payload")
    end

    it "omits description when the body param has none" do
      rb = build_body_rb({ "in" => "body", "name" => "b", "schema" => {} })
      expect(rb).not_to have_key("description")
    end

    it "carries required: true from the body parameter" do
      rb = build_body_rb({ "in" => "body", "name" => "b", "required" => true, "schema" => {} })
      expect(rb["required"]).to be true
    end

    it "omits required when absent from the body parameter" do
      rb = build_body_rb({ "in" => "body", "name" => "b", "schema" => {} })
      expect(rb).not_to have_key("required")
    end

    it "uses empty schema when the body parameter has no schema key" do
      expect { build_body_rb({ "in" => "body", "name" => "b" }) }.not_to raise_error
      rb = build_body_rb({ "in" => "body", "name" => "b" })
      expect(rb.dig("content", "application/json", "schema")).to eq({})
    end
  end

  # ---------------------------------------------------------------------------
  # build_request_body_from_form_params
  # ---------------------------------------------------------------------------

  describe ".build_request_body_from_form_params" do
    it "defaults to application/x-www-form-urlencoded when no file params present" do
      rb = build_form_rb([{ "in" => "formData", "name" => "name", "type" => "string" }])
      expect(rb["content"].keys).to eq(["application/x-www-form-urlencoded"])
    end

    it "switches to multipart/form-data when a file param is present" do
      rb = build_form_rb([{ "in" => "formData", "name" => "avatar", "type" => "file" }])
      expect(rb["content"].keys).to eq(["multipart/form-data"])
    end

    it "honours explicit multipart/form-data in consumes even without a file param" do
      rb = build_form_rb(
        [{ "in" => "formData", "name" => "name", "type" => "string" }],
        ["multipart/form-data"]
      )
      expect(rb["content"].keys).to eq(["multipart/form-data"])
    end

    it "maps file type to string/binary in the property schema" do
      rb = build_form_rb([{ "in" => "formData", "name" => "upload", "type" => "file" }])
      prop = rb.dig("content", "multipart/form-data", "schema", "properties", "upload")
      expect(prop).to eq("type" => "string", "format" => "binary")
    end

    it "includes description on the property schema" do
      rb = build_form_rb([{ "in" => "formData", "name" => "bio",
                            "type" => "string", "description" => "Author bio" }])
      prop = rb.dig("content", "application/x-www-form-urlencoded", "schema", "properties", "bio")
      expect(prop["description"]).to eq("Author bio")
    end

    it "collects required field names from required formData params" do
      rb = build_form_rb([
        { "in" => "formData", "name" => "email", "type" => "string", "required" => true },
        { "in" => "formData", "name" => "bio",   "type" => "string" }
      ])
      schema = rb.dig("content", "application/x-www-form-urlencoded", "schema")
      expect(schema["required"]).to eq(["email"])
    end

    it "omits required key when none of the formData params are required" do
      rb = build_form_rb([
        { "in" => "formData", "name" => "bio", "type" => "string" }
      ])
      schema = rb.dig("content", "application/x-www-form-urlencoded", "schema")
      expect(schema).not_to have_key("required")
    end

    it "preserves array type with items in property schema" do
      rb = build_form_rb([{ "in" => "formData", "name" => "tags", "type" => "array",
                            "items" => { "type" => "string" } }])
      prop = rb.dig("content", "application/x-www-form-urlencoded", "schema", "properties", "tags")
      expect(prop["type"]).to eq("array")
      expect(prop.dig("items", "type")).to eq("string")
    end
  end

  # ---------------------------------------------------------------------------
  # convert_response
  # ---------------------------------------------------------------------------

  describe ".convert_response" do
    it "passes a $ref response through unchanged" do
      resp = { "$ref" => "#/components/responses/NotFound" }
      expect(convert_resp(resp)).to eq(resp)
    end

    it "preserves description" do
      expect(convert_resp({ "description" => "Success" })["description"]).to eq("Success")
    end

    it "defaults description to empty string when absent" do
      expect(convert_resp({})["description"]).to eq("")
    end

    it "wraps schema in content" do
      result = convert_resp({ "description" => "ok", "schema" => { "type" => "object" } })
      expect(result.dig("content", "application/json", "schema", "type")).to eq("object")
    end

    it "creates one content entry per produces mime" do
      result = convert_resp(
        { "description" => "ok", "schema" => { "type" => "object" } },
        ["application/json", "application/xml"]
      )
      expect(result["content"].keys).to contain_exactly("application/json", "application/xml")
    end

    it "omits content when the response has no schema" do
      expect(convert_resp({ "description" => "No content" })).not_to have_key("content")
    end

    it "passes through x- extensions" do
      result = convert_resp({ "description" => "ok", "x-cache-ttl" => 300 })
      expect(result["x-cache-ttl"]).to eq(300)
    end

    context "response headers" do
      let(:response_with_headers) do
        {
          "description" => "ok",
          "headers"     => {
            "X-Rate-Limit" => {
              "type"        => "integer",
              "format"      => "int32",
              "description" => "Calls allowed in window"
            }
          }
        }
      end

      it "preserves header keys" do
        result = convert_resp(response_with_headers)
        expect(result["headers"]).to have_key("X-Rate-Limit")
      end

      it "preserves header description" do
        result = convert_resp(response_with_headers)
        expect(result.dig("headers", "X-Rate-Limit", "description"))
          .to eq("Calls allowed in window")
      end

      it "moves type to schema.type (OAS 3.0 Header Object compliance)" do
        result = convert_resp(response_with_headers)
        header = result.dig("headers", "X-Rate-Limit")
        expect(header.dig("schema", "type")).to eq("integer")
        expect(header).not_to have_key("type")
      end

      it "moves format to schema.format" do
        result = convert_resp(response_with_headers)
        header = result.dig("headers", "X-Rate-Limit")
        expect(header.dig("schema", "format")).to eq("int32")
        expect(header).not_to have_key("format")
      end

      it "passes through x- extensions on a header" do
        response = {
          "description" => "ok",
          "headers"     => { "X-Foo" => { "type" => "string", "x-internal" => true } }
        }
        header = convert_resp(response).dig("headers", "X-Foo")
        expect(header["x-internal"]).to be true
      end

      it "omits schema key when header has no type or format" do
        response = {
          "description" => "ok",
          "headers"     => { "X-Request-Id" => { "description" => "Trace ID" } }
        }
        header = convert_resp(response).dig("headers", "X-Request-Id")
        expect(header).not_to have_key("schema")
        expect(header["description"]).to eq("Trace ID")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # convert_path_item
  # ---------------------------------------------------------------------------

  describe ".convert_path_item" do
    def convert_item(path_item, gc = [], gp = [])
      described_class.convert_path_item(path_item, gc, gp)
    end

    it "passes through a path item that is a $ref" do
      item = { "$ref" => "#/x-path-items/shared" }
      expect(convert_item(item)).to eq(item)
    end

    it "preserves x- extensions at the path-item level" do
      item = {
        "x-visibility" => "internal",
        "get"          => { "responses" => { "200" => { "description" => "ok" } } }
      }
      result = convert_item(item)
      expect(result["x-visibility"]).to eq("internal")
    end

    it "does not bleed path-item extensions into the operation" do
      item = {
        "x-owner" => "team-a",
        "get"     => { "responses" => { "200" => { "description" => "ok" } } }
      }
      result = convert_item(item)
      expect(result["get"]).not_to have_key("x-owner")
    end
  end

  # ---------------------------------------------------------------------------
  # convert (full paths hash)
  # ---------------------------------------------------------------------------

  describe ".convert" do
    def base_swagger
      { "swagger" => "2.0", "info" => { "title" => "T", "version" => "1" }, "paths" => {} }
    end

    it "operation-level produces overrides global produces for response content-type keys" do
      swagger = base_swagger.merge(
        "produces" => ["application/json"],
        "paths"    => {
          "/x" => { "get" => {
            "produces"  => ["application/xml"],
            "responses" => { "200" => { "description" => "ok", "schema" => { "type" => "object" } } }
          } }
        }
      )
      content = described_class.convert(swagger).dig("/x", "get", "responses", "200", "content")
      expect(content.keys).to eq(["application/xml"])
    end

    it "operation-level consumes overrides global consumes for requestBody content-type keys" do
      swagger = base_swagger.merge(
        "consumes" => ["application/json"],
        "paths"    => {
          "/x" => { "post" => {
            "consumes"   => ["application/xml"],
            "parameters" => [{ "in" => "body", "name" => "b", "schema" => { "type" => "object" } }],
            "responses"  => { "200" => { "description" => "ok" } }
          } }
        }
      )
      content = described_class.convert(swagger).dig("/x", "post", "requestBody", "content")
      expect(content.keys).to eq(["application/xml"])
    end

    it "when two body parameters are present, uses the first one" do
      swagger = base_swagger.merge(
        "paths" => {
          "/x" => { "post" => {
            "parameters" => [
              { "in" => "body", "name" => "first",  "schema" => { "type" => "string" } },
              { "in" => "body", "name" => "second", "schema" => { "type" => "integer" } }
            ],
            "responses" => { "200" => { "description" => "ok" } }
          } }
        }
      )
      schema = described_class.convert(swagger)
                               .dig("/x", "post", "requestBody", "content", "application/json", "schema")
      expect(schema["type"]).to eq("string")
    end

    it "preserves tags: [] (empty array) on an operation" do
      swagger = base_swagger.merge(
        "paths" => {
          "/x" => { "get" => {
            "tags"      => [],
            "responses" => { "200" => { "description" => "ok" } }
          } }
        }
      )
      op = described_class.convert(swagger).dig("/x", "get")
      expect(op).to have_key("tags")
      expect(op["tags"]).to eq([])
    end
  end
end

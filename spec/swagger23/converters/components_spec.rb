# frozen_string_literal: true

require "spec_helper"

RSpec.describe Swagger23::Converters::Components do
  def convert(swagger)
    described_class.convert(swagger)
  end

  context "when swagger has no reusable sections" do
    it "returns an empty hash" do
      expect(convert({})).to eq({})
    end

    it "omits schemas key when definitions is absent" do
      expect(convert({})).not_to have_key("schemas")
    end

    it "omits parameters key when global parameters are absent" do
      expect(convert({})).not_to have_key("parameters")
    end

    it "omits responses key when global responses are absent" do
      expect(convert({})).not_to have_key("responses")
    end
  end

  # ── definitions → schemas ───────────────────────────────────────────────────

  describe "definitions → components/schemas" do
    it "moves definitions to schemas" do
      result = convert("definitions" => { "Pet" => { "type" => "object" } })
      expect(result["schemas"]).to eq("Pet" => { "type" => "object" })
    end

    it "includes all definitions verbatim" do
      result = convert("definitions" => {
        "Alpha"  => { "type" => "string" },
        "Beta"   => { "type" => "integer" },
        "Gamma"  => { "type" => "object", "properties" => {} }
      })
      expect(result["schemas"].keys).to contain_exactly("Alpha", "Beta", "Gamma")
    end
  end

  # ── global parameters → components/parameters ───────────────────────────────

  describe "global parameters → components/parameters" do
    it "includes all global parameters" do
      result = convert("parameters" => {
        "Limit"  => { "in" => "query",  "name" => "limit",  "type" => "integer" },
        "Offset" => { "in" => "query",  "name" => "offset", "type" => "integer" }
      })
      expect(result["parameters"].keys).to contain_exactly("Limit", "Offset")
    end

    it "moves type to schema for a query parameter" do
      result = convert("parameters" => {
        "Limit" => { "in" => "query", "name" => "limit", "type" => "integer" }
      })
      param = result.dig("parameters", "Limit")
      expect(param.dig("schema", "type")).to eq("integer")
      expect(param).not_to have_key("type")
    end

    it "moves type + format to schema" do
      result = convert("parameters" => {
        "ResourceId" => { "in" => "path", "name" => "id", "type" => "integer", "format" => "int64" }
      })
      schema = result.dig("parameters", "ResourceId", "schema")
      expect(schema["type"]).to eq("integer")
      expect(schema["format"]).to eq("int64")
    end

    it "preserves name and in on the converted parameter" do
      result = convert("parameters" => {
        "Offset" => { "in" => "query", "name" => "offset", "type" => "integer" }
      })
      param = result.dig("parameters", "Offset")
      expect(param["name"]).to eq("offset")
      expect(param["in"]).to eq("query")
    end

    it "forces required: true on a global path parameter" do
      result = convert("parameters" => {
        "ItemId" => { "in" => "path", "name" => "id", "type" => "string" }
      })
      expect(result.dig("parameters", "ItemId", "required")).to be true
    end

    it "preserves x- extensions on a global parameter" do
      result = convert("parameters" => {
        "ReqId" => { "in" => "header", "name" => "X-Request-Id", "type" => "string", "x-custom" => true }
      })
      expect(result.dig("parameters", "ReqId", "x-custom")).to be true
    end

    it "passes through a $ref global parameter unchanged" do
      result = convert("parameters" => {
        "Shared" => { "$ref" => "#/components/parameters/External" }
      })
      expect(result.dig("parameters", "Shared", "$ref")).to eq("#/components/parameters/External")
    end
  end

  # ── global responses → components/responses ─────────────────────────────────

  describe "global responses → components/responses" do
    it "includes all global responses" do
      result = convert("responses" => {
        "NotFound"    => { "description" => "Not found" },
        "ServerError" => { "description" => "Internal error" }
      })
      expect(result["responses"].keys).to contain_exactly("NotFound", "ServerError")
    end

    it "preserves description" do
      result = convert("responses" => { "Gone" => { "description" => "Resource deleted" } })
      expect(result.dig("responses", "Gone", "description")).to eq("Resource deleted")
    end

    it "wraps schema in content using global produces mime" do
      result = convert(
        "produces"  => ["application/json"],
        "responses" => { "Error" => { "description" => "err", "schema" => { "type" => "object" } } }
      )
      content = result.dig("responses", "Error", "content")
      expect(content.keys).to eq(["application/json"])
      expect(content.dig("application/json", "schema", "type")).to eq("object")
    end

    it "defaults to application/json when produces is absent" do
      result = convert(
        "responses" => { "Error" => { "description" => "err", "schema" => { "type" => "object" } } }
      )
      expect(result.dig("responses", "Error", "content").keys).to eq(["application/json"])
    end

    it "creates multiple content entries for multiple produces mimes" do
      result = convert(
        "produces"  => ["application/json", "application/xml"],
        "responses" => { "Ok" => { "description" => "ok", "schema" => { "type" => "object" } } }
      )
      expect(result.dig("responses", "Ok", "content").keys)
        .to contain_exactly("application/json", "application/xml")
    end

    it "omits content when the response has no schema" do
      result = convert("responses" => { "NoContent" => { "description" => "nothing" } })
      expect(result.dig("responses", "NoContent")).not_to have_key("content")
    end

    it "passes through x- extensions on a global response" do
      result = convert("responses" => { "Err" => { "description" => "e", "x-retry-after" => 30 } })
      expect(result.dig("responses", "Err", "x-retry-after")).to eq(30)
    end

    it "preserves response headers and moves type to schema (OAS 3.0 compliance)" do
      result = convert(
        "responses" => {
          "Paged" => {
            "description" => "paginated",
            "headers"     => {
              "X-Total-Count" => { "type" => "integer", "description" => "total items" }
            }
          }
        }
      )
      header = result.dig("responses", "Paged", "headers", "X-Total-Count")
      expect(header).not_to be_nil
      expect(header["description"]).to eq("total items")
      expect(header.dig("schema", "type")).to eq("integer")
      expect(header).not_to have_key("type")
    end
  end
end

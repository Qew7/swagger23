# frozen_string_literal: true

require "spec_helper"
require "benchmark"

RSpec.describe "Large specification handling" do
  # Generates a synthetic but realistic Swagger 2.0 document with:
  #   - `path_count` endpoints (each with GET + POST)
  #   - `definition_count` schema definitions
  #   - Nested schemas with $ref, allOf, properties
  #   - Deeply nested inline schemas (to stress the ref-rewriter)
  def build_large_swagger(path_count: 300, definition_count: 200, nesting_depth: 15)
    definitions = {}

    definition_count.times do |i|
      definitions["Model#{i}"] = {
        "type"       => "object",
        "properties" => {
          "id"     => { "type" => "integer" },
          "name"   => { "type" => "string" },
          "parent" => i > 0 ? { "$ref" => "#/definitions/Model#{i - 1}" } : { "type" => "null" }
        }
      }
    end

    # Build a deeply nested inline schema to exercise the iterative rewriter
    deep_schema = { "type" => "string" }
    nesting_depth.times do |i|
      deep_schema = {
        "type"       => "object",
        "properties" => {
          "level#{i}" => deep_schema,
          "ref#{i}"   => { "$ref" => "#/definitions/Model#{i % definition_count}" }
        }
      }
    end

    paths = {}
    path_count.times do |i|
      paths["/resources/#{i}"] = {
        "get" => {
          "operationId" => "getResource#{i}",
          "summary"     => "Get resource #{i}",
          "parameters"  => [
            { "in" => "path",  "name" => "id",     "required" => true, "type" => "integer" },
            { "in" => "query", "name" => "expand", "type" => "string" }
          ],
          "responses"   => {
            "200" => {
              "description" => "ok",
              "schema"      => { "$ref" => "#/definitions/Model#{i % definition_count}" }
            }
          }
        },
        "post" => {
          "operationId" => "createResource#{i}",
          "summary"     => "Create resource #{i}",
          "consumes"    => ["application/json"],
          "parameters"  => [
            {
              "in"     => "body",
              "name"   => "body",
              "schema" => {
                "allOf" => [
                  { "$ref" => "#/definitions/Model#{i % definition_count}" },
                  deep_schema
                ]
              }
            }
          ],
          "responses" => {
            "201" => { "description" => "created" },
            "422" => { "description" => "validation error" }
          }
        }
      }
    end

    {
      "swagger"     => "2.0",
      "info"        => { "title" => "Large API", "version" => "1.0" },
      "host"        => "api.example.com",
      "basePath"    => "/v1",
      "schemes"     => ["https"],
      "produces"    => ["application/json"],
      "consumes"    => ["application/json"],
      "paths"       => paths,
      "definitions" => definitions
    }
  end

  describe "correctness on large input" do
    let(:swagger) { build_large_swagger(path_count: 300, definition_count: 200) }
    let(:result)  { Swagger23.convert(swagger) }

    it "produces a valid openapi 3.0 root" do
      expect(result["openapi"]).to eq("3.0.3")
    end

    it "converts all paths" do
      expect(result["paths"].keys.size).to eq(300)
    end

    it "moves all definitions to components/schemas" do
      expect(result.dig("components", "schemas").keys.size).to eq(200)
    end

    it "rewrites every $ref in schemas" do
      raw_json = JSON.generate(result)
      expect(raw_json).not_to include("#/definitions/")
    end

    it "does not mutate the original swagger document" do
      raw_before = JSON.generate(swagger)
      Swagger23.convert(swagger)
      raw_after = JSON.generate(swagger)
      expect(raw_after).to eq(raw_before)
    end

    it "creates requestBody for every POST operation" do
      result["paths"].each_value do |path_item|
        next unless path_item.key?("post")

        expect(path_item.dig("post", "requestBody")).not_to be_nil,
          "POST operation is missing requestBody"
      end
    end
  end

  describe "performance" do
    it "converts a 300-path / 200-model spec in under 2 seconds" do
      swagger = build_large_swagger(path_count: 300, definition_count: 200)

      elapsed = Benchmark.realtime { Swagger23.convert(swagger) }

      expect(elapsed).to be < 2.0,
        "Conversion took #{elapsed.round(3)}s — expected < 2s"
    end

    it "does not raise SystemStackError on deeply nested schemas (depth 50)" do
      swagger = build_large_swagger(path_count: 5, definition_count: 5, nesting_depth: 50)

      expect { Swagger23.convert(swagger) }.not_to raise_error
    end
  end
end

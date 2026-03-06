# frozen_string_literal: true

require "spec_helper"

RSpec.describe Swagger23::RefRewriter do
  describe ".rewrite_ref" do
    {
      "#/definitions/Pet"           => "#/components/schemas/Pet",
      "#/parameters/PageSize"       => "#/components/parameters/PageSize",
      "#/responses/NotFound"        => "#/components/responses/NotFound",
      "#/securityDefinitions/OAuth" => "#/components/securitySchemes/OAuth"
    }.each do |input, expected|
      it "rewrites '#{input}'" do
        expect(described_class.rewrite_ref(input)).to eq(expected)
      end
    end

    it "leaves external $refs untouched" do
      expect(described_class.rewrite_ref("https://example.com/schema.json#/Foo"))
        .to eq("https://example.com/schema.json#/Foo")
    end

    it "leaves already-converted refs untouched" do
      expect(described_class.rewrite_ref("#/components/schemas/Foo"))
        .to eq("#/components/schemas/Foo")
    end

    it "leaves relative file refs untouched" do
      expect(described_class.rewrite_ref("./models/pet.yaml#/Pet"))
        .to eq("./models/pet.yaml#/Pet")
    end
  end

  describe ".rewrite" do
    it "returns a new object (does not mutate the input)" do
      input  = { "$ref" => "#/definitions/Foo" }
      result = described_class.rewrite(input)
      expect(input["$ref"]).to eq("#/definitions/Foo")      # unchanged
      expect(result["$ref"]).to eq("#/components/schemas/Foo")
    end

    it "rewrites $ref at the top level" do
      result = described_class.rewrite("$ref" => "#/definitions/Foo")
      expect(result["$ref"]).to eq("#/components/schemas/Foo")
    end

    it "rewrites $ref nested inside a hash" do
      input  = { "schema" => { "$ref" => "#/definitions/Bar" } }
      result = described_class.rewrite(input)
      expect(result.dig("schema", "$ref")).to eq("#/components/schemas/Bar")
    end

    it "rewrites $ref inside an array" do
      input  = [{ "$ref" => "#/definitions/A" }, { "$ref" => "#/parameters/B" }]
      result = described_class.rewrite(input)
      expect(result[0]["$ref"]).to eq("#/components/schemas/A")
      expect(result[1]["$ref"]).to eq("#/components/parameters/B")
    end

    it "rewrites multiple $refs in allOf / anyOf" do
      input = {
        "allOf" => [
          { "$ref" => "#/definitions/Base" },
          { "properties" => { "extra" => { "$ref" => "#/definitions/Extra" } } }
        ]
      }
      result = described_class.rewrite(input)
      expect(result.dig("allOf", 0, "$ref")).to eq("#/components/schemas/Base")
      expect(result.dig("allOf", 1, "properties", "extra", "$ref"))
        .to eq("#/components/schemas/Extra")
    end

    it "passes through non-$ref keys unchanged" do
      input  = { "type" => "object", "title" => "Foo" }
      result = described_class.rewrite(input)
      expect(result).to eq(input)
    end

    it "passes through scalar values" do
      expect(described_class.rewrite(42)).to eq(42)
      expect(described_class.rewrite("hello")).to eq("hello")
      expect(described_class.rewrite(nil)).to be_nil
      expect(described_class.rewrite(true)).to be true
    end

    it "handles empty hash" do
      expect(described_class.rewrite({})).to eq({})
    end

    it "handles empty array" do
      expect(described_class.rewrite([])).to eq([])
    end

    it "does not raise on deep nesting (depth 60)" do
      # Build a 60-level deep nested object with $refs at every level
      deep = { "type" => "string" }
      60.times { |i| deep = { "properties" => { "l#{i}" => deep, "ref" => { "$ref" => "#/definitions/X" } } } }

      expect { described_class.rewrite(deep) }.not_to raise_error
    end

    it "rewrites $refs inside deeply nested structure" do
      deep = { "$ref" => "#/definitions/Leaf" }
      10.times { deep = { "properties" => { "child" => deep } } }

      result = described_class.rewrite(deep)
      # Walk down to the leaf
      node = result
      10.times { node = node.dig("properties", "child") }
      expect(node["$ref"]).to eq("#/components/schemas/Leaf")
    end
  end
end

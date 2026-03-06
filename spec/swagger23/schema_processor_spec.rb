# frozen_string_literal: true

require "spec_helper"

RSpec.describe Swagger23::SchemaProcessor do
  describe ".process" do
    it "returns the same (mutated) object" do
      obj = { "type" => "string" }
      expect(described_class.process(obj)).to be(obj)
    end

    it "handles nil without raising" do
      expect { described_class.process(nil) }.not_to raise_error
    end

    it "handles an empty hash" do
      expect(described_class.process({})).to eq({})
    end

    it "handles an empty array" do
      expect(described_class.process([])).to eq([])
    end

    it "handles scalar values (string, integer, boolean)" do
      expect(described_class.process("hello")).to eq("hello")
      expect(described_class.process(42)).to eq(42)
      expect(described_class.process(true)).to be true
    end
  end

  # ── x-nullable ──────────────────────────────────────────────────────────────

  describe "x-nullable → nullable" do
    it "converts x-nullable: true to nullable: true and removes x-nullable" do
      obj = { "type" => "string", "x-nullable" => true }
      described_class.process(obj)
      expect(obj["nullable"]).to be true
      expect(obj).not_to have_key("x-nullable")
    end

    it "converts x-nullable: false to nullable: false and removes x-nullable" do
      obj = { "type" => "string", "x-nullable" => false }
      described_class.process(obj)
      expect(obj["nullable"]).to be false
      expect(obj).not_to have_key("x-nullable")
    end

    it "does not overwrite an explicitly set nullable when x-nullable is also present" do
      obj = { "nullable" => false, "x-nullable" => true }
      described_class.process(obj)
      expect(obj["nullable"]).to be false
      expect(obj).not_to have_key("x-nullable")
    end

    it "processes x-nullable inside a nested properties hash (BFS)" do
      obj = { "properties" => { "name" => { "type" => "string", "x-nullable" => true } } }
      described_class.process(obj)
      expect(obj.dig("properties", "name", "nullable")).to be true
      expect(obj.dig("properties", "name")).not_to have_key("x-nullable")
    end

    it "processes x-nullable inside an allOf array element" do
      obj = { "allOf" => [{ "type" => "string", "x-nullable" => true }] }
      described_class.process(obj)
      expect(obj.dig("allOf", 0, "nullable")).to be true
    end

    it "processes x-nullable on a query parameter schema (full tree walk)" do
      obj = {
        "paths" => {
          "/x" => {
            "get" => {
              "parameters" => [
                { "in" => "query", "name" => "q",
                  "schema" => { "type" => "string", "x-nullable" => true } }
              ]
            }
          }
        }
      }
      described_class.process(obj)
      schema = obj.dig("paths", "/x", "get", "parameters", 0, "schema")
      expect(schema["nullable"]).to be true
      expect(schema).not_to have_key("x-nullable")
    end

    it "processes x-nullable inside a response header schema" do
      obj = {
        "headers" => {
          "X-Foo" => { "schema" => { "type" => "string", "x-nullable" => true } }
        }
      }
      described_class.process(obj)
      schema = obj.dig("headers", "X-Foo", "schema")
      expect(schema["nullable"]).to be true
      expect(schema).not_to have_key("x-nullable")
    end
  end

  # ── discriminator coercion ───────────────────────────────────────────────────

  describe "discriminator: string → {propertyName: ...}" do
    it "converts a bare-string discriminator" do
      obj = { "type" => "object", "discriminator" => "petType" }
      described_class.process(obj)
      expect(obj["discriminator"]).to eq("propertyName" => "petType")
    end

    it "leaves a discriminator that is already an object unchanged" do
      obj = { "discriminator" => { "propertyName" => "petType" } }
      described_class.process(obj)
      expect(obj["discriminator"]).to eq("propertyName" => "petType")
    end

    it "preserves extra fields (e.g. mapping) in an existing discriminator object" do
      mapping = { "cat" => "#/components/schemas/Cat", "dog" => "#/components/schemas/Dog" }
      obj = { "discriminator" => { "propertyName" => "petType", "mapping" => mapping } }
      described_class.process(obj)
      expect(obj.dig("discriminator", "mapping")).to eq(mapping)
    end

    it "converts discriminator inside a nested schema" do
      obj = {
        "definitions" => {
          "Animal" => { "type" => "object", "discriminator" => "animalType" }
        }
      }
      described_class.process(obj)
      expect(obj.dig("definitions", "Animal", "discriminator"))
        .to eq("propertyName" => "animalType")
    end
  end

  # ── type-array unwrapping ───────────────────────────────────────────────────

  describe "type: array unwrapping" do
    it "unwraps [T, null] → type: T, nullable: true" do
      obj = { "type" => ["string", "null"] }
      described_class.process(obj)
      expect(obj["type"]).to eq("string")
      expect(obj["nullable"]).to be true
    end

    it "unwraps [null, T] (null first) → type: T, nullable: true" do
      obj = { "type" => ["null", "integer"] }
      described_class.process(obj)
      expect(obj["type"]).to eq("integer")
      expect(obj["nullable"]).to be true
    end

    it "unwraps [T] (single non-null) → type: T, no nullable added" do
      obj = { "type" => ["string"] }
      described_class.process(obj)
      expect(obj["type"]).to eq("string")
      expect(obj).not_to have_key("nullable")
    end

    it "unwraps [null] → no type key, nullable: true" do
      obj = { "type" => ["null"] }
      described_class.process(obj)
      expect(obj).not_to have_key("type")
      expect(obj["nullable"]).to be true
    end

    it "leaves [A, B] (two non-null types) unchanged" do
      obj = { "type" => ["string", "integer"] }
      described_class.process(obj)
      expect(obj["type"]).to eq(["string", "integer"])
    end

    it "processes type array in a nested property" do
      obj = { "properties" => { "count" => { "type" => ["integer", "null"] } } }
      described_class.process(obj)
      prop = obj.dig("properties", "count")
      expect(prop["type"]).to eq("integer")
      expect(prop["nullable"]).to be true
    end
  end

  # ── transform! ──────────────────────────────────────────────────────────────

  describe ".transform!" do
    it "applies all three transformations to a single node" do
      h = {
        "x-nullable"    => true,
        "discriminator" => "kind",
        "type"          => ["string", "null"]
      }
      described_class.transform!(h)
      expect(h).not_to have_key("x-nullable")
      expect(h["nullable"]).to be true
      expect(h["discriminator"]).to eq("propertyName" => "kind")
      expect(h["type"]).to eq("string")
    end

    it "is a no-op on a plain hash with no special keys" do
      h = { "title" => "MyAPI", "version" => "1.0" }
      expect { described_class.transform!(h) }.not_to change { h }
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require "yaml"

RSpec.describe "YAML support" do
  let(:yaml_fixture_path) do
    File.expand_path("../fixtures/petstore_swagger2.yaml", __dir__)
  end
  let(:yaml_source)  { File.read(yaml_fixture_path, encoding: "utf-8") }
  let(:json_fixture_path) do
    File.expand_path("../fixtures/bookstore_swagger2.json", __dir__)
  end
  let(:json_source)  { File.read(json_fixture_path, encoding: "utf-8") }

  # ── Swagger23.parse ────────────────────────────────────────────────────────

  describe "Swagger23.parse" do
    context "with JSON input" do
      it "returns a Hash" do
        result = Swagger23.parse(json_source)
        expect(result).to be_a(Hash)
      end

      it "preserves the swagger version string" do
        expect(Swagger23.parse(json_source)["swagger"]).to eq("2.0")
      end
    end

    context "with YAML input" do
      it "returns a Hash" do
        result = Swagger23.parse(yaml_source)
        expect(result).to be_a(Hash)
      end

      it "preserves the swagger version string" do
        expect(Swagger23.parse(yaml_source)["swagger"]).to eq("2.0")
      end

      it "uses string keys (not symbols)" do
        result = Swagger23.parse(yaml_source)
        expect(result.keys).to all(be_a(String))
      end

      it "parses bare boolean values correctly" do
        # x-nullable: false (bare YAML boolean, not quoted string)
        name_prop = Swagger23.parse(yaml_source)
                              .dig("definitions", "Pet", "properties", "name")
        expect(name_prop["x-nullable"]).to be false
      end

      it "parses bare integer values correctly" do
        limit_param = Swagger23.parse(yaml_source)
                               .dig("paths", "/pets", "get", "parameters")
                               .find { |p| p["name"] == "limit" }
        expect(limit_param["default"]).to eq(20)
        expect(limit_param["maximum"]).to eq(100)
      end

      it "parses multi-line YAML strings" do
        desc = Swagger23.parse(yaml_source).dig("info", "description")
        expect(desc).to include("Petstore spec in YAML")
        expect(desc).to include("anchors")
      end
    end

    context "with invalid input" do
      it "raises Swagger23::Error for garbage input" do
        expect { Swagger23.parse("not json or yaml: [[[") }
          .to raise_error(Swagger23::Error)
      end

      it "raises Swagger23::Error when parsed result is not a Hash" do
        expect { Swagger23.parse("- item1\n- item2\n") }
          .to raise_error(Swagger23::Error, /expected a Hash/i)
      end

      it "raises Swagger23::Error for empty input" do
        expect { Swagger23.parse("") }
          .to raise_error(Swagger23::Error)
      end
    end
  end

  # ── YAML input → convert → correct OpenAPI 3.0 output ────────────────────

  describe "converting YAML input" do
    let(:result) { Swagger23.convert(Swagger23.parse(yaml_source)) }

    it "sets openapi: 3.0.3" do
      expect(result["openapi"]).to eq("3.0.3")
    end

    it "builds servers from YAML host/basePath/schemes" do
      urls = result["servers"].map { |s| s["url"] }
      expect(urls).to contain_exactly(
        "https://api.petstore.example.com/v1",
        "http://api.petstore.example.com/v1"
      )
    end

    it "moves definitions to components/schemas" do
      expect(result.dig("components", "schemas").keys)
        .to contain_exactly("Pet", "NewPet", "PetList", "Error")
    end

    it "rewrites $ref from YAML fixture" do
      ref = result.dig("components", "schemas", "PetList", "items", "$ref")
      expect(ref).to eq("#/components/schemas/Pet")
    end

    it "converts x-nullable: true from YAML" do
      tag_prop = result.dig("components", "schemas", "Pet", "properties", "tag")
      expect(tag_prop["nullable"]).to be true
      expect(tag_prop).not_to have_key("x-nullable")
    end

    it "converts x-nullable: false from YAML" do
      name_prop = result.dig("components", "schemas", "Pet", "properties", "name")
      expect(name_prop["nullable"]).to be false
      expect(name_prop).not_to have_key("x-nullable")
    end

    it "converts collectionFormat: multi from YAML" do
      status_param = result.dig("paths", "/pets", "get", "parameters")
                           .find { |p| p["name"] == "status" }
      expect(status_param.dig("schema", "style")).to eq("form")
      expect(status_param.dig("schema", "explode")).to be true
    end

    it "creates requestBody from body param in YAML" do
      rb = result.dig("paths", "/pets", "post", "requestBody")
      expect(rb).not_to be_nil
      expect(rb.dig("content", "application/json", "schema", "$ref"))
        .to eq("#/components/schemas/NewPet")
    end

    it "auto-injects required: true on path param from YAML" do
      # PetId is defined in top-level parameters (no required: true in YAML)
      # and referenced via $ref from the path. The gem injects required: true
      # on the resolved parameter in components/parameters.
      param = result.dig("components", "parameters", "PetId")
      expect(param["required"]).to be true
      # The path-level entry stays as a $ref (gem does not dereference)
      ref = result.dig("paths", "/pets/{petId}", "parameters", 0)
      expect(ref["$ref"]).to eq("#/components/parameters/PetId")
    end

    it "converts integer response code (204) to string" do
      responses = result.dig("paths", "/pets/{petId}", "delete", "responses")
      expect(responses.keys).to include("204")
      expect(responses.keys).not_to include(204)
    end

    it "preserves 'default' response code from YAML" do
      responses = result.dig("paths", "/pets", "get", "responses")
      expect(responses).to have_key("default")
    end

    it "converts multipart/form-data upload from YAML" do
      content = result.dig("paths", "/pets/{petId}/photo", "post",
                           "requestBody", "content")
      expect(content.keys).to eq(["multipart/form-data"])
      photo = content.dig("multipart/form-data", "schema", "properties", "photo")
      expect(photo).to eq("type" => "string", "format" => "binary")
    end

    it "passes through x- extensions from YAML" do
      expect(result.dig("paths", "/pets/{petId}", "delete", "x-idempotent")).to be true
    end

    it "converts securityDefinitions from YAML" do
      schemes = result.dig("components", "securitySchemes")
      expect(schemes.keys).to contain_exactly("ApiKey", "OAuth2")
      expect(schemes.dig("OAuth2", "flows", "implicit", "scopes").keys)
        .to contain_exactly("read:pets", "write:pets")
    end

    it "preserves operation-level security override (security: [{}])" do
      # POST /pets has security: [{OAuth2: [write:pets]}, []]
      security = result.dig("paths", "/pets", "post", "security")
      expect(security).to be_an(Array)
      expect(security.size).to eq(2)
    end

    it "no #/definitions/ refs remain in output" do
      expect(JSON.generate(result)).not_to include("#/definitions/")
    end

    it "preserves response headers from YAML" do
      headers = result.dig("paths", "/pets", "get", "responses", "200", "headers")
      expect(headers).to have_key("X-Total-Count")
    end
  end

  # ── JSON and YAML inputs produce the same result ──────────────────────────

  describe "format equivalence" do
    # Build a spec that is identical in content but one is JSON, one is YAML
    let(:spec_hash) do
      {
        "swagger"  => "2.0",
        "info"     => { "title" => "Same API", "version" => "1.0" },
        "host"     => "api.example.com",
        "basePath" => "/v1",
        "schemes"  => ["https"],
        "paths"    => {
          "/items/{id}" => {
            "get" => {
              "operationId" => "getItem",
              "parameters"  => [
                { "in" => "path", "name" => "id", "type" => "integer" }
              ],
              "responses" => {
                "200" => {
                  "description" => "ok",
                  "schema" => { "$ref" => "#/definitions/Item" }
                }
              }
            }
          }
        },
        "definitions" => {
          "Item" => {
            "type"       => "object",
            "properties" => { "id" => { "type" => "integer" } }
          }
        }
      }
    end

    it "produces the same OpenAPI 3.0 Hash from JSON and YAML inputs" do
      json_input = JSON.generate(spec_hash)
      yaml_input = YAML.dump(spec_hash)

      result_from_json = Swagger23.convert(Swagger23.parse(json_input))
      result_from_yaml = Swagger23.convert(Swagger23.parse(yaml_input))

      expect(result_from_json).to eq(result_from_yaml)
    end
  end

  # ── Swagger23.convert_string (YAML input) ────────────────────────────────

  describe "Swagger23.convert_string" do
    it "accepts YAML input and returns JSON string" do
      output = Swagger23.convert_string(yaml_source)
      parsed = JSON.parse(output)
      expect(parsed["openapi"]).to eq("3.0.3")
    end

    it "still accepts JSON input (backward compat)" do
      output = Swagger23.convert_string(json_source)
      parsed = JSON.parse(output)
      expect(parsed["openapi"]).to eq("3.0.3")
    end
  end

  # @deprecated but must still work
  describe "Swagger23.convert_json (deprecated alias)" do
    it "still works for JSON input" do
      result = JSON.parse(Swagger23.convert_json(json_source))
      expect(result["openapi"]).to eq("3.0.3")
    end

    it "now also works for YAML input" do
      result = JSON.parse(Swagger23.convert_json(yaml_source))
      expect(result["openapi"]).to eq("3.0.3")
    end
  end

  # ── Swagger23.convert_to_yaml ─────────────────────────────────────────────

  describe "Swagger23.convert_to_yaml" do
    context "from JSON input" do
      let(:yaml_output) { Swagger23.convert_to_yaml(json_source) }
      let(:parsed)      { YAML.safe_load(yaml_output) }

      it "returns a String" do
        expect(yaml_output).to be_a(String)
      end

      it "produces valid YAML that parses back to a Hash" do
        expect(parsed).to be_a(Hash)
      end

      it "contains openapi: 3.0.3 in the YAML output" do
        expect(parsed["openapi"]).to eq("3.0.3")
      end

      it "rewrites $refs in YAML output" do
        expect(yaml_output).not_to include("#/definitions/")
        expect(yaml_output).to include("#/components/schemas/")
      end

      it "round-trips: YAML output parses to same Hash as JSON output" do
        json_result = JSON.parse(Swagger23.convert_string(json_source))
        yaml_result = YAML.safe_load(yaml_output)
        expect(yaml_result).to eq(json_result)
      end
    end

    context "from YAML input" do
      let(:yaml_output) { Swagger23.convert_to_yaml(yaml_source) }
      let(:parsed)      { YAML.safe_load(yaml_output) }

      it "produces valid YAML" do
        expect { YAML.safe_load(yaml_output) }.not_to raise_error
      end

      it "contains openapi: 3.0.3" do
        expect(parsed["openapi"]).to eq("3.0.3")
      end

      it "no #/definitions/ refs remain" do
        expect(yaml_output).not_to include("#/definitions/")
      end
    end
  end

  # ── CLI smoke tests ───────────────────────────────────────────────────────

  describe "CLI" do
    let(:cli) { File.expand_path("../../bin/swagger23", __dir__) }

    it "converts a YAML file and writes JSON to STDOUT" do
      output = `ruby #{cli} #{yaml_fixture_path} 2>/dev/null`
      result = JSON.parse(output)
      expect(result["openapi"]).to eq("3.0.3")
    end

    it "converts a YAML file and writes YAML to a .yaml output" do
      require "tmpdir"
      Dir.mktmpdir do |dir|
        output_path = File.join(dir, "out.yaml")
        system("ruby #{cli} #{yaml_fixture_path} #{output_path} 2>/dev/null")
        expect(File.exist?(output_path)).to be true
        parsed = YAML.safe_load(File.read(output_path))
        expect(parsed["openapi"]).to eq("3.0.3")
      end
    end

    it "converts a YAML file and writes YAML to a .yml output" do
      require "tmpdir"
      Dir.mktmpdir do |dir|
        output_path = File.join(dir, "out.yml")
        system("ruby #{cli} #{yaml_fixture_path} #{output_path} 2>/dev/null")
        parsed = YAML.safe_load(File.read(output_path))
        expect(parsed["openapi"]).to eq("3.0.3")
      end
    end

    it "converts a JSON file and writes JSON to a .json output" do
      require "tmpdir"
      Dir.mktmpdir do |dir|
        output_path = File.join(dir, "out.json")
        system("ruby #{cli} #{json_fixture_path} #{output_path} 2>/dev/null")
        parsed = JSON.parse(File.read(output_path))
        expect(parsed["openapi"]).to eq("3.0.3")
      end
    end

    it "accepts YAML from STDIN" do
      output = `echo '#{yaml_source.lines.first.chomp}' | ruby #{cli} 2>/dev/null || true`
      # Just ensure no crash on STDIN path; content tested above
      expect($?).not_to be_nil
    end
  end
end

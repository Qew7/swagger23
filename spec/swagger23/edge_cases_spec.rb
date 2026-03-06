# frozen_string_literal: true

require "spec_helper"

# Comprehensive edge-case tests.
# Each group targets one specific tricky conversion scenario that is likely to
# appear in real-world Swagger 2.0 documents but is easy to get wrong.
RSpec.describe "Edge cases" do
  def base
    {
      "swagger"  => "2.0",
      "info"     => { "title" => "T", "version" => "1" },
      "host"     => "api.example.com",
      "basePath" => "/v1",
      "schemes"  => ["https"],
      "paths"    => {}
    }
  end

  def convert(doc)
    Swagger23.convert(doc)
  end

  # ── 1. Schema-level type system ─────────────────────────────────────────────

  describe "x-nullable → nullable" do
    it "converts x-nullable: true on a definition property" do
      doc = base.merge("definitions" => {
        "User" => {
          "type"       => "object",
          "properties" => {
            "nickname" => { "type" => "string", "x-nullable" => true }
          }
        }
      })
      prop = convert(doc).dig("components", "schemas", "User", "properties", "nickname")
      expect(prop["nullable"]).to be true
      expect(prop).not_to have_key("x-nullable")
    end

    it "converts x-nullable on a top-level schema" do
      doc = base.merge("definitions" => {
        "MaybeString" => { "type" => "string", "x-nullable" => true }
      })
      schema = convert(doc).dig("components", "schemas", "MaybeString")
      expect(schema["nullable"]).to be true
      expect(schema).not_to have_key("x-nullable")
    end

    it "converts x-nullable: false (keeps the false value)" do
      doc = base.merge("definitions" => {
        "Strict" => { "type" => "string", "x-nullable" => false }
      })
      schema = convert(doc).dig("components", "schemas", "Strict")
      expect(schema["nullable"]).to be false
      expect(schema).not_to have_key("x-nullable")
    end

    it "does not overwrite an existing explicit nullable value" do
      doc = base.merge("definitions" => {
        "X" => { "type" => "string", "nullable" => false, "x-nullable" => true }
      })
      schema = convert(doc).dig("components", "schemas", "X")
      expect(schema["nullable"]).to be false  # existing value wins
    end

    it "converts x-nullable inside request body schema" do
      doc = base.merge(
        "consumes" => ["application/json"],
        "paths" => {
          "/x" => { "post" => {
            "parameters" => [{
              "in" => "body", "name" => "b",
              "schema" => { "type" => "string", "x-nullable" => true }
            }],
            "responses" => { "200" => { "description" => "ok" } }
          }}
        }
      )
      schema = convert(doc).dig("paths", "/x", "post", "requestBody",
                                "content", "application/json", "schema")
      expect(schema["nullable"]).to be true
    end
  end

  describe "discriminator: string → {propertyName: string}" do
    it "converts discriminator at definition level" do
      doc = base.merge("definitions" => {
        "Animal" => {
          "type"          => "object",
          "discriminator" => "animalType",
          "properties"    => { "animalType" => { "type" => "string" } }
        }
      })
      disc = convert(doc).dig("components", "schemas", "Animal", "discriminator")
      expect(disc).to eq("propertyName" => "animalType")
    end

    it "leaves a discriminator that is already an object unchanged" do
      doc = base.merge("definitions" => {
        "Animal" => {
          "type"          => "object",
          "discriminator" => { "propertyName" => "animalType" },
          "properties"    => { "animalType" => { "type" => "string" } }
        }
      })
      disc = convert(doc).dig("components", "schemas", "Animal", "discriminator")
      expect(disc).to eq("propertyName" => "animalType")
    end

    it "converts discriminator inside allOf branch" do
      doc = base.merge("definitions" => {
        "Base" => {
          "allOf" => [
            {
              "type"          => "object",
              "discriminator" => "kind",
              "properties"    => { "kind" => { "type" => "string" } }
            }
          ]
        }
      })
      disc = convert(doc).dig("components", "schemas", "Base", "allOf", 0, "discriminator")
      expect(disc).to eq("propertyName" => "kind")
    end
  end

  describe "type: [T, null] array → type: T + nullable: true" do
    it "converts [string, null]" do
      doc = base.merge("definitions" => {
        "X" => { "type" => ["string", "null"] }
      })
      schema = convert(doc).dig("components", "schemas", "X")
      expect(schema["type"]).to eq("string")
      expect(schema["nullable"]).to be true
    end

    it "converts [null, integer] (null first)" do
      doc = base.merge("definitions" => {
        "X" => { "type" => ["null", "integer"] }
      })
      schema = convert(doc).dig("components", "schemas", "X")
      expect(schema["type"]).to eq("integer")
      expect(schema["nullable"]).to be true
    end

    it "converts [string] (single-element array, no null)" do
      doc = base.merge("definitions" => {
        "X" => { "type" => ["string"] }
      })
      schema = convert(doc).dig("components", "schemas", "X")
      expect(schema["type"]).to eq("string")
      expect(schema.key?("nullable")).to be false
    end

    it "leaves [string, integer] (union without null) as-is" do
      doc = base.merge("definitions" => {
        "X" => { "type" => ["string", "integer"] }
      })
      schema = convert(doc).dig("components", "schemas", "X")
      expect(schema["type"]).to eq(["string", "integer"])
    end

    it "handles type: [null] — removes type and sets nullable" do
      doc = base.merge("definitions" => {
        "X" => { "type" => ["null"] }
      })
      schema = convert(doc).dig("components", "schemas", "X")
      expect(schema.key?("type")).to be false
      expect(schema["nullable"]).to be true
    end
  end

  # ── 2. Path parameter edge cases ─────────────────────────────────────────

  describe "path parameters" do
    it "auto-injects required: true even when absent in source" do
      doc = base.merge("paths" => {
        "/items/{id}" => {
          "get" => {
            "parameters" => [
              { "in" => "path", "name" => "id", "type" => "string" }
              # NOTE: required is intentionally omitted
            ],
            "responses" => { "200" => { "description" => "ok" } }
          }
        }
      })
      param = convert(doc).dig("paths", "/items/{id}", "get", "parameters", 0)
      expect(param["required"]).to be true
    end

    it "keeps required: true when already present" do
      doc = base.merge("paths" => {
        "/items/{id}" => {
          "get" => {
            "parameters" => [
              { "in" => "path", "name" => "id", "required" => true, "type" => "string" }
            ],
            "responses" => { "200" => { "description" => "ok" } }
          }
        }
      })
      param = convert(doc).dig("paths", "/items/{id}", "get", "parameters", 0)
      expect(param["required"]).to be true
    end

    it "does not force required on query params" do
      doc = base.merge("paths" => {
        "/items" => {
          "get" => {
            "parameters" => [
              { "in" => "query", "name" => "filter", "type" => "string" }
            ],
            "responses" => { "200" => { "description" => "ok" } }
          }
        }
      })
      param = convert(doc).dig("paths", "/items", "get", "parameters", 0)
      expect(param.key?("required")).to be false
    end

    it "auto-injects required on path-level parameter" do
      doc = base.merge("paths" => {
        "/items/{id}" => {
          "parameters" => [
            { "in" => "path", "name" => "id", "type" => "string" }
          ],
          "get" => { "responses" => { "200" => { "description" => "ok" } } }
        }
      })
      param = convert(doc).dig("paths", "/items/{id}", "parameters", 0)
      expect(param["required"]).to be true
    end
  end

  describe "path item with $ref" do
    it "passes through a $ref path item without losing the reference" do
      doc = base.merge("paths" => {
        "/shared" => { "$ref" => "#/x-path-items/shared" }
      })
      path_item = convert(doc).dig("paths", "/shared")
      expect(path_item["$ref"]).to eq("#/x-path-items/shared")
    end
  end

  # ── 3. Response edge cases ───────────────────────────────────────────────

  describe "'default' response code" do
    it "preserves 'default' as response key" do
      doc = base.merge("paths" => {
        "/x" => { "get" => {
          "produces"  => ["application/json"],
          "responses" => {
            "200"     => { "description" => "ok" },
            "default" => { "description" => "Unexpected error",
                           "schema" => { "type" => "object" } }
          }
        }}
      })
      result = convert(doc)
      expect(result.dig("paths", "/x", "get", "responses")).to have_key("default")
    end

    it "wraps default response schema in content" do
      doc = base.merge("paths" => {
        "/x" => { "get" => {
          "produces"  => ["application/json"],
          "responses" => {
            "default" => { "description" => "Error",
                           "schema" => { "$ref" => "#/definitions/Error" } }
          }
        }}
      }, "definitions" => { "Error" => { "type" => "object" } })
      content = convert(doc).dig("paths", "/x", "get", "responses", "default", "content")
      expect(content.keys).to eq(["application/json"])
    end
  end

  describe "integer response codes" do
    it "converts integer response code to string" do
      doc = base.merge("paths" => {
        "/x" => { "get" => {
          "responses" => { 200 => { "description" => "ok" } }
        }}
      })
      responses = convert(doc).dig("paths", "/x", "get", "responses")
      expect(responses.keys).to include("200")
      expect(responses.keys).not_to include(200)
    end
  end

  describe "response without description" do
    it "defaults description to empty string" do
      doc = base.merge("paths" => {
        "/x" => { "get" => {
          "responses" => { "200" => { "schema" => { "type" => "object" } } }
        }}
      })
      desc = convert(doc).dig("paths", "/x", "get", "responses", "200", "description")
      expect(desc).to eq("")
    end
  end

  describe "$ref-only response in operation" do
    it "passes $ref response through and rewrites it" do
      doc = base.merge(
        "responses" => { "NotFound" => { "description" => "Not found" } },
        "paths" => {
          "/x" => { "get" => {
            "responses" => { "404" => { "$ref" => "#/responses/NotFound" } }
          }}
        }
      )
      ref = convert(doc).dig("paths", "/x", "get", "responses", "404", "$ref")
      expect(ref).to eq("#/components/responses/NotFound")
    end
  end

  # ── 4. Security edge cases ──────────────────────────────────────────────

  describe "security: [] (no-auth override)" do
    it "preserves empty security array on operation (disables global security)" do
      doc = base.merge(
        "security" => [{ "ApiKey" => [] }],
        "securityDefinitions" => {
          "ApiKey" => { "type" => "apiKey", "name" => "X-Key", "in" => "header" }
        },
        "paths" => {
          "/public" => { "get" => {
            "security"  => [],      # explicitly public endpoint
            "responses" => { "200" => { "description" => "ok" } }
          }}
        }
      )
      security = convert(doc).dig("paths", "/public", "get", "security")
      expect(security).to eq([])   # must not be nil or absent
    end
  end

  describe "multiple security requirements (AND / OR)" do
    it "preserves AND-joined requirements as separate objects in array" do
      doc = base.merge(
        "security" => [
          { "ApiKey" => [], "OAuth" => ["read"] }  # AND
        ],
        "securityDefinitions" => {
          "ApiKey" => { "type" => "apiKey", "name" => "k", "in" => "header" },
          "OAuth"  => { "type" => "oauth2", "flow" => "implicit",
                        "authorizationUrl" => "https://a.example.com/", "scopes" => { "read" => "r" } }
        }
      )
      result = convert(doc)
      expect(result["security"].first.keys).to contain_exactly("ApiKey", "OAuth")
    end

    it "preserves OR-joined requirements as separate array elements" do
      doc = base.merge(
        "security" => [
          { "ApiKey" => [] },
          { "OAuth"  => ["read"] }   # OR
        ],
        "securityDefinitions" => {
          "ApiKey" => { "type" => "apiKey", "name" => "k", "in" => "header" },
          "OAuth"  => { "type" => "oauth2", "flow" => "implicit",
                        "authorizationUrl" => "https://a.example.com/", "scopes" => { "read" => "r" } }
        }
      )
      security = convert(doc)["security"]
      expect(security.size).to eq(2)
      expect(security.map(&:keys).flatten).to contain_exactly("ApiKey", "OAuth")
    end
  end

  # ── 5. Content negotiation edge cases ───────────────────────────────────

  describe "non-JSON produces (text/csv, application/pdf)" do
    it "uses non-JSON mime as content key" do
      doc = base.merge("paths" => {
        "/report" => { "get" => {
          "produces"  => ["text/csv"],
          "responses" => { "200" => { "description" => "CSV data",
                                      "schema" => { "type" => "string" } } }
        }}
      })
      content = convert(doc).dig("paths", "/report", "get", "responses", "200", "content")
      expect(content.keys).to eq(["text/csv"])
    end

    it "creates multiple content entries for multiple produces" do
      doc = base.merge("paths" => {
        "/data" => { "get" => {
          "produces"  => ["application/json", "application/xml"],
          "responses" => { "200" => { "description" => "ok",
                                      "schema" => { "type" => "object" } } }
        }}
      })
      content = convert(doc).dig("paths", "/data", "get", "responses", "200", "content")
      expect(content.keys).to contain_exactly("application/json", "application/xml")
    end
  end

  describe "operation with consumes: [] falls back to global" do
    it "uses global consumes when operation has empty array" do
      doc = base.merge(
        "consumes" => ["application/json"],
        "paths" => {
          "/x" => { "post" => {
            "consumes"   => [],   # explicitly empty → fall back
            "parameters" => [{ "in" => "body", "name" => "b",
                               "schema" => { "type" => "object" } }],
            "responses"  => { "200" => { "description" => "ok" } }
          }}
        }
      )
      content = convert(doc).dig("paths", "/x", "post", "requestBody", "content")
      expect(content.keys).to eq(["application/json"])
    end
  end

  describe "no consumes/produces anywhere → defaults to application/json" do
    it "falls back to application/json for requestBody" do
      doc = base.merge("paths" => {
        "/x" => { "post" => {
          "parameters" => [{ "in" => "body", "name" => "b",
                             "schema" => { "type" => "object" } }],
          "responses"  => { "200" => { "description" => "ok" } }
        }}
      })
      content = convert(doc).dig("paths", "/x", "post", "requestBody", "content")
      expect(content.keys).to eq(["application/json"])
    end

    it "falls back to application/json for response content" do
      doc = base.merge("paths" => {
        "/x" => { "get" => {
          "responses" => { "200" => { "description" => "ok",
                                      "schema" => { "type" => "object" } } }
        }}
      })
      content = convert(doc).dig("paths", "/x", "get", "responses", "200", "content")
      expect(content.keys).to eq(["application/json"])
    end
  end

  # ── 6. Schema composition edge cases ─────────────────────────────────────

  describe "self-referential (recursive) schema" do
    it "does not infinite-loop and rewrites $ref" do
      doc = base.merge("definitions" => {
        "TreeNode" => {
          "type"       => "object",
          "properties" => {
            "value"    => { "type" => "integer" },
            "children" => {
              "type"  => "array",
              "items" => { "$ref" => "#/definitions/TreeNode" }
            }
          }
        }
      })
      expect { convert(doc) }.not_to raise_error
      ref = convert(doc).dig("components", "schemas", "TreeNode",
                             "properties", "children", "items", "$ref")
      expect(ref).to eq("#/components/schemas/TreeNode")
    end
  end

  describe "allOf with only $ref entries" do
    it "preserves all $refs and rewrites them" do
      doc = base.merge("definitions" => {
        "Combined" => {
          "allOf" => [
            { "$ref" => "#/definitions/A" },
            { "$ref" => "#/definitions/B" }
          ]
        },
        "A" => { "type" => "object" },
        "B" => { "type" => "object" }
      })
      all_of = convert(doc).dig("components", "schemas", "Combined", "allOf")
      refs = all_of.map { |i| i["$ref"] }
      expect(refs).to contain_exactly(
        "#/components/schemas/A",
        "#/components/schemas/B"
      )
    end
  end

  describe "anyOf / oneOf passthrough" do
    it "passes anyOf through and rewrites refs" do
      doc = base.merge("definitions" => {
        "Combo" => {
          "anyOf" => [
            { "$ref" => "#/definitions/Cat" },
            { "type" => "object", "properties" => { "tag" => { "type" => "string" } } }
          ]
        },
        "Cat" => { "type" => "object" }
      })
      any_of = convert(doc).dig("components", "schemas", "Combo", "anyOf")
      expect(any_of.first["$ref"]).to eq("#/components/schemas/Cat")
      expect(any_of.last.dig("properties", "tag", "type")).to eq("string")
    end
  end

  describe "additionalProperties" do
    it "passes additionalProperties: false through" do
      doc = base.merge("definitions" => {
        "Strict" => { "type" => "object", "additionalProperties" => false }
      })
      expect(convert(doc).dig("components", "schemas", "Strict", "additionalProperties"))
        .to be false
    end

    it "passes additionalProperties as schema through and rewrites refs" do
      doc = base.merge("definitions" => {
        "Map" => {
          "type"                 => "object",
          "additionalProperties" => { "$ref" => "#/definitions/Value" }
        },
        "Value" => { "type" => "string" }
      })
      ap_ref = convert(doc).dig("components", "schemas", "Map",
                                "additionalProperties", "$ref")
      expect(ap_ref).to eq("#/components/schemas/Value")
    end
  end

  describe "enum values" do
    it "passes enum array through unchanged" do
      doc = base.merge("definitions" => {
        "Status" => { "type" => "string", "enum" => ["active", "inactive", "pending"] }
      })
      enum = convert(doc).dig("components", "schemas", "Status", "enum")
      expect(enum).to eq(["active", "inactive", "pending"])
    end

    it "handles enum with mixed types" do
      doc = base.merge("definitions" => {
        "Mixed" => { "enum" => [1, "two", nil, true] }
      })
      enum = convert(doc).dig("components", "schemas", "Mixed", "enum")
      expect(enum).to eq([1, "two", nil, true])
    end
  end

  # ── 7. Body / formData robustness ────────────────────────────────────────

  describe "body param without schema key" do
    it "creates requestBody with empty schema" do
      doc = base.merge("paths" => {
        "/x" => { "post" => {
          "parameters" => [{ "in" => "body", "name" => "data" }],
          "responses"  => { "200" => { "description" => "ok" } }
        }}
      })
      expect { convert(doc) }.not_to raise_error
      rb = convert(doc).dig("paths", "/x", "post", "requestBody")
      expect(rb).not_to be_nil
    end
  end

  describe "formData param with array type" do
    it "includes items in the property schema" do
      doc = base.merge("paths" => {
        "/x" => { "post" => {
          "consumes"   => ["application/x-www-form-urlencoded"],
          "parameters" => [{
            "in"    => "formData", "name" => "tags",
            "type"  => "array",
            "items" => { "type" => "string" },
            "collectionFormat" => "csv"
          }],
          "responses" => { "200" => { "description" => "ok" } }
        }}
      })
      schema = convert(doc).dig("paths", "/x", "post", "requestBody",
                                "content", "application/x-www-form-urlencoded",
                                "schema", "properties", "tags")
      expect(schema["type"]).to eq("array")
      expect(schema.dig("items", "type")).to eq("string")
    end
  end

  describe "both body and formData parameters present (invalid but real)" do
    it "prefers body over formData without crashing" do
      doc = base.merge("paths" => {
        "/x" => { "post" => {
          "parameters" => [
            { "in" => "body",     "name" => "payload", "schema" => { "type" => "object" } },
            { "in" => "formData", "name" => "extra",   "type"   => "string" }
          ],
          "responses" => { "200" => { "description" => "ok" } }
        }}
      })
      expect { convert(doc) }.not_to raise_error
      # body wins
      rb = convert(doc).dig("paths", "/x", "post", "requestBody", "content",
                            "application/json", "schema")
      expect(rb).not_to be_nil
    end
  end

  # ── 8. Header parameter edge cases ───────────────────────────────────────

  describe "header parameter" do
    it "preserves in: header and moves type to schema" do
      doc = base.merge("paths" => {
        "/x" => { "get" => {
          "parameters" => [
            { "in" => "header", "name" => "X-Tenant-ID", "type" => "string", "required" => true }
          ],
          "responses" => { "200" => { "description" => "ok" } }
        }}
      })
      param = convert(doc).dig("paths", "/x", "get", "parameters", 0)
      expect(param["in"]).to eq("header")
      expect(param.dig("schema", "type")).to eq("string")
    end
  end

  # ── 9. Null / missing optional fields ────────────────────────────────────

  describe "null values in optional fields" do
    it "does not crash when description is null" do
      doc = base.merge("paths" => {
        "/x" => { "get" => {
          "description" => nil,
          "responses"   => { "200" => { "description" => "ok" } }
        }}
      })
      expect { convert(doc) }.not_to raise_error
    end

    it "does not crash when summary is null" do
      doc = base.merge("paths" => {
        "/x" => { "get" => {
          "summary"   => nil,
          "responses" => { "200" => { "description" => "ok" } }
        }}
      })
      expect { convert(doc) }.not_to raise_error
    end

    it "does not crash when tags is null" do
      doc = base.merge("paths" => {
        "/x" => { "get" => {
          "tags"      => nil,
          "responses" => { "200" => { "description" => "ok" } }
        }}
      })
      expect { convert(doc) }.not_to raise_error
    end
  end

  describe "info.version as number" do
    it "does not crash when version is an integer" do
      doc = base.merge("info" => { "title" => "T", "version" => 2 })
      expect { convert(doc) }.not_to raise_error
      expect(convert(doc).dig("info", "version")).to eq(2)
    end
  end

  # ── 10. Extensions on all levels ─────────────────────────────────────────

  describe "x- extension passthrough at all levels" do
    it "preserves extensions on schema properties" do
      doc = base.merge("definitions" => {
        "Model" => {
          "type"       => "object",
          "properties" => { "id" => { "type" => "integer", "x-primary-key" => true } }
        }
      })
      prop = convert(doc).dig("components", "schemas", "Model", "properties", "id")
      expect(prop["x-primary-key"]).to be true
    end

    it "preserves extensions on response" do
      doc = base.merge("paths" => {
        "/x" => { "get" => {
          "responses" => { "200" => { "description" => "ok", "x-cache-ttl" => 300 } }
        }}
      })
      expect(convert(doc).dig("paths", "/x", "get", "responses", "200", "x-cache-ttl")).to eq(300)
    end
  end

  # ── 11. Paths passthrough edge cases ─────────────────────────────────────

  describe "operation with no parameters" do
    it "does not include parameters key when operation has none" do
      doc = base.merge("paths" => {
        "/x" => { "get" => { "responses" => { "200" => { "description" => "ok" } } } }
      })
      op = convert(doc).dig("paths", "/x", "get")
      expect(op).not_to have_key("parameters")
    end
  end

  describe "operation with no responses" do
    it "does not crash when responses key is absent" do
      doc = base.merge("paths" => {
        "/x" => { "get" => { "summary" => "health check" } }
      })
      expect { convert(doc) }.not_to raise_error
    end
  end

  describe "empty paths object" do
    it "produces an empty paths hash" do
      doc = base.merge("paths" => {})
      expect(convert(doc)["paths"]).to eq({})
    end
  end
end

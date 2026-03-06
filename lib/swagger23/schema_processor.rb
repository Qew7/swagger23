# frozen_string_literal: true

module Swagger23
  # Performs schema-level semantic transformations that bridge Swagger 2.0 and
  # OpenAPI 3.0 type systems.  Operates on the already-converted, already
  # $ref-rewritten document (i.e. called after RefRewriter).
  #
  # Transformations applied to every Hash node in the document:
  #
  #   1. x-nullable: true  →  nullable: true   (x-nullable key removed)
  #      Common in Java/Spring Boot codegen, AWS API Gateway exports, and any
  #      tool targeting Swagger 2.0 that needed to express nullability.
  #
  #   2. discriminator: "PropName"  →  discriminator: {propertyName: "PropName"}
  #      Swagger 2.0 uses a bare string; OAS 3.0 uses an object.
  #
  #   3. type: ["SomeType", "null"]  →  type: "SomeType", nullable: true
  #      Several tools (e.g. swagger-codegen from JSON Schema draft 4 sources)
  #      emit an array of types to express nullability.  OAS 3.0 uses nullable.
  #
  # Uses an iterative BFS (same pattern as RefRewriter) to avoid stack overflow
  # on deeply nested documents.
  module SchemaProcessor
    # @param obj [Hash, Array, Object] the already-converted OpenAPI 3.0 tree
    # @return obj mutated in-place
    def self.process(obj)
      queue = [obj]
      until queue.empty?
        current = queue.shift

        case current
        in Hash
          transform!(current)
          current.each_value { |v| queue << v if v in Hash | Array }
        in Array
          current.each { |item| queue << item if item in Hash | Array }
        else
          # scalar or nil — nothing to transform
        end
      end

      obj
    end

    # ---------------------------------------------------------------------------
    # Per-node transformations
    # ---------------------------------------------------------------------------

    def self.transform!(h)
      nullable_from_x_nullable!(h)
      coerce_discriminator!(h)
      unwrap_type_array!(h)
    end

    # x-nullable: true  →  nullable: true
    # If nullable is already explicitly set we respect it and still remove x-nullable.
    def self.nullable_from_x_nullable!(h)
      return unless h.key?("x-nullable")

      h["nullable"] = h["x-nullable"] unless h.key?("nullable")
      h.delete("x-nullable")
    end

    # discriminator: "PropName"  →  discriminator: {propertyName: "PropName"}
    # If discriminator is already an object (already-converted or OAS 3 input), leave it.
    def self.coerce_discriminator!(h)
      return unless h.key?("discriminator") && h["discriminator"].is_a?(String)

      h["discriminator"] = { "propertyName" => h["discriminator"] }
    end

    # type: ["T", "null"]  →  type: "T", nullable: true
    # type: ["T"]          →  type: "T"           (single-element array)
    # type: ["A", "B"]     →  kept as-is          (union of non-null types — no standard mapping)
    def self.unwrap_type_array!(h)
      return unless h.key?("type") && h["type"].is_a?(Array)

      types    = h["type"]
      non_null = types.reject { |t| t == "null" }
      has_null = non_null.size < types.size

      if non_null.size == 1
        h["type"]     = non_null.first
        h["nullable"] = true if has_null
      elsif non_null.empty?
        # type: ["null"] — technically invalid but handle gracefully
        h.delete("type")
        h["nullable"] = true
      end
      # else: multiple non-null types — leave array intact; let the validator surface it
    end
  end
end

# frozen_string_literal: true

module Swagger23
  # Walks any JSON-like structure and rewrites all $ref values so that internal
  # Swagger 2.0 references are mapped to their OpenAPI 3.0 equivalents.
  #
  # Rewrite rules:
  #   #/definitions/Foo        → #/components/schemas/Foo
  #   #/parameters/Foo         → #/components/parameters/Foo
  #   #/responses/Foo          → #/components/responses/Foo
  #   #/securityDefinitions/X  → #/components/securitySchemes/X
  #
  # Implementation note:
  #   Uses an iterative BFS on a JSON deep-clone rather than recursion so that
  #   very large or deeply nested specifications never risk a SystemStackError.
  #   The JSON round-trip (C extension) is the fastest way to deep-clone an
  #   arbitrary JSON-compatible Ruby object and ensures no shared references
  #   with the original swagger document remain.
  module RefRewriter
    REF_MAP = {
      "#/definitions/"         => "#/components/schemas/",
      "#/parameters/"          => "#/components/parameters/",
      "#/responses/"           => "#/components/responses/",
      "#/securityDefinitions/" => "#/components/securitySchemes/"
    }.freeze

    # @param obj [Hash, Array, Object] JSON-compatible Ruby object
    # @return a deep copy of obj with all $ref strings rewritten
    def self.rewrite(obj)
      # Deep-clone via JSON round-trip: fast (C ext), handles shared refs,
      # does not mutate the original document.
      # max_nesting: false disables JSON's default 100-level depth guard —
      # real Swagger specs (e.g. Kubernetes) can have deeply nested allOf/anyOf
      # compositions that exceed that limit.
      clone = JSON.parse(JSON.generate(obj, max_nesting: false), max_nesting: false)

      # Iterative BFS – O(n) in node count, O(max_width) in memory.
      # Mutates the clone in-place; no recursion, no stack pressure.
      queue = [clone]
      until queue.empty?
        current = queue.shift

        case current
        in Hash
          current.each_pair do |key, value|
            case [key, value]
            in ["$ref", String => ref]
              current[key] = rewrite_ref(ref)
            in [_, Hash | Array => nested]
              queue << nested
            else
              # primitive value — nothing to traverse
            end
          end
        in Array
          current.each { |item| queue << item if item in Hash | Array }
        else
          # scalar root (e.g. rewrite(42)) — nothing to do
        end
      end

      clone
    end

    def self.rewrite_ref(ref)
      REF_MAP.each do |from, to|
        return ref.sub(from, to) if ref.start_with?(from)
      end
      ref
    end
  end
end

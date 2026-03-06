# frozen_string_literal: true

require "json"
require_relative "swagger23/version"
require_relative "swagger23/error"
require_relative "swagger23/ref_rewriter"
require_relative "swagger23/schema_processor"
require_relative "swagger23/converters/info"
require_relative "swagger23/converters/servers"
require_relative "swagger23/converters/paths"
require_relative "swagger23/converters/components"
require_relative "swagger23/converters/security"
require_relative "swagger23/converter"

module Swagger23
  # Parse a JSON or YAML string into a Ruby Hash.
  #
  # Detection strategy: inspect the first non-whitespace byte.
  #   '{' or '['  →  JSON  (the only two valid JSON document starters)
  #   anything else  →  YAML
  #
  # This avoids trying to JSON-parse a UTF-8 YAML string, which raises
  # Encoding::InvalidByteSequenceError when the Ruby process is running with
  # an ASCII locale.
  #
  # @param source [String] raw JSON or YAML content
  # @return [Hash] parsed document
  # @raise [Swagger23::Error] if the source cannot be parsed as either format
  def self.parse(source)
    # Ensure we always work with a UTF-8 string regardless of how the caller
    # obtained it (File.read without encoding:, STDIN.read, etc.).
    source = source.dup.force_encoding("UTF-8") unless source.encoding == Encoding::UTF_8

    first = source.lstrip[0]

    if first == "{" || first == "["
      begin
        JSON.parse(source)
      rescue JSON::ParserError => e
        raise Swagger23::Error, "JSON parse error: #{e.message}"
      end
    else
      require "yaml"
      begin
        result = YAML.safe_load(source)
      rescue Psych::SyntaxError => e
        raise Swagger23::Error, "Could not parse input as YAML: #{e.message}"
      end

      if result.nil?
        raise Swagger23::Error, "Could not parse input: document is empty or null"
      end

      unless result.is_a?(Hash)
        raise Swagger23::Error, "Input parsed to #{result.class}, expected a Hash"
      end

      result
    end
  end

  # Convert a Swagger 2.0 Hash to an OpenAPI 3.0 Hash.
  #
  # @param swagger [Hash] parsed Swagger 2.0 document
  # @return [Hash] OpenAPI 3.0 document
  def self.convert(swagger)
    Converter.new(swagger).convert
  end

  # Parse a JSON or YAML string and return the converted OpenAPI 3.0 document
  # as a pretty-printed JSON string.
  #
  # @param source [String] Swagger 2.0 document as JSON or YAML
  # @return [String] OpenAPI 3.0 document as JSON
  def self.convert_string(source)
    JSON.pretty_generate(convert(parse(source)))
  end

  # Parse a JSON or YAML string and return the converted OpenAPI 3.0 document
  # as a YAML string.
  #
  # @param source [String] Swagger 2.0 document as JSON or YAML
  # @return [String] OpenAPI 3.0 document as YAML
  def self.convert_to_yaml(source)
    require "yaml"
    YAML.dump(stringify_keys_deep(convert(parse(source))))
  end

  # @deprecated Use {convert_string} instead (identical behaviour, clearer name).
  def self.convert_json(source)
    convert_string(source)
  end

  # ── Internal helpers ──────────────────────────────────────────────────────

  # YAML.dump can emit symbols as keys if the hash was built with symbol keys.
  # Our converter always uses string keys (coming from JSON.parse), but we
  # normalise just in case a caller passes in a symbolised hash.
  def self.stringify_keys_deep(obj)
    case obj
    in Hash
      obj.each_with_object({}) do |(k, v), h|
        h[k.to_s] = stringify_keys_deep(v)
      end
    in Array
      obj.map { |item| stringify_keys_deep(item) }
    else
      obj
    end
  end
  private_class_method :stringify_keys_deep
end

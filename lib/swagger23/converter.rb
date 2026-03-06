# frozen_string_literal: true

module Swagger23
  # Orchestrates the full Swagger 2.0 → OpenAPI 3.0 conversion.
  #
  # Usage:
  #   swagger_hash = JSON.parse(File.read("petstore.json"))
  #   openapi_hash = Swagger23::Converter.new(swagger_hash).convert
  class Converter
    SUPPORTED_SWAGGER_VERSION = "2.0"
    TARGET_OPENAPI_VERSION    = "3.0.3"

    # @param swagger [Hash] parsed Swagger 2.0 document
    def initialize(swagger)
      @swagger = swagger
    end

    # @return [Hash] OpenAPI 3.0 document
    def convert
      validate!

      result = {}

      result["openapi"] = TARGET_OPENAPI_VERSION
      result["info"]    = Converters::Info.convert(@swagger)
      result["servers"] = Converters::Servers.convert(@swagger)

      # Tags (identical structure between 2.0 and 3.0)
      result["tags"] = @swagger["tags"] if @swagger.key?("tags")

      # External docs (identical)
      result["externalDocs"] = @swagger["externalDocs"] if @swagger.key?("externalDocs")

      # Paths
      result["paths"] = Converters::Paths.convert(@swagger)

      # Components
      components = Converters::Components.convert(@swagger)
      security_schemes = Converters::Security.convert(@swagger)
      components["securitySchemes"] = security_schemes unless security_schemes.empty?

      result["components"] = components unless components.empty?

      # Top-level security requirements (identical structure)
      result["security"] = @swagger["security"] if @swagger.key?("security")

      # Top-level extensions
      @swagger.each do |key, value|
        result[key] = value if key.start_with?("x-")
      end

      # Pass 1: rewrite all $ref values (Swagger 2.0 paths → OpenAPI 3.0 paths)
      rewritten = RefRewriter.rewrite(result)

      # Pass 2: schema-level semantic transformations
      #   x-nullable → nullable, discriminator string → object, type arrays → nullable
      SchemaProcessor.process(rewritten)
    end

    private

    def validate!
      version = @swagger["swagger"]
      return if version.to_s == SUPPORTED_SWAGGER_VERSION

      raise InvalidSwaggerError,
            "Expected swagger version '#{SUPPORTED_SWAGGER_VERSION}', " \
            "got '#{version}'. Only Swagger 2.0 documents are supported."
    end
  end
end

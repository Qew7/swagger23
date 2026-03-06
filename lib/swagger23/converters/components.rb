# frozen_string_literal: true

module Swagger23
  module Converters
    # Converts Swagger 2.0 top-level reusable objects into OpenAPI 3.0
    # `components` section.
    #
    # Mapping:
    #   definitions         → components/schemas
    #   parameters          → components/parameters
    #   responses           → components/responses
    #   securityDefinitions → components/securitySchemes  (see Security converter)
    module Components
      def self.convert(swagger)
        components = {}

        if (definitions = swagger["definitions"])
          components["schemas"] = definitions
        end

        if (parameters = swagger["parameters"])
          converted_params = {}
          parameters.each do |name, param|
            converted_params[name] = Paths.convert_parameter(param)
          end
          components["parameters"] = converted_params
        end

        if (responses = swagger["responses"])
          converted_responses = {}
          responses.each do |name, resp|
            converted_responses[name] = convert_response(resp, swagger)
          end
          components["responses"] = converted_responses
        end

        components
      end

      # Convert a single Swagger 2.0 response object to OpenAPI 3.0 format.
      def self.convert_response(resp, swagger)
        result = {}
        result["description"] = resp["description"] if resp["description"]

        if (schema = resp["schema"])
          produces = swagger["produces"] || ["application/json"]
          content  = {}
          produces.each do |mime|
            content[mime] = { "schema" => schema }
          end
          result["content"] = content
        end

        if (headers = resp["headers"])
          converted_headers = {}
          headers.each do |name, header|
            h = header.dup
            h.delete("name")
            h.delete("in")
            converted_headers[name] = h
          end
          result["headers"] = converted_headers
        end

        # pass through extensions
        resp.each do |key, value|
          result[key] = value if key.start_with?("x-")
        end

        result
      end
    end
  end
end

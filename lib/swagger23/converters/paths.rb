# frozen_string_literal: true

module Swagger23
  module Converters
    # Converts Swagger 2.0 `paths` to OpenAPI 3.0 `paths`.
    #
    # Key transformations per operation:
    #   - `in: body` parameter          → requestBody
    #   - `in: formData` parameters     → requestBody (form-encoded or multipart)
    #   - `consumes` / `produces`       → content-type keys in requestBody / responses
    #   - response `schema`             → response.content[mime].schema
    #   - response headers              → response.headers (simplified)
    #   - all other parameters unchanged (path, query, header, cookie)
    module Paths
      HTTP_METHODS = %w[get put post delete options head patch trace].freeze

      # @param swagger [Hash] the full Swagger 2.0 document (needed for global consumes/produces)
      def self.convert(swagger)
        paths = swagger["paths"] || {}
        global_consumes = Array(swagger["consumes"])
        global_produces = Array(swagger["produces"])

        converted = {}
        paths.each do |path, path_item|
          converted[path] = convert_path_item(path_item, global_consumes, global_produces)
        end
        converted
      end

      # -------------------------------------------------------------------------
      # Path item
      # -------------------------------------------------------------------------

      def self.convert_path_item(path_item, global_consumes, global_produces)
        # Swagger 2.0 allows a $ref at path-item level (e.g. to share path items).
        # Pass it through; RefRewriter will rewrite the ref if it matches a known prefix.
        return path_item.dup if path_item.key?("$ref")

        result = {}

        # Path-level parameters (non-operation)
        if (params = path_item["parameters"])
          result["parameters"] = params.map { |p| convert_parameter(p) }
        end

        # Copy path-level extensions
        path_item.each do |key, value|
          result[key] = value if key.start_with?("x-")
        end

        HTTP_METHODS.each do |method|
          next unless path_item.key?(method)

          result[method] = convert_operation(
            path_item[method],
            global_consumes,
            global_produces
          )
        end

        result
      end

      # -------------------------------------------------------------------------
      # Operation
      # -------------------------------------------------------------------------

      def self.convert_operation(op, global_consumes, global_produces)
        result = {}

        # Passthrough scalar fields
        %w[summary description operationId deprecated tags externalDocs].each do |field|
          result[field] = op[field] if op.key?(field)
        end

        # Security
        result["security"] = op["security"] if op.key?("security")

        # Extensions
        op.each { |k, v| result[k] = v if k.start_with?("x-") }

        # Effective consumes / produces for this operation
        op_consumes = Array(op["consumes"]).then { |a| a.empty? ? global_consumes : a }
        op_produces = Array(op["produces"]).then { |a| a.empty? ? global_produces : a }

        # Default mime types when none specified
        op_consumes = ["application/json"] if op_consumes.empty?
        op_produces = ["application/json"] if op_produces.empty?

        # Split parameters
        all_params   = Array(op["parameters"])
        body_param   = all_params.find { |p| p["in"] == "body" }
        form_params  = all_params.select { |p| p["in"] == "formData" }
        other_params = all_params.reject { |p| %w[body formData].include?(p["in"]) }

        # Regular parameters (path / query / header / cookie)
        unless other_params.empty?
          result["parameters"] = other_params.map { |p| convert_parameter(p) }
        end

        # requestBody from body parameter
        if body_param
          result["requestBody"] = build_request_body_from_body_param(body_param, op_consumes)
        elsif !form_params.empty?
          result["requestBody"] = build_request_body_from_form_params(form_params, op_consumes)
        end

        # responses
        if (responses = op["responses"])
          result["responses"] = convert_responses(responses, op_produces)
        end

        # callbacks – not present in Swagger 2.0, skip
        result
      end

      # -------------------------------------------------------------------------
      # Parameters
      # -------------------------------------------------------------------------

      # Convert a single non-body/formData parameter.
      def self.convert_parameter(param)
        return param if param.key?("$ref")

        result = {}
        %w[name in description required deprecated allowEmptyValue].each do |field|
          result[field] = param[field] if param.key?(field)
        end

        # OAS 3.0 §4.8.12.1: path parameters MUST have required: true.
        # Swagger 2.0 technically requires it too, but many real specs omit it.
        result["required"] = true if result["in"] == "path"

        # `collectionFormat` → `style` + `explode`
        if (schema = build_param_schema(param))
          result["schema"] = schema
        end

        # Extensions
        param.each { |k, v| result[k] = v if k.start_with?("x-") }

        result
      end

      # Build the schema for a parameter from its inline type/format/etc.
      def self.build_param_schema(param)
        # If there's already a nested schema object use it
        return param["schema"] if param.key?("schema")

        schema = {}
        %w[type format default enum minimum maximum minLength maxLength
           pattern items uniqueItems collectionFormat].each do |field|
          schema[field] = param[field] if param.key?(field)
        end

        # collectionFormat → style
        if (collection_format = schema.delete("collectionFormat"))
          case collection_format
          when "csv"   then schema["style"] = "form";   schema["explode"] = false
          when "ssv"   then schema["style"] = "spaceDelimited"
          when "tsv"   then schema["style"] = "tabDelimited"
          when "pipes" then schema["style"] = "pipeDelimited"
          when "multi" then schema["style"] = "form";   schema["explode"] = true
          end
        end

        schema.empty? ? nil : schema
      end

      # -------------------------------------------------------------------------
      # requestBody helpers
      # -------------------------------------------------------------------------

      def self.build_request_body_from_body_param(body_param, consumes)
        schema  = body_param["schema"] || {}
        content = {}

        consumes.each do |mime|
          content[mime] = { "schema" => schema }
        end

        result = { "content" => content }
        result["description"] = body_param["description"] if body_param["description"]
        result["required"]    = body_param["required"]    if body_param.key?("required")
        result
      end

      def self.build_request_body_from_form_params(form_params, consumes)
        properties = {}
        required   = []

        form_params.each do |param|
          name   = param["name"]
          schema = build_param_schema(param) || {}

          # file upload → binary string
          if param["type"] == "file"
            schema = { "type" => "string", "format" => "binary" }
          end

          schema["description"] = param["description"] if param["description"]
          properties[name] = schema
          required << name if param["required"]
        end

        form_schema = { "type" => "object", "properties" => properties }
        form_schema["required"] = required unless required.empty?

        # Decide content-type: multipart/form-data if any file uploads
        has_file = form_params.any? { |p| p["type"] == "file" }
        mime     = has_file ? "multipart/form-data" : "application/x-www-form-urlencoded"

        # If the operation already declares an explicit form mime, honour it
        explicit = consumes.find { |c| c =~ /multipart|form-urlencoded/ }
        mime     = explicit || mime

        { "content" => { mime => { "schema" => form_schema } } }
      end

      # -------------------------------------------------------------------------
      # Responses
      # -------------------------------------------------------------------------

      def self.convert_responses(responses, produces)
        result = {}
        responses.each do |status, response|
          result[status.to_s] = convert_response(response, produces)
        end
        result
      end

      def self.convert_response(response, produces)
        return response if response.key?("$ref")

        result = {}
        result["description"] = response["description"] || ""

        # schema → content
        if (schema = response["schema"])
          content = {}
          produces.each do |mime|
            content[mime] = { "schema" => schema }
          end
          result["content"] = content
        end

        # headers
        if (headers = response["headers"])
          converted = {}
          headers.each do |name, header|
            h = {}
            %w[description type format].each { |f| h[f] = header[f] if header.key?(f) }
            converted[name] = h
          end
          result["headers"] = converted
        end

        # extensions
        response.each { |k, v| result[k] = v if k.start_with?("x-") }

        result
      end
    end

    # Alias used by Components converter for shared parameter conversion
    ParameterConverter = Paths
  end
end

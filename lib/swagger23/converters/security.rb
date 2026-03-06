# frozen_string_literal: true

module Swagger23
  module Converters
    # Converts Swagger 2.0 `securityDefinitions` to OpenAPI 3.0
    # `components/securitySchemes`.
    #
    # Swagger 2.0 types and their OpenAPI 3.0 equivalents:
    #
    #   basic           → http / scheme: basic
    #   apiKey          → apiKey (identical structure)
    #   oauth2 implicit → oauth2 / flows.implicit
    #   oauth2 password → oauth2 / flows.password
    #   oauth2 application → oauth2 / flows.clientCredentials
    #   oauth2 accessCode  → oauth2 / flows.authorizationCode
    module Security
      def self.convert(swagger)
        defs = swagger["securityDefinitions"]
        return {} unless defs

        schemes = {}
        defs.each do |name, definition|
          schemes[name] = convert_scheme(definition)
        end
        schemes
      end

      def self.convert_scheme(defn)
        type = defn["type"]

        case type
        when "basic"
          result = { "type" => "http", "scheme" => "basic" }
          result["description"] = defn["description"] if defn["description"]
          add_extensions(result, defn)
          result

        when "apiKey"
          result = {
            "type" => "apiKey",
            "name" => defn["name"],
            "in"   => defn["in"]
          }
          result["description"] = defn["description"] if defn["description"]
          add_extensions(result, defn)
          result

        when "oauth2"
          convert_oauth2(defn)

        else
          # Unknown type – pass through as-is with extensions
          result = defn.dup
          result
        end
      end

      def self.convert_oauth2(defn)
        flow_name = defn["flow"]
        result = { "type" => "oauth2" }
        result["description"] = defn["description"] if defn["description"]

        scopes         = defn["scopes"] || {}
        auth_url       = defn["authorizationUrl"]
        token_url      = defn["tokenUrl"]

        flow = {}
        flow["scopes"] = scopes

        case flow_name
        when "implicit"
          flow["authorizationUrl"] = auth_url
          result["flows"] = { "implicit" => flow }
        when "password"
          flow["tokenUrl"] = token_url
          result["flows"] = { "password" => flow }
        when "application"
          flow["tokenUrl"] = token_url
          result["flows"] = { "clientCredentials" => flow }
        when "accessCode"
          flow["authorizationUrl"] = auth_url
          flow["tokenUrl"]         = token_url
          result["flows"] = { "authorizationCode" => flow }
        else
          result["flows"] = {}
        end

        add_extensions(result, defn)
        result
      end

      def self.add_extensions(result, defn)
        defn.each do |key, value|
          result[key] = value if key.start_with?("x-")
        end
      end
    end
  end
end

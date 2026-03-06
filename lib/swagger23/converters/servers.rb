# frozen_string_literal: true

module Swagger23
  module Converters
    # Converts Swagger 2.0 `host` + `basePath` + `schemes` into an OpenAPI 3.0
    # `servers` array.
    #
    # Swagger 2.0 fields used:
    #   host      – e.g. "api.example.com" or "api.example.com:8080"
    #   basePath  – e.g. "/v2"
    #   schemes   – e.g. ["https", "http"]
    #
    # OpenAPI 3.0 result:
    #   servers:
    #     - url: https://api.example.com/v2
    #     - url: http://api.example.com/v2
    module Servers
      DEFAULT_HOST     = "localhost"
      DEFAULT_BASEPATH = "/"

      def self.convert(swagger)
        host      = swagger["host"]     || DEFAULT_HOST
        base_path = swagger["basePath"] || DEFAULT_BASEPATH
        schemes   = Array(swagger["schemes"])

        base_path = "/#{base_path}" unless base_path.start_with?("/")

        # When no schemes are provided, default to https and use the actual host.
        effective_schemes = schemes.empty? ? ["https"] : schemes

        effective_schemes.map do |scheme|
          { "url" => "#{scheme}://#{host}#{base_path}" }
        end
      end
    end
  end
end

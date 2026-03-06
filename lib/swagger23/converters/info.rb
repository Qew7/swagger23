# frozen_string_literal: true

module Swagger23
  module Converters
    # Converts the top-level `info` object.
    # The structure is identical between Swagger 2.0 and OpenAPI 3.0,
    # so this is essentially a deep-copy with no structural changes.
    module Info
      def self.convert(swagger)
        info = swagger["info"] || {}
        # Pass through all known and extension fields as-is
        info.dup
      end
    end
  end
end

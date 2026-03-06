# frozen_string_literal: true

module Swagger23
  class Error < StandardError; end

  # Raised when the input document is not a valid Swagger 2.0 document.
  class InvalidSwaggerError < Error; end
end

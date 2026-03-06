# frozen_string_literal: true

require_relative "lib/swagger23/version"

Gem::Specification.new do |spec|
  spec.name          = "swagger23"
  spec.version       = Swagger23::VERSION
  spec.authors       = ["Maxim Veysgeym"]
  spec.email         = []
  spec.summary       = "Convert Swagger 2.0 to OpenAPI 3.0 — Ruby library and CLI"
  spec.description   = <<~DESC
    swagger23 converts Swagger 2.0 (OAS 2) API specifications into OpenAPI 3.0.3 (OAS 3)
    specifications. Accepts JSON or YAML input, produces JSON or YAML output.
    Works as a Ruby library (Swagger23.convert) or a standalone CLI tool (swagger23).
    Handles paths, parameters, requestBody, components/schemas, securitySchemes,
    servers, $ref rewriting, collectionFormat, x-nullable, discriminator, OAuth2 flows,
    and file uploads. No external runtime dependencies. Safe for large specs.
  DESC
  spec.license       = "MIT"
  spec.homepage      = "https://github.com/Qew7/swagger23"

  spec.metadata = {
    "homepage_uri"      => spec.homepage,
    "source_code_uri"   => spec.homepage,
    "bug_tracker_uri"   => "#{spec.homepage}/issues",
    "documentation_uri" => "#{spec.homepage}/blob/main/README.md"
  }

  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir[
    "lib/**/*.rb",
    "sig/**/*.rbs",
    "bin/*",
    "swagger23.gemspec",
    "README.md",
    "LICENSE"
  ]

  spec.bindir        = "bin"
  spec.executables   = ["swagger23"]
  spec.require_paths = ["lib"]

  spec.add_dependency "json",       ">= 2.0"

  spec.add_development_dependency "rspec",     "~> 3.12"
  spec.add_development_dependency "rake",      "~> 13.0"
end

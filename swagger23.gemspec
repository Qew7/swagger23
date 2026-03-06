# frozen_string_literal: true

require_relative "lib/swagger23/version"

Gem::Specification.new do |spec|
  spec.name          = "swagger23"
  spec.version       = Swagger23::VERSION
  spec.authors       = ["Maxim Veysgeym"]
  spec.email         = []
  spec.summary       = "Converts Swagger 2.0 specifications to OpenAPI 3.0"
  spec.description   = <<~DESC
    A Ruby gem that converts Swagger 2.0 (fka Swagger) API specifications into
    OpenAPI 3.0.x specifications. Handles paths, parameters, requestBody,
    components/schemas, securitySchemes, servers, and $ref rewriting.
  DESC
  spec.license       = "MIT"
  spec.homepage      = "https://github.com/Qew7/swagger23"

  spec.metadata = {
    "homepage_uri"    => spec.homepage,
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri"   => "#{spec.homepage}/blob/main/CHANGELOG.md"
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

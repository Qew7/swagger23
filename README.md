# swagger23

[![Gem Version](https://badge.fury.io/rb/swagger23.svg)](https://rubygems.org/gems/swagger23)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A Ruby gem that converts [Swagger 2.0](https://swagger.io/specification/v2/) API specifications into [OpenAPI 3.0.3](https://spec.openapis.org/oas/v3.0.3) specifications.

Accepts **JSON or YAML** input, produces **JSON or YAML** output. Works as a Ruby library or a standalone CLI tool.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [CLI usage](#cli-usage)
- [Library usage](#library-usage)
- [Conversion reference](#conversion-reference)
- [Running tests](#running-tests)
- [Contributing](#contributing)
- [License](#license)

---

## Features

| Swagger 2.0 | OpenAPI 3.0.3 |
|---|---|
| `host` + `basePath` + `schemes` | `servers[].url` |
| `definitions` | `components/schemas` |
| `parameters` (top-level) | `components/parameters` |
| `responses` (top-level) | `components/responses` |
| `securityDefinitions` | `components/securitySchemes` |
| `in: body` parameter | `requestBody` |
| `in: formData` parameters | `requestBody` (form-encoded or multipart) |
| `type: file` parameter | `{ type: string, format: binary }` |
| `collectionFormat` | `style` + `explode` |
| `x-nullable: true` | `nullable: true` |
| `discriminator: "prop"` | `discriminator: { propertyName: "prop" }` |
| `type: ["T", "null"]` | `type: "T", nullable: true` |
| All `$ref` paths | Rewritten (`#/definitions/` → `#/components/schemas/`, etc.) |
| OAuth2 flows | Mapped to OAS 3 flow objects |
| `x-` extensions | Passed through as-is |

**Large-spec safe.** `$ref` rewriting and schema processing use iterative BFS (no recursion) and disable JSON nesting limits, so even deeply nested, multi-thousand-line specs convert without stack overflows.

---

## Requirements

- Ruby **≥ 2.7**
- No runtime gem dependencies beyond `json` (stdlib)

---

## Installation

Add to your `Gemfile`:

```ruby
gem "swagger23"
```

Then run:

```bash
bundle install
```

Or install globally:

```bash
gem install swagger23
```

---

## CLI usage

```
swagger23 [INPUT [OUTPUT]]
```

| Argument | Description |
|---|---|
| `INPUT` | Path to a Swagger 2.0 file (`.json`, `.yaml`, or `.yml`). Reads from **stdin** if omitted. |
| `OUTPUT` | Path to write the OpenAPI 3.0 result. Format is determined by the file extension: `.yaml` / `.yml` → YAML, anything else → JSON. Writes JSON to **stdout** if omitted. |

**Options:**

```
-v, --version   Print the gem version and exit.
-h, --help      Print this help message and exit.
```

**Examples:**

```bash
# JSON → JSON
swagger23 petstore.json openapi.json

# YAML → YAML
swagger23 petstore.yaml openapi.yaml

# YAML → JSON
swagger23 petstore.yaml openapi.json

# JSON → YAML
swagger23 petstore.json openapi.yaml

# Print converted JSON to stdout
swagger23 petstore.json

# Pipe from stdin
cat petstore.yaml | swagger23
cat petstore.json | swagger23 > openapi.json
```

---

## Library usage

### Quick start

```ruby
require "swagger23"

# --- From a Hash (format-agnostic) ---
swagger_hash = JSON.parse(File.read("petstore.json"))
openapi_hash = Swagger23.convert(swagger_hash)    # => Hash

# --- From a string (JSON or YAML auto-detected) ---

# Returns an OpenAPI 3.0 Hash
hash = Swagger23.convert(Swagger23.parse(source))

# Returns an OpenAPI 3.0 JSON string (pretty-printed)
json_string = Swagger23.convert_string(source)

# Returns an OpenAPI 3.0 YAML string
yaml_string = Swagger23.convert_to_yaml(source)
```

### `Swagger23.parse(source)` — input parsing

Parses a JSON or YAML string into a Ruby `Hash`. Format is detected automatically by the first non-whitespace character (`{` or `[` → JSON, everything else → YAML).

```ruby
hash = Swagger23.parse(File.read("petstore.yaml", encoding: "utf-8"))
```

Raises `Swagger23::Error` if the input cannot be parsed or is not a Hash.

### `Swagger23.convert(swagger_hash)` — conversion

Accepts a parsed Swagger 2.0 `Hash`, returns an OpenAPI 3.0.3 `Hash`.

```ruby
openapi = Swagger23.convert(swagger_hash)
puts JSON.pretty_generate(openapi)
```

Raises `Swagger23::InvalidSwaggerError` if the document is not a Swagger 2.0 spec.

### `Swagger23.convert_string(source)` — string → JSON string

Parses the input (JSON or YAML) and returns the converted spec as a pretty-printed JSON string.

```ruby
File.write("openapi.json", Swagger23.convert_string(File.read("swagger.yaml", encoding: "utf-8")))
```

### `Swagger23.convert_to_yaml(source)` — string → YAML string

Parses the input (JSON or YAML) and returns the converted spec as a YAML string.

```ruby
File.write("openapi.yaml", Swagger23.convert_to_yaml(File.read("swagger.json", encoding: "utf-8")))
```

### Low-level converters

Each conversion step is a separate, testable module under `Swagger23::Converters`:

| Module | Responsibility |
|---|---|
| `Converters::Info` | `info` object |
| `Converters::Servers` | `host` + `basePath` + `schemes` → `servers` |
| `Converters::Paths` | `paths`, parameters, `requestBody`, responses |
| `Converters::Components` | `definitions`, `parameters`, `responses` → `components` |
| `Converters::Security` | `securityDefinitions` → `components/securitySchemes` |
| `RefRewriter` | Rewrites all `$ref` paths to OAS 3 equivalents |
| `SchemaProcessor` | `x-nullable`, `discriminator`, `type` arrays |

---

## Conversion reference

### Servers

```yaml
# Swagger 2.0
host: api.example.com
basePath: /v2
schemes: [https, http]
```

```yaml
# OpenAPI 3.0.3
servers:
  - url: https://api.example.com/v2
  - url: http://api.example.com/v2
```

When `schemes` is absent, `https` is used as the default.

---

### Parameters

`in: body` and `in: formData` parameters are removed from the `parameters` array and converted to `requestBody`:

```yaml
# Swagger 2.0
parameters:
  - in: body
    name: pet
    required: true
    schema:
      $ref: "#/definitions/Pet"
```

```yaml
# OpenAPI 3.0.3
requestBody:
  required: true
  content:
    application/json:
      schema:
        $ref: "#/components/schemas/Pet"
```

File uploads (`type: file`) become `{ type: string, format: binary }` inside a `multipart/form-data` request body.

Path parameters without `required: true` are automatically promoted — OAS 3.0 mandates it.

---

### `collectionFormat` mapping

| Swagger 2.0 `collectionFormat` | OAS 3.0 `style` | `explode` |
|---|---|---|
| `csv` | `form` | `false` |
| `ssv` | `spaceDelimited` | — |
| `tsv` | `tabDelimited` | — |
| `pipes` | `pipeDelimited` | — |
| `multi` | `form` | `true` |

---

### Security schemes

`apiKey` and `basic` definitions map directly. OAuth2 flows are translated to the OAS 3.0 flow object structure:

| Swagger 2.0 `flow` | OAS 3.0 flow key |
|---|---|
| `implicit` | `implicit` |
| `password` | `password` |
| `application` | `clientCredentials` |
| `accessCode` | `authorizationCode` |

---

### `$ref` rewriting

All `$ref` values are rewritten in a single pass over the entire document:

| Swagger 2.0 | OpenAPI 3.0.3 |
|---|---|
| `#/definitions/Foo` | `#/components/schemas/Foo` |
| `#/parameters/Bar` | `#/components/parameters/Bar` |
| `#/responses/Baz` | `#/components/responses/Baz` |
| `#/securityDefinitions/Key` | `#/components/securitySchemes/Key` |

External `$ref` values (e.g. `./models.yaml#/Foo`) are passed through unchanged.

---

### Schema-level transforms

| Input | Output |
|---|---|
| `x-nullable: true` | `nullable: true` (key removed) |
| `x-nullable: false` | `nullable: false` (key removed) |
| `discriminator: "type"` | `discriminator: { propertyName: "type" }` |
| `type: ["string", "null"]` | `type: string, nullable: true` |

---

## Running tests

```bash
bundle exec rspec
```

The test suite contains **281 examples** covering:

- Unit tests for each converter module
- End-to-end fixture tests (`bookstore_swagger2.json`, `petstore_swagger2.yaml`)
- Edge cases: deeply nested specs, `collectionFormat`, file uploads, OAuth2, `x-nullable`, etc.
- YAML input/output round-trips
- Large-spec performance

---

## Contributing

1. Fork [github.com/Qew7/swagger23](https://github.com/Qew7/swagger23).
2. Create a feature branch: `git checkout -b my-feature`.
3. Add tests for your change.
4. Make sure the full suite passes: `bundle exec rspec`.
5. Submit a pull request.

Bug reports and feature requests are welcome on the [issue tracker](https://github.com/Qew7/swagger23/issues).

---

## Author

[Maxim Veysgeym](https://github.com/Qew7) — Ruby enthusiast, Moscow.

---

## License

Released under the [MIT License](LICENSE) © 2026 Maxim Veysgeym.

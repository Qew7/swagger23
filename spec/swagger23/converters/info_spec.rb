# frozen_string_literal: true

require "spec_helper"

RSpec.describe Swagger23::Converters::Info do
  def convert(swagger)
    described_class.convert(swagger)
  end

  it "passes through title and version" do
    result = convert("info" => { "title" => "My API", "version" => "2.0.0" })
    expect(result).to eq("title" => "My API", "version" => "2.0.0")
  end

  it "passes through description" do
    info = { "title" => "T", "version" => "1", "description" => "A great API" }
    expect(convert("info" => info)["description"]).to eq("A great API")
  end

  it "passes through contact object" do
    info = { "title" => "T", "version" => "1",
             "contact" => { "name" => "Support", "email" => "api@example.com", "url" => "https://example.com" } }
    expect(convert("info" => info)["contact"])
      .to eq("name" => "Support", "email" => "api@example.com", "url" => "https://example.com")
  end

  it "passes through license object" do
    info = { "title" => "T", "version" => "1",
             "license" => { "name" => "MIT", "url" => "https://opensource.org/licenses/MIT" } }
    expect(convert("info" => info)["license"])
      .to eq("name" => "MIT", "url" => "https://opensource.org/licenses/MIT")
  end

  it "passes through termsOfService" do
    info = { "title" => "T", "version" => "1", "termsOfService" => "https://example.com/tos" }
    expect(convert("info" => info)["termsOfService"]).to eq("https://example.com/tos")
  end

  it "passes through x- extension fields" do
    info = { "title" => "T", "version" => "1", "x-logo" => { "url" => "logo.png", "altText" => "Logo" } }
    expect(convert("info" => info)["x-logo"]).to eq("url" => "logo.png", "altText" => "Logo")
  end

  it "returns empty hash when info key is absent" do
    expect(convert({})).to eq({})
  end

  it "does not mutate the original info hash" do
    info   = { "title" => "T", "version" => "1" }
    before = info.dup
    convert("info" => info)
    expect(info).to eq(before)
  end
end

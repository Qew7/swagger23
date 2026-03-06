# frozen_string_literal: true

require "spec_helper"

RSpec.describe Swagger23::Converters::Servers do
  def convert(doc)
    described_class.convert(doc)
  end

  context "with host + basePath + schemes" do
    it "builds one server per scheme" do
      result = convert("host" => "api.example.com", "basePath" => "/v1", "schemes" => ["https", "http"])
      expect(result.size).to eq(2)
    end

    it "concatenates scheme + host + basePath" do
      result = convert("host" => "api.example.com", "basePath" => "/v1", "schemes" => ["https"])
      expect(result.first["url"]).to eq("https://api.example.com/v1")
    end

    it "includes port when present in host" do
      result = convert("host" => "api.example.com:8443", "basePath" => "/", "schemes" => ["https"])
      expect(result.first["url"]).to eq("https://api.example.com:8443/")
    end
  end

  context "basePath normalisation" do
    it "adds a leading slash when basePath lacks one" do
      result = convert("host" => "h", "basePath" => "v2", "schemes" => ["https"])
      expect(result.first["url"]).to end_with("/v2")
    end

    it "keeps a basePath that already starts with /" do
      result = convert("host" => "h", "basePath" => "/v2", "schemes" => ["https"])
      expect(result.first["url"]).to eq("https://h/v2")
    end

    it "uses / as basePath when key is absent" do
      result = convert("host" => "h", "schemes" => ["https"])
      expect(result.first["url"]).to eq("https://h/")
    end
  end

  context "with no schemes" do
    it "falls back to a localhost URL" do
      result = convert({})
      expect(result.first["url"]).to include("localhost")
    end

    it "returns exactly one server" do
      expect(convert({}).size).to eq(1)
    end
  end

  context "with empty schemes array" do
    it "defaults to https and uses the actual host" do
      result = convert("host" => "api.example.com", "schemes" => [])
      expect(result.size).to eq(1)
      expect(result.first["url"]).to eq("https://api.example.com/")
    end
  end

  context "with a single scheme" do
    it "returns exactly one server" do
      result = convert("host" => "api.example.com", "basePath" => "/", "schemes" => ["https"])
      expect(result.size).to eq(1)
    end
  end
end

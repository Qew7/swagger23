# frozen_string_literal: true

require "spec_helper"

RSpec.describe Swagger23::Converters::Security do
  def convert(defs)
    described_class.convert("securityDefinitions" => defs)
  end

  describe "basic auth" do
    subject { convert("Auth" => { "type" => "basic" })["Auth"] }

    it { is_expected.to include("type" => "http", "scheme" => "basic") }
    it "preserves description" do
      s = convert("Auth" => { "type" => "basic", "description" => "desc" })["Auth"]
      expect(s["description"]).to eq("desc")
    end

    it "passes through x- extensions on basic auth scheme" do
      s = convert("Auth" => { "type" => "basic", "x-internal" => true })["Auth"]
      expect(s["x-internal"]).to be true
    end
  end

  describe "apiKey" do
    subject { convert("Key" => { "type" => "apiKey", "name" => "X-Key", "in" => "header" })["Key"] }

    it { is_expected.to include("type" => "apiKey", "name" => "X-Key", "in" => "header") }

    it "works with in: query" do
      s = convert("Key" => { "type" => "apiKey", "name" => "api_key", "in" => "query" })["Key"]
      expect(s).to include("type" => "apiKey", "name" => "api_key", "in" => "query")
    end

    it "works with in: cookie" do
      s = convert("Key" => { "type" => "apiKey", "name" => "session", "in" => "cookie" })["Key"]
      expect(s).to include("type" => "apiKey", "name" => "session", "in" => "cookie")
    end
  end

  describe "oauth2 flows" do
    shared_examples "has scopes" do |flow_key|
      it "includes scopes" do
        expect(subject.dig("flows", flow_key, "scopes")).to eq("read" => "Read access")
      end
    end

    shared_examples "has tokenUrl" do |flow_key|
      it "includes tokenUrl" do
        expect(subject.dig("flows", flow_key, "tokenUrl")).to eq("https://auth.example.com/token")
      end
    end

    shared_examples "has authorizationUrl" do |flow_key|
      it "includes authorizationUrl" do
        expect(subject.dig("flows", flow_key, "authorizationUrl"))
          .to eq("https://auth.example.com/authorize")
      end
    end

    context "implicit" do
      subject do
        convert("O" => {
          "type"             => "oauth2",
          "flow"             => "implicit",
          "authorizationUrl" => "https://auth.example.com/authorize",
          "scopes"           => { "read" => "Read access" }
        })["O"]
      end

      it { is_expected.to include("type" => "oauth2") }
      it { expect(subject["flows"].keys).to eq(["implicit"]) }
      include_examples "has scopes", "implicit"
      include_examples "has authorizationUrl", "implicit"
    end

    context "password" do
      subject do
        convert("O" => {
          "type"     => "oauth2",
          "flow"     => "password",
          "tokenUrl" => "https://auth.example.com/token",
          "scopes"   => { "read" => "Read access" }
        })["O"]
      end

      it { expect(subject["flows"].keys).to eq(["password"]) }
      include_examples "has scopes", "password"
      include_examples "has tokenUrl", "password"
    end

    context "application (→ clientCredentials)" do
      subject do
        convert("O" => {
          "type"     => "oauth2",
          "flow"     => "application",
          "tokenUrl" => "https://auth.example.com/token",
          "scopes"   => { "read" => "Read access" }
        })["O"]
      end

      it "maps to clientCredentials flow" do
        expect(subject["flows"].keys).to eq(["clientCredentials"])
      end
      include_examples "has scopes", "clientCredentials"
      include_examples "has tokenUrl", "clientCredentials"
    end

    context "accessCode (→ authorizationCode)" do
      subject do
        convert("O" => {
          "type"             => "oauth2",
          "flow"             => "accessCode",
          "authorizationUrl" => "https://auth.example.com/authorize",
          "tokenUrl"         => "https://auth.example.com/token",
          "scopes"           => { "read" => "Read access" }
        })["O"]
      end

      it "maps to authorizationCode flow" do
        expect(subject["flows"].keys).to eq(["authorizationCode"])
      end
      include_examples "has scopes",           "authorizationCode"
      include_examples "has authorizationUrl", "authorizationCode"
      include_examples "has tokenUrl",         "authorizationCode"
    end

    context "unknown flow" do
      subject do
        convert("O" => { "type" => "oauth2", "flow" => "magic", "scopes" => {} })["O"]
      end

      it { is_expected.to include("type" => "oauth2") }
      it "returns an empty flows object" do
        expect(subject["flows"]).to eq({})
      end
    end
  end

  describe "x- extensions passthrough" do
    it "passes through extensions on apiKey scheme" do
      s = convert("K" => { "type" => "apiKey", "name" => "k", "in" => "header", "x-foo" => "bar" })["K"]
      expect(s["x-foo"]).to eq("bar")
    end

    it "passes through extensions on oauth2 scheme" do
      s = convert("O" => {
        "type" => "oauth2", "flow" => "implicit",
        "authorizationUrl" => "https://a.example.com/",
        "scopes" => {}, "x-tier" => "premium"
      })["O"]
      expect(s["x-tier"]).to eq("premium")
    end
  end

  describe "when securityDefinitions is absent" do
    it "returns an empty hash" do
      expect(described_class.convert({})).to eq({})
    end
  end

  describe "when securityDefinitions is present but empty" do
    it "returns an empty hash (not nil, not the empty hash itself)" do
      result = described_class.convert("securityDefinitions" => {})
      expect(result).to eq({})
    end
  end
end

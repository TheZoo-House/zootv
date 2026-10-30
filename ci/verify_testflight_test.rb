require "minitest/autorun"
require_relative "verify_testflight"

class TestFlightVerificationTest < Minitest::Test
  def verify(rows, version: "0.1.0", platform: "TV_OS")
    client = TestFlightVerification.new(env: {"BUNDLE_ID" => "house.example.app",
      "MARKETING_VERSION" => "0.1.0", "BUILD_NUMBER" => "4"})
    client.define_singleton_method(:app_id_for_bundle_id) { |_| "app" }
    client.define_singleton_method(:fetch_paginated_json) do |_path, params|
      raise "Missing exact tvOS version filter" unless params.values_at(
        "filter[preReleaseVersion.version]", "filter[version]", "filter[preReleaseVersion.platform]"
      ) == ["0.1.0", "4", "TV_OS"]
      rows
    end
    client.define_singleton_method(:fetch_json) do |path|
      raise "Wrong build relationship" unless path == "/v1/builds/build/preReleaseVersion"
      {"data" => {"attributes" => {"version" => version, "platform" => platform}}}
    end
    client.run
  end

  def build(state = "VALID", expired = false)
    {"id" => "build", "attributes" => {"version" => "4", "processingState" => state, "expired" => expired}}
  end

  def test_accepts_exact_valid_build
    assert_equal "build", verify([build]).fetch("buildId")
  end

  def test_rejects_missing_ambiguous_invalid_pending_or_expired_builds
    [[], [build, build], [build("INVALID")], [build("PROCESSING")], [build("VALID", true)]].each do |rows|
      assert_raises(AppStoreConnectClient::Error) { verify(rows) }
    end
  end

  def test_rejects_a_prefix_match_for_the_build_number
    row = build
    row["attributes"]["version"] = "40"
    assert_raises(AppStoreConnectClient::Error) { verify([row]) }
  end

  def test_rejects_wrong_marketing_version
    assert_raises(AppStoreConnectClient::Error) { verify([build], version: "0.1.1") }
  end

  def test_rejects_wrong_platform
    assert_raises(AppStoreConnectClient::Error) { verify([build], platform: "IOS") }
  end
end

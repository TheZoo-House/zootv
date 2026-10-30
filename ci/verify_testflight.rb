#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "app_store_connect"

# Read back the exact processed tvOS version/build.
class TestFlightVerification < AppStoreConnectClient
  def run
    app = app_id_for_bundle_id(required_env("BUNDLE_ID"))
    rows = fetch_paginated_json("/v1/builds", {
      "filter[app]" => app, "filter[version]" => required_env("BUILD_NUMBER"),
      "filter[preReleaseVersion.version]" => required_env("MARKETING_VERSION"),
      "filter[preReleaseVersion.platform]" => "TV_OS", "limit" => "200"
    })
    rows.select! { |row| row.dig("attributes", "version") == required_env("BUILD_NUMBER") }
    unless rows.length == 1 && rows.first.dig("attributes", "processingState") == "VALID" &&
           rows.first.dig("attributes", "expired") == false
      raise Error, "Expected one unexpired VALID tvOS build for this version and build number"
    end

    release = fetch_json("/v1/builds/#{rows.first.fetch('id')}/preReleaseVersion").fetch("data")
    unless release.dig("attributes", "version") == required_env("MARKETING_VERSION") &&
           release.dig("attributes", "platform") == "TV_OS"
      raise Error, "Processed build belongs to a different version or platform"
    end

    { "buildId" => rows.first.fetch("id"), "processingState" => "VALID",
      "version" => required_env("MARKETING_VERSION"), "buildNumber" => required_env("BUILD_NUMBER") }
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    puts JSON.generate(TestFlightVerification.new.run)
  rescue AppStoreConnectClient::Error => error
    warn error.message
    exit 1
  end
end

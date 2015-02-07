$: << File.expand_path("../../lib", __FILE__)

require "ciborg"
require "tempfile"

module SpecHelpers
  def self.ec2_credentials_present?
    ENV.has_key?("EC2_KEY") && ENV.has_key?("EC2_SECRET")
  end

  def self.hpcs_credentials_present?
    ENV.has_key?("HPCS_KEY") && ENV.has_key?("HPCS_SECRET") && ENV.has_key?("HPCS_IDENTITY_ENDPOINT_URL") && ENV.has_key?("HPCS_TENANT_ID") && ENV.has_key?("HPCS_AVAILABILITY_ZONE")
  end

  def ssh_key_pair_path
    File.join(File.dirname(__FILE__), 'fixtures', 'ssh_keys', 'vagrant_test_key').tap do |path|
      File.chmod(0400, path)
    end
  end
end

RSpec.configure do |c|
  c.treat_symbols_as_metadata_keys_with_true_values = true
  c.include SpecHelpers
end

$stderr.puts "***WARNING*** EC2 credentials are not present, so no AWS tests will be run" unless SpecHelpers::ec2_credentials_present?
$stderr.puts "***WARNING*** HPCS2 credentials are not present, so no HPCS tests will be run" unless SpecHelpers::hpcs_credentials_present?
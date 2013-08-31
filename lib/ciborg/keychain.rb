require "httpclient"
require "stringio"

module Ciborg
  class Keychain
    EXPECTED_SECURITY_STDERR = "at depth 0 - 20: unable to get local issuer certificate\n"
    attr_reader :config, :path

    def initialize(keychain_path)
      @path = keychain_path
    end

    def has_key?(key_name)
      system("sudo security find-certificate -c \"#{key_name}\" #{path} > /dev/null 2>&1")
    end

    def fetch_remote_certificate(host)
      cert_s = nil
      stderr = capture_stderr { cert_s = http_client.get(host).peer_cert.to_s }
      if stderr != EXPECTED_SECURITY_STDERR
        $stderr.print stderr
      end
      cert_s
    end

    def add_certificate(certificate)
      certificate_file = Tempfile.new("ciborg.crt").tap do |f|
        f.write(certificate)
        f.close
      end

      system("sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain #{certificate_file.path}")
    end

    private
    def http_client
      @http_client ||=
        HTTPClient.new.tap do |hc|
          hc.ssl_config.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
    end

    def capture_stderr
      previous_stderr, $stderr = $stderr, StringIO.new
      yield
      $stderr.string
    ensure
      $stderr = previous_stderr
    end
  end
end

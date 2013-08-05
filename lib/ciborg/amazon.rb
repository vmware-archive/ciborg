require "fog"

module Ciborg
  class Amazon
    PORTS_TO_OPEN = [22, 443] + (9000...9010).to_a

    AWS_REGION_AMI = {
      'us-east-1' => 'ami-a29943cb',
      'us-west-1' => 'ami-87712ac2',
      'us-west-2' => 'ami-20800c10',
      'eu-west-1' => 'ami-e1e8d395',
      'ap-southeast-1' => 'ami-a4ca8df6',
      'ap-southeast-2' => 'ami-974ddead',
      'ap-northeast-1' => 'ami-60c77761',
      'sa-east-1' => 'ami-8cd80691'
    }

    attr_reader :key, :secret, :region

    def initialize(key, secret, region)
      @key = key
      @secret = secret
      @region = region
    end

    def fog_security_groups
      fog.security_groups
    end

    def fog_key_pairs
      fog.key_pairs
    end

    def fog_servers
      fog.servers
    end

    def elastic_ip_address
      @elastic_ip_address ||= fog.addresses.create
    end

    def create_security_group(group_name)
      unless fog_security_groups.get(group_name)
        fog_security_groups.create(:name => group_name, :description => 'Ciborg-generated group')
      end
    end

    def open_port(group_name, *ports)
      group = fog_security_groups.get(group_name)
      ports.each do |port|
        unless group.ip_permissions.any? { |p| (p["fromPort"]..p["toPort"]).include?(port) }
          group.authorize_port_range(port..port)
        end
      end
    end

    def delete_key_pair(key_pair_name)
      fog_key_pairs.new(:name => key_pair_name).destroy
    end

    def add_key_pair(key_pair_name, public_key)
      fog_key_pairs.create(:name => key_pair_name, :public_key => public_key) unless fog_key_pairs.get(key_pair_name)
    end

    def with_key_pair(pubkey)
      unique_key_pair_name = "CIBORG-#{Time.now.to_i}"
      add_key_pair(unique_key_pair_name, pubkey)
      yield unique_key_pair_name if block_given?
    ensure
      delete_key_pair(unique_key_pair_name)
    end

    def launch_server(key_pair_name, security_group_name, instance_type = "m1.medium", availability_zone = nil)
      fog_servers.create(
        :image_id => AWS_REGION_AMI[region],
        :flavor_id => instance_type,
        :availability_zone => availability_zone,
        :tags => {"Name" => "Ciborg", "ciborg" => Ciborg::VERSION},
        :key_name => key_pair_name,
        :groups => [security_group_name]
      ).tap do |server|
        server.wait_for { ready? }
        fog.associate_address(server.id, elastic_ip_address.public_ip) # needs to be running
        server.reload
      end
    end

    def destroy_ec2(confirm_proc, *args)
      servers.each do |server|
        next unless (args == [:all]) || args.include?(server.id)
        next unless confirm_proc.call(server)
        ip = server.public_ip_address
        server.destroy
        release_elastic_ip(ip)
        yield(server) if block_given?
      end
    end

    def servers
      fog_servers.select { |s| s.tags.keys.include?("ciborg") && s.state == "running" }
    end

    def release_elastic_ip(ip)
      fog.addresses.get(ip).destroy if fog.addresses.get(ip)
    end

    private

    def fog
      @fog ||= Fog::Compute.new(
        :provider => "aws",
        :aws_access_key_id => key,
        :aws_secret_access_key => secret,
        :region => region
      )
    end
  end
end

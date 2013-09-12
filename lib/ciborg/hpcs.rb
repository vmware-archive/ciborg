require "fog"

module Ciborg
  class Hpcs
    PORTS_TO_OPEN = [22, 443] + (9000...9010).to_a

    attr_reader :key, :secret, :identity, :tenant, :zone

    def initialize(key, secret, identity, tenant, zone)
      @key = key
      @secret = secret
      @identity = identity
      @tenant = tenant
      @zone = zone
    end

    def fog_security_groups
      fog.security_groups
    end

    def fog_security_group_name_to_id(group_name)
      groups = {}
      fog.security_groups.map { |security_group| groups[security_group.name] = security_group.id }
      groups[group_name]
    end

    def fog_server_name_to_id(server_name)
      servers = {}
      fog.servers.map { |server| servers[server.name] = server.id }
      servers[server_name]
    end

    def fog_key_pairs
      fog.key_pairs
    end

    def with_key_pair(pubkey)
      unique_key_pair_name = "CIBORG-#{Time.now.to_i}"
      add_key_pair(unique_key_pair_name, pubkey)
      yield unique_key_pair_name if block_given?
    ensure
      delete_key_pair(unique_key_pair_name)
    end

    def fog_servers
      fog.servers
    end

    def elastic_ip_address
      @elastic_ip_address ||= fog.addresses.create
    end

    def release_elastic_ip(ip)
      fog.addresses.get(fog_ip_address_to_id(ip)).destroy if fog.addresses.get(fog_ip_address_to_id(ip))
    end

    def fog_ip_address_to_id(ip)
      ip_addresses = {}
      fog.addresses.map {|address| ip_addresses[address.ip] = address.id }
      ip_addresses[ip]
    end

    def fog_floating_ip(server)
      server.addresses["private"].map { |ip_addr| ip_addr["addr"] }.flatten & fog.addresses.map {|address| address.ip }
    end

    def create_security_group(group_name)
      unless fog_security_group_name_to_id(group_name)
        fog_security_groups.create(:name => group_name, :description => 'Ciborg-generated group')
      end
    end

    def open_port(group_name, *ports)
      group = fog_security_groups.get(fog_security_group_name_to_id(group_name))
      ports.each do |port|
        unless group.rules.any? { |p| (p["from_port"]..p["to_port"]).include?(port) }
          group.create_rule(port..port)
        end
      end
    end

    def add_key_pair(key_pair_name, public_key)
      fog_key_pairs.create(:name => key_pair_name, :public_key => public_key) unless fog_key_pairs.get(key_pair_name)
    end

    def delete_key_pair(key_pair_name)
      if fog.key_pairs.get(key_pair_name) != nil
        fog_key_pairs.get(key_pair_name).destroy
      end
    end


    def launch_server(key_pair_name, security_group_name, instance_type, zone)
      fog_servers.create(
          :image_id => "68425",
          :flavor_id => instance_type,
          :name => "Ciborg",
          :metadata => { "tags" => "ciborg #{Ciborg::VERSION}" },
          :key_name => key_pair_name,
          :security_groups => [security_group_name]
      ).tap do |server|
        server.wait_for { ready? }
       fog.associate_address(server.id, elastic_ip_address.ip) # needs to be running
        server.reload
      end
    end

    def destroy_vm(confirm_proc, *args)
      servers.each do |server|
        next unless (args == [:all]) || args.include?(server.id)
        next unless confirm_proc.call(server)
        ip = server.addresses["private"].map { |ip_addr| ip_addr["addr"] }.flatten & fog.addresses.map {|address| address.ip }
        server.destroy
        release_elastic_ip(ip)
        yield(server) if block_given?
      end
    end

    def servers
      fog_servers.select { |s| s.metadata.get("tags").value.include?("ciborg") && s.state == "ACTIVE" unless s.metadata.get("tags") == nil }
    end

    def fog
      @fog ||= Fog::Compute.new(
          :provider => "HP",
          :hp_access_key => key,
          :hp_secret_key => secret,
          :hp_auth_uri => identity,
          :hp_tenant_id => tenant,
          :hp_avl_zone => zone,
      )
    end

  end
end

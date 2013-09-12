require "spec_helper"
require "fog"

describe Ciborg::Hpcs, :slow do
  subject(:hpcs) { Ciborg::Hpcs.new(ENV["HPCS_KEY"], ENV["HPCS_SECRET"], ENV["HPCS_IDENTITY_ENDPOINT_URL"], ENV["HPCS_TENANT_ID"], ENV["HPCS_AVAILABILITY_ZONE"]) }
  let(:tempdir) { Dir.mktmpdir }
  let(:fog) { hpcs.send(:fog) }

  describe "hpcs connection" do
    if SpecHelpers::hpcs_credentials_present?
      it "can authenticate to hp cloud services" do
        hpcs.fog().should_not be nil
      end
    end
  end
  describe "#create_security_group" do
    if SpecHelpers::hpcs_credentials_present?
      after { hpcs.fog_security_groups.get(hpcs.fog_security_group_name_to_id(security_group)).destroy }

      context "when there is no existing security group" do
        let(:security_group) { "totally_a_honeypot" }

        it "creates a security group" do
          hpcs.create_security_group(security_group)
          hpcs.fog_security_groups.map(&:name).should include security_group
        end
      end

      context "when the security group already exists" do
        let(:security_group) { "bart_police" }
        before { hpcs.create_security_group(security_group) }

        it "does not complain" do
          expect { hpcs.create_security_group(security_group) }.not_to raise_error
        end
      end
    end
  end

  describe "#open_port" do
    if SpecHelpers::hpcs_credentials_present?
      let(:security_group) { "bag_of_weasels" }
      let(:group) { hpcs.fog_security_groups.get(hpcs.fog_security_group_name_to_id(security_group)) }

      before { hpcs.create_security_group(security_group) }
      after { hpcs.fog_security_groups.get(hpcs.fog_security_group_name_to_id(security_group)).destroy }

      def includes_port?(permissions, port)
        permissions.any? { |p| (p["from_port"]..p["to_port"]).include?(port) }
      end

      it "opens a port for business" do
        group.rules.should_not include "80"
        hpcs.open_port(security_group, 80)
        includes_port?(group.reload.rules, 80).should be_true
      end

      it "takes a bunch of ports" do
        hpcs.open_port(security_group, 22, 443)
        includes_port?(group.reload.rules, 22).should be_true
        includes_port?(group.reload.rules, 443).should be_true
      end
    end
  end

  describe "#add_key_pair" do
    if SpecHelpers::hpcs_credentials_present?
      let(:key_pair_pub) { File.read(File.expand_path(ssh_key_pair_path + ".pub")) }
      let(:key_pair_name) { "is_supernuts" }

      before { hpcs.delete_key_pair(key_pair_name) }
      after { hpcs.delete_key_pair(key_pair_name) }

      it "uploads the key" do
        hpcs.add_key_pair(key_pair_name, key_pair_pub)
        hpcs.fog_key_pairs.map(&:name).should include key_pair_name
      end

      context "when the key is already there" do
        before { hpcs.add_key_pair(key_pair_name, key_pair_pub) }

        it "doesn't reupload" do
          expect do
            hpcs.add_key_pair(key_pair_name, key_pair_pub)
          end.not_to raise_error
        end
      end
    end
  end
  describe "Checks if vm Ciborg is running" do
    if SpecHelpers::hpcs_credentials_present?
      it "does not have a ciborg vm running" do
        hpcs.fog_server_name_to_id("Ciborg").should_not be
      end
    end
  end

  describe "things which launch instances" do
    if SpecHelpers::hpcs_credentials_present?
      let(:key_pair_name) { "eating_my_cookie" }
      let(:security_group) { "chump_of_change" }
      let(:key_pair_pub) { File.read(File.expand_path(ssh_key_pair_path + ".pub")) }
      let(:freshly_launched_server) { hpcs.launch_server(key_pair_name, security_group, "100", ENV["HPCS_AVAILABILITY_ZONE"]) }

      before do
        hpcs.delete_key_pair(key_pair_name)
        hpcs.add_key_pair(key_pair_name, key_pair_pub)
        hpcs.create_security_group(security_group)
      end

      after do
        if  hpcs.fog_server_name_to_id("Ciborg")
          freshly_launched_server.destroy
        end
        hpcs.delete_key_pair(key_pair_name)
        # Make a best effort attempt to clean up after the tests have completed
        # EC2 does not always reap these resources fast enough for our tests, we could wait, but why bother?
        hpcs.elastic_ip_address.destroy rescue nil
        sleep(5)
        hpcs.fog_security_groups.get(hpcs.fog_security_group_name_to_id(security_group)).destroy rescue nil
      end

      describe "#launch_instance" do
        it "creates an instance" do
          expect { freshly_launched_server }.to change { hpcs.fog_servers.reload.count }.by(1)
          freshly_launched_server.flavor_id.should == "100"
          freshly_launched_server.name.should == "Ciborg"
          freshly_launched_server.key_name.should == key_pair_name
          freshly_launched_server.security_groups.first["name"].should == security_group
          freshly_launched_server.addresses["private"].map { |ip_addr| ip_addr["addr"] }.flatten.should include(hpcs.elastic_ip_address.ip)
        end
      end

      describe "#Gets the floating ip address" do
        it "can get the real floating ip address" do
            hpcs.fog_floating_ip(freshly_launched_server).should eq freshly_launched_server.addresses["private"].map { |ip_addr| ip_addr["addr"] }.flatten & fog.addresses.map {|address| address.ip }
        end
      end

      describe "#destroy_vm" do
        let!(:server_ip) { freshly_launched_server.public_ip_address }
        context 'with a confirmation Proc that returns true' do
          let(:proc) { ->(_) { true } }

          it "stops all the instances" do

            #TODO: This probably needs some more testing with n > 1 instances
            expect do
              hpcs.destroy_vm(proc, :all)
              freshly_launched_server.wait_for { !ready? }
            end.to change { freshly_launched_server.reload.state }.from("ACTIVE")
            sleep(5) #waits for the server to be destroyed
            hpcs.fog_server_name_to_id("Ciborg").should_not be
          end

          it "stops the named instances" do
            expect do
              hpcs.destroy_vm(proc, freshly_launched_server.id)
              freshly_launched_server.wait_for { !ready? }
            end.to change { freshly_launched_server.reload.state }.from("ACTIVE")
            sleep(5) #waits for the server to be destroyed
            hpcs.fog_server_name_to_id("Ciborg").should_not be
          end
        end

        context 'with a confirmation Proc that returns false' do
          let(:proc) { ->(_) { false } }
          it 'does not stop instances' do
            expect do
              hpcs.destroy_vm(proc, :all)
            end.to_not change { freshly_launched_server.reload.state }.from("ACTIVE")
            sleep(5) #waits for the server to be destroyed
            hpcs.fog_server_name_to_id("Ciborg").should be
          end
        end
      end
    end
  end

  describe "#elastic_ip_address" do
    if SpecHelpers::hpcs_credentials_present?
      it "allocates an ip address" do
        expect { hpcs.elastic_ip_address }.to change { fog.addresses.reload.count }.by(1)
        hpcs.elastic_ip_address.ip.should =~ /\d+\.\d+\.\d+\.\d+/
        hpcs.elastic_ip_address.destroy
      end
    end
  end

  describe "#release_elastic_ip" do
    if SpecHelpers::hpcs_credentials_present?
      let!(:elastic_ip) { hpcs.elastic_ip_address }

      it "releases the ip" do
        expect do
          hpcs.release_elastic_ip(elastic_ip.ip)
        end.to change { fog.addresses.reload.count }.by(-1)
      end
    end
  end
end
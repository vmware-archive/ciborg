require "spec_helper"

describe Ciborg::CLI do
  let(:cli) { subject }
  let(:sobo) { Ciborg::Sobo.new(ciborg_config.master, ciborg_config.server_ssh_key_path) }

  before do
    cli.stub(:ciborg_config).and_return(ciborg_config) # ciborg_config must be defined in each context below
  end

  context 'with Amazon' do
    let(:ciborg_config) {
      Ciborg::Config.new(
          :aws_key => ENV["EC2_KEY"],
          :aws_secret => ENV["EC2_SECRET"],
          :server_ssh_key => ssh_key_pair_path)
    }

    describe '#create & #destroy_ec2', :slow, :ec2 do
      it "launches an instance and associates elastic ip" do
        pending "Missing EC2 Credentials" unless SpecHelpers::ec2_credentials_present?
        cli.ciborg_config.instance_size = 't1.micro'
        expect { cli.create }.to change { ciborg_config.master }.from(nil)

        cli.stub(:options).and_return({'force' => 'force'})
        expect { cli.destroy_ec2 }.to change { ciborg_config.master }.to(nil)
      end
    end

    describe "#ssh" do
      it "starts an ssh session to the ciborg host" do
        cli.should_receive(:exec).with("ssh -i #{cli.ciborg_config.server_ssh_key_path} ubuntu@#{cli.ciborg_config.master} -p #{cli.ciborg_config.ssh_port}")
        cli.ssh
      end
    end

    describe "#open", :osx do
      let(:ciborg_config) do
        Ciborg::Config.new(:node_attributes => {
            :nginx => {
                :basic_auth_user => "ci",
                :basic_auth_password => "secret"
            }
        })
      end

      it "opens a web browser with the ciborg page" do
        ciborg_config.master = "127.0.0.1"
        cli.should_receive(:exec).with("open https://ci:secret@127.0.0.1/")
        cli.open
      end
    end

    describe "#trust_certificate", :osx do
      let(:keychain) { Ciborg::Keychain.new("/Library/Keychains/System.keychain") }
      before { ciborg_config.master = "192.168.99.99" }

      it "adds the key to the keychain" do
        fake_keychain = double(:keychain)
        fake_keychain.should_receive(:fetch_remote_certificate).with("https://#{ciborg_config.master}/").and_return("IAMACERTIFICATE")
        fake_keychain.should_receive(:add_certificate).with("IAMACERTIFICATE")
        Ciborg::Keychain.should_receive(:new).with("/Library/Keychains/System.keychain").and_return(fake_keychain)

        cli.trust_certificate
      end
    end

    describe "#add_build" do
      let(:name) { "bob" }
      let(:repository) { "http://github.com/mkocher/soloist.git" }
      let(:branch) { "master" }
      let(:command) { "script/ci_build.sh" }

      context "when the config is invalid" do
        before { ciborg_config.node_attributes.jenkins = {} }

        it "raises an error" do
          expect do
            cli.add_build(name, repository, branch, command)
          end.to raise_error %r{your config file does not have a}
        end
      end

      context "when the configuration is valid" do
        context "with persisted configuration data" do
          let(:tempfile) do
            Tempfile.new('ciborg-config').tap do |file|
              file.write YAML.dump({})
              file.close
            end
          end

          let(:ciborg_config) { Ciborg::Config.from_file(tempfile.path) }

          def builds
            cli.ciborg_config.reload.node_attributes.jenkins.builds
          end

          it "persists a build" do
            cli.add_build(name, repository, branch, command)
            builds.should_not be_nil
            builds.should_not be_empty
          end
        end
      end
    end

    context "with a fake amazon" do
      let(:ip_address) { "127.0.0.1" }
      let(:server) { double("server", :public_ip_address => ip_address).as_null_object }
      let(:amazon) { double("AMZN", :launch_server => server).as_null_object }
      let(:instance_id) { 'i-xxxxxx' }

      before do
        cli.stub(:amazon).and_return(amazon)
      end

      describe "#create" do
        before do
          amazon.stub(:with_key_pair).and_yield("unique-key-pair-name")
          cli.should_receive(:wait_for_server)
        end

        it "uses the configured key pair" do
          amazon.should_receive(:with_key_pair).with(cli.ciborg_config.server_ssh_pubkey)
          cli.create
        end

        context "with a custom security group", :slow => false do
          before { cli.ciborg_config.security_group = 'custom_group' }

          it "launches the instance with the configured security group" do
            amazon.should_receive(:create_security_group).with('custom_group')
            amazon.should_receive(:open_port).with('custom_group', anything, anything)
            amazon.should_receive(:launch_server).with(anything, 'custom_group', anything, anything)
            cli.create
          end
        end

        context "with a custom instance size", :slow => false do
          before { cli.ciborg_config.instance_size = 'really_big_instance' }

          it "launches the instance with the configured instance size" do
            amazon.should_receive(:launch_server).with(anything, anything, 'really_big_instance', 'us-east-1b')
            cli.create
          end
        end
      end

      describe "destroy_ec2" do
        before do
          cli.ciborg_config.master = ip_address
          cli.ciborg_config.instance_id = instance_id
        end

        context 'by default' do
          before do
            amazon.stub(:destroy_ec2).and_yield(double("SERVER").as_null_object)
          end

          it 'deletes the known instance' do
            amazon.should_receive(:destroy_ec2).and_yield(double("SERVER").as_null_object)
            cli.destroy_ec2
          end

          it 'clears the master ip address' do
            expect { cli.destroy_ec2 }.to change(cli.ciborg_config, :master).to(nil)
          end

          it 'clears the master instance id' do
            expect { cli.destroy_ec2 }.to change(cli.ciborg_config, :instance_id).to(nil)
          end

          it 'does not delete sibling instances' do
            amazon.should_receive(:destroy_ec2).with(a_kind_of(Proc), instance_id)
            cli.destroy_ec2
          end

          it 'prompts for confirmation' do
            cli.should_receive(:yes?).and_return(true)
            amazon.should_receive(:destroy_ec2).with(a_kind_of(Proc), instance_id) do |confirm_proc, instance_id|
              confirm_proc.call(double("SERVER").as_null_object)
            end
            cli.destroy_ec2
          end
        end

        context 'with --all' do
          before do
            cli.stub(:options).and_return({'all' => 'all'})
          end

          it 'deletes everything tagged "ciborg"' do
            amazon.should_receive(:destroy_ec2).with(a_kind_of(Proc), :all)
            cli.destroy_ec2
          end
        end

        context 'with --force' do
          before do
            cli.stub(:options).and_return({'force' => 'force'})
          end

          it 'does not prompt for confirmation' do
            cli.should_not_receive(:ask)
            amazon.should_receive(:destroy_ec2).with(a_kind_of(Proc), instance_id) do |confirm_proc, instance_id|
              confirm_proc.call(double("SERVER").as_null_object)
            end
            cli.destroy_ec2
          end
        end
      end
    end
  end

  context 'with HPCS' do
    let(:ciborg_config) {
      Ciborg::Config.new(
          :hpcs_key => ENV["HPCS_KEY"],
          :hpcs_secret => ENV["HPCS_SECRET"],
          :hpcs_identity => ENV["HPCS_IDENTITY_ENDPOINT_URL"],
          :hpcs_tenant => ENV["HPCS_TENANT_ID"],
          :hpcs_zone => ENV["HPCS_AVAILABILITY_ZONE"],
          :server_ssh_key => ssh_key_pair_path)
    }
    describe '#create & #destroy_hpcs', :slow, :hpcs do
      it "launches an instance and associates elastic ip" do
        pending "Missing HPCS Credentials" unless SpecHelpers::hpcs_credentials_present?
        cli.ciborg_config.instance_size = '100'
        expect { cli.create_hpcs }.to change { ciborg_config.master }.from(nil)

        cli.stub(:options).and_return({'force' => 'force'})
        expect { cli.destroy_hpcs }.to change { ciborg_config.master }.to(nil)
      end
    end

    describe "#ssh" do
      it "starts an ssh session to the ciborg host" do
        cli.should_receive(:exec).with("ssh -i #{cli.ciborg_config.server_ssh_key_path} ubuntu@#{cli.ciborg_config.master} -p #{cli.ciborg_config.ssh_port}")
        cli.ssh
      end
    end

    describe "#open", :osx do
      let(:ciborg_config) do
        Ciborg::Config.new(:node_attributes => {
            :nginx => {
                :basic_auth_user => "ci",
                :basic_auth_password => "secret"
            }
        })
      end

      it "opens a web browser with the ciborg page" do
        ciborg_config.master = "127.0.0.1"
        cli.should_receive(:exec).with("open https://ci:secret@127.0.0.1/")
        cli.open
      end
    end

    describe "#add_build" do
      let(:name) { "bob" }
      let(:repository) { "http://github.com/mkocher/soloist.git" }
      let(:branch) { "master" }
      let(:command) { "script/ci_build.sh" }

      context "when the config is invalid" do
        before { ciborg_config.node_attributes.jenkins = {} }

        it "raises an error" do
          expect do
            cli.add_build(name, repository, branch, command)
          end.to raise_error %r{your config file does not have a}
        end
      end

      context "when the configuration is valid" do
        context "with persisted configuration data" do
          let(:tempfile) do
            Tempfile.new('ciborg-config').tap do |file|
              file.write YAML.dump({})
              file.close
            end
          end

          let(:ciborg_config) { Ciborg::Config.from_file(tempfile.path) }

          def builds
            cli.ciborg_config.reload.node_attributes.jenkins.builds
          end

          it "persists a build" do
            cli.add_build(name, repository, branch, command)
            builds.should_not be_nil
            builds.should_not be_empty
          end
        end
      end
    end

    context "with a fake hpcs" do
      let(:ip_address) { "127.0.0.1" }
      let(:server) { double("server", :public_ip_address => ip_address).as_null_object }
      let(:hpcs) { double("HPCS", :launch_server => server).as_null_object }
      let(:instance_id) { '1' }

      before do
        cli.stub(:hpcs).and_return(hpcs)
      end

      describe "#create_hpcs" do
        before do
          hpcs.stub(:with_key_pair).and_yield("unique-key-pair-name")
          cli.should_receive(:wait_for_server)
        end
        it "uses the configured key pair" do
          hpcs.should_receive(:with_key_pair).with(cli.ciborg_config.server_ssh_pubkey)
          cli.create_hpcs
        end

        context "with a custom security group", :slow => false do
          before { cli.ciborg_config.security_group = 'custom_group' }

          it "launches the instance with the configured security group" do
            hpcs.should_receive(:create_security_group).with('custom_group')
            hpcs.should_receive(:open_port).with('custom_group', anything, anything)
            hpcs.should_receive(:launch_server).with(anything, 'custom_group', anything, anything)
            cli.create_hpcs
          end
        end

        context "with a custom instance size", :slow => false do
          before { cli.ciborg_config.instance_size = '1000' }

          it "launches the instance with the configured instance size" do
            hpcs.should_receive(:launch_server).with(anything, anything, '1000', 'us-east-1b')
            cli.create_hpcs
          end
        end
      end

      describe "destroy_hpcs" do
        before do
          cli.ciborg_config.master = ip_address
          cli.ciborg_config.instance_id = instance_id
        end

        context 'by default' do
          before do
            hpcs.stub(:destroy_vm).and_yield(double("SERVER").as_null_object)
          end

          it 'deletes the known instance' do
            hpcs.should_receive(:destroy_vm).and_yield(double("SERVER").as_null_object)
            cli.destroy_hpcs
          end

          it 'clears the master ip address' do
            expect { cli.destroy_hpcs }.to change(cli.ciborg_config, :master).to(nil)
          end

          it 'clears the master instance id' do
            expect { cli.destroy_hpcs }.to change(cli.ciborg_config, :instance_id).to(nil)
          end

          it 'does not delete sibling instances' do
            hpcs.should_receive(:destroy_vm).with(a_kind_of(Proc), instance_id)
            cli.destroy_hpcs
          end

          it 'prompts for confirmation' do
            cli.should_receive(:yes?).and_return(true)
            hpcs.should_receive(:destroy_vm).with(a_kind_of(Proc), instance_id) do |confirm_proc, instance_id|
              confirm_proc.call(double("SERVER").as_null_object)
            end
            cli.destroy_hpcs
          end
        end
      end
    end
  end
  def wait_for(&block)
    Timeout.timeout(150) { sleep 1 until block.call }
  end
end

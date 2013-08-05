require "thor"
require "thor/group"
require "pp"
require "tempfile"
require "json"
require "ciborg/configuration_wizard"
require "godot"

module Ciborg
  class CLI < ::Thor
    register(ConfigurationWizard, "setup", "setup", ConfigurationWizard::DESCRIPTION_TEXT)

    desc "ssh", "SSH into Ciborg"
    def ssh
      exec("ssh -i #{ciborg_config.server_ssh_key_path} ubuntu@#{ciborg_config.master} -p #{ciborg_config.ssh_port}")
    end

    desc "open", "Open a browser to Ciborg"
    def open
      exec("open #{ciborg_config.jenkins_url}/")
    end

    desc "create", "Create a new Ciborg server using EC2"
    def create
      server = amazon.with_key_pair(ciborg_config.server_ssh_pubkey) do |keypair_name|
        amazon.create_security_group(ciborg_config.security_group)
        amazon.open_port(ciborg_config.security_group, 22, 443)
        amazon.launch_server(keypair_name, ciborg_config.security_group, ciborg_config.instance_size, ciborg_config.availability_zone)
      end
      wait_for_server(server)

      say("Writing ip address for ec2: #{server.public_ip_address}")

      ciborg_config.update(master: server.public_ip_address, instance_id: server.id)
    end

    desc "destroy_ec2", "Destroys all the ciborg resources on EC2"
    method_option :all, default: false
    method_option :force, default: false
    def destroy_ec2
      instance = (options['all'] ? :all : ciborg_config.instance_id)

      amazon.destroy_ec2(confirmation_proc(options['force']), instance) do |server|
        say("Clearing ip address for ec2: #{server.public_ip_address}")

        ciborg_config.update(master: nil, instance_id: nil)
      end
    end

    desc "create_vagrant", "Creates a vagrant instance"
    def create_vagrant
      spawn_env = {"CIBORG_SSH_KEY" => ciborg_config.server_ssh_pubkey_path,
                   "VAGRANT_HOME" => File.expand_path("~")}
      spawn_options = {chdir: ciborg_root_path}

      pid = Process.spawn(spawn_env, "vagrant up", spawn_options)
      Process.wait(pid)

      vagrant_ip = "192.168.33.10"

      say("Writing ip address for vagrant: #{vagrant_ip}")

      ciborg_config.update(master: vagrant_ip)
    end

    desc "config", "Dumps all configuration data for Ciborg"
    def config
      say ciborg_config.display
    end

    desc "certificate", "Dump the certificate"
    def certificate
      say(keychain.fetch_remote_certificate("https://#{ciborg_config.master}"))
    end

    desc "bootstrap", "Configures Ciborg's master node"
    def bootstrap
      sync_bootstrap_script
      master_server.system!("bash -l script/bootstrap_server.sh")
    rescue Errno::ECONNRESET
      sleep 1
    end

    desc "chef", "Uploads chef recipes and runs them"
    def chef
      sync_chef_recipes
      upload_soloist
      sync_github_ssh_key
      master_server.upload(File.expand_path('../../../templates/Gemfile-remote', __FILE__), 'Gemfile')
      master_server.system!("rvm autolibs enable; bash -l -c 'rvm use 1.9.3; bundle install; soloist'")    rescue Errno::ECONNRESET
      sleep 1
    end

    desc "add_build <name> <repository> <branch> <command>", "Adds a build to Ciborg"
    def add_build(name, repository, branch, command)
      raise ciborg_config.errors.join(" and ") unless ciborg_config.valid?

      ciborg_config.add_build(name, repository, branch, command)
      ciborg_config.save
    end

    desc "trust_certificate", "Adds the current master's certificate to your OSX keychain"
    def trust_certificate
      certificate_contents = keychain.fetch_remote_certificate("https://#{ciborg_config.master}/")
      keychain.add_certificate(certificate_contents)
    end

    no_tasks do
      def master_server
        @master_server ||= Ciborg::Sobo.new(ciborg_config.master, ciborg_config.server_ssh_key_path)
      end

      def ciborg_config
        @ciborg_config ||= Ciborg::Config.from_file(ciborg_config_path)
      end

      def amazon
        @amazon ||= Ciborg::Amazon.new(ciborg_config.aws_key, ciborg_config.aws_secret, ciborg_config.aws_region)
      end

      def keychain
        @keychain ||= Ciborg::Keychain.new("/Library/Keychains/System.keychain")
      end

      def sync_bootstrap_script
        master_server.upload(File.join(ciborg_root_path, "script/"), "script/")
      end

      def sync_github_ssh_key
        master_server.upload(ciborg_config.github_ssh_key_path, "~/.ssh/id_rsa")
      end

      def sync_chef_recipes
        master_server.upload(File.join(ciborg_root_path, "chef/"), "chef/")
        master_server.upload("cookbooks/", "chef/project-cookbooks/")
      end

      def upload_soloist
        Tempfile.open("ciborg-soloistrc") do |file|
          file.write(YAML.dump(JSON.parse(JSON.dump(ciborg_config.soloistrc))))
          file.close
          master_server.upload(file.path, "soloistrc")
        end
      end
    end

    private

    def ciborg_root_path
      File.expand_path('../../..', __FILE__)
    end

    def ciborg_config_path
      File.expand_path("config/ciborg.yml", Dir.pwd)
    end

    def wait_for_server(server)
      Godot.new(server.public_ip_address, 22, :timeout => 180).wait!
    end

    # The proc is given a Fog server object and must return true/false
    def confirmation_proc(force)
      if force
        ->(_) { true }
      else
        ->(server) {
          yes?("DESTROY #{server.id} (#{server.public_ip_address})?")
        }
      end
    end
  end
end

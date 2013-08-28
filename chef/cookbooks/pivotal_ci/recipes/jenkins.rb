cookbook_file "#{Chef::Config[:file_cache_path]}/jenkins-ci.org.key" do
  source "jenkins-ci.org.key"
end

execute "apt-key add #{Chef::Config[:file_cache_path]}/jenkins-ci.org.key" do
  not_if "apt-key list | grep -q 'Kohsuke Kawaguchi'"
end

file "/etc/apt/sources.list.d/jenkins.list" do
  content "deb http://pkg.jenkins-ci.org/debian binary/"
  notifies :run, "execute[apt-get update]", :immediately
end

execute "apt-get update" do
  action :nothing
end

package "jenkins"

execute "usermod jenkins -aG rvm" do
  not_if "groups jenkins | grep rvm"
end

jenkins_flags = "--httpListenAddress=127.0.0.1"
jenkins_config_file = "/etc/default/jenkins"
execute %(echo 'JENKINS_ARGS="$JENKINS_ARGS #{jenkins_flags}"' >> #{jenkins_config_file}) do
  not_if "grep -e '#{jenkins_flags}' #{jenkins_config_file}"
end

service "jenkins" do
  action :restart
end

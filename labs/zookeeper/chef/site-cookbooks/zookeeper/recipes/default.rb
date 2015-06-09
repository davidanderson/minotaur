# Dealing with Zookeeper
#

# Overriding default attributes
node.override['build-essential']['compile_time'] = true

# Use Oracle JDK
node.override['java']['jdk_version'] = '7'
node.override['java']['install_flavor'] = 'oracle'
# staged Oracle JDK tarballs and sha256sum checksums
node.override['java']['jdk']['7']['x86_64']['url'] = 'https://s3.amazonaws.com/bronto-tmp/jdk-7u79-linux-x64.tar.gz'
node.override['java']['jdk']['7']['x86_64']['checksum'] = '29d75d0022bfa211867b876ddd31a271b551fa10727401398295e6e666a11d90'
node.override['java']['jdk']['8']['x86_64']['url'] = 'https://s3.amazonaws.com/bronto-tmp/jdk-8u45-linux-x64.tar.gz'
node.override['java']['jdk']['8']['x86_64']['checksum'] = 'f298ca9239051dfddf8642fcc9e264f7fe5af10adb67027feb3a0ed0a1a2316d'
node.override['java']['oracle']['accept_oracle_download_terms'] = true

node.override['zookeeper']['version'] = ENV['zk_version'].to_s.empty? ? node[:zookeeper][:version] : ENV['zk_version']

# Forming path's and uri's
executable_path = ::File.join(node[:zookeeper][:install_dir],
                              "zookeeper-#{node[:zookeeper][:version]}",
                              'bin',
                              'zkServer.sh')

zookeeper_uri = ::File.join(node[:zookeeper][:mirror],
                              "zookeeper-#{node[:zookeeper][:version]}",
                              "zookeeper-#{node[:zookeeper][:version]}.tar.gz")

config_path = ::File.join(node[:zookeeper][:install_dir],
                          "zookeeper-#{node[:zookeeper][:version]}",
                          'conf',
                          'zoo.cfg')

java_config_path = ::File.join(node[:zookeeper][:install_dir],
                          "zookeeper-#{node[:zookeeper][:version]}",
                          'conf',
                          'java.env')

if node['zookeeper']['version'] == '3.3.6'
  node.override['zookeeper']['checksum'] = 'eb311ec0479a9447d075a20350ecfc5cf6a2a6d9842d13b59d7548430ac37521'
elsif node['zookeeper']['version'] == '3.5.0-alpha'
  node.override['zookeeper']['checksum'] = '87814f3afa9cf846db8d7e695e82e11480f7b19d79d8f146e58c4aefb4289bf4'
end

# Get zookeeper servers either from ENV or from chef environment provided by knife
# Must be in a form of comma-separated list
node.override['zookeeper']['servers'] = ENV['zk_servers'].to_s.empty? ? node[:zookeeper][:servers] : ENV['zk_servers']

# Java and runit are provided by corresponding cookbooks
include_recipe 'build-essential::default'
include_recipe 'java::default'
include_recipe 'runit'

# IPFinder depends on this gem
chef_gem "ipaddr_extensions" do
  version '1.0.0'
end

# Getting zookeeper tarball and extracting it to install_dir
zookeeper node[:zookeeper][:version] do
  user        node[:zookeeper][:user]
  mirror      node[:zookeeper][:mirror]
  checksum    node[:zookeeper][:checksum]
  install_dir node[:zookeeper][:install_dir]
  action      :install
end

# Crafting a config
template "#{config_path}" do
  source "zoo.cfg.erb"
  user node[:zookeeper][:user]
  mode "0755"
  variables({
    :zk_servers => node[:zookeeper][:servers]
  })
end

# config java flags / args 
template "#{java_config_path}" do
  source "java.env.erb"
  user node[:zookeeper][:user]
  mode "0755"
  variables({
    :jvmflags => "-Xms2g -Xmx2g"
  })
end

# Creating data_dir
directory node[:zookeeper][:data_dir] do
  owner node[:zookeeper][:user]
end

# Configuring myid
template "#{node[:zookeeper][:data_dir]}/myid" do
  source "myid.erb"
  owner node[:zookeeper][:user]
  variables({
    :zk_servers => node[:zookeeper][:servers]
  })
  not_if { node[:zookeeper][:servers].nil? }
end

# Adding zookeeper to init
runit_service 'zookeeper' do
  default_logger true
  options({
    exec: executable_path
  })
  action [:enable, :start]
end

# Subscribe to config changes
service 'zookeeper' do
  subscribes :restart, resources(:template => "#{config_path}")
  subscribes :restart, resources(:template => "#{java_config_path}")
end

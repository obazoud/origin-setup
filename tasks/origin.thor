#!/usr/bin/env ruby
#
# Set up an OpenShift Origin service on AWS EC2
#
require 'rubygems'
require 'parseconfig'
require 'aws'
require 'thor'

# create a puppetmaster host

class Origin < Thor

  class_option :verbose, :type => :boolean, :default => false
  class_option :debug, :type => :boolean, :default => false
  class_option :quiet, :type => :boolean, :default => false

  desc "baseinstance NAME", "create a base instance for customization"
  method_option :baseos, :type => :string
  method_option :image, :type => :string
  def baseinstance(name)
    puts "task: origin:baseinstance #{name}" unless options[:quiet]

    @config = get_config if not @config

    #----------------
    # Select an image
    #----------------
    #
    # if we have an image, create an instance, start it and learn the OS
    image_id = options[:image]
    if not image_id
      # use the current OS unless told explicitly
      baseos = options[:baseos] || guess_os
      # TODO: validate baseos
      puts "- baseos: #{baseos}" unless options[:quiet]

      image_id  = @config[baseos]['BaseOSImage']
    end
    # TODO: valudate image_id
    puts "- image id: #{image_id}" unless options[:quiet]

    # ------------------------------
    # create new instance and get id
    # ------------------------------
    #
    instance = invoke('ec2:instance:create', [], 
      :image => image_id, :name => name, :key => @config['AWSKeyPairName'],
      :type => @config['AWSEC2Type']
      )

    puts "instance #{instance.id} starting" if options[:verbose]

    # monitor startup process: wait until running
    (1..20).each do |trynum|
      break if instance.status.to_s === 'running'
      puts "#{instance.id} '#{instance.status}' waiting..." if options[:verbose]
      sleep 15
    end
    raise Exception.new "Instance failed to start" if not instance.status.to_s === 'running'

    #-------------------------
    # get instance information
    #-------------------------

    puts "waiting 3 sec for DNS to be available" if options[:verbose]
    sleep 3

    hostname = instance.dns_name
    puts "waiting for #{hostname} to accept SSH connections" if options[:verbose]

    username = options[:username] || Remote.ssh_username
    # wait for SSH to respond
    available = invoke("remote:available", [hostname], :username => username,
      :wait => true, :verbose => options[:verbose])

    raise Exception.new("host #{hostname} not available") if not available

    instance
  end

  # ================
  # customize a host
  # ================
  desc "prepare HOSTNAME", "add yum repositories and install and config puppet"
  method_option :username, :type => :string
  method_option :ssh_id, :type => :string
  def prepare(hostname)

    # check release and version
    os, releasever = invoke("remote:distribution", [hostname])

    # check archecture
    arch = invoke("remote:arch", [hostname])
    puts "new instance is #{os}-#{releasever} #{arch}" if options[:verbose]

    # ===============================================
    # Prepare the instance for installation
    # ===============================================

    # select stock, nightly, private or local
    #invoke("origin:yum:repo:nightly", [hostname, os, releasever, arch])
    #invoke("origin:yum:repo:extras", [hostname, os, releasever, arch])

    # add puppetlabs repo release RPM
    #if not os === "fedora"
    #  invoke "origin:yum:repo:puppetlabs", [hostname, os, releasever, arch]
    #end

    # packages for configuration management
    pkglist = ['puppet', 'facter', 'augeas']
    invoke "remote:yum:install", [hostname, [pkglist]]

    #invoke "remote:puppet:init", [hostname, puppetcfg]
  end

  desc "puppetmaster NAME", "create a puppetmaster instance"
  method_option :instance, :type => :string
  method_option :hostname, :type => :string
  
  def puppetmaster(name)

    puts "origin:puppetmaster #{name}" unless options[:quiet]

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file

    # create an instance (if not provided)
    if not options[:instance]
      instance = invoke "origin:baseinstance", [name]
    else
      # name the instance (if provided)
      
      instance = invoke "ec2:instance:info", [], :id => options[:instance]
      invoke("ec2:instance:rename", [], :id => options[:instnace],
        :newname => name)
    end

    hostname = instance.dns_name
    invoke "origin:prepare", [hostname]

    # install puppet-server
    Remote::Yum.install_rpms(hostname, username, key_file, 'puppet-server',
      options[:verbose])

    # initialize configuration

    # add certname=<fqdn> to puppet config

    # set manifest location
    # create /var/lib/puppet/manifests
    # set permissions on /var/lib/puppet/manifests
 
    # add manifestdir=/var/lib/puppet/manifests to puppet config

    # create site.pp (clone config git repo?)

    # add local hosts entry?? (external IP == fqdn)

    # configure firewall
    # allow port 8140/TCP (in EC2, limit to internal address space)

    # start puppet master daemon

    #

  end

  no_tasks do

      # Create an EC2 connection
      def login(access_key_id=nil, secret_access_key=nil, credentials_file=nil, 
          region=nil)
        # explicit credentials take precedence over a file
        if not (access_key_id and secret_access_key) then
          credentials_file ||= AWS_CREDENTIALS_FILE
          config = ParseConfig.new File.expand_path(credentials_file)
          access_key_id = config.params['AWSAccessKeyId']
          secret_key = config.params['AWSSecretKey']

          # check them
        end

        connection = AWS::EC2.new(
          :access_key_id => access_key_id,
          :secret_access_key => secret_key
          )
        region ? connection.regions[region] : connection
      end

      def get_config
        filename = ENV["AWS_CREDENTIALS_FILE"] || "~/.awscred"
        ParseConfig.new(File.expand_path(filename)).params
      end

      # determine which distribution family we're running on
      def guess_os
        return "fedora" if File.exist?("/etc/fedora-release")
        if File.exist?("/etc/redhat-release")
          data = File.read("/etc/redhat-release")
          return "centos" if data.match(/centos/)
          return "rhel"
        end
      end
  end

end

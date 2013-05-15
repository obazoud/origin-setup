#!/usr/bin/env ruby
#
# Set up an OpenShift Origin service on AWS EC2
#
require 'rubygems'
require 'thor'
require 'resolv'

require 'openshift/aws'

# create a puppetmaster host

module OpenShift
  class Origin < Thor

    namespace "origin"

    class_option :verbose, :type => :boolean, :default => false
    class_option :debug, :type => :boolean, :default => false
    class_option :quiet, :type => :boolean, :default => false

    desc "baseinstance NAME", "create a base instance for customization"
    method_option :baseos, :type => :string
    method_option :image, :type => :string
    method_option :securitygroup, :type => :string, :default => "default"
    def baseinstance(name)
      puts "task: origin:baseinstance #{name}" unless options[:quiet]

      config = ::OpenShift::AWS.config
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

        image_id  = config[baseos]['BaseOSImage']
      end
      # TODO: valudate image_id
      puts "- image id: #{image_id}" unless options[:quiet]

      # ------------------------------
      # create new instance and get id
      # ------------------------------
      #
      instance = invoke('ec2:instance:create', [], 
        :image => image_id, :name => name, :key => config['AWSKeyPairName'],
        :type => config['AWSEC2Type'], :securitygroup => options[:securitygroup]
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
      puts "instance is #{os}-#{releasever} #{arch}" if options[:verbose]

      # ===============================================
      # Prepare the instance for installation
      # ===============================================

      # NOTE: do these with puppet later ML 201305
      # select stock, nightly, private or local
      #invoke("origin:yum:repo:nightly", [hostname, os, releasever, arch])
      #invoke("origin:yum:repo:extras", [hostname, os, releasever, arch])

      # add puppetlabs repo release RPM
      #if not os === "fedora"
      #  invoke "origin:yum:repo:puppetlabs", [hostname, os, releasever, arch]
      #end
      
      ipaddr = Resolv.new.getaddress hostname
      invoke("remote:set_hostname", [hostname], :ipaddr => ipaddr, 
        :verbose => options[:verbose])

      # packages for firewall management
      pkglist = ["system-config-firewall-base"]
      
      # packages for configuration management
      pkglist << ['puppet', 'facter', 'augeas']
      invoke "remote:yum:install", [hostname, [pkglist]]

      #invoke "remote:puppet:init", [hostname, puppetcfg]
    end


    desc "puppetmaster NAME", "create a puppetmaster instance"
    method_option :instance, :type => :string
    method_option :hostname, :type => :string
    
    def puppetmaster(hostname)

      puts "origin:puppetmaster #{hostname}" unless options[:quiet]

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      manifestdir='/var/lib/puppet/manifests'

      # create an instance (if not provided)
      #if not options[:instance]
      #  instance = invoke "origin:baseinstance", [name]
      #else
      # name the instance (if provided)
      
      #  instance = invoke "ec2:instance:info", [], :id => options[:instance]
      #  invoke("ec2:instance:rename", [], :id => options[:instnace],
      #    :newname => name)
      #end

      #hostname = instance.dns_name
      invoke "origin:prepare", [hostname]

      # install puppet-server
      Remote::Yum.install_rpms(hostname, username, key_file, 'puppet-server',
        options[:verbose])

      # initialize configuration
      # TODO: determine location of data dir
      Remote::File.scp_put(hostname, username, key_file, 
        'data/puppet-master.conf.erb', 'puppet.conf')

      # set hostname in appropriate places in the config
      cmd = "sed -i -e 's/<%= hostname %>/#{hostname}/' puppet.conf"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      # set location of the manifests in the user's home directory
      cmd = "sed -i -e \"/manifestdir\s*=/s|=\s*.*$|= #{manifestdir}|\" puppet.conf"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      # set location of the site.pp in the user's home directory
      cmd = "sed -i -e \"/manifest\s*=/s|=\s*.*$|= #{manifestdir}/site.pp|\" puppet.conf"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      Remote::File.copy(hostname, username, key_file, 
        "puppet.conf", "/etc/puppet/puppet.conf", true, false, false, options[:verbose])

      Remote::File.mkdir(hostname, username, key_file, manifestdir, true, true, 
        options[:verbose])

      cmd = "sudo chown puppet:puppet #{manifestdir}"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      # create site.pp (clone config git repo?)
      cmd = "sudo -u puppet touch #{manifestdir}/site.pp"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      systemd = true if Remote.pidone(hostname, username, key_file) == "systemd"

      # start puppet master daemon
      invoke("remote:service:enable", [hostname, "puppetmaster"],
        :systemd => systemd, :verbose => options[:verbose])
      invoke("remote:service:start", [hostname, "puppetmaster"], 
        :systemd => systemd, :verbose => options[:verbose])

      #cmd = "sudo firewall-cmd --zone public --add-service ssh"
      cmd = "sudo lokkit --service=ssh"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      cmd = "sudo lokkit --port 8140:tcp"
      #cmd = "sudo firewall-cmd --zone public --add-port 8140/tcp"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

    end

    desc "puppetclient NAME", "create a puppet client instance"
    method_option :instance, :type => :string
    method_option :hostname, :type => :string
    
    def puppetclient(hostname, puppetmaster)

      puts "origin:puppetclient #{hostname}, #{puppetmaster}" unless options[:quiet]

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      
    end

    no_tasks do

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
end

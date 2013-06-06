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
    method_option :type, :type => :string
    method_option :keypair, :type => :string
    method_option :securitygroup, :type => :array, :default => ['default']
    method_option :hostname, :type => :string
    method_option :ipaddress, :type => :string
    def baseinstance(name)
      puts "task: origin:baseinstance #{name}" unless options[:quiet]

      config = ::OpenShift::AWS.config

      #  check that the IP address is a valid Elastic IP
      ipaddress = options[:ipaddress]
      if ipaddress
        eip = invoke "ec2:ip:info", [ipaddress]
        # check that it is an existing elastic IP
        if not eip
          raise ArgumentError.new "invalid elastic IP address: #{ipaddress}"
        end
      else
        eip = nil
      end

      #
      hostname = options[:hostname]
      if hostname
        # check if the name has an A record associated
        # determine the available zones
        zones = invoke "route53:zone:contains", [hostname]
        if zones.count == 0
          raise ArgumentError.new(
            "no available zones contain hostname #{hostname}"
            )
        end
          
        # find the containing zone
        zonename = zones[0][:name]
        fqdn = hostname
        fqdn += '.' unless hostname.end_with? '.'
        hostpart = fqdn.gsub('.' + zonename, '')

        host_rr_list = invoke "route53:record:get", [zonename, hostpart]
        if host_rr_list.count < 1
          puts "- no IP address"
          hostip=nil

          # no DNS A record
          # create a new IP address if needed
          if not eip
            eip = invoke("ec2:ip:create", []) if not eip
            ipaddress = eip.ip_address
          end

          # add the IP address to the zone
          # Wait for it to be in sync or you'll get negative record caching
          # on the first DNS query and the whole thing will stop.
          invoke("route53:record:create", [zonename, hostpart, 'A', ipaddress],
            :ttl => 300, :wait => true, :verbose => options[:verbose])

        elsif host_rr_list.count > 1
          raise Exception.new("too many records for #{fqdn}")
        else
          # this needs better checking
          hostip = host_rr_list[0][:resource_records][0][:value]

          puts "- #{hostname}: #{hostip}"
          # there's an A record: does it match the ipaddress?
          if ipaddress and (not ipaddress == hostip)
            raise ArgumentError.new(
              "ipaddress and hostname ip do not match:\n" +
              "ipaddress: #{ipaddress}\n" +
              "dns address: #{hostip} - #{hostname}"
              )
          else
            # create a new IP address
            if not invoke "ec2:ip:info", [hostip]
              raise ArgumentError.new "invalid elastic IP address: #{hostip}"
            end
            ipaddress = hostip
          end

        end

      else
        # hostname not given
        # find one from IP if given

      end


      # -----------------------------------------------
      # hostname, ipaddress and eip have current values
      # -----------------------------------------------

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

      keypair = options[:keypair] || config['AWSKeyPairName']
      type = options[:type] || config['AWSEC2Type']

      # ------------------------------
      # create new instance and get id
      # ------------------------------
      #
      instance = invoke('ec2:instance:create', [], 
        :image => image_id, :name => name, 
        :key => config['AWSKeyPairName'],
        :type => config['AWSEC2Type'], 
        :securitygroup => options[:securitygroup],
        :verbose => options[:verbose]
        )

      puts "- instance #{instance.id} starting" unless options[:quiet]

      # monitor startup process: wait until running
      (1..20).each do |trynum|
        break if instance.status.to_s === 'running'
        puts "- #{instance.id} '#{instance.status}' waiting..." if options[:verbose]
        sleep 15
      end
      raise Exception.new "Instance failed to start" if not instance.status.to_s === 'running'
      puts "- instance #{instance.id} running" unless options[:quiet]

      #-------------------------
      # get instance information
      #-------------------------

      puts "- waiting 3 sec for DNS to be available" if options[:verbose]
      sleep 3

      #hostname ||= instance.dns_name
      puts "- waiting for #{instance.dns_name} to accept SSH connections" unless options[:quiet]

      username = options[:username] || Remote.ssh_username
      # wait for SSH to respond
      available = invoke("remote:available", [instance.dns_name], :username => username,
        :wait => true, :verbose => options[:verbose])

      raise Exception.new("host #{instance.dns_name} not available") if not available
      puts "- host #{instance.dns_name} is available" unless options[:quiet]

      # ----------------------------------------
      # associate instance with eip if available
      # ----------------------------------------
      invoke('ec2:ip:associate', [ipaddress, instance.id]) if ipaddress

      # report how long before the name will resolve
      # new records aren't propagated until the SOA TTL expires.
      # AWS sets the SOA TTL at 900 seconds (15 min) so that's the longest
      # you should have to wait for a new name.
      if defined? fqdn
        begin
          newaddr = Resolv.getaddress fqdn
          puts "- #{fqdn} resolves to #{newaddr}"
        rescue
          resolver = Resolv::DNS.open
          zone_info = resolver.getresources(
            zonename, Resolv::DNS::Resource::IN::SOA)
          puts "- #{fqdn} will resolve in #{zone_info[0].ttl} seconds" if options[:verbose]
        end
      else
        puts "- fqdn is undefined"
      end

      instance
    end

    # ================
    # customize a host
    # ================
    desc "prepare HOSTNAME", "add yum repositories and install and config puppet"
    method_option :username, :type => :string
    method_option :ssh_id, :type => :string
    method_option :packages, :type => :array, :default => []
    method_option :ntpservers, :type => :array, :default => []
    method_option :timezone, :type => :string, :default => "UTC"

    def prepare(hostname)

      puts "task: origin:prepare #{hostname}" unless options[:quiet]

      # check release and version
      os, releasever = invoke("remote:distribution", [hostname])

      # check archecture
      arch = invoke("remote:arch", [hostname])
      puts "- instance is #{os}-#{releasever} #{arch}" if options[:verbose]

      invoke "remote:timezone", [hostname, options[:timezone]]

      ipaddr = Resolv.new.getaddress hostname
      invoke("remote:set_hostname", [hostname], :ipaddr => ipaddr, 
        :verbose => options[:verbose])

      # packages for firewall management and system config management
      pkglist = options[:packages] + ["system-config-firewall-base", 'augeas']
      

      invoke "remote:yum:install", [hostname, [pkglist]]

    end


    desc "puppetmaster NAME", "create a puppetmaster instance"
    method_option :instance, :type => :string
    method_option :hostname, :type => :string
    method_option :timezone, :type => :string, :default => "UTC"
    method_option :siteroot, :type => :string, :default => "/var/lib/puppet/site"
    method_option :siterepo, :type => :string
    
    def puppetmaster(hostname)

      puts "origin:puppetmaster #{hostname}" unless options[:quiet]

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      # check DNS resolution for hostname?
      
      available = invoke("remote:available", [hostname], :username => username,
        :wait => true, :verbose => options[:verbose])

      raise Exception.new("host #{hostname} not available") if not available

      #hostname = instance.dns_name
      invoke("origin:prepare", [hostname],
        :packages => ['puppet-server', 'git'],
        :timezone => options[:timezone],
        :verbose => options[:verbose],
        )

      # add the user to the puppet group
      invoke "puppet:master:join_group", [hostname]

      # create the site root (where the site files will go) if needed
      # check if the directory exists
      invoke "puppet:master:siteroot", [hostname, options[:siteroot]]

      
      # Clone the manifests into place
      invoke("remote:git:clone", [hostname, options[:siterepo]],
        :destdir => File.dirname(options[:siteroot]),
        :destname => File.basename(options[:siteroot]),
        :verbose => options[:verbose]) if options[:siterepo]

      # tell it where to find modules and the site (manifests)
      invoke("puppet:master:configure", [hostname],
        :moduledir => options[:siteroot] + "/modules",
        :manifestdir => options[:siteroot] + "/manifests",
        :verbose => options[:verbose])
      
      # split logs out into their own file
      invoke "puppet:master:enable_logging", [hostname]

      # install standard modules
      invoke "puppet:module:install", [hostname, ['puppetlabs-ntp']]

      # open ports for SSH and puppet
      invoke "remote:firewall:stop", [hostname]
      invoke "remote:firewall:service", [hostname, 'ssh']
      invoke "remote:firewall:port", [hostname, 8140]
      invoke "remote:firewall:start", [hostname]

      #invoke("puppet:cert:generate", [hostname, hostname])

      systemd = true if Remote.pidone(hostname, username, key_file) == "systemd"

      # start puppet master daemon
      invoke("remote:service:enable", [hostname, "puppetmaster"],
        :systemd => systemd, :verbose => options[:verbose])
      invoke("remote:service:start", [hostname, "puppetmaster"], 
        :systemd => systemd, :verbose => options[:verbose])
    end

    desc "puppetclient HOSTNAME MASTER", "create a puppet client instance"
    method_option :timezone, :type => :string, :default => "UTC"

    def puppetclient(hostname, puppetmaster)

      puts "origin:puppetclient #{hostname}, #{puppetmaster}" unless options[:quiet]

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      available = invoke("remote:available", [hostname], :username => username,
        :wait => true, :verbose => options[:verbose])

      raise Exception.new("host #{hostname} not available") if not available

      systemd = true if Remote.pidone(hostname, username, key_file) == "systemd"

      # also install additional packages
      invoke("origin:prepare", [hostname], :packages => ['puppet', 'facter'],
        :timezone => options[:timezone],
        :verbose => options[:verbose])

      invoke "puppet:agent:set_server", [hostname, puppetmaster]

      # split logs out into their own file
      invoke "puppet:agent:enable_logging", [hostname]

      # start puppet daemon
      invoke("remote:service:enable", [hostname, "puppet"],
        :systemd => systemd, :verbose => options[:verbose])
      invoke("remote:service:start", [hostname, "puppet"], 
        :systemd => systemd, :verbose => options[:verbose])

      # wait for the signing request to appear?
      maxtries = 5
      pollinterval = 5 # seconds
      (1..maxtries).each { |trynum|
        certlist = Puppet::Cert.list(puppetmaster, username, key_file, hostname, false, 
          options[:verbose])
        puts "- try #{trynum}: certlist = #{certlist}" if options[:verbose]
        break if certlist.count > 0
        sleep pollinterval
      }

      # raise Exception.new "timed out waiting for cert request" if certlist.count == 0

      # then sign it?
      invoke "puppet:cert:sign", [puppetmaster, hostname]

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

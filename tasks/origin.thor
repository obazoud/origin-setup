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
    method_option :securitygroup, :type => :string, :default => "default"
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
        begin
          hostip = Resolv.getaddress hostname
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

        rescue Resolv::ResolvError => e
          # no DNS A record
          # create a new IP address if needed
          if not eip
            eip = invoke("ec2:ip:create", []) if not eip
            ipaddress = eip.ip_address
          end

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
          puts "- fqdn = #{fqdn}"
          hostpart = fqdn.gsub('.' + zonename, '')

          # add the IP address to the zone
          # Wait for it to be in sync or you'll get negative record caching
          # on the first DNS query and the whole thing will stop.
          invoke("route53:record:create", [zonename, hostpart, 'A', ipaddress],
            :ttl => 120, :wait => true, :verbose => options[:verbose])

          # report how long before the name will resolv
          #resolver = Resolv::DNS.open
          #zone_info = resolver.getresources(
          #  zonename, Resolv::DNS::Resource::IN::SOA)
          #puts "- #{zonename} fqdn #{fqdn} will resolve in #{zone_info[0].ttl} seconds" if options[:verbose]
          
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

      #hostname ||= instance.dns_name
      puts "waiting for #{instance.dns_name} to accept SSH connections" if options[:verbose]

      username = options[:username] || Remote.ssh_username
      # wait for SSH to respond
      available = invoke("remote:available", [instance.dns_name], :username => username,
        :wait => true, :verbose => options[:verbose])

      raise Exception.new("host #{instance.dns_name} not available") if not available

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
    method_option :timezone, :type => :string, :default => 

    def prepare(hostname)

      puts "task: origin:prepare #{hostname}" unless options[:quiet]

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
      pkglist = options[:packages] + ["system-config-firewall-base"]
      
      # packages for configuration management
      pkglist << ['puppet', 'facter', 'augeas']

      invoke "remote:yum:install", [hostname, [pkglist]]

      # get ssh access
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      # log puppet to its own file
      Remote::File.scp_put(hostname, username, key_file,
        "data/rsyslog-puppet.conf", "rsyslog-puppet.conf",
        options[:verbose])

      Remote::File.copy(hostname, username, key_file,
        "rsyslog-puppet.conf", "/etc/rsyslog.d/puppet.conf",
        true, false, false, options[:verbose])

      cmd = "sudo touch /var/log/puppet.log"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      cmd = "sudo touch /var/log/puppet-master.log"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      systemd = true if Remote.pidone(hostname, username, key_file) == "systemd"

      invoke("remote:service:restart", [hostname, "rsyslog"],
        :systemd => systemd, :verbose => options[:verbose])

      #invoke "puppet:master:init", [hostname, puppetcfg]
    end


    desc "puppetmaster NAME", "create a puppetmaster instance"
    method_option :instance, :type => :string
    method_option :hostname, :type => :string
    method_option :siterepo, :type => :string
    
    def puppetmaster(hostname)

      puts "origin:puppetmaster #{hostname}" unless options[:quiet]

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      # check DNS resolution for hostname?
      
      manifestdir = '/var/lib/puppet/manifests'
      moduledir = '/var/lib/puppet/modules'

      #hostname = instance.dns_name
      invoke("origin:prepare", [hostname],
        :packages => ['puppet-server', 'git'],
        :verbose => options[:verbose])

      # add the user to the puppet group
      cmd = "sudo augtool --autosave set /files/etc/group/puppet/user[1] #{username}"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      # unpack the puppet site information where it can be managed
      if options[:siterepo]

        sitename = File.basename(options[:siterepo], '.git')
        sitepath = '/var/lib/puppet/' + sitename

        manifestdir = sitepath + '/manifests'
        moduledir = sitepath + '/modules'

        Remote::File.mkdir(hostname, username, key_file,
          sitepath, true, true, options[:verbose])

        Remote::File.group(hostname, username, key_file,
          sitepath, 'puppet', true, false, options[:verbose])

        # Allow the puppet group to write to the manifests area
        Remote::File.permission(hostname, username, key_file,
          sitepath, 'g+ws', true, false, options[:verbose])

        # Clone the manifests into place
        invoke("remote:git:clone", [hostname, options[:siterepo]],
          :destdir => '/var/lib/puppet',
          :destname => sitename,
          :verbose => options[:verbose])

        # Allow git pulls from user $HOME/manifests
        Remote::File.symlink(hostname, username, key_file,
          sitepath, sitename, 
          false, options[:verbose])
      end

      # initialize configuration
      # TODO: determine location of data dir
      Remote::File.scp_put(hostname, username, key_file, 
        'data/puppet-master.conf.erb', 'puppet.conf')

      # set hostname in appropriate places in the config
      cmd = "sed -i -e 's/<%= hostname %>/#{hostname}/' puppet.conf"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      # set location of the manifests
      cmd = "sed -i -e 's|<%= manifestdir %>|#{manifestdir}|' puppet.conf"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      # set location of the modules
      cmd = "sed -i -e 's|<%= moduledir %>|#{moduledir}|' puppet.conf"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      Remote::File.copy(hostname, username, key_file, 
        "puppet.conf", "/etc/puppet/puppet.conf", true, false, false, options[:verbose])


      Remote::File.mkdir(hostname, username, key_file,
        "/var/lib/puppet/modules", true, true, options[:verbose])

      invoke "puppet:module:install", [hostname, ['puppetlabs-ntp']]

      systemd = true if Remote.pidone(hostname, username, key_file) == "systemd"

      cmd = "sudo service iptables stop"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      
      # lokkit seems to block when run via rubygem-ssh
      #cmd = "sudo firewall-cmd --zone public --add-service ssh"
      cmd = "sudo lokkit --nostart --service=ssh"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      #cmd = "sudo firewall-cmd --zone public --add-port 8140/tcp"
      cmd = "sudo lokkit --nostart --port=8140:tcp"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      # NOTE: lokkit seems to hang when run by rubygem-ssh
      #cmd = "sudo lokkit --enabled &"
      #exit_code, exit_signal, stdout, stderr = Remote.remote_command(
      #  hostname, username, key_file, cmd, options[:verbose])

      cmd = "sudo service iptables start"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      invoke("puppet:cert:generate", [hostname, hostname])

      # start puppet master daemon
      invoke("remote:service:enable", [hostname, "puppetmaster"],
        :systemd => systemd, :verbose => options[:verbose])
      invoke("remote:service:start", [hostname, "puppetmaster"], 
        :systemd => systemd, :verbose => options[:verbose])

    end

    desc "puppetclient HOSTNAME MASTER", "create a puppet client instance"
    method_option :instance, :type => :string    
    def puppetclient(hostname, puppetmaster)

      puts "origin:puppetclient #{hostname}, #{puppetmaster}" unless options[:quiet]

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      systemd = true if Remote.pidone(hostname, username, key_file) == "systemd"

      invoke "origin:prepare", [hostname]

      invoke "puppet:agent:set_server", [hostname, puppetmaster]

      # start puppet daemon
      invoke("remote:service:enable", [hostname, "puppet"],
        :systemd => systemd, :verbose => options[:verbose])
      invoke("remote:service:start", [hostname, "puppet"], 
        :systemd => systemd, :verbose => options[:verbose])

      # wait for the signing request to appear?
      sleep 5
      # maxtries = 5
      # pollinterval = 5 # seconds
      # (1..maxtries).each { |trynum|
      #   certlist = invoke "puppet:cert:list", [puppetmaster, hostname]
      #   break if certlist.count > 0
      #   sleep pollinterval
      # }

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

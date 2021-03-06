#!/usr/bin/env ruby
#
# Set up an OpenShift Origin service on AWS EC2
#
require 'rubygems'
require 'thor'
require 'resolv'

#require 'openshift/aws'

# create a puppetmaster host

module OpenShift
  class Origin < Thor
    
   namespace "origin"

    class_option :verbose, :type => :boolean, :default => false
    class_option :debug, :type => :boolean, :default => false
    class_option :quiet, :type => :boolean, :default => false
    class_option :baseos, :type => :string, :default => "fedora19"

    # The default location of the AWS credentials file
    default_awscred_filename = ENV['HOME'] + "/.awscred"

    desc "baseinstance NAME", "create a base instance for customization"
    method_option :image, :type => :string
    method_option :type, :type => :string
    method_option :keypair, :type => :string
    method_option :disksize, :type => :numeric, :default => 10
    method_option :securitygroup, :type => :array, :default => ['default']
    method_option :hostname, :type => :string
    method_option :ipaddress, :type => :string
    method_option :enable_updates, :type => :boolean, :default => true
    method_option :elasticip, :type => :boolean, :default => false
    method_option :awscred, :type => :string, :default => default_awscred_filename
    def baseinstance(name)
      puts "task: origin:baseinstance #{name}" unless options[:quiet]

      start_time = Time.now

      puts "awscred file = #{options[:awscred]}"

      # Initialize the AWS configuration if environment variables are not set.
      # Priority:
      #  specified awscred config
      #  AWS_* environment variables
      #  $HOME/.awscred config
      #  ./.awscred config
      if options[:awscred] and File.exists? options[:awscred]
        config = ParseConfig.new(options[:awscred])
      else
        local_filename = File.expand_path('.awscred')
        global_filename = ENV['HOME'] + '/.awscred'
        if File.exist?(local_filename)
          real_filename = local_filename
        elsif File.exist?(global_filename)
          real_filename = global_filename
        end
        if defined? real_filename
          config = ParseConfig.new(real_filename)
        else
          raise Exception.new("unable to find AWS configuration")
        end
      end

      #  check that the IP address is a valid Elastic IP
      ipaddress = options[:ipaddress]
      if ipaddress
        eip = invoke "ec2:ip:info", [ipaddress], options
        # check that it is an existing elastic IP
        if not eip
          raise ArgumentError.new "invalid elastic IP address: #{ipaddress}"
        end
      else
        eip = nil
      end

      #
      hostname = options[:hostname]
      if hostname and options[:elasticip]
        # check if the name has an A record associated
        # determine the available zones
        zones = invoke "route53:zone:contains", [hostname], options
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

        host_rr_list = invoke "route53:record:get", [zonename, hostpart], options
        if host_rr_list.count < 1
          puts "- no IP address"
          hostip=nil

          # no DNS A record
          # create a new IP address if needed
          if not eip
            eip = invoke("ec2:ip:create", [], options) if not eip
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
            if not invoke "ec2:ip:info", [hostip], options
              raise ArgumentError.new "invalid elastic IP address: #{hostip}"
            end
            ipaddress = hostip
          end

        end

      else
        # hostname not given
        # find one from IP if given
        puts "no hostname given or no elastic IP"
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
        if options[:baseos]
          puts "trying to get osname and osversion from #{options[:baseos]}"
          #osname, osversion
          osmatch = options[:baseos].downcase.match(/([^\d-]+)-?([\.\d]+)/)
          puts "osmatch = #{osmatch}"
          @osname, @osversion = osmatch[1..2] if osmatch
        end
        puts "- before guess: osname = #{@osname}, osversion = #{@osversion}"
        osname, osversion = guess_os unless osname and osversion
        # TODO: validate baseos
        puts "- osname: #{@osname}, osversion: #{@osversion}" unless options[:quiet]

        image_id  = config[@osname + @osversion]['BaseOSImage']        
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
        :type => (options[:type] || config['AWSEC2Type']), 
        :securitygroup => options[:securitygroup],
        :disksize => options[:disksize],
        :verbose => options[:verbose]
        )

      puts "- instance #{instance.id} starting" unless options[:quiet]

      # set a few tags
      # owner = $USER
      # ssh_user = {root|ec2-user|fedora}
      # 

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

      username = options[:username] || Remote.ssh_username(options[:baseos])
      # wait for SSH to respond
      available = invoke("remote:available", [instance.dns_name], :username => username,
        :wait => true, :verbose => options[:verbose])


      raise Exception.new("host #{instance.dns_name} not available") if not available
      puts "- host #{instance.dns_name} is available" unless options[:quiet]

      # ----------------------------------------
      # associate instance with eip if available
      # ----------------------------------------
      if ipaddress
        invoke('ec2:ip:associate', [ipaddress, instance.id], options)

        # report how long before the name will resolve
        # new records aren't propagated until the SOA TTL expires.
        # AWS sets the SOA TTL at 900 seconds (15 min) so that's the longest
        # you should have to wait for a new name.
        if ((defined? fqdn) and (not fqdn == nil))
          begin
            puts "trying to resolve '#{fqdn}'"
            newaddr = Resolv.getaddress fqdn
            puts "- #{fqdn} resolves to #{newaddr}"
          rescue
            resolver = Resolv::DNS.open
            zone_info = 
              resolver.getresources(zonename, Resolv::DNS::Resource::IN::SOA)
            puts "- #{fqdn} will resolve in #{zone_info[0].ttl} seconds" if options[:verbose]
          end
        else
          puts "- fqdn is undefined - no hostname specified"
        end

        # make sure it's available under its new name before proceeding
        username = options[:username] || Remote.ssh_username
        key_file = options[:ssh_key_file] || Remote.ssh_key_file
        Remote.available(instance.dns_name, username, key_file, 
                         true, 15, 10, options[:verbose])

        raise Exception.new("host #{instance.dns_name} not available") if not available
        puts "- host #{instance.dns_name} is available" unless options[:quiet]

      end

      # set hostname and preserve if provided
      if hostname
        # set the remote hostname:
        #  /etc/hostname
        #  /etc/sysconfig/network
        invoke('remote:set_hostname', [hostname, instance.dns_name], options)

        # preserve: /etc/cloud/cloud.conf add
        invoke('remote:preserve_hostname', [instance.dns_name], options)
      end

      end_time = Time.new()
      duration = end_time - start_time
      if options[:verbose]
        puts "+ baseinstance complete: duration #{duration.round(2)} seconds"
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
    method_option :timezone, :type => :string, :default => "Etc/UTC"
    def prepare(hostname)

      start_time = Time.now

      puts "task: origin:prepare #{hostname}" unless options[:quiet]

      username = options[:username] || Remote.ssh_username(options[:baseos])
      key_file = options[:ssh_key_file] || Remote.ssh_key_file
      puts "- username: #{username}, key_file: #{key_file}" if options[:verbose]

      # check release and version
      os, releasever = invoke("remote:distribution", [hostname], options)

      # check archecture
      arch = invoke("remote:arch", [hostname], options)
      puts "- instance is #{os}-#{releasever} #{arch}" if options[:verbose]

      invoke "remote:timezone", [hostname, options[:timezone]], options

      ipaddr = Resolv.new.getaddress hostname

      # temporarily disable updates
      #if not options[:enable_updates]
      #  cmd = "sudo sed -i -e '/enabled=/s/=1/=0/' /etc/yum.repos.d/fedora-updates.repo"
      #  exit_code, exit_signal, stdout, stderr = Remote.remote_command(
      #    hostname, username, key_file, cmd, options[:verbose], )
      #end

      # packages for firewall management and system config management
      pkglist = options[:packages] + ['ntp', 'ntpdate', 'firewalld', 'augeas']      
      invoke "remote:yum:install", [hostname, [pkglist]], options

      # enable firewall?

      systemd = Remote.pidone(hostname, username, key_file, options[:verbose]) == "systemd"

      # enable NTP?
      Remote::Service.execute(hostname, username, key_file, 'ntpdate', 'enable', systemd, options[:verbose])
      Remote::Service.execute(hostname, username, key_file, 'ntpdate', 'start', systemd, options[:verbose])
      Remote::Service.execute(hostname, username, key_file, 'ntpd', 'enable', systemd, options[:verbose])
      Remote::Service.execute(hostname, username, key_file, 'ntpd', 'start', systemd, options[:verbose])

      end_time = Time.new()
      duration = end_time - start_time
      if options[:verbose]
        puts "+ prepare complete: duration #{duration.round(2)} seconds"
      end

    end


    desc "puppetmaster NAME", "create a puppetmaster instance"
    method_option :instance, :type => :string
    method_option :hostname, :type => :string
    method_option :timezone, :type => :string, :default => "UTC"
    method_option :siteroot, :type => :string, :default => "/var/lib/puppet/site"
    method_option :siterepo, :type => :string
    method_option :puppetlabs, :type => :boolean, :default => false
    method_option :storedconfigs, :type => :boolean, :default => true
    
    def puppetmaster(hostname)

      start_time = Time.now

      puts "origin:puppetmaster #{hostname}" unless options[:quiet]

      username = options[:username] || Remote.ssh_username(options[:baseos])
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      # check DNS resolution for hostname?
      
      available = invoke("remote:available", [hostname], :username => username,
        :wait => true, :verbose => options[:verbose])

      raise Exception.new("host #{hostname} not available") if not available

      package_list = ['git', 'puppet-server', 'patch',
                      'rubygem-activerecord', 'rubygem-sqlite']

      invoke('remote:yum:install', [hostname, package_list], options)

      invoke "puppet:agent:set_server", [hostname, hostname], options

      # add the user to the puppet group
      invoke "puppet:master:join_group", [hostname], options

      # create the site root (where the site files will go) if needed
      # check if the directory exists
      invoke "puppet:master:siteroot", [hostname, options[:siteroot]], options

      if options[:storedconfigs]
        invoke "puppet:master:storedconfigs", [hostname], options 
      end
      
      # Clone the manifests into place
      invoke("remote:git:clone", [hostname, options[:siterepo]],
        :destdir => File.dirname(options[:siteroot]),
        :destname => File.basename(options[:siteroot]),
        :verbose => options[:verbose]) if options[:siterepo]
      
      # initialize git sub-modules to pull in forked module git repos
      # (avoiding stale packages in puppetforge if needed)
      invoke('remote:git:checkout',  [hostname, 'site'], options)
      invoke('remote:git:submodule:init', [hostname, 'site'], options)
      invoke('remote:git:submodule:update', [hostname, 'site'], options)

      # tell it where to find modules and the site (manifests)
      invoke("puppet:master:configure", [hostname],
        :moduledir => options[:siteroot] + "/modules",
        :manifestdir => options[:siteroot] + "/manifests",
        :verbose => options[:verbose])
      
      # split logs out into their own file
      invoke "puppet:master:enable_logging", [hostname], options


      # install standard modules for puppet master process
      invoke(
        "puppet:module:install", 
        [hostname,
            'puppetlabs-ntp', 
            'puppetlabs-java',
            #'puppetlabs-mongodb',
            #'puppetlabs-activemq',
            #'puppetlabs-mcollective',
        ], 
        options.merge({'username' => 'root'}))

      #invoke("puppet:cert:generate", [hostname, hostname])

      systemd = true if Remote.pidone(hostname, username, key_file) == "systemd"

      Remote::Service.execute(hostname, username, key_file, 'firewalld',
        'enable', systemd, options[:verbose])
      Remote::Service.execute(hostname, username, key_file, 'firewalld',
        'start', systemd, options[:verbose])

      sleep 2

      Remote.available(hostname, username, key_file, true, 10, 15,
        options[:verbose])

      # open ports for SSH and puppet
      #invoke "remote:firewall:service", [hostname, 'ssh'], options
      Remote::Firewall.port(hostname, username, key_file, 8140, 'tcp',
        false, true, options[:verbose])

      # start puppet master daemon
      Remote::Service.execute(hostname, username, key_file, 'puppetmaster',
        'enable', systemd, options[:verbose])
      Remote::Service.execute(hostname, username, key_file, 'puppetmaster',
        'start', systemd, options[:verbose])

      end_time = Time.new()
      duration = end_time - start_time
      if options[:verbose]
        puts "+ puppet master complete: duration #{duration.round(2)} seconds"
      end

    end

    desc "puppetclient HOSTNAME MASTER", "create a puppet client instance"
    method_option :timezone, :type => :string, :default => "UTC"
    method_option :puppetlabs, :type => :boolean, :default => false
    def puppetclient(hostname, puppetmaster)

      start_time = Time.now

      puts "origin:puppetclient #{hostname}, #{puppetmaster}" unless options[:quiet]

      username = options[:username] || Remote.ssh_username(options[:baseos])
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      available = invoke("remote:available", [hostname], :username => username,
        :wait => true, :verbose => options[:verbose])

      raise Exception.new("host #{hostname} not available") if not available


      puppet_packages = ['ruby', 'puppet', 'facter']
      invoke("remote:yum:install", [hostname, puppet_packages], options)

      systemd = true if Remote.pidone(hostname, username, key_file) == "systemd"

      Remote::Service.execute(hostname, username, key_file, 'firewalld',
        'enable', systemd, options[:verbose])
      Remote::Service.execute(hostname, username, key_file, 'firewalld',
        'start', systemd, options[:verbose])

      sleep 2

      Remote.available(hostname, username, key_file, true, 10, 15, 
        options[:verbose])

      invoke "puppet:agent:set_server", [hostname, puppetmaster], options
      #invoke "puppet:agent:pluginsync", [hostname]

      # split logs out into their own file
      invoke "puppet:agent:enable_logging", [hostname], options

      systemd = true if Remote.pidone(hostname, username, key_file) == "systemd"

      osname, osvers = Remote.distribution(hostname, username, key_file)
      puppetagent = (osname == 'fedora' and osvers.to_i > 18) ? 'puppetagent' : 'puppet'
      
      key_id = invoke "remote:get_hostname", [hostname]
      
      # start puppet daemon
      invoke("remote:service:enable", [hostname, puppetagent],
        :systemd => systemd, :verbose => options[:verbose])
      invoke("remote:service:start", [hostname, puppetagent], 
        :systemd => systemd, :verbose => options[:verbose])

      # wait for the signing request to appear?
      maxtries = 5
      pollinterval = 5 # seconds
      (1..maxtries).each { |trynum|
        certlist = Puppet::Cert.list(puppetmaster, username, key_file, key_id, false, 
          options[:verbose])
        puts "- try #{trynum}: certlist = #{certlist}" if options[:verbose]
        break if certlist.count > 0
        sleep pollinterval
      }

      # raise Exception.new "timed out waiting for cert request" if certlist.count == 0

      # then sign it?
      invoke "puppet:cert:sign", [puppetmaster, key_id], options

      end_time = Time.new()
      duration = end_time - start_time
      if options[:verbose]
        puts "+ puppet client complete: duration #{duration.round(2)} seconds"
      end

    end

    no_tasks do

      # determine which distribution family we're running on
      def guess_os
        raise Exception.new("Unable to get base OS: no release file") unless File.exist?("/etc/redhat-release")
        data = File.read("/etc/redhat-release").strip
        parts = data.match(/^(.*)\srelease\s+((\d+)(\.(\d+))?)\s+/)
        return nil if parts == nil
        osname = "fedora" if parts[1] == "Fedora"
        osname = "rhel" if parts[1] == "Red Hat Enterprise Linux Server"
        osname = "centos" if data.downcase.match(/centos/) #
        raise Exception.new("Unable to get base OS from release file") if not defined? osname

        osversion = parts[2]
        return osname, osversion
      end
    end

    desc "baserepo HOSTNAME", "initialize the OpenShift Origin yum repo on the host"
    method_option :username
    method_option :ssh_key_file
    def baserepo(hostname)
      puts "task: baserepo #{hostname}" if not options[:quiet]

      username = options[:username] || Remote.ssh_username(options[:baseos])
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      repo_file = 'openshift-origin.repo'

      # copy the deps configfile
      Remote::File.scp_put(hostname, username, key_file,
        "data/#{repo_file}", repo_file)
      cmd = "sudo mv #{repo_file} /etc/yum.repos.d/#{repo_file}"
      Remote.remote_command(hostname, username, key_file, cmd,
        options[:verbose])
      distro, osversion = invoke 'remote:distribution', [hostname], options
      Remote::Yum.setvar(hostname, username, key_file,
        'distro', distro, options[:verbose])
      Remote::Yum.setvar(hostname, username, key_file,
        'osmajorvers', osversion.to_i, options[:verbose])      
    end

    desc "depsrepo HOSTNAME", "initialize the OpenShift Origin dependancies yum repo on the host"
    method_option :username
    method_option :ssh_key_file
    def depsrepo(hostname)
      puts "task: depsrepo #{hostname}" if not options[:quiet]

      username = options[:username] || Remote.ssh_username(options[:baseos])
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      repo_file = 'openshift-origin-deps.repo'

      # copy the deps configfile
      Remote::File.scp_put(hostname, username, key_file,
        "data/#{repo_file}", repo_file, false, options[:verbose])
      cmd = "sudo mv #{repo_file} /etc/yum.repos.d/#{repo_file}"
      Remote.remote_command(hostname, username, key_file, cmd,
        options[:verbose])

      @distro, @osversion = Remote.distribution(hostname, username, key_file,
                                                  options[:verbose])
      @distro = 'rhel' if @distro == 'centos'
      Remote::Yum.setvar(hostname, username, key_file,
                         'distro', @distro, options[:verbose])
      Remote::Yum.setvar(hostname, username, key_file,
                         'osmajorvers', @osversion.to_i, options[:verbose])
    end

    desc "builddep HOSTNAME GITROOT", "install build requirements"
    def builddep(hostname, gitroot)
      puts "task: builddep #{hostname} #{gitroot}" if not options[:quiet]

      username = options[:username] || Remote.ssh_username(options[:baseos])
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      #cmd = "find #{gitroot} -name \*.spec | xargs sudo yum-builddep -y"
      cmd = "for SPEC in $(find #{gitroot} -name \*.spec) ; do sudo yum-builddep -y $SPEC ; done"
      Remote.remote_command(hostname, username, key_file, cmd, 
                            options[:verbose])
    end
  
    desc "buildhost HOSTNAME GITURL", "turn a host into a build box"
    method_option :gitroot
    method_option :branch
    method_option :pkgroot
    method_option :build, :type => :boolean, :default => true
    def buildhost(hostname, giturl)
      puts "task: buildhost #{hostname} #{giturl}" if not options[:quiet]


      gitroot = options[:gitroot] || File.basename(giturl, '.git')

      invoke 'origin:prepare', [hostname], options.merge({:packages => ['git',  'yum-utils',  'tito']})

      invoke 'remote:git:clone', [hostname, giturl], options

      invoke 'origin:depsrepo', [hostname], options

      invoke 'origin:builddep', [hostname, gitroot], options

      invoke('origin:buildrpms', [hostname, gitroot]) if options[:build]

    end

    desc "buildrpms HOSTNAME GITROOT", "build all packages on the build host"
    method_option :pkgname, :default => '\*'
    method_option :test, :type => :boolean, :default => false
    method_option :rpmbuild_basedir
    def buildrpms(hostname, gitroot)
      puts "task: buildrpms #{hostname} #{gitroot} '#{options[:pkgname]}" if not options[:quiet]
      username = options[:username] || Remote.ssh_username(options[:baseos])
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      test = options[:test] ? '--test' : ""

      cmd = <<EOF
for SPECFILE in $(find #{gitroot} -name #{options[:pkgname]}.spec)
do
  PKGDIR=$(dirname $SPECFILE)
  ( cd $PKGDIR ; tito build --rpm #{test} )
done
EOF

      Remote.remote_command(hostname, username, key_file, cmd, 
                            options[:verbose])

    end


  end

end

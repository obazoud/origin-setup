#!/usr/bin/env ruby
# Present tasks to manage AWS EC2 images and instances
#
require 'rubygems'
require 'thor'

'''
Tasks:
  devenv build NAME BUILD_NUM       # Build a new devenv AMI with the given NAME
'''

  # Manage Amazon Web Services EC2 instances and images
module OpenShift
  class Devenv < Thor

    namespace "devenv"

    class_option :verbose, :type => :boolean, :default => false
    class_option :live, :type => :boolean, :default => true
    class_option :username, :type => :string
    class_option :ssh_key_id, :type => :string

    # Build a new devenv AMI
    desc "build NAME BUILD_NUM", "Build a new devenv AMI with the given NAME"
    method_option :base_os, :default => nil, :desc => "Operating system for Origin (fedora or rhel)"
    method_option :register, :type => :boolean, :desc => "Register the instance"
    method_option :terminate, :type => :boolean, :desc => "Terminate the instance on exit"
    method_option :branch, :default => "master", :desc => "Build instance off the specified branch"
    method_option :yum_repo, :default => "candidate", :desc => "Build instance off the specified yum repository"
    method_option :reboot, :type => :boolean, :desc => "Reboot the instance after updating"
    method_option :verbose, :type => :boolean, :desc => "Enable verbose logging"
    method_option :official, :type => :boolean, :desc => "For official use.  Send emails, etc."
    method_option :exclude_broker, :type => :boolean, :desc => "Exclude broker tests"
    method_option :exclude_runtime, :type => :boolean, :desc => "Exclude runtime tests"
    method_option :exclude_site, :type => :boolean, :desc => "Exclude site tests"
    method_option :exclude_rhc, :type => :boolean, :desc => "Exclude rhc tests"
    method_option :include_web, :type => :boolean, :desc => "Include running Selenium tests"
    method_option :include_extended, :required => false, :desc => "Include extended tests"
    method_option :base_image_filter, :desc => "Filter for the base image to use EX: devenv-base_*"
    method_option :region, :required => false, :desc => "Amazon region override (default us-east-1)"
    method_option :install_from_source, :type => :boolean, :desc => "Indicates whether to build based off origin/master"
    method_option :install_from_local_source, :type => :boolean, :desc => "Indicates whether to build based on your local source"
    method_option :install_required_packages, :type => :boolean, :desc => "Create an instance with all the packages required by OpenShift"
    method_option :skip_verify, :type => :boolean, :desc => "Skip running tests to verify the build"
    method_option :instance_type, :required => false, :desc => "Amazon machine type override (default c1.medium)"
    method_option :extra_rpm_dir, :required => false, :dessc => "Directory containing extra rpms to be installed"
    method_option :disable_selinux, :required => false, :default => false, :type => :boolean, :dessc => "Directory containing extra rpms to be installed"

    def build(name, build_num)

      #
      # Create a connection to the AWS service
      #
      handle = login
      
      # read the configuration information
      defaults = devenvconfig

      # =================================
      #
      # Start a new instance to configure
      #
      # =================================

      # ---------------------------------
      # Find the image to use as the base
      # ---------------------------------

      # determine the OS to use
      base_os = options[:base_os] || guess_os
      raise ArgumentError.new "unable to determine base_os family" if base_os === nil
      if not ['fedora', 'rhel', 'centos'].member? base_os
        raise ArgumentError.new "Invalid base_os family #{base_os}"
      end
      puts "building devenv on #{base_os}" if options[:verbose]
      
      # find the base AMI for new devenv instances
      if defaults[base_os] and defaults[base_os]['BaseOSImage'] then
        # ask from the config file
        base_image = defaults[base_os]['BaseOSImage']
        puts "using base image #{base_image} from cfgfile" if options[:verbose]
      else
        # look for one tagged for this base OS?
        puts "Looking for devenv images for base_os #{base_os}"
        images = handle.images.with_owner(:self).
          filter('tag-key', 'devenv_base_os').filter('tag-value', base_os)
        puts "I found #{images.count} devenv images for base_os #{base_os}"

        if images.count === 1
          base_image = images.to_a[0].id
        else
          # look in the old constants file
          begin
            require 'origin_constants'
          rescue LoadError => e
            puts "cannot load origin constants for base os AMI for #{base_os}"
          end
        end
      end

      puts "using image #{base_image} to create a new devenv instance named #{name}"

      # ------------------------------
      # create new instance and get id
      # ------------------------------
      instance = invoke('ec2:instance:create', [], 
        :image => base_image, :name => name, :key => defaults['AWSKeyPairName'],
        :type => defaults['AWSEC2Type']
        )

      puts "instance #{instance.id} starting" if options[:verbose]

      # monitor startup process: wait until running
      (1..20).each do |trynum|
        break if instance.status.to_s === 'running'
        puts "#{instance.id} '#{instance.status}' waiting..." if options[:verbose]
        sleep 15
      end
      raise Exception.new "Instance failed to start" if not instance.status.to_s === 'running'

      puts "waiting 3 sec for DNS to be available" if options[:verbose]
      sleep 3

      hostname = instance.dns_name
      puts "waiting for #{hostname} to accept SSH connections" if options[:verbose]

      username = options[:username] || Remote.ssh_username
      # wait for SSH to respond
      available = invoke("remote:available", [hostname], :username => username,
        :wait => true, :verbose => options[:verbose])

      raise Exception.new("host #{hostname} not available") if not available


      # check release and version
      real_os, releasever = invoke("remote:distribution", [hostname])

      # check archecture
      real_arch = invoke("remote:arch", [hostname])
      puts "new image is #{real_os}-#{releasever} #{real_arch}" if options[:verbose]

      # ===============================================
      # Prepare the instance for installation
      # ===============================================

      # select stock, nightly, private or local
      invoke("devenv:build:yum_repo_nightly", [hostname, real_os, releasever, real_arch])
      invoke("devenv:build:yum_repo_extras", [hostname, real_os, releasever, real_arch])

      # add puppetlabs repo release RPM
      if not base_os === "fedora"
        invoke "devenv:build:yum_repo_puppetlabs", [hostname]
      end

      # wget is not in the fedora base
      if real_os === 'fedora'
        invoke("devenv:build:install_wget", [hostname])
      end
      invoke "devenv:build:install_puppet", [hostname]
      invoke "devenv:build:init_puppet", [hostname]

      # install git
      #invoke "devenv:build:install_git", [hostname]
      


      # Any errors and we can terminate the instance
      begin

        if options[:install_required_packages]
          # -
          # install tools needed to build and test the openshift software
          # -


          # update all packages
          packages = invoke "remote:yum:update", [hostname], :verbose => options[:verbose]

          # remove epel repo rpm if installed
          # add current epel repo RPM if it's RHEL or CentOS
          # 
          if ['rhel', 'centos'].member? base_os
            invoke "devenv:build:yum_repo_epel", [hostname]
          end

          # install packages for thor
          # ruby, ruby-irb, ruby-libs, ruby-devel, rubygem-thor
          # I suspect that rubygem-thor and ruby-devel is enough
          invoke "devenv:build:install_thor", [hostname]

          # install thor (again) and cucumber
          invoke "devenv:build:install_cucumber", [hostname]

        end

        # remove /data if installing from source (of any kind)
        if options[:install_from_source] || options[:install_from_local_source]
          invoke "devenv:build:remove_builds", [hostname]
        end

        # create /data and give ownership to the user
        invoke "devenv:build:prepare_builds", [hostname]


        # clone all of the repos into /data
        # if local source, sync them from host
        #if options[:install_from_local_source]
        #  invoke("devenv:build:clone_local_sources", [hostname])
        #else
          # otherwise clone the 'bare' repos into /data and checkout a branch
          # clear /data and then clone all the repos in one
        #  invoke("devenv:build:clone_sources", 
        #    [hostname, defaults['sourcerepos']],
        #    :destdir => "/data",
        #    :bare => true,
        #    :verbose => options[:verbose],
        #    )
        #end

        # create build extras directory in origin-server
        # copy all of the extra RPMs over so they're avallable
        # install all of the extra RPMs
        if options[:extra_rpm_dir]
          invoke "devenv:build:install_extras", [hostname, options[:extra_rpm_dir]]
        end

        # install build tools
        #if ['rhel', 'centos'].member? base_os
        #invoke("devenv:build:install_tools", [hostname], 
        #  :base_os => base_os,
        #  :tooldir => '/data/origin-dev-tools', 
        #  :verbose => options[:verbose])
        #end

        #  - if on RHEL or CentOS 6, enable scl ruby193

        # install package build requirements
        #invoke devenv:build:install_deps, [hostname, defaults['sourcerepos']]
        #invoke("devenv:build:install_deps", [hostname],
        #  :base_os => base_os,
        #  :tooldir => '/data/origin-dev-tools',
        #  :verbose => options[:verbose])

        # build packages
        # invoke devenv:build:rpms, [hostname, defaults['sourcerepos']]

        # update selinux configuration
        # disable selinux if requested
        invoke("remote:set_selinux", [hostname], :verbose => options[:verbose],
          :username => username,
          :enforce => (not options[:disable_linux]), 
          :enable => (not options[:disable_linux]),)

        # create puppet module files in /etc/puppet/modules/openshift_origin

        # update hostname in /etc/sysconfig/network with public hostname
        # set hostname 'manually'
        invoke "remote:set_hostname", [hostname]

        # create a puppet file for "openshift origin"

        # run remote build of origin-server packages
        # install built packages
        # invoke "devenv:build:install_openshift"

        # install bind and generate DNS update keys
        # remove leftover DNS update key file
        # install bind again
        # generate a new key
        # copy the key
        # invoke "devenv:build:bind_server"

        # run "post_launch_setup"

        # puppet apply configure_hostname
        # puppet apply configure_origin.pp

        # restart services:
        # mongod, activemq, httpd, openshift-broker, openshift-console
        # named, network, cgconfig, cgred, openshift-cgroups, mcollective sshd
        # stop proxy then restart
        # invoke "devenv:build:restartservices"
        
        if options[:register]
          image_description = invoke('devenv:rpm_manifest', [hostname])
          image_id = invoke('devenv:ami:create_new_image', 
            [instance, name],
            :description => image_description,
            :verbose => options[:verbose])
          puts "registered new image: #{image_id} #{name}"
        end
        
      ensure

        # No matter what, terminate if requested
        begin
          if options[:terminate]
            # could probably do this directly with instance
            invoke("ec2:instance:delete", :id => instance.id, 
              :verbose => options[:verbose]) 
          end
        rescue
          # suppress termination errors - they are already logged
        end

      end
    end

    desc "rpm_manifest HOSTNAME", "get a truncated list of openshift packages"
    def rpm_manifest(hostname)
      puts "task: devenv:rpm_manifest #{hostname}" unless options[:quiet]
      packages = invoke("remote:yum:list", [hostname])

      packages.keys.select { |pkgname| 
        puts "checking #{pkgname}"
        pkgname.match("openshift|rhc")
      }.map { |ospkgname|
        # disassemble each name and compose the manifest string
        ospkgname.gsub!('(rubygem|openshift)-', '')
        ospkgname.gsub!('mcollective-', 'mco-')
      }.join(' ')[0..254]
    end

    # =======================
    # Non task helper methods
    # =======================
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

      def devenvconfig
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

    end # no_tasks
  end # class
end # module

if self.to_s === "main" then
  OpenShift::Devenv.start()
end

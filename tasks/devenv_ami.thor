# 
require 'rubygems'
require 'thor'
require 'parseconfig'


module OpenShift
  class Devenv < Thor
    namespace "devenv"

    class AmiHelpers < Thor
      namespace "devenv:ami"

      class_option :verbose, :type => :boolean, :default => false
      class_option(:username, :type => :string)
      class_option(:ssh_key_file, :type => :string)

      desc("select_image BASEOS", 
        "select an image to use as the base for a new devenv")
      def select_image(base_os=nil)
        puts "task: devenv:ami:select_image"
        
        base_os = guess_os if not base_os

        # determine the OS to use
        raise ArgumentError.new "unable to determine base_os family" if base_os === nil
        if not ['fedora', 'rhel', 'centos'].member? base_os
          raise ArgumentError.new "Invalid base_os family #{base_os}"
        end
        puts "building devenv on #{base_os}" if options[:verbose]

        # from .awsconfig
        defaults = devenvconfig

        # find the base AMI for new devenv instances
        if defaults[base_os] and defaults[base_os]['BaseOSImage'] then
          # ask from the config file
          base_image = defaults[base_os]['BaseOSImage']
          puts "using base image #{base_image} from cfgfile" if options[:verbose]
        else
          # look for one tagged for this base OS?
          puts "Looking for devenv images for base_os #{base_os}"
          # AWS login
          handle = awslogin        
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

        puts "image_id: #{base_image}"
        return base_image
      end

      desc("create_instance IMAGEID, NAME",
        "create a new instance from the selected AMI")
      def create_instance(image_id, name)
        puts "task: devenv:ami:create_instance ${image_id} #{name}"

        # from .awsconfig
        defaults = devenvconfig

        # ------------------------------
        # create new instance and get id
        # ------------------------------
        instance = invoke('ec2:instance:create', [], 
          :image => image_id, :name => name, :key => defaults['AWSKeyPairName'],
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

        puts "instance_id: #{instance.id}"
        instance
      end

      desc("prepare_install HOSTNAME",
        "prepare to install openshift on a running host")
      def prepare_install(hostname)
        puts "task: devenv:ami:prepare_install #{hostname}"

        # check release and version
        real_os, releasever = invoke("remote:distribution", [hostname])

        # check archecture
        real_arch = invoke("remote:arch", [hostname])

        # Add YUM repositories
        invoke("devenv:build:yum_repo_extras", [hostname, real_os, releasever, real_arch])

        # remove epel repo rpm if installed
        # add current epel repo RPM if it's RHEL or CentOS
        # 
        if ['rhel', 'centos'].member? real_os
          invoke "devenv:build:yum_repo_epel", [hostname]
        end

        # Fedora 18 doesn't want puppetlabs version of puppet (> 2.7)
        #invoke("devenv:build:yum_repo_puppetlabs", [hostname])

        # update all packages
          packages = invoke "remote:yum:update", [hostname], :verbose => options[:verbose]

        # install new packages
        # wget is not in the fedora base
        if real_os === 'fedora'
          invoke("devenv:build:install_wget", [hostname])
        end

        # install puppet on the remote host
        invoke("devenv:build:install_puppet", [hostname])
        # prepare required puppet modules
        invoke("devenv:build:init_puppet", [hostname])

        # update selinux configuration
        # disable selinux if requested
        invoke("remote:set_selinux", [hostname], :verbose => options[:verbose],
          :enforce => (not options[:disable_linux]), 
          :enable => (not options[:disable_linux]),)

        # update hostname in /etc/sysconfig/network with public hostname
        # set hostname 'manually'
        invoke "remote:set_hostname", [hostname]

      end

      desc("install_openshift HOSTNAME",
        "install OpenShift packages on a running host")
      def install_openshift
        puts "installing OpenShift packages"
      end

      desc("configure_openshift HOSTNAME",
        "configure OpenShift components on a running host")
      def configure_openshift
        puts "configuring the openshift service"
      end

      desc("clean_for_new_image HOSTNAME",
        "clean up in preparation to copy this instance to a new image")
      def clean_for_new_image
        puts "cleaning up instance for cloning"
      end

      desc("create_new_image INSTANCE NAME", 
        "create and register a new AMI from a running instance")
      def create_new_image(instance, name)
        puts "task: devenv:ami:create_new_image"

        # if instance is an instance id string, retrieve the instance
        if a.class === String and a.match(/^i-/)
          handle = login
          instance_id = instance
          begin 
            instances = handle.instances.filter('id', instance_id)
            instance = instances[0]
          rescue NoMethodError => e
            raise ArgumentError.new("Invalid instance ID #{instance_id}")
          end          
        end

        # reset the hostname
        
        # reset the network
        invoke("remote:reset_eth0_config", [hostname])

        # now create a new image
        invoke("ec2:image:create", :instance => instance, :name => name,
          :description => description)
      end
      

      # =======================
      # Non task helper methods
      # =======================
      no_tasks do


        # Create an EC2 connection
        def awslogin(access_key_id=nil, secret_access_key=nil, 
            credentials_file=nil, region=nil)
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


      # +++++++++++++++++++
      # TRY THIS AT THE END
      # +++++++++++++++++++


      desc("prepare NAME BUILDNUM",
        "prepare a new base AMI for development and testing")
      class Prepare < Thor::Group

        namespace "devenv:ami:prepare"


        #desc "prepare NAME BUILDNUM", "hey this is what it does"
        def select_image
          puts "selecting an AMI to use as the base image"
        end

        def create_instance
          puts "create and start an instance using the selected image"
        end

        def prepare_install
          puts "preparing to install OpenShift"
        end

        def install_openshift
          puts "installing OpenShift packages"
        end

        def configure_openshift
          puts "configuring the openshift service"
        end

        def clean_for_new_image
          puts "cleaning up instance for cloning"
        end

        def create_new_image
          puts "creating a new image with OpenShift installed and configured"
        end
          

      end

      #register(Prepare, "prepare", "prepare NAME BUILDNUM",
      #  "create a new base AMI for development and testing")
      
    end


  end
end

#
require 'rubygems'
require 'thor'
require 'net/http'
require 'parseconfig'


      # install packages for thor
      # ruby, ruby-irb, ruby-libs, ruby-devel, rubygem-thor
      # I suspect that rubygem-thor and ruby-devel is enough
      #invoke "devenv:build:install_thor"

module OpenShift
  class Devenv < Thor
    class BuildHelpers < Thor
      namespace "devenv:build"

      class_option :verbose, :type => :boolean, :default => false
      class_option(:username, :type => :string)
      class_option(:ssh_key_file, :type => :string)

      desc "install_thor HOSTNAME", "Install Rubygem Thor and deps"
      def install_thor(hostname)

        puts "task: devenv:build:install_thor #{hostname}" unless options[:quiet]

        username = options[:username] || Remote.ssh_username
        ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

        cmd = "sudo yum -y -q install rubygem-thor ruby-devel"
        
        # Remote comes from remote.thor magically
        Remote.remote_command(hostname, username, ssh_key_file, cmd,
          options[:verbose])

        # TODO: get and process return values
      end

      desc "install_git HOSTNAME", "Install Rubygem Thor and deps"
      def install_git(hostname)

        puts "task: devenv:build:install_git #{hostname}" unless options[:quiet]

        username = options[:username] || Remote.ssh_username
        ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

        cmd = "sudo yum -y -q install git"
        
        # Remote comes from remote.thor magically
        Remote.remote_command(hostname, username, ssh_key_file, cmd,
          options[:verbose])

        # TODO: get and process return values
      end

      desc "yum_repo_extras HOSTNAME DISTRO VERSION ARCH", "enable the openshift extras repo"
      def yum_repo_extras(hostname, distro, version, arch)

        puts "task: devenv:build:yum_repo_extras #{hostname} #{distro} #{version} #{arch}" unless options[:quiet]

        username = options[:username] || Remote.ssh_username
        ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

        filename = "openshift-extras.repo"
        # centos is rhel for this
        repo_os = distro === 'centos' ? 'rhel' : distro
        # we only want the major number
        major_number = version.split('.')[0]

        repo_file = File.dirname(File.dirname(__FILE__)) + "/data/" + filename
        raise Errno::ENOENT.new(repo_file) if not File.exists? repo_file
        #puts "#{repo_file} not found" if not File.exists? repo_file

        Remote::File.scp_put(hostname, username, ssh_key_file, repo_file, '.')

        # replace string on remote
        cmd = "sed -i -e 's/BASEOS/#{repo_os}/ ; s/VERSION/#{major_number}/' #{filename}"
        Remote.remote_command(hostname, username, ssh_key_file, cmd,
          options[:verbose])

        cmd = "sudo mv #{filename} /etc/yum.repos.d"
        Remote.remote_command(hostname, username, ssh_key_file, cmd,
          options[:verbose])

      end

      desc "yum_repo_epel HOSTNAME", "enable the EPEL repo on the host"
      def yum_repo_epel(hostname)

        puts "task: devenv:build:yum_repo_epel #{hostname}" unless options[:quiet]

        username = options[:username] || Remote.ssh_username
        ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

        # TODO: find mirrors? check arch?
        dirurl = 'http://dl.fedoraproject.org/pub/epel/6/x86_64/'

        # determine the URL of the most recent epel package
        url = URI.parse(dirurl)
        request = Net::HTTP::Get.new(url.path)
        connection = Net::HTTP::start(url.host)
        dirpage = connection.request(request)
        # check
        epel_line = dirpage.body.split("\n").select {|l| l.match "epel-release"}[0]
        # check
        epel_rpm = epel_line.match(/^.*"(epel-release.*)".*$/)[1]
        # check

        cmd = "wget #{dirurl}/#{epel_rpm}"
        Remote.remote_command(hostname, username, ssh_key_file, cmd,
          options[:verbose])

        # check

        cmd = "sudo yum -y -q install #{epel_rpm}"
        Remote.remote_command(hostname, username, ssh_key_file, cmd,
          options[:verbose])
      end

      desc "yum_repo_puppetlabs HOSTNAME", "enable the puppetlabs repo on the host"
      def yum_repo_puppetlabs(hostname)
        puts "task: devenv:build:yum_repo_puppetlabs #{hostname}" unless options[:quiet]

        username = options[:username] || Remote.ssh_username
        ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

        # TODO: find mirrors? check arch?
        dirurl = 'https://yum.puppetlabs.com/el/6/products/x86_64/'

        # determine the URL of the most recent epel package
        url = URI.parse(dirurl)
        request = Net::HTTP::Get.new(url.path)
        connection = Net::HTTP::start(url.host)
        dirpage = connection.request(request)
        # check
        plab_rpm = dirpage.body.split("\n").select {|line|
          line.match /^.*"(puppetlabs-release.*)".*$/
        }.map {|entry|
          m = entry.match(/^.*"(puppetlabs-release.*.rpm)".*$/)[1]
        }.sort[-1]

        cmd = "wget #{dirurl}/#{plab_rpm}"
        Remote.remote_command(hostname, username, ssh_key_file, cmd,
          options[:verbose])

        # check

        cmd = "sudo yum -y -q install #{plab_rpm}"
        Remote.remote_command(hostname, username, ssh_key_file, cmd,
          options[:verbose])
      end


      desc "install_wget HOSTNAME", "Install wget on a remote host"
      def install_wget(hostname)

        puts "task: devenv:build:install_wget #{hostname}" unless options[:quiet]
        username = options[:username] || Remote.ssh_username
        ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

        cmd = "sudo yum -y -q install wget"
        
        # Remote comes from remote.thor magically
        exit_code, exit_signal, stout, stderr = Remote.remote_command(
          hostname, username, ssh_key_file, cmd, options[:verbose])

        # TODO: get and process return values
      end

      desc "install_cucumber HOSTNAME", "Install Cucumber BDD testing and deps"
      def install_cucumber(hostname)

        puts "task: devenv:build:install_cucumber #{hostname}" unless options[:quiet]
        username = options[:username] || Remote.ssh_username
        ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

        cmd = "sudo yum -y -q install rubygem-cucumber-rails"
        
        # Remote comes from remote.thor magically
        Remote.remote_command(hostname, username, ssh_key_file, cmd,
          options[:verbose])

        # TODO: get and process return values
      end

      desc "install_puppet HOSTNAME", "Install puppet host management and deps"
      def install_puppet(hostname)

        puts "task: devenv:build:install_puppet #{hostname}" unless options[:quiet]
        username = options[:username] || Remote.ssh_username
        ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

        cmd = "sudo yum -y -q install puppet facter"
        
        # Remote comes from remote.thor magically
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, ssh_key_file, cmd, options[:verbose])

        # TODO: get and process return values
      end

      desc("init_puppet HOSTNAME",
        "initialize puppet configuration on a remote host")
      def init_puppet(hostname)
        puts "task: devenv:build:init_puppet #{hostname}" unless options[:quiet]
        username = options[:username] || Remote.ssh_username
        ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

        cmd = "sudo mkdir -p /etc/puppet/modules"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, ssh_key_file, cmd, options[:verbose])
        # TODO: get and process return values

        cmd = "sudo puppet module install puppetlabs/stdlib"        
        # Remote comes from remote.thor magically
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, ssh_key_file, cmd, options[:verbose])
        # TODO: get and process return values

        cmd = "sudo puppet module install puppetlabs/ntp"        
        # Remote comes from remote.thor magically
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, ssh_key_file, cmd, options[:verbose])
        # TODO: get and process return values
      end

      desc("remove_builds HOSTNAME",
        "delete old builds to make room for new ones")
      method_option :destdir, :default => "/data"
      def remove_builds(hostname)

        puts "task: devenv:build:remove_builds " +
          "#{hostname} #{options[:destdir]}" unless options[:quiet]

        username = options[:username] || Remote.ssh_username
        ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

        # remove if needed (install_from_source || install_from_local_source)
        cmd = "sudo rm -rf #{options[:destdir]}"
        Remote.remote_command(hostname, username, ssh_key_file, cmd,
          options[:verbose])
      end

      desc "prepare_builds HOSTNAME", "Create and populate a space for software builds on the host"
      method_option :destdir, :default => "/data"
      def prepare_builds(hostname)

        puts "task: devenv:build:prepare_builds " +
          "#{hostname} #{options[:data]}" unless options[:quiet]
        username = options[:username] || Remote.ssh_username
        ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

        puts "preparing build location #{options[:destdir]} on #{hostname}" if options[:verbose]

        # create and give ownership (why not in home?)
        cmd = "sudo mkdir -p #{options[:destdir]}"
        puts "Creating build directory #{options[:destdir]}" if options[:verbose]
        Remote.remote_command(hostname, username, ssh_key_file, cmd,
          options[:verbose])

        cmd = "sudo chown \$USER:\$USER #{options[:destdir]}"
        puts "Setting ownership of build directory #{options[:destdir]}" if options[:verbose]
        Remote.remote_command(hostname, username, ssh_key_file, cmd,
          options[:verbose])

      end


      desc "install_extras HOSTNAME SOURCEDIR", "install special packages needed by openshift"
      method_option :destdir, :default => "/data/extras"
      def install_extras(hostname, srcdir)

        puts "task: devenv:build:install_extras #{hostname} " +
          "#{srcdir} #{options[:destdir]}" unless options[:quiet]
        username = options[:username] || Remote.ssh_username
        ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

        cmd = "mkdir " + options[:destdir]
        puts "executing #{cmd} on #{hostname}"  if options[:verbose]
        Remote.remote_command(hostname, username, ssh_key_file, cmd, 
          options[:verbose])
        
        files = Dir.glob srcdir + "/*.rpm"
        puts "copying #{files.count} RPMs to #{hostname}:#{options[:destdir]}" if options[:verbose]
        files.each do |filename| 
          Remote::File.scp_put(hostname, username, ssh_key_file, 
            srcdir, options[:destdir])
        end
        
        cmd = "sudo yum --quiet -y install #{options[:destdir]}/*.rpm"
        Remote::File.scp_put(hostname, username, ssh_key_file, 
          srcdir, options[:destdir])
      end

      desc "install_tools HOSTNAME", "initialize the package build environment on the host"
      method_option :tooldir, :default => "/data/origin-dev-tools"
      def install_tools(hostname)
        puts "task: devenv:build:install_tools #{hostname} " +
          "#{options[:tooldir]}" unless options[:quiet]

        username = options[:username] || Remote.ssh_username
        ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

        # install build prerequisites
        cmd = "cd #{options[:tooldir]} ; sudo build/devenv"

        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, ssh_key_file, cmd, options[:verbose])

        # run the build:prepare task for the whole system
        # cmd = "thor build:prepare"

        if not exit_code === 0
          puts "COMMAND: #{cmd}"
          puts "EXIT CODE: #{exit_code}" +
            "\n------------\n" +
            stdout.join("\n") +
            "\n------------\n" +
            stderr.join("\n")
        end

      end

      desc "install_deps HOSTNAME", "install package build requirements"
      method_option :tooldir, :default => "/data/origin-dev-tools"
      def install_deps(hostname)

        puts "task: devenv:build:install_deps #{hostname} " + 
          "#{options[:tooldir]}" unless options[:quiet]

        username = options[:username] || Remote.ssh_username
        ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

        # install build prerequisites
        cmd = "cd #{options[:tooldir]} ; sudo build/devenv install_required_packages"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, ssh_key_file, cmd, options[:verbose])

        # run the build:requirements task in each git repo root

        if not exit_code === 0
          puts "COMMAND: #{cmd}"
          puts "EXIT CODE: #{exit_code}" +
            "\n------------\n" +
            stdout.join("\n") +
            "\n------------\n" +
            stderr.join("\n")
        end
        exit_code
      end

      desc "install_bind HOSTNAME", "install a local named with updates enabled"
      def install_bind(hostname)
        # install the bind and bind_utils package on the remote host

        # generate update keys

        # 
      end


      desc "service_mongod HOSTNAME", "Install and configure a mongod service for OpenShift"
      def service_mongod(hostname)
      end

      desc "service_activemq HOSTNAME", "Install and configure a activemq service for OpenShift"
      def service_activemq(hostname)
      end

      desc "service_bind HOSTNAME", "Install and configure a bind service for OpenShift"
      def service_bind(hostname)

        # install packages

        # generate config files

        # generate update keys

        # verify service

        # enable on boot

      end

    end
  end
end

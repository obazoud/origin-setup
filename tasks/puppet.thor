#!/usr/bin/env ruby
#
# Set up an OpenShift Origin service on AWS EC2
#
require 'rubygems'
require 'thor'

module OpenShift

  module  Puppet

    class Cert < Thor
      namespace "puppet:cert"

      class_option :verbose, :type => :boolean, :default => false
      class_option :debug, :type => :boolean, :default => false
      class_option :quiet, :type => :boolean, :default => false

      desc "sign MASTER HOSTNAME", "sign an agent certificate"
      def sign(master, hostname)
        puts "task puppet:cert:sign #{master} #{hostname}" unless options[:quiet]

        username = options[:username] || Remote.ssh_username
        key_file = options[:ssh_key_file] || Remote.ssh_key_file

        cmd = "sudo puppet cert sign #{hostname}"

        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        master, username, key_file, cmd, options[:verbose])

      end


      desc "generate MASTER HOSTNAME", "sign an agent certificate"
      def generate(master, hostname)
        puts "task puppet:cert:generate #{master} #{hostname}" unless options[:quiet]

        username = options[:username] || Remote.ssh_username
        key_file = options[:ssh_key_file] || Remote.ssh_key_file

        # wait for the master cert to be waiting and then sign?

        cmd = "sudo puppet cert sign #{hostname}"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        master, username, key_file, cmd, options[:verbose])

      end

      desc "clean MASTER HOSTNAME", "remove a host certificate from the master list"
      def clean(master, hostname)
        puts "task puppet:cert:clean #{master} #{hostname}" unless options[:quiet]

        username = options[:username] || Remote.ssh_username
        key_file = options[:ssh_key_file] || Remote.ssh_key_file

        cmd = "sudo puppet cert clean #{hostname}"

        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        master, username, key_file, cmd, options[:verbose])

      end

      desc "list MASTER [HOSTNAME]", "list the outstanding unsigned (or all) certs"
      method_option :all, :type => :boolean, :default => false
      def list(master, hostname=nil)
        puts "task puppet:cert:list #{master}" unless options[:quiet]

        username = options[:username] || Remote.ssh_username
        key_file = options[:ssh_key_file] || Remote.ssh_key_file

        certlist = Puppet::Cert.list(master, username, key_file, hostname, options[:all],
          options[:verbose])

        puts "there are #{certlist.count} matches" if options[:verbose]
        certlist.each { |state, name, fingerprint|
          puts "#{state} #{name} #{fingerprint}"
        }
        
        certlist
      end
      
      no_tasks do
        def self.list(master, username, key_file, hostname, all=false, verbose=false)

          cert_re = /^((\+|-)\s)?"([^\s]+)"\s+\(((([A-F0-9]{2}):){15}[A-F0-9]{2})\)/

          cmd = "sudo puppet cert list #{hostname}"
          cmd << " --all" if all

          exit_code, exit_signal, stdout, stderr = Remote.remote_command(
            master, username, key_file, cmd, verbose)

          # check exit_code

          # parse the cert lines for 
          certlist = stdout.map {|line|
            # only pick lines that match
            match = line.match cert_re
            match and match.to_a.slice(2,4)
            # and filter the null entries
          }.select {|entry| entry }
        
          certlist
        end
      end
    end

    class Master < Thor

      namespace "puppet:master"

      class_option :username
      class_option :ssh_key_file
      class_option :verbose
      
      desc "configure HOSTNAME", "set the puppet master configuration on a host"
      method_option(:moduledir, :type => :string, 
        :default => "/var/lib/puppet/manifests")
      method_option(:manifestdir, :type => :string,
        :default => '/var/lib/puppet/modules')
      def configure(hostname)
        puts "puppet:master:configure #{hostname}"

        username = options[:username] || Remote.ssh_username
        key_file = options[:ssh_key_file] || Remote.ssh_key_file

        # initialize configuration
        # TODO: determine location of data dir
        Remote::File.scp_put(hostname, username, key_file, 
          'data/puppet-master.conf.erb', 'puppet.conf', options[:verbose])

        # set hostname in appropriate places in the config
        cmd = "sed -i -e 's/<%= hostname %>/#{hostname}/' puppet.conf"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, options[:verbose])

        # set location of the manifests
        cmd = "sed -i -e 's|<%= manifestdir %>|#{options[:manifestdir]}|' puppet.conf"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, options[:verbose])

        # set location of the modules
        cmd = "sed -i -e 's|<%= moduledir %>|#{options[:moduledir]}|' puppet.conf"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, options[:verbose])

        Remote::File.copy(hostname, username, key_file, 
          "puppet.conf", "/etc/puppet/puppet.conf", true, false, false,
          options[:verbose])

        Remote::File.mkdir(hostname, username, key_file,
          options[:moduledir], true, true, options[:verbose])
      end

      desc "siteroot HOSTNAME PATH", "create a directory to contain the puppet site configuration"
      def siteroot(hostname, sitepath)

        username = options[:username] || Remote.ssh_username
        key_file = options[:ssh_key_file] || Remote.ssh_key_file

        manifestdir = sitepath + '/manifests'
        moduledir = sitepath + '/modules'

        Remote::File.mkdir(hostname, username, key_file,
          sitepath, true, true, options[:verbose])

        Remote::File.group(hostname, username, key_file,
          sitepath, 'puppet', true, false, options[:verbose])

        # Allow the puppet group to write to the manifests area
        Remote::File.permission(hostname, username, key_file,
          sitepath, 'g+ws', true, false, options[:verbose])

        # Allow git pulls from user $HOME/manifests
        Remote::File.symlink(hostname, username, key_file,
          sitepath, "site", 
          false, options[:verbose])
      end
        
      desc "join_group HOSTNAME", "add the user to the puppet group"
      def join_group(hostname)

        puts "task puppet:master:join_group #{hostname}" unless options[:quiet]

        username = options[:username] || Remote.ssh_username
        key_file = options[:ssh_key_file] || Remote.ssh_key_file
        
        # add the user to the puppet group
        cmd = "sudo augtool --autosave set /files/etc/group/puppet/user[1] #{username}"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, options[:verbose])
      end

      desc "enable_logging HOSTNAME", "log puppet master events to a specific file"
      def enable_logging(hostname)
        puts "task: puppet:master:enable_logging #{hostname}"

        # get ssh access
         username = options[:username] || Remote.ssh_username
         key_file = options[:ssh_key_file] || Remote.ssh_key_file

        # log puppet to its own file
        Remote::File.scp_put(hostname, username, key_file,
          "data/rsyslog-puppet-master.conf", "rsyslog-puppet-master.conf",
          options[:verbose])

        Remote::File.copy(hostname, username, key_file,
          "rsyslog-puppet-master.conf", "/etc/rsyslog.d/puppet-master.conf",
          true, false, false, options[:verbose])

        cmd = "sudo touch /var/log/puppet-master.log"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, options[:verbose])

        if options[:systemd] == nil
          systemd = Remote.pidone(hostname, username, key_file) == "systemd"
        else
          systemd = options[:systemd]
        end

        Remote::Service.execute(hostname, username, key_file, 
          "rsyslog", 'restart', systemd, options[:verbose])
      end
    end
    
    class Agent < Thor

      namespace "puppet:agent"

      class_option :verbose, :type => :boolean, :default => false
      class_option :debug, :type => :boolean, :default => false
      class_option :quiet, :type => :boolean, :default => false

      desc "set_server HOSTNAME MASTER", "set the master hostname on an agent"
      def set_server(hostname, master)

        puts "task puppet:agent:set_server #{hostname} #{master}" unless options[:quiet]

        username = options[:username] || Remote.ssh_username
        key_file = options[:ssh_key_file] || Remote.ssh_key_file

        Remote::File.copy(hostname, username, key_file,
          '/etc/puppet/puppet.conf', 'puppet.conf', 
          false, false, false, options[:verbose])

        cmd = "sed -i -e  '/\\[main\\]/a\\    server = #{master}' puppet.conf"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, options[:verbose])

        Remote::File.copy(hostname, username, key_file,
          'puppet.conf', '/etc/puppet/puppet.conf',
          true, false, false, options[:verbose])
      end

      desc "enable_logging HOSTNAME", "log puppet agent events to a specific file"
      def enable_logging(hostname)
        puts "task: puppet:agent:enable_logging #{hostname}"

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

        if options[:systemd] == nil
          systemd = Remote.pidone(hostname, username, key_file) == "systemd"
        else
          systemd = options[:systemd]
        end

        Remote::Service.execute(hostname, username, key_file, 
          "rsyslog", 'restart', systemd, options[:verbose])
      end

    end

    class Module < Thor
      namespace "puppet:module"

      class_option :verbose, :type => :boolean, :default => false
      class_option :debug, :type => :boolean, :default => false
      class_option :quiet, :type => :boolean, :default => false

      desc "install HOSTNAME MODULE [MODULE]...", "install a puppet module on a remote host"
      def install(hostname, *modules)
        
        puts "task: puppet:module:install #{hostname} #{modules.join(' ')}" if not options[:quiet]

        username = options[:username] || Remote.ssh_username
        key_file = options[:ssh_key_file] || Remote.ssh_key_file

        cmd = "sudo puppet module install --mode master #{modules.join(' ')}"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, options[:verbose]
          )

      end


    end

  end

end


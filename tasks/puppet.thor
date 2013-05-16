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

      desc "sign MASTER HOSTNAME", "sign an agent certificate"
      def sign(master, hostname)
        puts "task puppet:cert:sign #{master} #{hostname}" unless options[:quiet]

        username = options[:username] || Remote.ssh_username
        key_file = options[:ssh_key_file] || Remote.ssh_key_file

        cmd = "sudo puppet cert sign #{hostname}"

        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        master, username, key_file, cmd, options[:verbose])

      end
    end

    class Master < Thor

      namespace "puppet:master"


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

        cmd = "sed -i -e  '/\[main\]/a\    server = #{master}' puppet.conf"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, options[:verbose])

        Remote::File.copy(hostname, username, key_file,
          'puppet.conf', '/etc/puppet/puppet.conf',
          true, false, false, options[:verbose])
      end

    end
  end

end


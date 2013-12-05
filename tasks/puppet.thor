#!/usr/bin/env ruby
#
# Set up an OpenShift Origin service on AWS EC2
#
require 'rubygems'
require 'thor'
require 'net/http'

class  Puppet < Thor

  class_option :verbose, :type => :boolean, :default => false
  class_option :debug, :type => :boolean, :default => false
  class_option :quiet, :type => :boolean, :default => false
  class_option :username
  class_option :ssh_key_file

  class Cert < Thor
    #namespace "puppet:cert"

    class_option :verbose, :type => :boolean, :default => false
    class_option :debug, :type => :boolean, :default => false
    class_option :quiet, :type => :boolean, :default => false
    class_option :username
    class_option :ssh_key_file

    desc "sign MASTER HOSTNAME", "sign an agent certificate"
    def sign(master, hostname)
      puts "task: puppet:cert:sign #{master} #{hostname}" unless options[:quiet]

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      cmd = "sudo puppet cert sign #{hostname}"

      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        master, username, key_file, cmd, options[:verbose])

    end


    desc "generate MASTER HOSTNAME", "sign an agent certificate"
    def generate(master, hostname)
      puts "task: puppet:cert:generate #{master} #{hostname}" unless options[:quiet]

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

    #namespace "puppet:master"

    class_option :username
    class_option :ssh_key_file
    class_option :verbose, :type => :boolean, :default => false
    
    desc "configure HOSTNAME", "set the puppet master configuration on a host"
    method_option(:moduledir, :type => :string, 
      :default => "/var/lib/puppet/manifests")
    method_option(:manifestdir, :type => :string,
      :default => '/var/lib/puppet/modules')
    def configure(hostname)
      puts "task: puppet:master:configure #{hostname}"

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      puppet_conf = "/files/etc/puppet/puppet.conf/main/"
      path = puppet_conf + "modulepath"
      value = "/etc/puppet/modules:/usr/share/puppet/modules:#{options[:moduledir]}"
      Remote::Augeas.set(hostname, username, key_file, path, value, 
        options[:verbose])

      path = puppet_conf + "manifestdir"
      value = options[:manifestdir]
      Remote::Augeas.set(hostname, username, key_file, path, value,
        options[:verbose])

      path = puppet_conf + "manifest"
      value = options[:manifestdir] + "/site.pp"
      Remote::Augeas.set(hostname, username, key_file, path, value,
        options[:verbose])

      Remote::File.mkdir(hostname, username, key_file,
        options[:moduledir], true, true, options[:verbose])
    end

    desc "storedconfigs HOSTNAME", "Enable stored configs for the puppermaster"
    method_option :dbadaptor, :type => :string, :default => "sqlite3"
    method_option(:dblocation, :type => :string, 
      :default => "/var/lib/puppet/server_data/storeconfigs.sqlite")
    def storedconfigs(hostname)

      puts "task: puppet:master:storedconfigs #{hostname}"

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      puppet_conf = "/files/etc/puppet/puppet.conf/master/"

      path = puppet_conf + "storedconfigs"
      Remote::Augeas.set(hostname, username, key_file, path, "true", 
        options[:verbose])

      path = puppet_conf + "dbadaptor"
      Remote::Augeas.set(hostname, username, key_file, 
        path, options[:dbadaptor], options[:verbose])

      path = puppet_conf + "dblocation"
      Remote::Augeas.set(hostname, username, key_file, 
        path, options[:dblocation], options[:verbose])

      puppet_version = Remote::Rpm.version(hostname, username, key_file, 
        'puppet', options[:verbose])
      
      if puppet_version.to_f < 3.2
        Remote::Patch.apply(hostname, username, key_file,
          'data/puppet-rails-resource.rb.diff',
          '/usr/share/ruby/vendor_ruby/puppet/rails/resource.rb',
          true, options[:verbose])
      end
    end
    
    desc "siteroot HOSTNAME PATH", "create a directory to contain the puppet site configuration"
    def siteroot(hostname, sitepath)
      
      puts "task: puppet:master:siteroot #{hostname} #{sitepath}"

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      Remote::File.mkdir(hostname, username, key_file,
        sitepath, true, true, options[:verbose])

      Remote::File.set_group(hostname, username, key_file,
        sitepath, 'puppet', true, false, options[:verbose])

      # Allow the puppet group to write to the manifests area
      Remote::File.set_permission(hostname, username, key_file,
        sitepath, 'g+ws', true, false, options[:verbose])

      # Allow git pulls from user $HOME/manifests
      Remote::File.symlink(hostname, username, key_file,
        sitepath, "site", 
        false, options[:verbose])
    end
    
    desc "join_group HOSTNAME", "add the user to the puppet group"
    def join_group(hostname)

      puts "task: puppet:master:join_group #{hostname}" unless options[:quiet]

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

    desc "onetime HOSTNAME", "run the puppet agent a single time"
    method_option :noop, :type => :boolean, :default => false
    def onetime(hostname)
      puts "task: puppet:agent:onetime #{hostname} " unless options[:quiet]

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      cmd = "sudo puppet agent --onetime --no-daemonize"
      cmd += " --noop" if options[:noop]
      cmd += " --verbose" if options[:verbose]

      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])
    end

    desc "set_server HOSTNAME MASTER", "set the master hostname on an agent"
    def set_server(hostname, master)

      puts "task: puppet:agent:set_server #{hostname} #{master}" unless options[:quiet]

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      path = '/files/etc/puppet/puppet.conf/main/server'
      Remote::Augeas.set(hostname, username, key_file, path, master,
        options[:verbose])
    end

    desc "pluginsync HOSTNAME [-[-not]-enabled]", "set the master hostname on an agent"
    method_option :enabled, :type => :boolean, :default => true
    def pluginsync(hostname)

      puts "task: puppet:agent:pluginsync #{hostname}" unless options[:quiet]

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      path = '/files/etc/puppet/puppet.conf/main/pluginsync'
      Remote::Augeas.set(hostname, username, key_file, 
        path, options[:enabled] ? "true" : "false", 
        options[:verbose])
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
    #namespace "puppet:module"

    class_option :verbose, :type => :boolean, :default => false
    class_option :debug, :type => :boolean, :default => false
    class_option :quiet, :type => :boolean, :default => false
    class_option :username, :type=> :string, :default => 'root'
    class_option :ssh_key_file

    desc "install HOSTNAME MODULE [MODULE]...", "install a puppet module on a remote host"
    method_option(:puppetuser, :type => :string)
    def install(hostname, *modules)
      
      puts "task: puppet:module:install #{hostname} #{modules.join(' ')}" if not options[:quiet]

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      if options[:puppetuser]
        cmd_prefix = "cd ~#{options[:puppetuser]} ; sudo -u #{options[:puppetuser]} "
      else
        cmd_prefix = ""
      end
      
      modules.each do |module_name|
        #cmd = "sudo puppet module install --mode master #{modules.join(' ')}"
        cmd = cmd_prefix + "puppet module install #{module_name}"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, options[:verbose]
        )
      end
    end
  end

  desc "apply HOSTNAME MANIFEST", "apply a puppet manifest to a remote host"
  method_option :modulepath
  def apply(hostname, manifest)
    
    puts "task: puppet:apply #{hostname} #{manifest}" if not options[:quiet]

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file

    cmd = "sudo puppet apply --verbose #{manifest}"

    cmd += " --modulepath=" + options[:modulepath] if options[:modulepath]
    exit_code, exit_signal, stdout, stderr = Remote.remote_command(
      hostname, username, key_file, cmd, options[:verbose]
      )
  end

  desc "version HOSTNAME", "report the puppet version on the remote host"
  def version(hostname)
    
    puts "task: puppet:version #{hostname}" if not options[:quiet]

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file

    cmd = "sudo puppet --version"
    exit_code, exit_signal, stdout, stderr = Remote.remote_command(
      hostname, username, key_file, cmd, options[:verbose]
      )
    puts stdout[0]
    stdout[0]
  end

  desc "config HOSTNAME", "return the puppet configuration"
  def config(hostname)
    puts "task: puppet:config #{hostname}" if not options[:quiet]

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file

    cmd = "sudo puppet config print"
    exit_code, exit_signal, stdout, stderr = Remote.remote_command(
      hostname, username, key_file, cmd, options[:verbose]
      )
    puts stdout.join("\n")

    config = {}
    stdout.each do |line|
      keystring, value = line.split(' = ')
      keysym = keystring.to_sym
      config[keysym] = value
    end
    config
  end

  
  desc "repo HOSTNAME", "enable the puppetlabs repo to a host"
  def repo(hostname)
    puts "task: puppet:config #{hostname}" if not options[:quiet]

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file

    # get distribution
    distro, version = Remote.distribution(hostname, username, key_file,
      options[:verbose])
    arch = Remote.arch(hostname, username, key_file, options[:verbose])

    release_rpm = Puppet.puppetlabs_release_rpm_url(distro, version, arch)


    if release_rpm != nil
      Remote::Yum.install_rpms(hostname, username, key_file,
        [release_rpm], options[:verbose])
    end
  end

  no_tasks do

    def self.puppetlabs_release_rpm_url(distro, version, arch)

      if distro == 'fedora'
        dstring = distro
        vstring = 'f' + version
      elsif distro == 'rhel'
        dstring = 'el'
        vstring = version.split('.')[0] + "Server"
      else
        raise "invalid distribution: #{distro} - must be rhel or fedora"
      end

      repo_root_url = "http://yum.puppetlabs.com"

      dir_url = repo_root_url + "/#{dstring}/#{vstring}/products/#{arch}/"

      dir_listing_html = Net::HTTP.get_response(URI.parse(dir_url))

      #puts dir_listing_html.body.match(/(.*href="([^"]+)")+/)

      alist = dir_listing_html.body.split('<a ').map {|anchor|
        href = anchor.match(/href="([^"]+)"/)
        href ? href[1] : nil
      }.select { |m| m != nil }.select {|rpm| rpm.match(/puppetlabs-release/)}

      alist.length > 0 ? dir_url + "/" + alist[-1] : nil
    end

  end
end

#!/usr/bin/thor
# Remote tasks on hosts

require 'rubygems'
require 'thor'
require 'parseconfig'
#require 'resolv'

# rubygem-net-ssh is only available from the openshift repo for RHEL
require 'net/ssh'


# We're going to create a local class named "File".  We have to avoid losing
# the main.File module from scope
# Could also have used ::File throughout
RealFile = File

# Default location to find config and auth information
AWS_CONFIG_FILE = ENV["AWS_CONFIG_FILE"] || ".awscred"

# Remote tasks (using SSH)

class Remote < Thor
  include Thor::Actions

  namespace "remote"

  no_tasks do

    def self.ssh_key_file
      credentials_file ||= AWS_CONFIG_FILE
      config = ParseConfig.new RealFile.expand_path(credentials_file)
      key_pair_name = config.params['AWSKeyPairName']
      # TODO: check that the key_pair_name is set
      RealFile.expand_path("~/.ssh/#{key_pair_name}.pem") 
      # TODO: check that the key file exists?
    end

    def self.ssh_username(baseos=nil)
      credentials_file ||= AWS_CONFIG_FILE
      config = ParseConfig.new(RealFile.expand_path(credentials_file))
      
      baseos ? config.params[baseos]['RemoteUser'] : config.params['RemoteUser'] 
    end

    def self.remote_command(hostname, username, key_file, command, verbose=false, timeout=15, maxtries=6)

      puts "- remote command: #{command}" if verbose
      #
      # check that DNS resolves
      #
      begin
        dns_record = Resolv.getaddress(hostname)
      rescue Resolv::ResolvError => e
        puts "hostname does not resolve: #{hostname}"
        return false
      end

      start_time = Time.new() 

      (1..maxtries).each do |trynum|
        puts "- remote command try #{trynum}" if verbose

        exit_code = nil
        exit_signal = nil
        stdout = []
        stderr = []

        begin
          Net::SSH.start(hostname, username, :timeout => timeout,
            :keys => [key_file], :keys_only => true, 
            :paranoid => false) do |ssh|

            ssh.open_channel do | channel |
              channel.request_pty

              puts "- cmd: #{command}" if verbose
              result = channel.exec(command) do |ch, success|

                channel.on_data do | ch, data |
                  puts "- remote: #{data.strip}" if verbose and not data.match(/^\s+$/)
                  stdout << data.strip if not data.match(/^\s+$/)
                end      

                channel.on_extended_data do | ch, type, data |
                  #puts "stderr: #{data}"
                  stderr << data.strip if not data.match(/^\s+$/)
                end

                channel.on_request('exit-status') do |ch, data|
                  exit_code = data.read_long
                end

                channel.on_request('exit-signal') do |ch, data|
                  exit_signal = data.read_long
                end
              end

              channel.wait
            end # channel
          end # Net::SSH.start
          end_time = Time.new()
          puts "- duration: #{(end_time - start_time).round(2)} seconds" if verbose
          return [exit_code, exit_signal, stdout, stderr]

        rescue Net::SSH::AuthenticationFailed => e
          puts "- #{trynum}: Authentication failed" if verbose
        rescue Net::SSH::Disconnect => e
          puts "- #{trynum}: Connection closed by remote host" if verbose
        rescue SocketError => e
          puts "- #{trynum}: socket error: #{e.message}" if verbose
        rescue Errno::ETIMEDOUT => e
          puts "- #{trynum}: timed out attempting to connect" if verbose
        rescue Timeout::Error => e
          puts "- #{trynum}: timed out attempting to connect" if verbose
        rescue Errno::ECONNREFUSED
          puts "- #{trynum}: connection refused" if verbose
        rescue Errno::ECONNRESET
          puts "- #{trynum}: connection reset" if verbose
        rescue Exception => e
          puts "- #{trynum}: unknown exception #{e}"
        end # try block
        #puts "- trying again"
      end
      end_time = Time.new()
      puts "- duration: #{(end_time - start_time).round(2)} seconds" if verbose
      return nil
    end # remote_command

    # determine if a host uses init (upstart) or systemd
    def self.pidone(hostname, username, key_file, verbose=false)
      cmd = "ps -h -o comm -p 1"
      puts "- cmd = #{cmd}" if verbose
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, verbose)
      stdout[0]
    end

    def self.distribution(hostname, username, key_file, verbose=false)
      distro_table = {
        "Red Hat" => 'rhel',
        "CentOS" => 'centos',
        "Fedora" => 'fedora'
      }

      cmd = "cat /etc/redhat-release"

      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, verbose)

      # check for exit code == 0

      # parse contents of output
      info = stdout[0].match /^(Fedora|Red Hat|CentOS).*release ([\d.]+)/

      [distro_table[info[1]], info[2]]
    end

  end # no_tasks

  class_option :verbose, :type => :boolean, :default => false
  class_option(:username, :type => :string)
  class_option(:ssh_key_file, :type => :string)


  desc "available HOSTNAME", "determine if a remote host is accessible"
  method_option(:wait, :default => false)
  method_option(:tries, :type => :numeric, :default => 15)
  method_option(:pollrate, :type => :numeric, :default => 10)
  def available(hostname)
    puts "task: remote:available #{hostname}" unless options[:quiet]
    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file

    tries = options[:tries] || 15
    pollrate = options[:pollrate] || 10

    Remote.available(hostname, username, key_file, 
      options[:wait], tries, pollrate, options[:verbose])
  end

  no_tasks do
    def self.available(hostname, username, key_file, 
        wait=false, tries=15, pollrate=10, verbose=false)

      puts "- trying up to #{tries} times at #{pollrate} second intervals" if verbose
      puts "- using username #{username} and key file #{key_file}" if verbose

      cmd = "echo success"

      (1..tries).each do |trynum|
        result = Remote.remote_command(
          hostname, username, key_file, cmd, verbose)
        if result then
          exit_code, exit_signal, stdout, stderr = result
          if verbose then
            puts "- STDOUT\n" + stdout.join("\n") 
            puts "- STDERR\n" + stderr.join("\n")
            puts "- stdout length = #{stdout.count}"
            puts "- exit code: #{exit_code}"
          end
          return true
        end
        break if not wait
        puts "- sleeping #{pollrate}" if verbose
        sleep pollrate
      end
      puts "- #{hostname} not available" if verbose
      return false
    end
  end

  desc "distribution HOSTNAME", "probe the distribution information from a remote host"
  def distribution(hostname)

    puts "task: remote:distribution #{hostname}" unless options[:quiet]

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file

    release_info = Remote.distribution(hostname, username, key_file, options[:verbose])

    puts release_info.join
    release_info
  end

  desc "sed HOSTNAME PATTERN FILENAME", "make a pattern change to a file"
  method_option :destfile, :type => :string
  method_option :inplace, :type => :boolean, :default => false
  def sed(hostname, pattern, filename)
    puts "task: remote:sed #{hostname} #{pattern} #{filename}" unless options[:quiet]

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file
    
    # add protection to quotes in the pattern
    pattern = pattern.gsub("'", "\\\\'")

    cmd = "echo \"#{pattern}\" | sed -f -" + (options[:inplace] ? " -i " : " ") + filename
    cmd += (" > " + options[:destfile]) if not options[:destfile] == nil

    puts "command = " + cmd
    exit_code, exit_signal, stdout, stderr = Remote.remote_command(
      hostname, username, key_file, cmd, options[:verbose])
    puts stdout.join("\n")
    puts stderr.join("\n")

  end

  desc "pullurl HOSTNAME URL", "pull a file to a remote host using wget"
  method_option(:filepath, :type => :string)
  def pullurl(hostname, url)

    puts "task: remote:pullurl #{hostname} #{url}" unless options[:quiet]

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file
    puts "- using key file #{key_file}" if options[:verbose]

    puts "- username: #{username}" if options[:verbose]
    puts "- key_file: #{key_file}" if options[:verbose]

    cmd = "wget -q #{options[:filepath]? ('-O ' + options[:filepath]):''} #{url} "

    exit_code, exit_signal, stdout, stderr = Remote.remote_command(
      hostname, username, key_file, cmd, options[:verbose])
    puts stdout.join("\n")
    puts stderr.join("\n")
  end


  desc("ipaddress HOSTNAME INTERFACE",
    "get the IP address of the indicated interface on the host")
  method_option :cidrmask, :type => :boolean, :default => false
  def ipaddress(hostname, interface)
    puts "task: remote:ipaddress #{hostname} #{interface}" unless options[:quiet]

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file
    puts "using key file #{key_file}" if options[:verbose]

    puts "username: #{username}" if options[:verbose]
    puts "key_file: #{key_file}" if options[:verbose]

    # match just the IP address unless the caller asks for the cidr mask too
    terminator = options[:cidrmask] ? ' ' : '/'

    cmd = "/usr/sbin/ip address show dev #{interface} | " + 
      "sed -n -e 's/\s*inet \\([^#{terminator}]*\\).*/\\1/p'"

    puts "cmd = #{cmd}" if options[:verbose]

    exit_code, exit_signal, stdout, stderr = Remote.remote_command(
      hostname, username, key_file, cmd, options[:verbose])

    puts stdout
    # return the first line returned
    stdout[0]
  end

  desc "pidone", "determine which init process the host uses"
  def pidone(hostname)
    puts "task: pidone #{hostname}"

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file
    puts "using key file #{key_file}" if options[:verbose]

    puts "username: #{username}" if options[:verbose]
    puts "key_file: #{key_file}" if options[:verbose]

    start_process = Remote.pidone(hostname, username, key_file,
      options[:verbose])

    puts start_process
    start_process
  end

  desc "timezone HOSTNAME [ZONE]", "get or set the system timezone on a remote host"
  def timezone(hostname, zone=nil)
    puts "task: remote:timezone #{hostname} #{zone}"

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file

    puts "- username: #{username}" if options[:verbose]
    puts "- key_file: #{key_file}" if options[:verbose]

    if zone
      filename = "/usr/share/zoneinfo/#{zone}"

      cmd = "test -f #{filename} && (sudo rm /etc/localtime ; sudo ln -s #{filename} /etc/localtime)"

      puts "- cmd = #{cmd}" if options[:verbose]

      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      if not exit_code == 0
        puts "invalid time zone string #{zone}: #{filename} - file not found"        
      end
    
    else
      cmd = "date +%Z"
      puts "- cmd = #{cmd}" if options[:verbose]

      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      puts stdout[0]
      stdout[0]

    end

  end

  class File < Thor
  #   #namespace "remote:file"

    no_tasks do
      #
      # rubygem-net-scp is not available for RHEL
      #
      begin

        # define SCP commands using net-scp
        require 'net/scp'

        def self.scp_get(hostname, username, key_file, filepath, destpath, recursive=false)
          Net::SCP.start(hostname, username,
            :keys => [key_file], :keys_only => true) do |scp|
            scp.download! filepath, destpath, :recursive => recursive
          end
        end

        def self.scp_put(hostname, username, key_file, filepath, destpath, recursive=false)
          Net::SCP.start(hostname, username,
            :keys => [key_file], :keys_only => true) do |scp|
            scp.upload! filepath, destpath, :recursive => recursive
          end
        end

      rescue LoadError => e

        # define SCP commands using binary scp

        def self.scp_get(hostname, username, key_file, filepath, destpath, recursive=false)
          recurse_arg = recursive ? "-r": ""
          cmd = "scp -i #{key_file} #{recurse_arg} " +
            "#{username}@#{hostname}:#{filepath} #{destpath}"

          begin
            Timeout::timeout(15) { output = `#{cmd}` ; exit_code = $?.exitstatus }
          rescue Timeout::Error
            output = "scp get request timed out"
          end
          output
        end

        def self.scp_put(hostname, username, key_file, filepath, destpath, recursive=false)
          recurse_arg = recursive ? "-r": ""
          cmd = "scp -i #{key_file} #{recurse_arg} " +
            "#{filepath} #{username}@#{hostname}:#{destpath}"

          begin
            Timeout::timeout(15) { output = `#{cmd}` ; exit_code = $?.exitstatus }
          rescue Timeout::Error
            output = "scp get request timed out"
          end
          output
          
        end

      end

      # Delete a file or file tree on a remote host
      # Defining this as a function allows it to be called repeatedly
      # by different tasks.
      #
      # This is a class method, not to be confused with the task by the same
      # name which is an instance method
      def self.delete(hostname, username, keyfile, filepath,
          sudo=false, recursive=false, force=false, verbose=false)

        cmd = sudo ? "sudo " : ""
        cmd += "rm"
        cmd += " -r" if recursive
        cmd += " -f" if force
        cmd += " " + filepath
        Remote.remote_command(hostname, username, keyfile, cmd, verbose)
      end

      def self.copy(hostname, username, keyfile, sourcepath, destpath,
          sudo=false, recursive=false, force=false, verbose=false)
        cmd = sudo ? "sudo " : ""
        cmd += "cp"
        cmd += " -r" if recursive
        cmd += " -f" if force
        cmd += " " + sourcepath + " " + destpath
        Remote.remote_command(hostname, username, keyfile, cmd, verbose)
      end

      def self.touch(hostname, username, keyfile, filepath,
          sudo=false, verbose=false)

        cmd = sudo ? "sudo " : ""
        cmd += "touch"
        cmd += " " + filepath
        Remote.remote_command(hostname, username, keyfile, cmd, verbose)
      end

      def self.mkdir(hostname, username, keyfile, dirpath,
          sudo=false, parents=false, verbose=false)
        cmd = sudo ? "sudo " : ""
        cmd += "mkdir"
        cmd += " -p" if parents
        cmd += " " + dirpath
        Remote.remote_command(hostname, username, keyfile, cmd, verbose)
      end

      def self.set_permission(hostname, username, keyfile, path, mode,
          sudo=false, recursive=false, verbose=false)
        cmd = sudo ? "sudo " : ""
        cmd += "chmod"
        cmd += " -R" if recursive
        cmd += " " + mode + " " + path
        Remote.remote_command(hostname, username, keyfile, cmd, verbose)
      end

      def self.set_group(hostname, username, keyfile, path, group,
           sudo=false, recursive=false, verbose=false)
         cmd = sudo ? "sudo " : ""
         cmd += "chgrp"
         cmd += " -R" if recursive
         cmd += " " + group + " " + path
         Remote.remote_command(hostname, username, keyfile, cmd, verbose)
      end

      def self.symlink(hostname, username, keyfile, srcpath, dstpath,
          sudo=false, verbose=false)

        cmd = sudo ? "sudo " : ""
        cmd += "ln -s #{srcpath} #{dstpath}"
        Remote.remote_command(hostname, username, keyfile, cmd, verbose)
      end

    end # no_tasks

    class_option :verbose, :type => :boolean, :default => false
    class_option(:username, :type => :string)
    class_option(:ssh_key_file, :type => :string)

    desc "get HOSTNAME FILEPATH", 'copy a file back from a remote host'
    method_option(:destpath, :type => :string)
    method_option(:recursive, :type => :boolean, :default => false)
    def get(hostname, filepath)
      puts "task: remote:file:get #{hostname} #{filepath}" unless options[:quiet]
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file
      puts "using key file #{key_file}" if options[:verbose]

      # TODO: check if key file exists

      destpath = options[:destpath] || RealFile.basename(filepath)
      puts "destination = #{destpath}" if options[:verbose]

      File.scp_get(hostname, username, key_file, filepath, destpath, 
        options[:recursive])

      #Net::SCP.start(hostname, username,
      #  :keys => [key_file], :keys_only => true) do |scp|
      #  scp.download! filepath, destpath
      #end
    
    end

    desc "put HOSTNAME FILEPATH", 'copy a file back from a remote host'
    method_option(:destpath, :type => :string)
    method_option(:recursive, :type => :boolean, :default => false)
    def put(hostname, filepath)
      puts "task: remote:file:put #{hostname} #{filepath}" unless options[:quiet]
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file
      puts "using key file #{key_file}" if options[:verbose]

      # TODO: check if key_file exists

      destpath = options[:destpath] || RealFile.basename(filepath)
      puts "destination = #{destpath}" if options[:verbose]

      File.scp_put(hostname, username, key_file, filepath, destpath,
        options[:recursive])

      #Net::SCP.start(hostname, username,
      #  :keys => [key_file], :keys_only => true) do |scp|
      #  scp.upload! filepath, destpath
      #end

    end

    desc "copy HOSTNAME SOURCE DEST", "copy a remote file from one place to another"
    method_option(:sudo, :type => :boolean, :default => false)
    def copy(hostname, src, dst)
      username = options[:username] || Remote.ssh_username
      keyfile = options[:ssh_key_file] || Remote.ssh_key_file

      puts "task: remote:file:copy #{hostname} #{src} #{dst}" unless options[:quiet]
      exit_code, exit_signal, stdout, stderr = File.copy(
        hostname, username, keyfile, src, dst,
        options[:sudo], options[:recursive], options[:force], options[:verbose])
      
      
    end

    desc("delete HOSTNAME FILEPATH",
      "delete a file or directory on a remote host"
      )
    method_option(:sudo, :type => :boolean, :default => false)
    method_option(:recursive, :type => :boolean, :default => false)
    method_option(:force, :type => :boolean, :default => false)
    def delete(hostname, filepath)
      username = options[:username] || Remote.ssh_username
      keyfile = options[:ssh_key_file] || Remote.ssh_key_file

      puts "task: remote:file:delete #{hostname} #{filepath}" unless options[:quiet]
      exit_code, exit_signal, stdout, stderr = File.delete(
        hostname, username, keyfile, filepath, 
        options[:sudo], options[:recursive], options[:force], options[:verbose])
    end

    desc "touch HOSTNAME FILEPATH", "create a file on a remote host"
    method_option(:sudo, :type => :boolean, :default => false)
    def touch(hostname, filepath)
      username = options[:username] || Remote.ssh_username
      keyfile = options[:ssh_key_file] || Remote.ssh_key_file

      puts "task: remote:file:touch #{hostname} #{filepath}" unless options[:quiet]

      Remote::File.touch(hostname, username, keyfile, filepath,
        options[:sudo], options[:verbose])
    end


    desc "mkdir HOSTNAME DIRPATH", "create a directory on a remote host"
    method_option(:sudo, :type => :boolean, :default => false)
    method_option(:parents, :type => :boolean, :default => false)
    def mkdir(hostname, dirpath)
      username = options[:username] || Remote.ssh_username
      keyfile = options[:ssh_key_file] || Remote.ssh_key_file

      puts "task: remote:file:mkdir #{hostname} #{dirpath}" unless options[:quiet]

      cmd = ""
      cmd += "sudo " if options[:sudo]
      cmd += "mkdir "
      cmd += "-p " if options[:parents]
      cmd += dirpath

      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, keyfile, cmd, options[:verbose])
    end

    desc "claim HOSTNAME FILEPATH", "take ownership of a remote file"
    method_option :newuser, :default => "$USER"
    method_option :newgroup
    def claim(hostname, filepath)
      username = options[:username] || Remote.ssh_username
      keyfile = options[:ssh_key_file] || Remote.ssh_key_file

      puts "task: remote:claim #{hostname} #{filepath}" unless options[:quiet]

      newgroup = options[:newgroup] || options[:newuser]

      cmd = "sudo chown #{options[:newuser]}:#{newgroup} #{filepath}"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, keyfile, cmd, options[:verbose])
    end


    desc "permission HOSTNAME FILEPATH MODE", "change the permissions on a remote file or directory"
    method_option :recursive, :type => :boolean, :default => false
    def permission(hostname, path, mode)
      username = options[:username] || Remote.ssh_username
      keyfile = options[:ssh_key_file] || Remote.ssh_key_file

      puts "task: remote:file:permissions #{hostname} #{path} #{mode}" unless options[:quiet]

       exit_code, exit_signal, stdout, stderr = File.set_permission(
        hostname, username, keyfile, path, mode,
        options[:sudo], options[:recursive], options[:verbose])
    end

    desc "group HOSTNAME FILEPATH GROUP", "change the group on a remote file or directory"
    def group(hostname, path, group)
      username = options[:username] || Remote.ssh_username
      keyfile = options[:ssh_key_file] || Remote.ssh_key_file

      puts "task: remote:file:group #{hostname} #{path} #{group}" unless options[:quiet]

       exit_code, exit_signal, stdout, stderr = File.set_group(
        hostname, username, keyfile, path, group,
        options[:sudo], options[:recursive], options[:verbose])
      

    end

  end

  class Rpm < Thor

    class_option(:verbose, :type => :boolean, :default => false)
    class_option(:username, :type => :string)
    class_option(:ssh_key_file, :type => :string)

    desc "version HOSTNAME PACKAGE", "Get the version of an installed package"
    def version(hostname, package)
      puts "task: remote:rpm:version #{hostname} #{package}"

      username = options[:username] || Remote.ssh_username
      keyfile = options[:ssh_key_file] || Remote.ssh_key_file

      version = Remote::Rpm.version(hostname, username, keyfile, package,
        options[:verbose])
      puts version
      version
    end

    no_tasks do

      def self.version(hostname, username, keyfile, package, verbose)
        cmd = "rpm -q #{package} --qf %{VERSION}"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, keyfile, cmd, verbose)
      
        if exit_code == 0
          return stdout[0]
        else
          return nil
        end
      end
    end
  end


  class Yum < Thor

    #namespace "remote:yum"

    class_option(:verbose, :type => :boolean, :default => false)
    class_option(:username, :type => :string)
    class_option(:ssh_key_file, :type => :string)

    desc "install HOSTNAME RPMNAME", "install an RPM on the remote system"
    def install(hostname, *rpmlist)

      rpmlist = rpmlist.join(' ') if rpmlist.class == Array
      puts "task: remote:yum:install #{hostname} #{rpmlist}" unless options[:quiet]
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file
      puts "using key file #{key_file}" if options[:verbose]

      # TODO: check if key_file exists

      puts "username: #{username}" if options[:verbose]
      puts "key_file: #{key_file}" if options[:verbose]

      #cmd = "sudo yum --debuglevel 1 -y install #{rpmname}"
      #exit_code, exit_signal, stdout, stderr = Remote.remote_command(
      #  hostname, username, key_file, cmd, options[:verbose])
      Yum.install_rpms hostname, username, key_file, rpmlist, options[:verbose]

    end

    desc "remove HOSTNAME RPMNAME", "remove an RPM on the remote system"
    def remove(hostname, rpmname)
      puts "task: remote:yum:remove #{hostname} #{rpmname}" unless options[:quiet]
      puts "removing #{rpmname} on #{hostname}" if options[:verbose]
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file
      puts "using key file #{key_file}" if options[:verbose]

      cmd = "sudo yum --debuglevel 1 -y remove #{rpmname}"

      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])
      puts "stdout length = #{stdout.count}"
      puts stdout.join("\n")
      puts stderr.join("\n")
    end

    desc "update HOSTNAME", "update RPMs on the remote system"
    def update(hostname)
      puts "task: remote:yum:update #{hostname}" unless options[:quiet]

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file
      puts "using key file #{key_file}" if options[:verbose]

      puts "username: #{username}" if options[:verbose]
      puts "key_file: #{key_file}" if options[:verbose]

      cmd = "sudo yum --debuglevel 1 -y update"

      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])
      #puts stdout.join("\n")
      #puts stderr.join("\n")

    end

    desc "list HOSTNAME", "list RPMs on the remote system"
    method_option :filter, :default => "installed"
    def list(hostname)
      puts "task: remote:yum:list #{hostname} #{options[:filter]}" unless options[:quiet]

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      # | cat causes the shell to throw away the terminal formatting
      cmd = "sudo yum --quiet --color=no list #{options[:filter]}"

      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      if not exit_code == 0
        raise Exception.new("error getting packages: #{exit_code}")
      end
      stdout = stdout[stdout.index("Installed Packages")+1..-1]
      #puts stdout.join("\n")

      pkgs = {}
      stdout.map do |line|
        pkgspec, version, repo = line.split
        pkgname, arch = pkgspec.split(".")
        pkgs[pkgname] = {:arch => arch, :version => version, :repository => repo}
      end
      pkgs
    end

    desc("exclude HOSTNAME REPO PATTERN",
      "exclude a package pattern from the specified repository")
    def exclude(hostname, repo, pattern)
      puts "task: remote:yum:exclude #{hostname} #{repo} #{pattern}" unless options[:quiet]

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      cmd = "sudo augtool -b set /files/etc/yum.repos.d/#{repo}.repo/#{repo}/exclude '#{pattern}'"

      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

    end

    desc "setvar HOSTNAME VARNAME VALUE", "set a yum variable value"
    def setvar(hostname, varname, value)
      puts "task: remote:yum:setvar #{hostname} #{varname} #{value}" unless options[:quiet]

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      Remote::Yum.setvar hostname, username, key_file, varname, value, options[:verbose]
    end

    no_tasks do

      def self.setvar(hostname, username, key_file, varname, value, verbose=false)
        cmd = "sudo python -c 'open(\"/etc/yum/vars/#{varname}\", \"w\").write(\"#{value}\\n\")'"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, verbose)

      end

      def self.install_rpms(hostname, username, key_file, packages, verbose=false)
        packages = packages.join(' ') if packages.class == Array
        cmd = "sudo yum --debuglevel 1 -y install #{packages}"

        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, verbose)

      end
    end

  end

  # manage yum repos 
  class Repo < Thor

    namespace "remote:repo"

    class_option(:verbose, :type => :boolean, :default => false)
    class_option(:username, :type => :string)
    class_option(:ssh_key_file, :type => :string)

    desc("enable HOSTNAME REPONAME", 
      "enable the components of a repo")
    method_option :all, :type => :boolean, :default => false
    def enable(hostname, reponame)
      puts "task: remote:repo:enable #{hostname} #{reponame} #{subrepo}"
    end

    desc("disable HOSTNAME REPONAME",
      "disable the components of a repo")
    method_option :all, :type => :boolean, :default => false
    def disable(hostname, reponame)
      puts "task: remote:repo:disable #{hostname} #{reponame}"

    end

    desc "create HOSTNAME REPONAME REPOFILE", "create a new YUM repo on the remote host"
    method_option(:string, :type => :boolean, :default => false,
      :desc => "repofile is the literal string content"
      )
    def create(hostname, reponame, repofile)
      puts "task: remote:repo:create #{hostname} #{reponame} #{repofile}"

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      filename = "/etc/yum.repos.d/#{reponame}.repo"

      if options[:string]
      #   write to a file or scp a string/stream?

      else
        # copy file to host
        # remove file, using sudo, no recurse, no force
        Remote::File.scp_put(hostname, username, key_file, 
          repofile, RealFile.basename(repofile))
        
      end
      # copy file on host to /etc/yum.repos.d/<filename>.repo
      Remote::File.copy(hostname, username, key_file, 
        RealFile.basename(repofile), filename,
        true, false, false, options[:verbose])
    end

    desc "delete HOSTNAME REPONAME REPOFILE", "remove a YUM repo on the remote host"
    def delete(hostname, reponame)
      puts "task: remote:repo:delete #{hostname} #{reponame} #{reponame}"

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      filename = "/etc/yum.repos.d/#{reponame}.repo"
      # remove file, using sudo, no recurse, no force
      Remote::File.delete(hostname, username, key_file, filename, 
        true, false, false, options[:verbose])
    end

    no_tasks do

    end
  end

  class Git < Thor

    include Thor::Actions

    namespace "remote:git"

    class_option(:verbose, :type => :boolean, :default => false)
    class_option(:username, :type => :string)
    class_option(:ssh_key_file, :type => :string)

    no_tasks do

      # clone a GIT repository into a remote host location
      # This is a separate method so that it can be called from other
      # tasks.  It's a class method, don't confuse it with the Task with the
      # same name (which calls this)
      def self.clone(hostname, username, key_file, giturl,
          destdir=nil, destname=nil, bare=false, verbose=false)
     
        # Compose the remote git clone command
        cmd = "git clone --quiet "
        cmd += "--bare " if bare
        cmd += giturl + " "
        cmd += destdir + "/" if destdir
        if destname
          cmd += destname
        else
          cmd += RealFile.basename(giturl, '.git')
        end
        cmd += "-bare" if bare
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, verbose)
      end


      # pull updates to remote repo/branch
      def self.pull(hostname, username, key_file, 
          gitroot, remote='origin', branch=nil, 
          verbose=false)
     
        # Compose the remote git clone command
        cmd = "cd #{gitroot} ; git pull --no-progress "
        cmd << " --verbose " if verbose
        cmd << remote
        cmd << " " + branch if branch
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, verbose)
      end

      # pull updates to remote repo/branch
      def self.fetch(hostname, username, key_file, 
          gitroot, remote='origin', branch=nil, 
          verbose=false)
     
        # Compose the remote git clone command
        cmd = "cd #{gitroot} ; git fetch --no-progress "
        cmd << " --verbose " if verbose
        cmd << remote
        cmd << " " + branch if branch
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, verbose)
      end

    end # no_tasks

    desc "clone HOSTNAME GITURL", "clone a git URL on a remote host"
    method_option(:destdir)
    method_option(:destname)
    method_option(:bare, :type => :boolean, :default => false)
    def clone(hostname, giturl)

      puts "task: remote:git:clone #{hostname} #{giturl}" unless options[:quiet]
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file
    
      # Call the class method to execute
      Git.clone(hostname, username, key_file, giturl,
        options[:destdir], options[:destname], options[:bare], options[:verbose]
        )
    end

    desc "checkout HOSTNAME REPODIR BRANCH", "checkout a branch on the remote repo"
    method_option(:remote, :default => "origin")
    method_option(:track, :type => :boolean, :default => false)
    def checkout(hostname, repodir, branch)
      puts "task: remote:git:checkout #{hostname} #{repodir} #{branch}" unless options[:quiet]
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file
    
      cmd = "cd #{repodir} ; git checkout "
      cmd += "-t #{options[:remote]}/" if options[:remote] and options[:track]
      cmd += branch
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      # check if you're already there.
      puts "exit code: #{exit_code}" if ( not exit_code === 0 || options[:verbose])
      puts "stdout: " + stdout.join("\n") if options[:verbose]
      puts "stderr: " + stderr.join("\n") if options[:verbose]
    end

    desc "pull HOSTNAME REPODIR", "pull the most recent updates from the git repo"
    method_option(:remote, :default => "origin")
    method_option(:branch)
    def pull(hostname, repodir)
      puts "task: remote:git:pull #{hostname} #{repodir} #{options[:remote]} #{options[:branch]}" unless options[:quiet]
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

    
      cmd = "cd #{repodir} ; git pull #{options[:remote]}"
      cmd += " " + options[:branch] if options[:branch]
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      
      puts "exit code: #{exit_code}" if options[:verbose]
      puts "stdout: " + stdout.join("\n") if options[:verbose]
      puts "stderr: " + stderr.join("\n") if options[:verbose]
    end

    desc "push_local HOSTNAME REPO...", "push a local git workspace to a remote host"
    method_option :destdir, :default => ""
    def push_local(hostname, *repolist)
      puts "task: remote:push_local #{hostname} #{repolist.join(' ')}"

      username = options[:username] || Remote.ssh_username
      ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

      repolist.each do |repodir|
        push_git_repo(hostname, username, ssh_key_file, repodir,
          options[:destdir], options[:verbose])
      end
    end

    desc "fetch HOSTNAME REPODIR", "fetch changes from a remote repo"
    method_option(:remote, :default => "origin")
    method_option(:branch)
    def fetch(hostname, repodir)
      puts "task: remote:git:fetch #{hostname} #{repodir} #{options[:remote]} #{options[:branch]}" unless options[:quiet]
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      cmd = "cd #{repodir} ; git fetch #{options[:remote]}"
      cmd += " " + options[:branch] if options[:branch]
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])
      
      puts "exit code: #{exit_code}" if options[:verbose]
      puts "stdout: " + stdout.join("\n") if options[:verbose]
      puts "stderr: " + stderr.join("\n") if options[:verbose]

    end

    no_tasks do

      # create a temporary file to shim ssh for git
      def write_ssh_shim(filename, ssh_key_file)
        # yeah, yeah, this could be a string
        ssh_options = {
          'StrictHostKeyChecking' => 'no',
          'UserKnownHostsFile' => '/dev/null',
          'PasswordAuthentication' => 'no'
        }

        # produce the ssh option string
        git_ssh_options = ssh_options.map { |key, value| 
          '-o ' + [key, value].join('=') }.join(' ')

        git_ssh = "ssh 2>/dev/null " + git_ssh_options + " -i #{ssh_key_file} $@"

        # write temp file
        f = open(filename, 'w')
        f.write git_ssh + "\n"
        f.close

        # set temp file executable
        RealFile.chmod(0700, filename)
      end

      # Push a local git repository to a remote machine
      def push_git_repo(hostname, username, ssh_key_file, repodir, destdir, verbose=false)

        destdir = RealFile.basename repodir if not destdir

        puts "push_git_repo #{hostname} #{username} #{ssh_key_file} #{repodir} #{destdir}"

        # This should be in a tmp directory and should probably be randomized
        ssh_shim = RealFile.expand_path("~/.ssh_shim", ssh_key_file)

        #git_ssh = RealFile.dirname(RealFile.dirname(__FILE__)) + 
        #  "/build/lib/openshift/ssh-override"
        git_cmd = "git push "        
        git_dest = "#{username}@#{hostname}:#{destdir}"
        git_branches = "#{current_branch repodir}:master"
        git_options = "--tags --force --quiet"


        cmd = "#{git_cmd} #{git_dest} #{git_branches} " + git_options

        puts "cmd: #{cmd}" if verbose
        temporary_commit repodir, verbose

        begin
          git_ssh_saved = ENV['GIT_SSH']
          ENV['GIT_SSH'] = ssh_shim
          write_ssh_shim(ssh_shim, ssh_key_file)
          #init_repos(hostname, false, repo_name, repost
          inside(repodir) do
            exit_code = run(cmd)
          end
        ensure
          RealFile.delete ssh_shim if RealFile.exists? ssh_shim
          ENV['GIT_SSH'] = git_ssh_saved
          revert_temporary_commit repodir, verbose
        end
        
      end

      # Find the current commit of a git repository
      def current_commit(workdir='.')
        `git --work-tree #{workdir} --git-dir #{workdir}/.git log -n 1`.
          split("\n")[0].split()[1]
      end

      # find the current branch of a git repository
      def current_branch(workdir='.', verbose=false)
        puts "checking #{workdir}" if verbose
        full = `git --work-tree #{workdir} --git-dir #{workdir}/.git status`
        puts "current branch: #{full}" if verbose
        if full
          return full.split("\n")[0].split()[3]
        end
      end

      # temporary_commit
      def temporary_commit(workdir=".", verbose=false)
        # Detect bad repo?
        `git --work-tree #{workdir} diff-index --quiet HEAD 2>&1 >/dev/null`

        if $? == 0
          # commit if there uncommited files
          commit = current_commit
          puts "creating temporary commit" if verbose
          `git --work-dir #{workdir} commit -a -m "Temporary commit to build" 2>&1 >/dev/null`
          if $? == 0
            puts "No-op"
          else
            @temp_commit = commit
            puts "done"
          end
        end
      end
      

      # revert_temporary_commit
      def revert_temporary_commit(workdir=".", verbose=false)
        if @temp_commit
          puts "Undoing temporary commit"
          `git --work-dir #{workdir} reset #{@temp_commit} 2>&1 >/dev/null`
          @temp_commit = nil
        end
      end


    end


    class Submodule < Thor
      
      #namespace "remote:git:submodule"

      class_option :verbose, :type => :boolean, :default => false
      class_option(:username, :type => :string)
      class_option(:ssh_key_file, :type => :string)
 
      desc "init HOSTNAME REPODIR", "initialize git submodules"
      def init(hostname, repodir='')
        puts "task: remote:git:submodule init #{hostname} #{repodir}"
      
        username = options[:username] || Remote.ssh_username
        key_file = options[:ssh_key_file] || Remote.ssh_key_file

        
        cmd = "(cd #{repodir} ; git submodule init)"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, options[:verbose]
          )
      end

      desc "update HOSTNAME REPODIR", "update remote submodules"
      method_option :branch, :type => :string, :default => 'master'
      def update(hostname, repodir='')
        puts "task: remote:git:submodule update #{hostname} #{repodir}"
      
        username = options[:username] || Remote.ssh_username
        key_file = options[:ssh_key_file] || Remote.ssh_key_file

        
        cmd = "(cd #{repodir} ; git submodule update)"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, options[:verbose]
          )
      end

    end

  end


  class Firewall < Thor
    
   namespace "remote:firewall"

    class_option :verbose, :type => :boolean, :default => false
    class_option(:username, :type => :string)
    class_option(:ssh_key_file, :type => :string)
    class_option(:systemd, :type => :boolean)


    desc "firewalld HOSTNAME", "determine if the remote host uses firewalld"
    def firewalld(hostname)
      puts "task: remote:firewall:firewalld #{hostname}"
      
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      # check for systemctl

      cmd = "sudo systemctl status firewalld.service"
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose]
        )

      case exit_code
      when 1
        puts "systemctl not present - using iptables"
      when 3
        puts "firewalld not running"
        # check if it's enabled
        cmd = "sudo systemctl is-enabled firewalld.service"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, options[:verbose]
          )
        puts "firewalld is #{exit_code == 0 ? "" : 'not '}enabled"
      when 0
        puts "firewalld present, enabled, running"
      end
      # conditions:
      #  exit code = 1 # systemctl not present
      #    stderr matches "sudo: systemctld: command not found"
      #    return "false"
      #
      #  exit code = 3 # systemctl present, no such service
      #    stdout matches "Loaded: error (Reason: No such file or directory)"
      #    return "false"
      # 
      #  exit code = 3 # systemctl present, service installed but disabled
      #    stdout matches "Loaded: loaded (.* disabled)$
      # 
      #  exit code = 3 # systemctl present, service installed enabled, stopped
      #    stdout matches "Loaded: loaded (.* enabled)$"
      #                   "Active: inactive (dead)$"
      #
      #  exit code = 0 # systemct present, service installed enabled, running
      #    stdout matches "Loaded: loaded (.*; enabled)
      #    stdout matches "Active: active (running)"

      $firewalld = exit_code == 0
      exit_code == 0
      
    end
    
    desc "port HOSTNAME PORTNUM [PORTNUM]...", "open a port on a remote host"
    method_option :protocol, :type => :string, :default => "tcp"
    def port(hostname, *ports)
      puts "task: remote:firewall:port #{hostname} #{ports.join(' ')}"
      
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      invoke "remote:firewall:firewalld", [hostname]

      ports.each { |portnum|
        puts "opening port #{portnum}" if options[:verbose]
        Remote::Firewall.port(hostname, username, key_file,  
          portnum, protocol=(options[:protocol] || 'tcp'), 
          close=false, $firewalld, options[:verbose])
      }
    end

    desc "service HOSTNAME SERVICE [SERVICE]...", "allow a service on a remote host"
    def service(hostname, *services)
      puts "task: remote:firewall:service #{hostname} #{services.join(' ')}"
      
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      services.each { |service|
        puts "allowing service #{service}" if options[:verbose]
        Remote::Firewall.service(hostname, username, key_file, service,
          options[:verbose])
      }
    end

    desc "start HOSTNAME", "start the firewall service on the host"
    def start(hostname)
      puts "task: remote:firewall:start #{hostname}"
      
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      systemd = options[:systemd]
      systemd = Remote.pidone(hostname, username, key_file, options[:verbose]) if systemd == nil

      firewalld = ($firewalld != nil ? $firewalld : invoke("remote:firewall:firewalld", [hostname]))

      if firewalld 
        Remote::Service.execute(hostname, username, key_file,
          'firewalld', 'start', systemd, options[:verbose])        
      else
        Remote::Service.execute(hostname, username, key_file,
          'iptables', 'start', systemd, options[:verbose])
      end
    end

    desc "stop HOSTNAME", "stop the firewall service on the host"
    def stop(hostname)
      puts "task: remote:firewall:stop #{hostname}"
      
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      systemd = options[:systemd]
      systemd = Remote.pidone(hostname, username, key_file, options[:verbose]) if systemd == nil

      firewalld = ($firewalld != nil ? $firewalld : invoke("remote:firewall:firewalld", [hostname]))

      if firewalld 
        Remote::Service.execute(hostname, username, key_file,
          'firewalld', 'stop', systemd, options[:verbose])        
      else
        Remote::Service.execute(hostname, username, key_file,
          'iptables', 'stop', systemd, options[:verbose])
      end
    end

    desc "enable HOSTNAME", "enable the firewall service on the host"
    def enable(hostname)
      puts "task: remote:firewall:enable #{hostname}"
      
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      systemd = options[:systemd]
      systemd = Remote.pidone(hostname, username, key_file, options[:verbose]) if systemd == nil

      firewalld = ($firewalld != nil ? $firewalld : invoke("remote:firewall:firewalld", [hostname]))

      if firewalld 
        Remote::Service.execute(hostname, username, key_file,
          'firewalld', 'enable', systemd, options[:verbose])        
      else
        Remote::Service.execute(hostname, username, key_file,
          'iptables', 'enable', systemd, options[:verbose])
      end

    end

    desc "disable HOSTNAME", "disable the firewall service on the host"
    def disable(hostname)
      puts "task: remote:firewall:disable #{hostname}"
      
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      systemd = options[:systemd]
      systemd = Remote.pidone(hostname, username, key_file, options[:verbose]) if systemd == nil

      firewalld = ($firewalld != nil ? $firewalld : invoke("remote:firewall:firewalld", [hostname]))

      if firewalld 
        Remote::Service.execute(hostname, username, key_file,
          'firewalld', 'disable', systemd, options[:verbose])        
      else
        Remote::Service.execute(hostname, username, key_file,
          'iptables', 'disable', systemd, options[:verbose])
      end

    end

    desc "status HOSTNAME", "status of the firewall service on the host"
    def status(hostname)
      puts "task: remote:firewall:status #{hostname}"
      
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      systemd = options[:systemd]
      systemd = Remote.pidone(hostname, username, key_file, options[:verbose]) if systemd == nil

      firewalld = ($firewalld != nil ? $firewalld : invoke("remote:firewall:firewalld", [hostname]))

      if firewalld 
        Remote::Service.execute(hostname, username, key_file,
          'firewalld', 'status', systemd, options[:verbose])        
      else
        Remote::Service.execute(hostname, username, key_file,
          'iptables', 'status', systemd, options[:verbose])
      end

    end

    no_tasks do
      def self.port(hostname, username, key_file, 
          portnum, protocol='tcp', close=false, firewalld=false,
          verbose=false)

        if firewalld == true
          cmd = "sudo firewall-cmd --zone public --add-port #{portnum}/#{protocol}"
          exit_code, exit_signal, stdout, stderr = Remote.remote_command(
            hostname, username, key_file, cmd, verbose)
          
          cmd += " --permanent"
          exit_code, exit_signal, stdout, stderr = Remote.remote_command(
            hostname, username, key_file, cmd, verbose)

        else
          cmd = "sudo lokkit --nostart --port=#{portnum}:#{protocol}"
          exit_code, exit_signal, stdout, stderr = Remote.remote_command(
            hostname, username, key_file, cmd, verbose)
        end
      end

      def self.service(hostname, username, key_file, service,
          verbose=false)

        #cmd = "sudo firewall-cmd --zone public --add-port 8140/tcp"
        cmd = "sudo lokkit --nostart --service=#{service}"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, verbose)
      end

    end
  end


  class Service < Thor

   #namespace "remote:service"

    class_option(:verbose, :type => :boolean, :default => false)
    class_option(:username, :type => :string)
    class_option(:ssh_key_file, :type => :string)
    class_option(:systemd, :type => :boolean, :default => nil)

    no_tasks do

      def self.cmd(service, action, systemd=true)
        if systemd
          return "systemctl #{action} #{service}.service"
        end

        if ['enable', 'disable'].member? action
          return "chkconfig #{service} #{action == 'enable'? 'on' : 'off'}"
        end
          
        "service #{service} #{action}"
      end

      def self.execute(hostname, username, key_file, service, action, systemd, 
          verbose=false)

        cmd = "sudo " + Remote::Service.cmd(service, action, systemd)
        Remote.remote_command(hostname, username, key_file, cmd, verbose)
      end

    end

    # start
    desc "start HOSTNAME SERVICE [SERVICE...]", "start a service on a remote host"
    def start(hostname, *services)
      puts "task: remote:service:start #{hostname} #{services.join(' ')}"


      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      if options[:systemd] == nil
        systemd = Remote.pidone(hostname, username, key_file, options[:verbose]) == "systemd"
      else
        systemd = options[:systemd]
      end
      
      services.each { |service|
        Remote::Service.execute(hostname, username, key_file,
          service, 'start', systemd, options[:verbose])
      }

    end

    # stop
    desc "stop HOSTNAME SERVICE [SERVICE...]", "start a service on a remote host"
    def stop(hostname, *services)
      puts "task: remote:service:stop #{hostname} #{services.join(' ')}"


      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      if options[:systemd] == nil
        systemd = Remote.pidone(hostname, username, key_file) == "systemd"
      else
        systemd = options[:systemd]
      end
      
      services.each { |service|
        Remote::Service.execute(hostname, username, key_file,
          service, 'stop', systemd, options[:verbose])
      }

    end

    # restart
    # start
    desc "restart HOSTNAME SERVICE [SERVICE...]", "start a service on a remote host"
    def restart(hostname, *services)
      puts "task: remote:service:restart #{hostname} #{services.join(' ')}"


      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      if options[:systemd] == nil
        systemd = Remote.pidone(hostname, username, key_file) == "systemd"
      else
        systemd = options[:systemd]
      end
      
      services.each { |service|
        Remote::Service.execute(hostname, username, key_file,
          service, 'restart', systemd, options[:verbose])
      }
    end

    # status

    # enable
    desc "enable HOSTNAME SERVICE [SERVICE...]", "start a service on a remote host"
    def enable(hostname, *services)

      puts "task: remote:service:enable #{hostname} #{services.join(' ')}"

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      if options[:systemd] == nil
        systemd = Remote.pidone(hostname, username, key_file) == "systemd"
      else
        systemd = options[:systemd]
      end
      
      services.each { |service|
        Remote::Service.execute(hostname, username, key_file,
          service, 'enable', systemd, options[:verbose])
      }
    end

    # disable
    desc "disable HOSTNAME SERVICE [SERVICE...]", "start a service on a remote host"
    def disable(hostname, *services)
      puts "task: remote:service:disable #{hostname} #{services.join(' ')}"

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      if options[:systemd] == nil
        systemd = Remote.pidone(hostname, username, key_file) == "systemd"
      else
        systemd = options[:systemd]
      end
      
      services.each { |service|
        Remote::Service.execute(hostname, username, key_file,
          service, 'disable', systemd, options[:verbose])
      }

    end

  end

  # remote augeas commands
  class Augeas < Thor

    class_option :verbose, :type => :boolean, :default => false
    class_option(:username, :type => :string)
    class_option(:ssh_key_file, :type => :string)

    desc "get HOSTNAME PATH", "retrieve a value from a remote host using Augeas"
    def get(hostname, path)
      
      puts "remote:augeas:get #{hostname} #{path}"
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      value = Remote::Augeas.get(hostname, username, key_file, path, 
        options[:verbose])
      puts value
      return value
    end

    desc "set HOSTNAME PATH VALUE", "put a value on a remote host using Augeas"
    def set(hostname, path, value)

      puts "remote:augeas:set #{hostname} #{path} #{value}"
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      Remote::Augeas.set(hostname, username, key_file, path, value, 
        options[:verbose])
    end

    no_tasks do

      def self.get(hostname, username, key_file, path, verbose)
        cmd = "sudo augtool get #{path}"

        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, verbose)

        response = stdout[0]
        check_path, value = response.split('=')
        value.strip        
      end

      def self.set(hostname, username, key_file, path, value, verbose=false)

        cmd = "sudo augtool -s set #{path} #{value}"

        puts "- cmd: #{cmd}" if verbose
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, verbose)

        return exit_code == 0        
      end
    end

  end

  class Patch < Thor

    class_option :verbose, :type => :boolean, :default => false
    class_option(:username, :type => :string)
    class_option(:ssh_key_file, :type => :string)

    desc "apply hostname patchfile destfile", "Patch a remote file with a local patch file"
    method_option(:sudo, :type => :boolean, :default => false)
    def apply(hostname, patchfile, destfile)
      puts "remote:patch:apply #{hostname} #{patchfile} #{destfile}"

      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file

      Remote::Patch.apply(hostname, username, key_file, patchfile, destfile,
        options[:sudo], options[:verbose])
    end

    no_tasks do
      def self.apply(hostname, username, key_file, patchfile, destfile, sudo, verbose)
        remotepatchfile = RealFile.basename(patchfile)
        # copy the patchfile to remote home
        Remote::File.scp_put(hostname, username, key_file, 
          patchfile, remotepatchfile)
        # apply the patch
        cmd = sudo ? "sudo " : ""
        cmd += "patch --backup --forward #{destfile} #{remotepatchfile}"
        exit_code, exit_signal, stdout, stderr = Remote.remote_command(
          hostname, username, key_file, cmd, verbose)
      end
    end

  end

  desc "arch HOSTNAME", "get the base architcture of the host"
  def arch(hostname)
    
    puts "task: remote:arch #{hostname}" unless options[:quiet]

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file

    cmd = "arch"
    puts "executing #{cmd} on #{hostname}" if options[:verbose]
    arch = Remote.arch(hostname, username, key_file, options[:verbose])
    puts arch
    arch
  end

  no_tasks do
    def self.arch(hostname, username, key_file, verbose)
      cmd = "arch"
      puts "executing #{cmd} on #{hostname}" if options[:verbose]
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])
      return stdout[0]
    end
  end

  desc "set_selinux HOSTNAME", "control SELinux settings on a remote host"
  method_option(:enforce, :type => :boolean, :default => true)
  method_option(:enable, :type => :boolean, :default => true)
  def set_selinux(hostname)

    puts "task: remote:set_selinux  #{hostname} " +
      "#{'no' if not options[:enforce]}enforce " +
      "#{'no' if not options[:enable]}enable" unless options[:quiet]

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file

    defstate = options[:enable] ? "enabled" : "disabled"
    cmd = "sudo sed -i -e '/^SELINUX=/s/=.*$/=#{defstate}/' /etc/selinux/config"
    puts "executing #{cmd} on #{hostname}" if options[:verbose]
    exit_code, exit_signal, stdout, stderr = Remote.remote_command(
      hostname, username, key_file, cmd, options[:verbose])

    cmd = "sudo setenforce " + (options[:enforce] ? "1" : "0")
    puts "executing #{cmd} on #{hostname}" if options[:verbose]
    exit_code, exit_signal, stdout, stderr = Remote.remote_command(
      hostname, username, key_file, cmd, options[:verbose])
  end

  desc "set_hostname HOSTNAME", "set the remote hostname provided"
  method_option :ipaddr, :type => :string
  def set_hostname(hostname)

    puts "task: remote:hostname #{hostname}" unless options[:quiet]

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file

    cmd = "sudo hostname #{hostname}"
    puts "executing #{cmd} on #{hostname}" if options[:verbose]
    exit_code, exit_signal, stdout, stderr = Remote.remote_command(
      hostname, username, key_file, cmd, options[:verbose])

    cmd = "sudo sed -i -e '/HOSTNAME=/s/=.*/=#{hostname}/' /etc/sysconfig/network"
    puts "executing #{cmd} on #{hostname}" if options[:verbose]
    exit_code, exit_signal, stdout, stderr = Remote.remote_command(
      hostname, username, key_file, cmd, options[:verbose])

    if options[:ipaddr]
      # set the hostname/ip address in /etc/hosts if it's not there
      # This should probably be done with puppet and augeas, but this is simpler for now:
      # believe it or not, delete after append works.
      cmd = "sudo sed -i -e '$a#{options[:ipaddr]} #{hostname}' -e '/#{hostname}/d' /etc/hosts"
      puts "executing #{cmd} on #{hostname}" if options[:verbose]
      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

      # What I really want to do is:
      #   if and entry for that hostname exists, set the IP to the one provided
      #   else add a new line, but that's three commands not one on a clean machine.
    end


  end
  
  desc "reset_net_config HOSTNAME", "reset the network configuration to simple DHCP"
  def reset_net_config(hostname, device="eth0")
    puts "task remote:reset_net_config #{hostname} #{device}" unless options[:quiet]

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file

    filename = "ifcfg-#{device}"
    # Aliased RealFile so we could have a class in scope named File
    localfile = RealFile.dirname(RealFile.dirname(__FILE__)) + "/data/ifcfg-eth0"
    cfgdir = '/etc/sysconfig/network-scripts'
    remotefile = "#{cfgdir}/ifcfg-#{device}"
    # copy the file to the host
    Remote::File.scp_put(hostname, username, key_file, localfile, filename)

    # optionally replace eth0 with another device?
    #cmd = "sed -i -e'/DEVICE=/s/=.*$/=#{device}' #{filename}"

    # copy the file in place
    cmd = "sudo cp #{filename} #{cfgdir}"
    exit_code, exit_signal, stdout, stderr = Remote.remote_command(
      hostname, username, key_file, cmd, options[:verbose])

    # restart network

    #
  end


end

#if self.to_s === "main" then
#  Tasks::Remote.start()
#end


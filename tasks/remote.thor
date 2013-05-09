# /usr/bin/thor
# Remote tasks on hosts

require 'rubygems'
require 'thor'
require 'parseconfig'

# rubygem-net-ssh is only available from the openshift repo for RHEL
require 'net/ssh'


# We're going to create a local class named "File".  We have to avoid losing
# the main.File module from scope
# Could also have used ::File throughout
RealFile = File

# Default location to find config and auth information
AWS_CREDENTIALS_FILE = ENV["AWS_CREDENTIALS_FILE"] || "~/.awscred"

# Remote tasks (using SSH)

class Remote < Thor
  include Thor::Actions

  namespace "remote"

  no_tasks do

    def self.ssh_key_file
      credentials_file ||= AWS_CREDENTIALS_FILE
      config = ParseConfig.new RealFile.expand_path(credentials_file)
      key_pair_name = config.params['AWSKeyPairName']
      # TODO: check that the key_pair_name is set
      RealFile.expand_path("~/.ssh/#{key_pair_name}.pem") 
      # TODO: check that the key file exists?
    end

    def self.ssh_username
      credentials_file ||= AWS_CREDENTIALS_FILE
      config = ParseConfig.new(RealFile.expand_path(credentials_file))
      config.params['RemoteUser']
    end

    def self.remote_command(hostname, username, key_file, command, verbose=false, timeout=15)
      stdout = []
      stderr = []
      exit_code = nil
      exit_signal = nil

      begin
        Net::SSH.start(hostname, username, :timeout => timeout,
          :keys => [key_file], :keys_only => true) do |ssh|

          ssh.open_channel do | channel |
            channel.request_pty

            puts "cmd: #{command}" if verbose
            result = channel.exec(command) do |ch, success |

              channel.on_data do | ch, data |
                puts "remote: #{data.strip}" if verbose and not data.match(/^\s+$/)
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

      rescue Net::SSH::AuthenticationFailed => e
        puts "Authentication failed" if verbose
        return nil
      rescue Net::SSH::Disconnect => e
        puts "Connection closed by remote host" if verbose
        return nil
      rescue SocketError => e
        puts "socket error: #{e.message}" if verbose
        return nil
      rescue Errno::ETIMEDOUT => e
        puts "timed out attempting to connect" if verbose
        return nil
      rescue Timeout::Error => e
        puts "timed out attempting to connect" if verbose
        return nil
      rescue Errno::ECONNREFUSED
        puts "connection refused" if verbose
        return nil
      rescue Errno::ECONNRESET
        puts "connection reset" if verbose
        return nil
      end # try block
      [exit_code, exit_signal, stdout, stderr]
    end # remote_command

    
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
    puts "using username #{username} and key file #{key_file}" if options[:verbose]

    cmd = "echo success"

    (1..10).each do |trynum|
      result = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])
      if result then
        exit_code, exit_signal, stdout, stderr = result
        if options[:verbose] then
          puts stdout.join("\n") 
          puts stderr.join("\n")
          puts "stdout length = #{stdout.count}"
          puts "exit code: #{exit_code}"
        end
        return true
      end
      break if not options[:wait]
      puts "sleeping #{options[:pollrate]}" if options[:verbose]
      sleep 10
    end
    puts "#{hostname} not available" if options[:verbose]
    return false
  end

  desc "distribution HOSTNAME", "probe the distribution information from a remote host"
  def distribution(hostname)

    puts "task: remote:distribution #{hostname}" unless options[:quiet]
    distro_table = {
      "Red Hat" => 'rhel',
      "CentOS" => 'centos',
      "Fedora" => 'fedora'
    }

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file
    puts "using key file #{key_file}" if options[:verbose]

    cmd = "cat /etc/redhat-release"

    exit_code, exit_signal, stdout, stderr = Remote.remote_command(
      hostname, username, key_file, cmd, options[:verbose])

    # check for exit code == 0

    # parse contents of output
    info = stdout[0].match /^(Fedora|Red Hat|CentOS).*release ([\d.]+)/

    release_info = [distro_table[info[1]], info[2]]
    puts release_info[0] + ' ' + release_info[1]
    release_info
  end

  desc "pullurl HOSTNAME URL", "pull a file to a remote host using wget"
  method_option(:filepath, :type => :string)
  def pullurl(hostname, url)

    puts "task: remote:pullurl #{hostname} #{url}" unless options[:quiet]

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file
    puts "using key file #{key_file}" if options[:verbose]

    puts "username: #{username}" if options[:verbose]
    puts "key_file: #{key_file}" if options[:verbose]

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

  class File < Thor

    namespace "remote:file"

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
    def copy
      
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

      puts "task: remote:delete #{hostname} #{filepath}" unless options[:quiet]
      exit_code, exit_signal, stdout, stderr = File.delete(
        hostname, username, keyfile, filepath, 
        options[:sudo], options[:recursive], options[:force], options[:verbose])
    end


    desc "mkdir HOSTNAME DIRPATH", "create a directory on a remote host"
    method_option(:sudo, :type => :boolean, :default => false)
    method_option(:parents, :type => :boolean, :default => false)
    def mkdir(hostname, dirpath)
      username = options[:username] || Remote.ssh_username
      keyfile = options[:ssh_key_file] || Remote.ssh_key_file

      puts "task: remote:mkdir #{hostname} #{dirpath}" unless options[:quiet]

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


  end

  class Yum < Thor

    namespace "remote:yum"

    class_option(:verbose, :type => :boolean, :default => false)
    class_option(:username, :type => :string)
    class_option(:ssh_key_file, :type => :string)

    desc "install HOSTNAME RPMNAME", "install an RPM on the remote system"
    def install(hostname, rpmname)

      puts "task: remote:yum:install #{hostname} #{rpmname}" unless options[:quiet]
      username = options[:username] || Remote.ssh_username
      key_file = options[:ssh_key_file] || Remote.ssh_key_file
      puts "using key file #{key_file}" if options[:verbose]

      # TODO: check if key_file exists

      puts "username: #{username}" if options[:verbose]
      puts "key_file: #{key_file}" if options[:verbose]

      cmd = "sudo yum --debuglevel 1 -y install #{rpmname}"

      exit_code, exit_signal, stdout, stderr = Remote.remote_command(
        hostname, username, key_file, cmd, options[:verbose])

    end

    desc "remove HOSTNAME RPMNAME", "remove an RPM on the remote system"
    def remove(hostname, rpmname)
      puts "task: remote:yum:remove #{hostname} #{rpm}" unless options[:quiet]
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

    desc "list HOSTNAME", "update RPMs on the remote system"
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
        cmd = "git clone "
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
  end

  class Service < Thor

    namespace "remote:service"

    class_option(:verbose, :type => :boolean, :default => false)
    class_option(:username, :type => :string)
    class_option(:ssh_key_file, :type => :string)

    # start
    desc "start SERVICE [SERVICE...]", "start a service on a remote host"
    method_option(:uplift, :type => :boolean, :default => false)
    def start(hostname, services)

    end

    # stop

    # restart

    # status

    # enable

    # disable

  end

  class Puppet < Thor

    class_option(:verbose, :type => :boolean, :default => false)
    class_option(:username, :type => :string)
    class_option(:ssh_key_file, :type => :string)
  
  end

  desc "arch HOSTNAME", "get the base architcture of the host"
  def arch(hostname)
    
    puts "task: remote:arch #{hostname}" unless options[:quiet]

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file

    cmd = "arch"
    puts "executing #{cmd} on #{hostname}" if options[:verbose]
    exit_code, exit_signal, stdout, stderr = Remote.remote_command(
      hostname, username, key_file, cmd, options[:verbose])
    puts stdout[0]
    stdout[0]
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
#  OpenShift::Tasks::Remote.start()
#end


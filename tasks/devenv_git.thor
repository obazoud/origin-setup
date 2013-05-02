#
require 'rubygems'
require 'thor'
require 'net/http'
require 'parseconfig'

module OpenShift
  class Devenv < Thor
    class GitHelpers < Thor
      namespace "devenv:git"

      # clone sources (bare)

      # clone bare to working

      # push local to bare

      # checkout branch on working

      # from remote
      desc "clone_sources HOSTNAME REPO=URL...", "pull source trees to the host"
      method_option :destdir, :default => "/data"
      method_option :replace, :type => :boolean, :default => true
      method_option :bare, :type => :boolean, :default => false
      def clone_sources(hostname, *repolist)

        puts "task: devenv:build:clone_sources #{hostname}" unless options[:quiet]
        username = options[:username] || Remote.ssh_username
        ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

        # if repospecs is an array of key=val pairs, convert it to a hash
        if repolist.count === 1 and repolist[0].class == Hash
          repospecs = repolist[0]
        else
          repospecs = {}
          repolist.each do |spec|
            name, url = spec.match(/(^[^=]+)=(.*$)/)[1..2]
            repospecs[name] = url
          end
        end

        # TODO: validate repospecs
        
        repospecs.each do |reponame, url|
          filepath = options[:destdir] + "/" + reponame
          # delete the existing repo recursive, and force (if it exists)
          Remote::File.delete(hostname, username, ssh_key_file,
           filepath, false, true, true, options[:verbose]
            ) if options[:replace]
          puts "cloning repo #{reponame} from #{url} to #{options[:destdir]}/#{reponame}" if options[:verbose]
          Remote::Git.clone(hostname, username, ssh_key_file, url,
            options[:destdir], reponame, options[:bare], options[:verbose]
            )
        end

      end

      desc("push_local HOSTNAME REPO...", 
        "push a local git source workspace to a remote host")
      method_option :destdir, :default => "/data"
      method_option :replace, :type => :boolean, :default => true
      def push_working(hostname, *repolist)
        puts "task: devenv:build:push_repo #{hostname} #{repolist.join(' ')}" unless options[:quiet]

        username = options[:username] || Remote.ssh_username
        ssh_key_file = options[:ssh_key_file] || Remote.ssh_key_file

        # push each repo found to the host
        repodirlist = local_repo_directories repolist
        puts repodirlist.to_s
        
        repodirlist.each do |repodir|
          # remove remote if replace
          # clone bare
          invoke("remote:git:put_local", [hostname, repodir])
        end

      end
      
      no_tasks do
        
        # find git repos nearby the current working directory
        def local_repo_directories(repolist=[])
          if repolist.count === 0
            cfg = ParseConfig.new(File.expand_path("~/.awscred"))
            repolist = cfg['sourcerepos'].keys
          end
          dirlist = repolist.map { |reponame| File.expand_path("../"+reponame) }
          dirlist.select { |repopath| 
            Dir.exists? repopath and
            Dir.exists? repopath + "/.git"
          }
        end

      end # no_tasks

    end
  end
end

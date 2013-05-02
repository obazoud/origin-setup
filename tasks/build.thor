#!/usr/bin/env ruby
#
# A set of tasks to prepare and build the OpenShift Origin source tree
# into packages
#
require 'rubygems'
require 'thor'

# Used to search for spec files and other marker files within the source tree
require 'find'

SOURCE_ROOT = ENV["OPENSHIFT_SOURCE_ROOT"] || "."
REPO_ROOT = ENV["OPENSHIFT_REPO_ROOT"] || "/tmp/tito"
YARDOC_ROOT = ENV["OPENSHIFT_YARDOC_ROOT"] || "./doc"

PREREQUISITES = ['git', 'tito', 'rpm-build', 'rubygem-redcarpet']

  class Build < Thor

    desc "prepare", "prepare the build environment"
    def prepare
      cmd = "yum install #{PREREQUISITES.join(' ')}"
      cmd = "sudo " + cmd if not Process.uid == 0
      system cmd
    end

    desc "requirements", "install packages required to build software"
    method_option(:source, :aliases => "-s", 
      :type => :string, :default => '.',
      :desc => "location of the source tree"
      )
    method_option(:assumeyes, :aliases => "-y", 
      :type => :boolean, :default => false,
      :desc => "say 'yes' when prompted."
      )
    def requirements
      cmd = "yum-builddep " + ((" --assumeyes " if options[:assumeyes]) || "")
      specfiles = spec_file_list(options[:source]).join(' ')
      cmd += specfiles
      cmd = "sudo " + cmd if not Process.uid == 0
      system cmd
    end

    desc "rpm", "build RPM packages from source code"
    method_option(:source, :aliases => "-s", 
      :type => :string, :default => '.',
      :desc => "location of the source tree"
      )
    method_option :repodir, :aliases => "-r", :default => REPO_ROOT,
      :desc => "location for the YUM repo"
    method_option :test, :aliases => "-t",:type => :boolean, :default => false,
      :desc => "build test packages instead of release packages"
    def rpm
      pkg_root_list(options[:source]).each {|pkgdir|
        cmd = "tito build --rpm --output #{options[:repodir]}"
        cmd << " --test" if options[:test]
        system "cd #{pkgdir} ; #{cmd}"
      }
    end

    desc "repo", "generate YUM repository metadata"
    method_option :repodir, :aliases => "-r", :default => REPO_ROOT,
      :desc => "location for the YUM repo"
    def repo
      repodir = options[:repodir]
      raise ArgumentError.new "directory #{repodir} does not exist" if not Dir.exists? repodir
      system "createrepo #{repodir}"
      puts "generating repo in #{repodir}"
    end

    begin
      require 'yard'
      desc "yardoc", "build comprehensive yard documentation"
      method_option(:source, :aliases => "-s", 
        :type => :string, :default => '.',
        :desc => "location of the source tree"
        )
      method_option :output, :aliases => "-o", :default => YARDOC_ROOT,
        :desc => "location for yardoc output"
      def yardoc
        system "cd #{options[:source]} ; yardoc #{pkg_root_list.join(' ')} --output-dir #{options[:output]}"
      end
    rescue LoadError => e
      
    end

    private

    # Find the RPM spec files beneath a directory tree
    # @param rootdir [String] The root of the search
    def spec_file_list(rootdir=SOURCE_ROOT)
      Find.find(rootdir).select { | filename | filename.end_with? ".spec" }
    end

    # Find the list of package directories from the location of spec files
    def pkg_root_list(rootdir=SOURCE_ROOT)
      spec_file_list(rootdir).map {|specfile| File.dirname specfile }
    end
  end

# Allow inclusion as a library
if self.to_s === 'main' then
  Build.start
end

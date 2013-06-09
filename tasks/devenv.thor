#!/usr/bin/ruby
#
require 'rubygems'
require 'thor'
require 'thor/actions'

require 'logger'
# Force synchronous stdout
STDOUT.sync, STDERR.sync = true

# Setup logger
@@log = Logger.new(STDOUT)
@@log.level = Logger::DEBUG

def log
  @@log
end

class Devenv < Thor

  class_option :verbose, :type => :boolean, :default => false
  class_option :debug, :type => :boolean, :default => false

  desc "launch NAME", "create a new instance with the given name"
  method_option :image
  method_option :baseos
  method_option :keypair
  method_option :type, :default => "m1.large"
  method_option :securitygroup, :type => :array, :default => ['devenv']
  def launch(name)
    puts "task: devenv:launch #{name}" unless options.quiet?

    config = OpenShift::AWS.config

    # enable logging/debugging
    options.verbose? ? log.level = Logger::DEBUG : log.level = Logger::ERROR

    #----------------
    # Select an image
    #----------------
    #
    # if we have an image, create an instance, start it and learn the OS
    image_id = options[:image]
    if not image_id
      # use the current OS unless told explicitly
      baseos = options[:baseos] || guess_os
      # TODO: validate baseos
      puts "- baseos: #{baseos}" unless options[:quiet]

      image_id  = config[baseos]['BaseOSImage']
    end
    # TODO: validate image_id
    puts "- image id: #{image_id}" unless options[:quiet]

    keypair = options[:keypair] || config['AWSKeyPairName']

    # select the instance type
    type = options[:type] || config['AWSEC2Type']

    instance = invoke("ec2:instance:create", [], 
      :name => name,
      :image => image_id,
      :key => config['AWSKeyPairName'],
      :type => type,
      :securitygroup => options[:securitygroup],
      :verbose => options[:verbose]
      )
    
    # monitor startup process: wait until running
    (1..20).each do |trynum|
      break if instance.status.to_s === 'running'
      puts "- #{instance.id} '#{instance.status}' waiting..." if options[:verbose]
      sleep 15
    end
    raise Exception.new "Instance failed to start" if not instance.status.to_s === 'running'
    puts "- instance #{instance.id} running" unless options[:quiet]

    # update facts

    # post launch

    # verify
 
    # update api ?

    # update ssh_config

    puts "Public IP:       #{instance.public_ip_address}"
    puts "Public Hostname: #{instance.dns_name}"
    puts "Site URL:        https://#{instance.dns_name}"
    puts "Done"

  end

  no_tasks do
    # determine which distribution family we're running on
    def guess_os
      if File.exist?("/etc/redhat-release")
        data = File.read("/etc/redhat-release").strip
        parts = data.match(/^(.*)\srelease(\d*(\.\d+)?)\s\((.*)\)$/)
        return nil if parts == nil
        return "fedora" + parts[2] if parts[1] == "Fedora"
        return "rhel" + parts[2] if parts[1] == "Red Hat Enterprise Linux Server"
        return "centos" + parts[2] if data.match(/centos/)
      end
    end
   
  end

end

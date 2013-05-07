#!/usr/bin/env ruby
# Present tasks to manage AWS EC2 images and instances
#
require 'rubygems'
require 'thor'
require 'aws'
require 'parseconfig'

#require 'openshift/aws'


  # Manage Amazon Web Services EC2 instances and images
module OpenShift
  class Instance < Thor

    namespace "ec2:instance"

    class_option :verbose, :type => :boolean, :default => false

    AWS_CREDENTIALS_FILE = ENV["AWS_CREDENTIALS_FILE"] || "~/.awscred"

    desc "list", "list the set of running instances"
    method_option(:name, :desc => "filter for instance names")
    def list
      handle = login
#      handle.instances.filter('tag-key', "Name").filter('tag-value', options[:name]).each do |i|

      instances = handle.instances
      if options[:name]
        instances = instances.filter('tag-key', "Name").
          filter('tag-value', options[:name])
      end

      instances.each do |i|
        tags = i.tags.map { |t| t.to_s }.join(' ')
        if options[:verbose] then
          puts "#{i.id} #{i.tags['Name']} #{i.status}"
        else
          puts "#{i.id} #{i.tags['Name']}"
        end
      end
    end
    
    desc "create", "create a new EC2 instance from an existing image"
    method_option(:name, :type => :string, :required => true,
      :desc => "the name for the new instance")
    method_option(:image, :type => :string, :required => true,
      :desc => "an EC2 image id")
    method_option(:key, :type => :string,
      :desc => "an access key pair name")
    # m1.small or t1.micro
    method_option(:type, :type => :string, :default => "t1.micro",
      :desc => "an EC2 image type")
    method_option(:secgroup, :type => :string, :default => "default",
      :desk => "the security group to apply to this instance")
    method_option(:wait, :type => :boolean, :default => false)
    def create
      puts "task: ec2:instance:create " +
        "#{options[:image]} #{options[:name]}" unless options[:quiet]

      handle = login

      # use configured value if not provided
      key = options[:key] || Remote.ssh_key_file

      # TODO: check if it already exists?

      instance = handle.instances.create(
        :image_id => options[:image],
        :instance_type => options[:type],
        :key_name => options[:key],
        :security_groups => [options[:secgroup]],
        :block_device_mappings => {'/dev/sdb' => 'ephemeral0'}
        )
            
      (1..3).each do |i|
        begin
          instance.add_tag('Name', :value => options[:name])
          break;
        rescue AWS::EC2::Errors::InvalidInstanceID::NotFound => e
          sleep i
        end
      end

      if options[:verbose]
        puts "created new instance: id = #{instance.id}, " +
          "name = #{instance.tags['Name']}"
      else
        puts "  id = " + instance.id unless options[:quiet]
      end

      #if options[:wait] then
      #  
      #end

      instance
    end

    desc "delete", "delete an EC2 instance"
    method_option(:id, :type => :string, :desc => "an EC2 instance id")
    method_option(:name, :type => :string)
    method_option(:force, :type => :boolean, :default => false)
    def delete
      puts "task: ec2:instance:delete " +
        "#{options[:id]} #{options[:name]}" unless options[:quiet]
      handle = login
      instance = find_instance(handle, options)
      
      if not options[:force] then
        answer = nil
        until (['y', 'n'].member? answer) do
          answer = ask "Delete instance #{instance.id} (#{instance.tags['Name']}) (y/n)"
        end
        if answer === 'n' then
          puts "not deleting"
          return
        end
      end
      if options[:verbose] then
        puts "Deleting instance #{instance.id} (#{instance.tags['Name']})" 
      end
      begin
        instance.delete
      rescue AWS::EC2::Errors::UnauthorizedOperation => e
        puts "you can't do that: #{e.message}"
      end
    end

    desc "rename", "rename an EC2 instance"
    method_option :id, :type => :string
    method_option :name, :type => :string, :default => "*"
    method_option :newname, :type => :string, :required => true
    def rename
      puts "task: ec2:instance:delete #{options[:id]} " +
        "#{options[:name]} => #{options[:newname]}" unless options[:quiet]
      handle = login
      instance = find_instance(handle, options)
      puts "renaming instance #{instance.id} (#{instance.tags['Name']}) to #{options[:newname]}"
      instance.tags['Name'] = options[:newname]
    end

    desc "start", "start an existing EC2 instance"
    method_option :id, :type => :string
    method_option :name, :type => :string
    method_option :wait, :type => :boolean, :default => false
    def start
      puts "task: ec2:instance:start #{options[:id]} " +
        "#{options[:name]}" unless options[:quiet]
      handle = login
      instance = find_instance(handle, options)
      instance.start

      if options[:wait] then
        puts "waiting to reach status 'running'" if options[:verbose]
        invoke :wait, [], :id => instance.id, :state => :running, :verbose => options[:verbose]
      end

    end

    desc "stop", "stop a running EC2 instance"
    method_option :id, :type => :string
    method_option :name, :type => :string
    method_option :wait, :type => :boolean, :default => false
    def stop
      puts "task: ec2:instance:stop #{options[:id]} " +
        "#{options[:name]}" unless options[:quiet]
      handle = login
      instance = find_instance(handle, options)
      puts "Stopping instance #{instance.id}" if options[:verbose]
      instance.stop

      if options[:wait] then
        puts "waiting to reach status 'stopped'" if options[:verbose]
        invoke :wait, [], :id => instance.id, :state => :stopped, :verbose => options[:verbose]
      end
    end

    desc "info", "get information about an existing instance"
    method_option :id, :type => :string
    method_option :name, :type => :string, :default => "*"
    def info
      # Open a connection to the AWS service
      handle = login
      instance = find_instance(handle, options)
      raise ArgumentError.new("no instance matches") if not instance
      if options[:verbose] then
        image = handle.images[instance.image_id]
        puts "EC2 Instance: #{instance.id} (#{instance.tags['Name']})"
        puts "  DNS Name: #{instance.dns_name}"
        puts "  Status: #{instance.status}"
        puts "  Image: #{instance.image_id}"
        puts "  Platform: #{image.platform}"
      else
        puts "#{instance.id} #{instance.tags['Name']}, #{instance.status} " + 
          ([:running, :pending].member?(instance.status) ? instance.dns_name : "")
      end
    end

    desc "tag", "set or retrieve information about a specified image"
    method_option(:id, :type => :string)
    method_option(:name, :type => :string)
    method_option(:tag, :type => :string, :required => true)
    method_option(:value, :type => :string)
    method_option(:clear, :type => :boolean, :default => false)
    def tag

      puts "ec2:instance:tag #{options[:id] || options[:name]} " +
        "#{options[:tag]} #{options[:value]}" unless options[:quiet]

      if not options[:id] || options[:name] then
        puts "No values provided for either --name or --id"
        return
      end

      handle = login
      instance = find_instance(login, options)

      if not instance
        puts "no matching instance"
        return
      end

      # set a value if it is given
      if options[:value] then
        instance.add_tag(options[:tag], { :value => options[:value] })
      elsif options[:clear] then
        instance.add_tag(options[:tag], { :value => nil })
      else
        value = instance.tags[options[:tag]]
        puts "#{options[:tag]}: #{value}"
        return value
      end
    end

    desc "hostname", "print the hostname of an identified instance"
    method_option :id, :type => :string
    method_option :name, :type => :string, :default => "*"
    def hostname
      # Open a connection to the AWS service
      handle = login
      instance = find_instance(handle, options)
      raise ArgumentError.new("no instance matches") if not instance
      puts instance.dns_name
    end
    
    desc "status", "get status of an existing instance"
    method_option :id, :type => :string
    method_option :name, :type => :string, :default => "*"
    def status
      # Open a connection to the AWS service
      handle = login
      instance = find_instance(handle, options)
      if options[:verbose] then
        puts "Status: #{instance.status}"
      else
        puts instance.status
      end
    end

    desc "wait", "wait until an instance reaches the desired status"
    method_option :id, :type => :string
    method_option :name, :type => :string, :default => "*"
    method_option :state, :type => :string
    method_option :pollrate, :type => :numeric, :default => 5
    method_option :maxtries, :type => :numeric, :default => 12
    def wait
      handle = login
      instance = find_instance(handle, options)
      
      target_status = options[:state].to_sym
      (1 .. options[:maxtries]).each do |try|
        return if instance.status === target_status
        puts "try #{try}: #{instance.status}" if options[:verbose]
        sleep options[:pollrate]
      end

      raise Exception.new("instance did not reach #{options[:state]}")
      
    end

    private
    no_tasks do

      # Create an EC2 connection
      def login(access_key_id=nil, secret_access_key=nil, credentials_file=nil, 
          region=nil)
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

      # Find a single instance given an ID or name
      def find_instance(connection, options)

        if options[:id] then
          instance = connection.instances[options[:id]]
          raise ArgumentError.new("id #{options[:id]}: no matches") if not instance
          return instance
        end

        instances = connection.instances.
          filter('tag-key', 'Name').
          filter('tag-value', options[:name])

        if instances.count === 0 then
          raise ArgumentError.new(
            "name #{options[:name]}: no matches")
        elsif
          instances.count > 1 then
          raise ArgumentError.new(
          "name #{options[:name]} matches #{instances.count} instances")
        end

        # get the first element of an iterator
        instances.to_a[0]
      end
    end
  end
end

if self.to_s === "main" then
  OpenShift::Instance.start()
end

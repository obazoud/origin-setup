#!/usr/bin/env ruby
#
# Set up an EC2 Origin service on AWS EC2
#
require 'rubygems'
require 'thor'
require 'openshift/aws'

module EC2

  class Snapshot < Thor

    namespace "ec2:snapshot"

    class_option :verbose, :type => :boolean, :default => false

    desc "list", "list the available snapshots"
    def list
      handle = AWS::EC2.new
      
      snapshots = handle.snapshots
      snapshots.with_owner(:self).each { |snapshot|
        puts "#{snapshot.id}: start #{snapshot.start_time} (#{snapshot.status}) #{snapshot.volume_id} (#{snapshot.volume_size}GB)"
      }

    end

    desc "delete SNAPSHOT", "delete the snapshot"
    def delete(snapshot_id)
      handle = AWS::EC2.new
      
      snapshots = handle.snapshots
      snapshots.with_owner(:self).select { |snapshot|
        snapshot.id == snapshot_id
      }.each {|snapshot|
        snapshot.delete
      }
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

#!/usr/bin/env ruby
#
# Set up an OpenShift Origin service on AWS EC2
#
require 'rubygems'
require 'parseconfig'
require 'aws'
require 'thor'

module Openshift

  class Volume < Thor

    namespace "ec2:volume"

    class_option :verbose, :type => :boolean, :default => false

    AWS_CREDENTIALS_FILE = ENV["AWS_CREDENTIALS_FILE"] || "~/.awscred"

    desc "list", "list the available snapshots"
    def list
      handle = login
      
      volumes = handle.volumes
      volumes.each { |volume|
        puts "#{volume.id}: start #{volume.create_time} (#{volume.status}) (#{volume.size}GB)"
      }

    end

    desc "delete VOLUME", "delete the volume"
    def delete(volume_id)
      handle = login
      
      volumes = handle.volumes
      volumes.with_owner(:self).select { |volume|
        volume.id == volume_id
      }.each {|volume|
        volume.delete
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

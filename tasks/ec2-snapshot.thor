#!/usr/bin/env ruby
#
# Set up an EC2 Origin service on AWS EC2
#
require 'rubygems'
require 'thor'
require 'aws'

module EC2

  class Snapshot < Thor

    namespace "ec2:snapshot"

    class_option :awscred
    class_option :verbose, :type => :boolean, :default => false

    desc "list", "list the available snapshots"
    def list
      OpenShift::AWS.init options[:awscred]
      handle = AWS::EC2.new
      
      snapshots = handle.snapshots
      snapshots.with_owner(:self).each { |snapshot|
        puts "#{snapshot.id}: start #{snapshot.start_time} (#{snapshot.status}) #{snapshot.volume_id} (#{snapshot.volume_size}GB)"
      }

    end

    desc "delete SNAPSHOT", "delete the snapshot"
    def delete(snapshot_id)
      OpenShift::AWS.init options[:awscred]
      handle = AWS::EC2.new
      
      snapshots = handle.snapshots
      snapshots.with_owner(:self).select { |snapshot|
        snapshot.id == snapshot_id
      }.each {|snapshot|
        snapshot.delete
      }
    end
  end
end

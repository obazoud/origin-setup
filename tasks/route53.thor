#!/usr/bin/env ruby
#
#
require 'rubygems'
require 'thor'
require 'aws'
require 'parseconfig'

  class Route53 < Thor

    class_option :awscred
    class_option :verbose, :type => :boolean, :default => false

    class Zone < Thor
     #namespace "route53:zone"

      class_option :awscred
      class_option :verbose, :type => :boolean, :default => false

      desc "list", "list hosted zones"
      def list

        puts "task: route53:zone:list" unless options[:quiet]
        OpenShift::AWS.init options[:awscred]
        handle = AWS::Route53::Client.new

        response = handle.list_hosted_zones
        zones = response[:hosted_zones]
        zones.each { |zone|
          puts "id: #{zone[:id].split('/')[2]} name: #{zone[:name]} records: #{zone[:resource_record_set_count]}"
        }
        zones.to_a
      end

      desc "id ZONE", "return the zone id of a name"
      def id(zonename)
        puts "task: route53:zone:id #{zonename}" unless options[:quiet]

        OpenShift::AWS.init options[:awscred]
        handle = AWS::Route53.Client.new

        id = Route53.zone_id(handle, zonename)
        puts "id = " + id
      end

      desc "contains HOSTNAME", "list the zones that could contain the hostname"
      method_option :all, :type => :boolean, :default => false
      def contains(hostname)
        puts "task: route53:zone:contains #{hostname}"

        hostname += "." if not hostname.end_with? '.'
        OpenShift::AWS.init options[:aswcred]
        handle = AWS::Route53::Client.new

        response = handle.list_hosted_zones
        allzones = response[:hosted_zones]

        zones = allzones.select {|zone|
          hostname.match "#{zone[:name]}$"
        }

        # sort in descending order (best match first)
        zones.sort! { |a, b| a[:name] <=> b[:name] }
        
        # only return the longest one
        unless (options[:all] or zones.count < 1) 
          zones = zones.slice(0,1)
        end

        zones.each { |zone|
          puts zone[:id].split('/')[2] + " " + zone[:name]
        }
        zones
      end

    end

    class Record < Thor

     #namespace "route53:record"
      
      types = ['A', 'NS', 'SOA', 'TXT', 'CNAME']

      class_option :awscred
      class_option :verbose, :type => :boolean, :default => false
      class_option :wait, :type => :boolean, :default => false

      desc("list ZONE [TYPE]",
        "create a new resource record")
      def list(zonename, type=nil)
        puts "task: route53:record:list #{zonename}"

        OpenShift::AWS.init options[:awscred]
        handle = AWS::Route53::Client.new

        zoneid = Route53.zone_id(handle, zonename)
        puts "looking for zone id #{zoneid}" unless options[:quiet]

        opts = {:hosted_zone_id => "/hostedzone/#{zoneid}"}

        response = handle.list_resource_record_sets(opts)

        response.data[:resource_record_sets].each { |rrset|
          name = rrset[:name]
          rrtype = rrset[:type]
          if type === nil or rrtype === type.upcase
            values = rrset[:resource_records]
            record_string = "#{rrset[:name]} #{rrtype} #{rrset[:ttl]}"

            values.each { |rvalue|
              record_string += " #{rvalue[:value]}"
            }
            puts record_string

          end
        }
        
      end

      desc("get ZONE NAME [TYPE]",
        "get a resource record")
      def get(zonename, recordname, type=nil)
        puts "task: route53:record:get #{zonename} #{recordname} #{type}"

        OpenShift::AWS.init options[:awscred]
        handle = AWS::Route53::Client.new

        zoneid = Route53.zone_id(handle, zonename)
        opts = {:hosted_zone_id => "/hostedzone/#{zoneid}"}

        fqdn = recordname + "." + zonename
        fqdn += "." unless fqdn.end_with? "."
        
        record_sets = handle.list_resource_record_sets(opts)[:resource_record_sets]

        record_sets.select! { |record| record[:name] == fqdn }
        record_sets.each {|record|
          puts "#{record[:name]} #{record[:type]} #{record[:ttl]} #{record[:resource_records].map {|v| v[:value]}.join(' ')}"
        }
        record_sets
      end
      

      desc("create ZONE NAME TYPE VALUE",
        "create a new resource record")
      method_option :ttl, :type => :numeric, :default => 300
      def create(zone, name, type, value)
        puts "task: route53:record:create #{zone} #{name} #{type} #{value}"

        fqdn = "#{name}.#{zone}"

        OpenShift::AWS.init options[:awscred]
        handle = AWS::Route53::Client.new
        zoneid = Route53.zone_id(handle, zone)

        update = {
          :comment => "add #{type} record #{fqdn}",
          :changes => [change_record("CREATE", fqdn, type, options[:ttl], value)]
        }

        puts "update record = #{update}" if options[:verbose]

        response = handle.change_resource_record_sets(
          {
            :hosted_zone_id => "/hostedzone/" + zoneid,
            :change_batch => update
          }
          )

        # TODO:check for success/fail

        # result.data[:change_info] contains the change request id and status
        puts "response = #{response.data}" if options[:verbose]

        if options[:wait] and 
            not response.data[:change_info][:status] == "INSYNC"
          change_id = response.data[:change_info][:id]
          # poll for INSYNC
          wait_for_sync(handle, change_id, 12, 5, options[:verbose])
        end

      end

      desc("delete ZONE NAME [TYPE [VALUE]]",
        "delete a resource record")
      method_option :ttl, :type => :numeric, :default => 300
      def delete(zone, name, type=nil, value=nil)
        puts "task: route53:record:delete #{zone} #{type} #{name}"

        fqdn = "#{name}.#{zone}"

        OpenShift::AWS.init options[:awscred]
        handle = AWS::Route53::Client.new
        zoneid = Route53.zone_id(handle, zone)

        update = {
          :comment => "delete #{type} record #{fqdn}",
          :changes => [change_record("DELETE", fqdn, type, options[:ttl], value)]
        }

        puts "update record = #{update}" if options[:verbose]

        response = handle.change_resource_record_sets(
          {
            :hosted_zone_id => "/hostedzone/" + zoneid,
            :change_batch => update
          }
          )

        # TODO:check for success/fail

        # result.data[:change_info] contains the change request id and status
        puts "response = #{response.data}" if options[:verbose]

        if options[:wait] and 
            not response.data[:change_info][:status] == "INSYNC"
          change_id = response.data[:change_info][:id]
          # poll for INSYNC
          wait_for_sync(handle, change_id, 12, 5, options[:verbose])
        end

      end

      desc "exist HOSTNAME", "check if a record exists for a given name"
      def exist(zonename, hostpart)
        puts "task: route53:record:exist #{zonename} #{hostpart}" unless options[:quiet]

        OpenShift::AWS.init options[:awscred]
        handle = AWS::Route53::Client.new

        zoneid = Route53.zone_id(handle, zonename)
        opts = {:hosted_zone_id => "/hostedzone/#{zoneid}"}

        fqdn = hostpart + "." + zonename
        fqdn += "." unless fqdn.end_with? "."
        
        record_sets = handle.list_resource_record_sets(opts)[:resource_record_sets]
        record_sets.select! { |record| record[:name] == fqdn }
        
        puts record_sets if options[:verbose]
        return record_sets.count > 0
      end

      no_tasks do
        def change_record(action, fqdn, type, ttl, value)

          # validate action: ['CREATE', 'DELETE']
          # validate type 

          {
            :action => action,
            :resource_record_set => {
              :name => fqdn,
              :type => type,
              :ttl => ttl,
              :resource_records => [{:value => value}]
            }
          }
        end

        def wait_for_sync(handle, change_id, maxtries=12, pollinterval=5,
            verbose=false)
          # poll for INSYNC
          change_status = "UNKNOWN"
          (1..maxtries).each { |trynum|
            puts "#{trynum}) change id: #{change_id}, status: #{change_status} - sleeping #{pollinterval}" if verbose
            sleep pollinterval
            response = handle.get_change(:id => change_id)
            change_status = response.data[:change_info][:status]
            break if change_status == "INSYNC"
          }
          if not change_status == "INSYNC"
            raise Exception.new("timed out polling for change complete")
          end
        end
      end

    end

    no_tasks do
      # Create a Route53 connection
      def self.login(access_key_id=nil, secret_access_key=nil,
          credentials_file=nil, region=nil)
        # explicit credentials take precedence over a file
        if not (access_key_id and secret_access_key) then
          credentials_file ||= AWS_CONFIG_FILE
          config = ParseConfig.new File.expand_path(credentials_file)
          access_key_id = config.params['AWSAccessKeyId']
          secret_key = config.params['AWSSecretKey']

          # check them
        end

        connection = AWS::Route53.new(
          :access_key_id => access_key_id,
          :secret_access_key => secret_key
          ).client
      end

      def self.zone_id(handle, zonename)
        # allow non-canonical zone names
        zonename += "." if not zonename.end_with? "."
        response = handle.list_hosted_zones
        zones = response[:hosted_zones]
        zones.select! { |zone|
          zone[:name] == zonename
        }
        zones[0][:id].split('/')[2]
      end 
    end
  end

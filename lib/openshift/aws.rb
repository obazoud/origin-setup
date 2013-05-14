#
# Load configuration information for AWS communications
#

require 'rubygems'
require 'aws'
require 'parseconfig'


# OpenShift Origin related methods
module OpenShift
  
  # Amazon Web Services access
  module AWS

    CONFIG_FILE = ENV['AWS_CONFIG_FILE'] || File.expand_path("~/.awsconfig")

    @@configfile = CONFIG_FILE
    @@config = nil

    # Load the AWS Credentials and configuration information
    # @param [String] configfile
    #   the location of a file to load instead of the default
    def self.config(configfile=nil)      
      if configfile
        @@configfile = File.expand_path(configfile)
        @@config = ParseConfig.new @@configfile
      end
      @@config = ParseConfig.new CONFIG_FILE if not @@config
      @@config
    end

    def self.awscred(access_key_id=nil, secret_access_key=nil, region=nil)
      ::AWS.config(
        :access_key_id => access_key_id || OpenShift::AWS.config.params['AWSAccessKeyId'],
       :secret_access_key => secret_access_key || OpenShift::AWS.config.params['AWSSecretKey'],
        :region => region || OpenShift::AWS.config.params['AWSRegion']
        )
    end

    # EC2 login
    module EC2

      # Create an EC2 connection
      def self.login(access_key_id=nil, secret_access_key=nil, config_file=nil, 
          region=nil)

        ::AWS::EC2.new(
          :access_key_id => access_key_id,
          :secret_access_key => secret_access_key)
      end

    end

    module Route53

      # Create a Route53 connection
      def self.login(access_key_id=nil, secret_access_key=nil, config_file=nil, 
          region=nil)

        ::AWS::Route53.new(
          :access_key_id => access_key_id,
          :secret_access_key => secret_access_key)

      end

    end

  end
end

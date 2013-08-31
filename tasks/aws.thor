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

    CONFIG_FILE = ENV['AWS_CONFIG_FILE'] || File.expand_path(".awscred")

    @@configfile = CONFIG_FILE
    @@config = nil

    # Load the AWS Credentials and configuration information
    # @param [String] configfile
    #   the location of a file to load instead of the default
    def self.config(configfile=nil, reload=false)

      return @@config if @@config and not reload

      @@configfile = (configfile ? File.expand_path(configfile) : CONFIG_FILE)
      raise Exception.new("File not found: #{@@configfile}") if not File.exists? @@configfile
      @@config = ParseConfig.new @@configfile
      @@config
    end

    def self.awscred(access_key_id=nil, secret_access_key=nil, region=nil)
      # don't read the config if all params are provided
      if not (access_key_id && secret_access_key && region)
          config = OpenShift::AWS.config
      end
        
      ::AWS.config(
        :access_key_id => access_key_id || config.params['AWSAccessKeyId'],
        :secret_access_key => secret_access_key || config.params['AWSSecretKey'],
        :region => region || config.params['AWSRegion']
        )
    end

    def self.init(awscred='./awscred')
      OpenShift::AWS::config awscred
      OpenShift::AWS::awscred
    end

  end
end

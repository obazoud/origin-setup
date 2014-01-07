#
#  initialize the aws-sdk communications
#

# Anchor this to the root. - There must be a better way to make this available
# to all tasks.
module ::AWS

  # Methods to initialize AWS CLI operations: 
  module CLI

    # The default location of the AWS credentials file
    @@default_awscred_filename = ENV['HOME'] + "/.awscred"

    # Initialize the AWS configuration if environment variables are not set.
    # Priority:
    #  specified awscred config
    #  AWS_* environment variables
    #  $HOME/.awscred config
    #  ./.awscred config
    def self.init(awscred_filename=nil)
      if awscred_filename and File.exists? awscred_filename
        awscred = ParseConfig.new(awscred_filename)
        ::AWS.config(:access_key_id => awscred['AWSAccessKeyId'],
                     :secret_access_key => awscred['AWSSecretAccessKey']
                     )
      elsif ENV['AWS_ACCESS_KEY_ID'] and ENV['AWS_SECRET_ACCESS_KEY']
        # Running config will initialize with the environment variables
        ::AWS.config
        
      else
        local_filename = File.expand_path('.awscred')
        global_filename = ENV['HOME'] + '/.awscred'
        if File.exist?(local_filename)
          real_filename = local_filename
        elsif File.exist?(global_filename)
          real_filename = global_filename
        end
        if defined? real_filename
          awscred = ParseConfig.new(real_filename)
          ::AWS.config(:access_key_id => awscred['AWSAccessKeyId'],
                       :secret_access_key => awscred['AWSSecretAccessKey']
                       )
        else
          raise Exception.new("unable to find AWS credentials")
        end
      end
    end
  end
end

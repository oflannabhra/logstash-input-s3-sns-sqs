require 'thread'

module LogStash module Inputs class S3SNSSQS < LogStash::Inputs::Base
  class S3ClientFactory

    def initialize(options)
      @sts_client = Aws::STS::Client.new(region: options[:aws_region])
      # FIXME: options are non-generic (...by_bucket mixes credentials with folder stuff)
      @options_by_bucket = options[:s3_options_by_bucket]
      # lazy-init this as well:
      # @credentials_by_bucket = @options_by_bucket.map { |bucket, options|
      #   [bucket.to_sym, assume_s3_role(options['credentials'])]
      # }.to_h
      @default_session_name = options[:s3_role_session_name]
      @clients_by_bucket = {}
      @mutexes_by_bucket = {}
    end

    def get_s3client(bucket_name)
      bucket_symbol = bucket_name.to_sym
      if @clients_by_bucket[bucket_symbol].nil?
        options = aws_options_hash
        if @options_by_bucket[bucket_name] and @options_by_bucket[bucket_name]['credentials']
          options.merge!(credentials: assume_s3_role(@options_by_bucket[bucket_name]['credentials']))
        end
        @clients_by_bucket[bucket_symbol] = Aws::S3::Client.new(options)
        @mutexes_by_bucket[bucket_symbol] = Mutex.new
      end
      # to be thread-safe, one uses this method like this:
      # s3_client_factory.get_s3client(my_s3_bucket) do
      #   ... do stuff ...
      # end
      @mutexes_by_bucket[bucket_symbol].synchronize do
        yield @clients_by_bucket[bucket_name]
      end
    end

    private

    def assume_s3_role(credentials)
      # reminder: these are auto-refreshing!
      return Aws::AssumeRoleCredentials.new(
          client: @sts_client,
          role_arn: credentials['role'],
          role_session_name: @s3_role_session_name
      ) if credentials['role']
    end
  end
end

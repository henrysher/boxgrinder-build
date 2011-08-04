require 'boxgrinder-build/helpers/aws-helper'

module BoxGrinder
  class S3Helper < AWSHelper

    #AWS::S3 object should be instantiated already, as config can be inserted
    #via global AWS.config or via AWS::S3.initialize
    def initialize(ec2, s3, options={})
      raise ArgumentError, "ec2 argument must not be nil" if ec2.nil?
      raise ArgumentError, "s3 argument must not be nil" if s3.nil?
      @ec2 = ec2
      @s3 = s3
      @log = options[:log] || LogHelper.new
    end

    def bucket(options={})
      defaults = {:bucket => nil, :acl => :private, :location_constraint => 'us-east-1', :create_if_missing => false}.merge!(options)
      options = parse_opts(options, defaults)

      s3b = @s3.buckets[options[:bucket]]
      return s3b if s3b.exists?
      return @s3.buckets.create(options[:bucket],
                         :acl => options[:acl],
                         :location_constraint => options[:location_constraint]) if options[:create_if_missing]
      nil
    end

    #There is no 'key_exists?' type method.. so this is a work-around.
    #If the object does not exist, and you attempt to read the etag it returns a NoMethodError
    #but it *should* return a NoSuchKey exception (bug). This seems better than listing all keys and searching..
    def object_exists?(s3_object)
      @log.trace "Checking if '#{s3_object.key}' exists"
      begin
        if s3_object.etag
          @log.trace "Object exists! #{s3_object.etag}"
          return true
        end
      rescue AWS::S3::Errors::NoSuchKey, NoMethodError
        @log.trace "Object does not exist"
        return false
      end
    end

    def delete_folder(bucket, path)
      bucket.objects.with_prefix(deslash(path)).map(&:delete)
    end

    def stub_s3obj(bucket, path)
      bucket.objects[path]
    end

    def parse_path(path)
      return '' if path == '/'
      #Remove preceding and trailing slashes
      deslash(path) << '/'
    end

    def self.endpoints
      ENDPOINTS
    end

    private

    #Remove extraneous slashes on paths to ensure they are valid for S3
    def deslash(path)
      "#{path.gsub(/^(\/)*/, '').gsub(/(\/)*$/, '')}"
    end

    ENDPOINTS = {
      'eu-west-1' => {
        :endpoint => 's3-eu-west-1.amazonaws.com',
        :location => 'EU',
        :kernel => {
          :i386 => {:aki => 'aki-4deec439'},
          :x86_64 => {:aki => 'aki-4feec43b'}
        }
      },

      'ap-southeast-1' => {
        :endpoint => 's3-ap-southeast-1.amazonaws.com',
        :location => 'ap-southeast-1',
        :kernel => {
          :i386 => {:aki => 'aki-13d5aa41'},
          :x86_64 => {:aki => 'aki-11d5aa43'}
        }
      },

      'ap-northeast-1' => {
        :endpoint => 's3-ap-northeast-1.amazonaws.com',
        :location => 'ap-northeast-1',
        :kernel => {
          :i386 => {:aki => 'aki-d209a2d3'},
          :x86_64 => {:aki => 'aki-d409a2d5'}
        }
      },

      'us-west-1' => {
        :endpoint => 's3-us-west-1.amazonaws.com',
        :location => 'us-west-1',
        :kernel => {
          :i386 => {:aki => 'aki-99a0f1dc'},
          :x86_64 => {:aki => 'aki-9ba0f1de'}
        }
      },

      'us-east-1' => {
        :endpoint => 's3.amazonaws.com',
        :location => '',
        :kernel => {
          :i386 => {:aki => 'aki-407d9529'},
          :x86_64 => {:aki => 'aki-427d952b'}
        }
      }
    }

  end
end
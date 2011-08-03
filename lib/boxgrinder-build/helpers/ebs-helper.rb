require 'aws-sdk'
require 'boxgrinder-build/helpers/aws-helper'

module BoxGrinder
  class EBSHelper < AWSHelper

    def initialize(ec2, options={})
      raise ArgumentError, "ec2 argument must not be nil" if ec2.nil?
      @ec2 = ec2
      @log = options[:log] || LogHelper.new
    end

    def self.endpoints
      SERVICES
    end

    SERVICES = {
          'eu-west-1' => {
            :endpoint => 'ec2.eu-west-1.amazonaws.com',
            :location => 'EU',
            :kernel => {
              :i386 => {:aki => 'aki-4deec439'},
              :x86_64 => {:aki => 'aki-4feec43b'}
            }
          },

          'ap-southeast-1' => {
            :endpoint => 'ec2.ap-southeast-1.amazonaws.com',
            :location => 'ap-southeast-1',
            :kernel => {
              :i386 => {:aki => 'aki-13d5aa41'},
              :x86_64 => {:aki => 'aki-11d5aa43'}
            }
          },

          'ap-northeast-1' => {
            :endpoint => 'ec2.ap-northeast-1.amazonaws.com',
            :location => 'ap-northeast-1',
            :kernel => {
              :i386 => {:aki => 'aki-d209a2d3'},
              :x86_64 => {:aki => 'aki-d409a2d5'}
            }
          },

          'us-west-1' => {
            :endpoint => 'ec2.us-west-1.amazonaws.com',
            :location => 'us-west-1',
            :kernel => {
              :i386 => {:aki => 'aki-99a0f1dc'},
              :x86_64 => {:aki => 'aki-9ba0f1de'}
            }
          },

          'us-east-1' => {
            :endpoint => 'ec2.amazonaws.com',
            :location => '',
            :kernel => {
              :i386 => {:aki => 'aki-407d9529'},
              :x86_64 => {:aki => 'aki-427d952b'}
            }
          }
        }
  end
end
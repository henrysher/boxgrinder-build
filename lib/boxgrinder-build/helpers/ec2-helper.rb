require 'aws-sdk'
require 'boxgrinder-build/helpers/aws-helper'
require 'timeout'
require 'pp'

module BoxGrinder
  class EC2Helper < AWSHelper
    
    DEF_POLL_FREQ = 1
    DEF_TIMEOUT = 1000
    HTTP_TIMEOUT = 10

    def initialize(ec2, opts={})
      raise ArgumentError, "ec2 argument must not be nil" if ec2.nil?
      @ec2 = ec2
      @log = opts[:log] || LogHelper.new
    end

    def wait_for_image_state(state, ami, opts={})
      #First wait for the AMI to be confirmed to exist (after creating, an immediate query can cause an error)
      opts = parse_opts(opts, {:frequency => DEF_POLL_FREQ, :timeout => DEF_TIMEOUT})
      wait_with_timeout(opts[:frequency], opts[:timeout]){ ami.exists? }
      wait_with_timeout(opts[:frequency], opts[:timeout]){ ami.state == state }
    end

    def wait_for_image_death(ami, opts={})
      opts = parse_opts(opts, {:frequency => DEF_POLL_FREQ, :timeout => DEF_TIMEOUT})
      wait_with_timeout(opts[:frequency], opts[:timeout]){ !ami.exists? }
    end

    def wait_for_instance_status(status, instance, opts={})
      opts = parse_opts(opts, {:frequency => DEF_POLL_FREQ, :timeout => DEF_TIMEOUT})
      wait_with_timeout(opts[:frequency], opts[:timeout]){ instance.status == status }
    end

    #Being serial shouldn't be much slower as we are blocked by the slowest stopper anyway
    def wait_for_instance_death(instance, opts={})
      wait_for_instance_status(:terminated, instance, opts) if instance.exists?
    rescue AWS::EC2::Errors::InvalidInstanceID::NotFound
    end

    def wait_for_snapshot_status(status, snapshot, opts={})
      opts = parse_opts(opts, {:frequency => DEF_POLL_FREQ, :timeout => DEF_TIMEOUT})
      progress = -1
      wait_with_timeout(opts[:frequency], opts[:timeout]) do
        current_progress = snapshot.progress || 0
          unless progress == current_progress
            @log.info "Progress: #{current_progress}%"
            progress = current_progress
          end
        snapshot.status == status
      end
    rescue Exception
      @log.debug "Polling of snapshot #{snapshot.id} for status '#{status}' failed" unless snapshot.nil?
      raise
    end

    def wait_for_volume_status(status, volume, opts={})
      opts = parse_opts(opts, {:frequency => DEF_POLL_FREQ, :timeout => DEF_TIMEOUT})
      wait_with_timeout(opts[:frequency], opts[:timeout]) do
        volume.status == status
      end
    rescue Exception
      @log.debug "Polling of volume #{volume.id} for status '#{status}' failed: #{PP::pp(volume)}" unless volume.nil?
      raise
    end

    def self.get_meta_data(path)
      timeout(HTTP_TIMEOUT) do
        req = Net::HTTP::Get.new(path)
        res = Net::HTTP.start('169.254.169.254', 80) {|http| http.request(req)}
        return res.body if  Net::HTTPSuccess
        res.error!
      end
    end

    def self.current_availability_zone
      get_meta_data('/latest/meta-data/placement/availability-zone/')
    end

    def self.current_instance_id
      get_meta_data('/latest/meta-data/instance-id')
    end

    def self.availability_zone_to_region(availability_zone)
      availability_zone.scan(/((\w+)-(\w+)-(\d+))/).flatten.first
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
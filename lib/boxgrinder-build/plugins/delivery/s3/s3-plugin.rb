#
# Copyright 2010 Red Hat, Inc.
#
# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as
# published by the Free Software Foundation; either version 3 of
# the License, or (at your option) any later version.
#
# This software is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this software; if not, write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
# 02110-1301 USA, or see the FSF site: http://www.fsf.org.

require 'rubygems'
require 'aws-sdk'
require 'boxgrinder-build/plugins/base-plugin'
require 'boxgrinder-build/helpers/package-helper'

module BoxGrinder
  class S3Plugin < BasePlugin
    REGION_OPTIONS = {
        'eu-west-1' => {
            :endpoint => 's3-eu-west-1.amazonaws.com',
            :location => 'EU',
            :kernel => {
                'i386' => {:aki => 'aki-4deec439'},
                'x86_64' => {:aki => 'aki-4feec43b'}
            }
        },

        'ap-southeast-1' => {
            :endpoint => 's3-ap-southeast-1.amazonaws.com',
            :location => 'ap-southeast-1',
            :kernel => {
                'i386' => {:aki => 'aki-13d5aa41'},
                'x86_64' => {:aki => 'aki-11d5aa43'}
            }
        },

        'ap-northeast-1' => {
            :endpoint => 's3-ap-northeast-1.amazonaws.com',
            :location => 'ap-northeast-1',
            :kernel => {
                'i386' => {:aki => 'aki-d209a2d3'},
                'x86_64' => {:aki => 'aki-d409a2d5'}
            }

        },

        'us-west-1' => {
            :endpoint => 's3-us-west-1.amazonaws.com',
            :location => 'us-west-1',
            :kernel => {
                'i386' => {:aki => 'aki-99a0f1dc'},
                'x86_64' => {:aki => 'aki-9ba0f1de'}
            }
        },

        'us-east-1' => {
            :endpoint => 's3.amazonaws.com',
            :location => '',
            :kernel => {
                'i386' => {:aki => 'aki-407d9529'},
                'x86_64' => {:aki => 'aki-427d952b'}
            }
        }
    }

    def after_init
      register_supported_os("fedora", ['13', '14', '15'])
      register_supported_os("centos", ['5'])
      register_supported_os("rhel", ['5', '6'])
      register_supported_os("sl", ['5', '6'])

      @ami_build_dir = "#{@dir.base}/ami"
      @ami_manifest = "#{@ami_build_dir}/#{@appliance_config.name}.ec2.manifest.xml"
    end

    def validate
      set_default_config_value('overwrite', false)
      set_default_config_value('path', '/')
      set_default_config_value('region', 'us-east-1')
      validate_plugin_config(['bucket', 'access_key', 'secret_access_key'], 'http://boxgrinder.org/tutorials/boxgrinder-build-plugins/#S3_Delivery_Plugin')

      subtype(:ami) do
        set_default_config_value('snapshot', false)
        validate_plugin_config(['cert_file', 'key_file', 'account_number'], 'http://boxgrinder.org/tutorials/boxgrinder-build-plugins/#S3_Delivery_Plugin')
      end

      raise PluginValidationError, "Invalid region specified: #{@plugin_config['region']}. This plugin only aware of the following regions: #{REGION_OPTIONS.keys.join(", ")}" unless REGION_OPTIONS.has_key?(@plugin_config['region'])
    end

    def execute
        # Set global AWS configuration
        AWS.config(:access_key_id => @plugin_config['access_key'],
            :secret_access_key => @plugin_config['secret_access_key'],
            :ec2_endpoint => "ec2.#{@plugin_config['region']}.amazonaws.com",
            :s3_endpoint => REGION_OPTIONS[@plugin_config['region']][:endpoint],
            :max_retries => 5,
            :use_ssl => @plugin_config['use_ssl'])
            #:logger => @log)   need to  modify our logger to accept blah.log(:level, 'message')

      case @type
        when :s3
          upload_to_bucket(@previous_deliverables)
        when :cloudfront
          upload_to_bucket(@previous_deliverables, 'public-read')
        when :ami
          @plugin_config['account_number'] = @plugin_config['account_number'].to_s.gsub(/-/, '')

          @ec2 = AWS::EC2.new

          ami_dir = ami_key(@appliance_config.name, @plugin_config['path'])
          ami_manifest_key = s3_stub_obj "#{ami_dir}/#{@appliance_config.name}.ec2.manifest.xml"

          @log.debug "Going to check whether s3 object exists"

          if s3_object_exists?(ami_manifest_key) and @plugin_config['overwrite']
            @log.info "Object exists, attempting to deregister an existing image"
            deregister_image(ami_manifest_key) # Remove existing image
            delete_folder(bucket(),ami_dir) # Avoid triggering dupe detection
          end

          if !s3_object_exists?(ami_manifest_key) or @plugin_config['snapshot']
            @log.info "Doing bundle/snapshot"
            bundle_image(@previous_deliverables)
            fix_sha1_sum
            upload_image(ami_dir)
          end
          register_image(ami_manifest_key)
      end
    end

    def delete_folder(bucket,ami_dir)
      bucket.objects.with_prefix(ami_dir.sub(/\/$/,'')).map(&:delete)
    end

    # https://jira.jboss.org/browse/BGBUILD-34
    def fix_sha1_sum
      ami_manifest = File.open(@ami_manifest).read
      ami_manifest.gsub!('(stdin)= ', '')

      File.open(@ami_manifest, "w") { |f| f.write(ami_manifest) }
    end

    #There is no 'key_exists?' type method.. so this is a work-around.
    #If the object does not exist, and you attempt to read the etag it returns a NoMethodError
    #but it *should* return a NoSuchKey exception (bug). This seems better than listing all keys and searching..
    def s3_object_exists?(s3_object)
      @log.trace "Checking if '#{s3_object.key}' path exists in #{@plugin_config['bucket']}..."
      begin
        if s3_object.etag
          @log.trace "Path exists! #{s3_object.etag}"
          return true
        end
      rescue AWS::S3::Errors::NoSuchKey, NoMethodError
        @log.trace "Path does not exist"
        return false
      end
    end

    def upload_to_bucket(previous_deliverables, permissions = :private)
      register_deliverable(
          :package => "#{@appliance_config.name}-#{@appliance_config.version}.#{@appliance_config.release}-#{@appliance_config.os.name}-#{@appliance_config.os.version}-#{@appliance_config.hardware.arch}-#{current_platform}.tgz"
      )

      # quick and dirty workaround to use @deliverables[:package] later in code
      FileUtils.mv(@target_deliverables[:package], @deliverables[:package]) if File.exists?(@target_deliverables[:package])

      PackageHelper.new(@config, @appliance_config, :log => @log, :exec_helper => @exec_helper).package(File.dirname(previous_deliverables[:disk]), @deliverables[:package])

      remote_path = "#{s3_path(@plugin_config['path'])}#{File.basename(@deliverables[:package])}"
      size_m = File.size(@deliverables[:package])/1024**2
      s3_obj = s3_stub_obj(remote_path.gsub(/^\//, '').gsub(/\/\//, ''))
      # Does it really exist?
      obj_exists = s3_object_exists?(s3_obj)

      if !obj_exists or @plugin_config['overwrite']
        @log.info "Will overwrite existing file #{remote_path}" if obj_exists and @plugin_config['overwrite']
        @log.info "Uploading #{File.basename(@deliverables[:package])} (#{size_m}MB) to '#{@plugin_config['bucket']}#{remote_path}' path..."
        s3_obj.write(:file => @deliverables[:package],
                        :acl => permissions)
        @log.info "Appliance #{@appliance_config.name} uploaded to S3."
      else
        @log.info "File '#{@plugin_config['bucket']}#{remote_path}' already uploaded, skipping."
      end
    end

    def bucket(create_if_missing = true, permissions = :private)
      @s3 ||= AWS::S3.new
      s3b = @s3.buckets[@plugin_config['bucket']]
      return s3b if s3b.exists?

      return @s3.buckets.create(@plugin_config['bucket'],
                         :acl => permissions,
                         :location_constraint => REGION_OPTIONS[@plugin_config['region']][:location]) if create_if_missing
      nil
    end

    def bundle_image(deliverables)
      if @plugin_config['snapshot']
        @log.debug "Removing bundled image from local disk..."
        FileUtils.rm_rf(@ami_build_dir)
      end

      return if File.exists?(@ami_build_dir)

      @log.info "Bundling AMI..."

      FileUtils.mkdir_p(@ami_build_dir)

      @exec_helper.execute("euca-bundle-image --ec2cert #{File.dirname(__FILE__)}/src/cert-ec2.pem -i #{deliverables[:disk]} --kernel #{REGION_OPTIONS[@plugin_config['region']][:kernel][@appliance_config.hardware.base_arch][:aki]} -c #{@plugin_config['cert_file']} -k #{@plugin_config['key_file']} -u #{@plugin_config['account_number']} -r #{@appliance_config.hardware.base_arch} -d #{@ami_build_dir}", :redacted => [@plugin_config['account_number'], @plugin_config['key_file'], @plugin_config['cert_file']])

      @log.info "Bundling AMI finished."
    end

    def upload_image(ami_dir)
      bucket # this will create the bucket if needed
      @log.info "Uploading #{@appliance_config.name} AMI to bucket '#{@plugin_config['bucket']}'..."

      @exec_helper.execute("euca-upload-bundle -U #{@plugin_config['url'].nil? ? "http://#{REGION_OPTIONS[@plugin_config['region']][:endpoint]}" : @plugin_config['url']} -b #{@plugin_config['bucket']}/#{ami_dir} -m #{@ami_manifest} -a #{@plugin_config['access_key']} -s #{@plugin_config['secret_access_key']}", :redacted => [@plugin_config['access_key'], @plugin_config['secret_access_key']])
    end

    def register_image(ami_manifest_key)
      ami = ami_info(ami_manifest_key)

      if ami
        @log.info "Image for #{@appliance_config.name} is already registered under id: #{ami.id} (region: #{@plugin_config['region']})."
      else
        ami = @ec2.images.create(:image_location =>  "#{@plugin_config['bucket']}/#{ami_manifest_key.key}")
        @log.info "Image for #{@appliance_config.name} successfully registered under id: #{ami.id} (region: #{@plugin_config['region']})."
      end
    end

    def deregister_image(ami_manifest_key)
      info = ami_info(ami_manifest_key)
      if info
        @log.info "Preexisting image '#{info.location}' for #{@appliance_config.name} will be de-registered, it had id: #{info.id} (region: #{@plugin_config['region']})."
        info.deregister
      else # This occurs when the AMI is de-registered externally but the file structure is left intact in S3. In this instance, we simply overwrite and register the image as if it were "new".
        @log.info "Possible dangling/unregistered AMI skeleton structure in S3, there is nothing to deregister"
      end
    end

    def ami_info(ami_manifest_key)
      AWS.memoize do #http://docs.amazonwebservices.com/AWSRubySDK/latest/AWS.html#memoize-class_method
        ami = @ec2.images.with_owner(@plugin_config['account_number']).
            filter("manifest-location","#{@plugin_config['bucket']}/#{ami_manifest_key.key}")
        return nil unless ami
        ami.first
      end
    end

    def s3_path(path)
      return '' if path == '/'

      "#{path.gsub(/^(\/)*/, '').gsub(/(\/)*$/, '')}/"
    end

    def s3_stub_obj(path)
        bucket().objects[path]
    end

    def ami_key(appliance_name, path)
      base_path = "#{s3_path(path)}#{appliance_name}/#{@appliance_config.os.name}/#{@appliance_config.os.version}/#{@appliance_config.version}.#{@appliance_config.release}"

      return "#{base_path}/#{@appliance_config.hardware.arch}" unless @plugin_config['snapshot']

      @log.info "Determining snapshot name"

      snapshot = 1

      while s3_object_exists?(s3_stub_obj "#{base_path}-SNAPSHOT-#{snapshot}/#{@appliance_config.hardware.arch}/")
        snapshot += 1
      end

      # Reuse the last key (if there was one)
      snapshot -=1 if snapshot > 1 and @plugin_config['overwrite']

      "#{base_path}-SNAPSHOT-#{snapshot}/#{@appliance_config.hardware.arch}"
    end

  end
end

plugin :class => BoxGrinder::S3Plugin, :type => :delivery, :name => :s3, :full_name => "Amazon Simple Storage Service (Amazon S3)", :types => [:s3, :cloudfront, :ami]

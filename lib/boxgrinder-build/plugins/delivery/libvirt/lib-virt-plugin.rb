require 'boxgrinder-build/plugins/base-plugin'

require 'libvirt'
require 'net/sftp'
require 'fileutils'

module BoxGrinder
  class LibVirtPlugin < BasePlugin


    def after_init
      set_default_config_value('script', false)
      set_default_config_value('image_path', '/var/lib/libvirt/images/')
      set_default_config_value('graphics', 'none')
      set_default_config_value('noautoconsole', true)
      set_default_config_value('network', false)
      set_default_config_value('remote_no_verify', true)
      set_default_config_value('bus','virtio')

      set_default_config_value('overwrite', false)
      set_default_config_value('default_permissions', 0644)
    end

    def validate
      @script = @plugin_config['script']
      @image_path = @plugin_config['image_path']
      @no_auto_console = @plugin_config['noautoconsole']
      @graphics = @plugin_config['graphics']
      @network = @plugin_config['network']

      @remote_no_verify = @plugin_config['remote_no_verify'] ? 1 : 0

      @libvirt_uri = @plugin_config['libvirt_uri'] << "?no_verify=#{@remote_no_verify}"
      @bus = @plugin_config['device_bus']
    end

    def execute
      remote_hypervisor = !(Regexp.new('^.*:///').match(@image_path)) || Regexp.new('^remote')

      if remote_hypervisor
        upload_image
      else
        @log.info("Attempting to move disk to #{@image_path}")
        FileUtils.mv(@previous_deliverables.disk, @image_path)
      end

      xml = get_xml

      begin
        conn = Libvirt::open(@libvirt_uri)
        conn.define_domain_xml(xml)
      ensure
        conn.close unless conn.closed?
      end

    end

    # Remote only
    def upload_image
      uploader = SFTPPlugin.new
      uploader.connect
      uploader.upload_files(@image_path, @plugin_config['default_permissions'],
                            File.basename(@previous_deliverables.disk) => @previous_deliverables.disk)
    ensure
      uploader.disconnect if uploader.connected?
    end

    def get_xml
      cmd_string = "virt-install --disk #{@image_path}/#{File.basename(@previous_deliverables.disk)},device=disk,bus=#{@bus} " <<
                            "--name #{@appliance_config.name}-#{@appliance_config.version}.#{@appliance_config.release}-#{@appliance_config.os.name}-#{@appliance_config.os.version}-#{@appliance_config.hardware.arch}-#{current_platform} " <<
                            "--summary #{@appliance_config.summary} " <<
                            "--os-type linux " <<
                            "--os-variant #{@appliance_config.os.name}#{@appliance_config.os.version} " <<
                            "--ram #{@appliance_config.hardware.memory} " <<
                            "--vcpus #{@appliance_config.hardware.cpus} " <<
                            "--graphics #{@graphics}" <<
                            "--hvm " <<
                            "--print-xml "

      cmd_string << "--network #{@network} " if @network #otherwise leave defaults
      cmd_string << "--noautoconsole " if @no_auto_console
            
      # At present we can use virt-install to generate the xml. Unfortunately if we
      # use it actually install into libvirt, it starts up the appliance on the remote side
      # and never terminates it, even when just using --import.
      xml = IO::popen(cmd_string).gets

      if @script
        @log.info "Attempting to run user provided script for modifying libVirt XML..."
        xml = IO::popen("#{script} #{xml}").gets
        @log.debug "Response was: #{xml}"
      end

      xml
    end

  end
end

plugin :class => BoxGrinder::LibVirtPlugin, :type => :delivery, :name => :libvirt, :full_name => "libVirt Virtualisation API"
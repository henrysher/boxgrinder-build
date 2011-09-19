require 'boxgrinder-build/plugins/base-plugin'

require 'libvirt'
require 'net/sftp'
require 'fileutils'
require 'uri'
require 'etc'

module BoxGrinder
  class LibVirtPlugin < BasePlugin

    def after_init
      patch
    end

    def set_defaults
       set_default_config_value('script', false)
       set_default_config_value('image_delivery_uri', '/var/lib/libvirt/images/')
       set_default_config_value('graphics', 'none')
       set_default_config_value('no_auto_console', true)
       set_default_config_value('network', false)
       # Disable certificate verification procedures by default
       set_default_config_value('remote_no_verify', true)
       #set_default_config_value('bus','virtio')
       set_default_config_value('bus','ide')
       set_default_config_value('overwrite', false)
       set_default_config_value('undefine_existing', false)
       set_default_config_value('default_permissions', 0644)

       validate_plugin_config(['libvirt_hypervisor_uri'])
     end

     def validate
       set_defaults

       # Optional user provided script
       @script = @plugin_config['script']
       @image_delivery_uri = URI.parse(@plugin_config['image_delivery_uri'])

       # The path that the image will be accessible at on the {remote, local} libvirt
       # If not specified we assume it is the same as the @image_delivery_uri. It is valid
       # that they can be different - for instance the image is delivered to a central repository
       # by SSH that maps to a local mount on host using libvirt.
       @libvirt_image_uri = (@plugin_config['libvirt_image_uri'] ||= @image_delivery_uri.path)

       @no_auto_console = @plugin_config['no_auto_console']
       @graphics = @plugin_config['graphics']
       @network = @plugin_config['network']
       @bus = @plugin_config['bus']
       @undefine_existing = @plugin_config['undefine_existing']

       # no_verify determines whether certificate validation performed
       @remote_no_verify = @plugin_config['remote_no_verify'] ? 1 : 0
       @libvirt_hypervisor_uri = @plugin_config['libvirt_hypervisor_uri'] << "?no_verify=#{@remote_no_verify}"

       @appliance_name = "#{@appliance_config.name}-#{@appliance_config.version}.#{@appliance_config.release}-" <<
                         "#{@appliance_config.os.name}-#{@appliance_config.os.version}-#{@appliance_config.hardware.arch}-#{current_platform}"
     end

    def execute

      if @image_delivery_uri.scheme =~ /(sftp|scp)/
        @log.info("Assuming this is a remote address.")
        #upload_image
      else
        @log.info("Copying disk #{@previous_deliverables.disk} to: #{@image_delivery_uri}")
        #FileUtils.cp(@previous_deliverables.disk, @image_delivery_uri)
      end

      begin
        conn = Libvirt::open(@libvirt_hypervisor_uri)
        if dom = get_existing_domain(conn, @appliance_name)
          unless @undefine_existing
            @log.fatal("A domain already exists with the name #{@appliance_name}. Set undefine_existing:true to automatically destroy and undefine it.")
            raise RuntimeError, "Domain '#{@appliance_name}' already exists"  #Make better specific exception
          end
          undefine_domain(dom)
        end

        xml = get_xml
        conn.define_domain_xml(xml)
      rescue Exception => e
        @log.fatal("There was a problem interacting with the remote libvirt server.")
        raise
      ensure
        if conn
          conn.close unless conn.closed?
        end
      end

    end

    # Remote only
    def upload_image
      uploader = SFTPPlugin.new
      uploader.instance_variable_set(:@log, @log)
      #SFTP library automagically uses keys registered with the OS first before trying a password.
      uploader.connect(@image_delivery_uri.host,
      (@image_delivery_uri.user ||= Etc.getlogin), # Use user provided in URI or current user
      @image_delivery_uri.password)

      uploader.upload_files(@image_delivery_uri.path,
                            @plugin_config['default_permissions'],
                            @plugin_config['overwrite'],
                            File.basename(@previous_deliverables.disk) => @previous_deliverables.disk)
    ensure
      uploader.disconnect if uploader.connected?
    end

    def get_xml
      cmd_string = "virt-install --disk '#{@libvirt_image_uri}/#{File.basename(@previous_deliverables.disk)},device=disk,bus=#{@bus},size=#{File.size(@previous_deliverables.disk)}' " <<
                            "--connect #{@libvirt_hypervisor_uri} "
                            "--name '#{@appliance_name}' " <<
                            "--description '#{@appliance_config.summary}' " <<
                            "--os-type linux " <<
                            "--os-variant '#{@appliance_config.os.name}#{@appliance_config.os.version}' " <<
                            "--ram #{@appliance_config.hardware.memory} " <<
                            "--vcpus #{@appliance_config.hardware.cpus} " <<
                            "--graphics #{@graphics} " <<
                            "--import " <<
                            "--print-xml " <<
                            "--dry-run "

      cmd_string << "--network #{@network} " if @network #otherwise leave defaults
      cmd_string << "--noautoconsole " if @no_auto_console

      @log.debug cmd_string
            
      # At present we can use virt-install to generate the xml. Unfortunately if we
      # use it actually install into libvirt, it starts up the appliance on the remote side
      # and never terminates it, even when just using --import.
      xml = IO::popen(cmd_string).read

      @log.debug xml

      # Let the user modify the XML specification to their requirements
      if @script
        @log.info "Attempting to run user provided script for modifying libVirt XML..."
        xml = IO::popen("#{script} #{xml}").read
        @log.debug "Response was: #{xml}"
      end

      xml
    end

    def get_existing_domain(conn, name)
      return conn.lookup_domain_by_name(name)
    rescue Error => e
      return nil if e.libvirt_code == 42 # If domain not defined
      raise # Otherwise reraise
    end

    def undefine_domain(dom)
      case dom.info.state
        when Libvirt::Domain::RUNNING, Libvirt::Domain::PAUSED, Libvirt::Domain::BLOCKED
          dom.destroy
      end
      dom.undefine
    end

    # Current libvirt library provides no way of getting the libvirt_code for
    # errors, this patches it in.
    def patch
      # If an update fixes this, do nothing.
      return if Libvirt::Error.respond_to?(:libvirt_code, false)
        Libvirt::Error.module_eval do
          def libvirt_code; @libvirt_code end
        end
    end

  end
end

plugin :class => BoxGrinder::LibVirtPlugin, :type => :delivery, :name => :libvirt, :full_name => "libVirt Virtualisation API"
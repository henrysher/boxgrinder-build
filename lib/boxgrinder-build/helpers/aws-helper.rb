require 'aws-sdk'

module BoxGrinder
  class AWSHelper
    #Setting value of a key to nil in opts_defaults forces non-nil value of key in opts_in
    def parse_opts(opts_in, opts_defaults)
      diff_id = opts_in.keys - opts_defaults.keys
      raise ArgumentError, "Unrecognised argument(s): #{diff_id.join(", ")}" if diff_id.any?

      (opts_in.keys & opts_defaults.keys).each do |k|
        raise ArgumentError, "Argument #{k.to_s} must not be nil" if opts_defaults[k] == nil and opts_in[k] == nil
      end

      (opts_defaults.keys - opts_in.keys).each do |k|
        raise ArgumentError, "Argument #{k.to_s} must not be nil" if opts_defaults[k] == nil
        opts_in.merge!(k => opts_defaults[k])
      end
      opts_in
    end

    def wait_with_timeout(cycle_seconds, timeout_seconds)
      Timeout::timeout(timeout_seconds) do
        while not yield
          sleep cycle_seconds
        end
      end
    end

    def select_aki(region, pattern)
      candidates = region.images.with_owner('amazon').
          filter('manifest-location','*pv-grub*').
          sort().
          reverse

      candidates.each do |image|
        return image.id if image.location =~ pattern
      end
    end

    #Currently there is no API call for discovering S3 endpoint addresses
    #but the base is presently the same as the EC2 endpoints, so this somewhat better
    #than manually maintaining the data.
    #def endpoints
    #  endpoints = {}
    #  AWS.memoize do
    #    @ec2.regions.each do |region|
    #      endpoints.merge!({
    #        :s3 => {
    #          region.name => {
    #            :endpoint => 's3.' << region.name << '.amazonaws.com',
    #            :kernel => {
    #              :i386 => select_aki(region, /hd0-.*i386/),
    #              :x86_64 => select_aki(region, /hd0-.*x86_64/)
    #            }
    #          }
    #        },
    #        :ebs => {
    #          region.name => {
    #            :endpoint => region.endpoint,
    #            :kernel => {
    #              :i386 => select_aki(region, /hd00-.*i386/),
    #              :x86_64 => select_aki(region, /hd00-.*x86_64/)
    #            }
    #          }
    #        }
    #      })
    #    end
    #  end
    #end

  end
end
require 'aws-sdk'

module BoxGrinder
  class AWSHelper
    #Setting value of a key to nil in opts_defaults forces non-nil value of key in opts_in
    def parse_opts(opts_in, opts_defaults)
      opts_in.merge!(opts_defaults).each_pair do |k,v|
        raise ArgumentError, "Unrecognised argument #{k.to_s}" unless opts_defaults.has_key?(k)
        raise ArgumentError, "Argument #{k.to_s} must not be nil" if v == nil and opts_defaults[k] == nil
      end
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
class Gemma
  module Storage
    class S3 < Storage::Base
      # How a bucket appears in request URLs.
      #
      # - `VirtualHosted`: the bucket is part of the host name,
      #   `https://<bucket>.<endpoint host>/<key>`. AWS recommends it, and
      #   DigitalOcean Spaces presigned URLs must use it.
      # - `Path`: the bucket is the first path segment,
      #   `https://<endpoint host>/<bucket>/<key>`. Use it for MinIO and other
      #   local endpoints, and for AWS buckets whose names contain dots.
      enum AddressingStyle
        VirtualHosted
        Path
      end
    end
  end
end

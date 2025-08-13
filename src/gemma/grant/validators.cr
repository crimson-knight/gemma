class Gemma
  module Grant
    # Validation helpers for attachments
    module AttachmentValidators
      # Validates file size
      macro validate_file_size_of(name, maximum = nil, minimum = nil, message = nil)
        validate :validate_{{name.id}}_file_size
        
        private def validate_{{name.id}}_file_size
          file = self.{{name.id}}
          return unless file
          
          size = file.size
          return unless size
          
          {% if maximum %}
            if size > {{maximum}}
              errors.add(:{{name.id}}, {{message}} || "is too large (maximum is {{maximum}} bytes)")
            end
          {% end %}
          
          {% if minimum %}
            if size < {{minimum}}
              errors.add(:{{name.id}}, {{message}} || "is too small (minimum is {{minimum}} bytes)")
            end
          {% end %}
        end
      end
      
      # Validates content type
      macro validate_content_type_of(name, accept = nil, reject = nil, message = nil)
        validate :validate_{{name.id}}_content_type
        
        private def validate_{{name.id}}_content_type
          file = self.{{name.id}}
          return unless file
          
          content_type = file.mime_type
          return unless content_type
          
          {% if accept %}
            accepted = {{accept}}
            accepted = [accepted] unless accepted.is_a?(Array)
            
            unless accepted.any? { |type| content_type_matches?(content_type, type) }
              errors.add(:{{name.id}}, {{message}} || "has invalid content type")
            end
          {% end %}
          
          {% if reject %}
            rejected = {{reject}}
            rejected = [rejected] unless rejected.is_a?(Array)
            
            if rejected.any? { |type| content_type_matches?(content_type, type) }
              errors.add(:{{name.id}}, {{message}} || "has forbidden content type")
            end
          {% end %}
        end
      end
      
      # Validates presence of attachment
      macro validate_presence_of(name, message = nil)
        validate :validate_{{name.id}}_presence
        
        private def validate_{{name.id}}_presence
          unless self.{{name.id}}
            errors.add(:{{name.id}}, {{message}} || "must be attached")
          end
        end
      end
      
      # Validates dimensions for images
      macro validate_dimensions_of(name, width = nil, height = nil, message = nil)
        validate :validate_{{name.id}}_dimensions
        
        private def validate_{{name.id}}_dimensions
          file = self.{{name.id}}
          return unless file
          
          # Check if dimensions are in metadata
          width_actual = file.metadata["width"]?.try(&.to_i)
          height_actual = file.metadata["height"]?.try(&.to_i)
          
          return unless width_actual && height_actual
          
          {% if width %}
            width_range = {{width}}
            if width_range.is_a?(Range)
              unless width_range.includes?(width_actual)
                errors.add(:{{name.id}}, {{message}} || "width must be between #{width_range.begin} and #{width_range.end} pixels")
              end
            elsif width_actual != width_range
              errors.add(:{{name.id}}, {{message}} || "width must be #{width_range} pixels")
            end
          {% end %}
          
          {% if height %}
            height_range = {{height}}
            if height_range.is_a?(Range)
              unless height_range.includes?(height_actual)
                errors.add(:{{name.id}}, {{message}} || "height must be between #{height_range.begin} and #{height_range.end} pixels")
              end
            elsif height_actual != height_range
              errors.add(:{{name.id}}, {{message}} || "height must be #{height_range} pixels")
            end
          {% end %}
        end
      end
      
      # Helper method to match content types with wildcards
      private def content_type_matches?(actual : String, pattern : String) : Bool
        if pattern.includes?("*")
          # Handle wildcards like "image/*"
          regex_pattern = pattern.gsub("*", ".*")
          actual.matches?(/^#{regex_pattern}$/)
        else
          actual == pattern
        end
      end
      
      # Validate collection size for has_many_attached
      macro validate_collection_size_of(name, maximum = nil, minimum = nil, message = nil)
        validate :validate_{{name.id}}_collection_size
        
        private def validate_{{name.id}}_collection_size
          files = self.{{name.id}}
          count = files.size
          
          {% if maximum %}
            if count > {{maximum}}
              errors.add(:{{name.id}}, {{message}} || "too many files (maximum is {{maximum}})")
            end
          {% end %}
          
          {% if minimum %}
            if count < {{minimum}}
              errors.add(:{{name.id}}, {{message}} || "too few files (minimum is {{minimum}})")
            end
          {% end %}
        end
      end
    end
  end
end
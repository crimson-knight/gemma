require "../attacher"
require "grant"

class Gemma
  module Grant
    module Attachable
      macro has_one_attached(name, uploader = Gemma)
        {% attacher_name = "_#{name.id}_attacher".id %}
        {% column = "#{name.id}_data".id %}
        
        @{{attacher_name}} : Gemma::Attacher?
        @{{name.id}}_changed = false
        @{{name.id}}_previous : Gemma::UploadedFile?
        
        def {{attacher_name}}
          @{{attacher_name}} ||= begin
            attacher = {{uploader}}::Attacher.new
            if data = self.{{column}}
              attacher.load_data(data)
            end
            attacher
          end
        end
        
        def {{name.id}}=(value : IO | Nil)
          # Store old file for cleanup if being replaced
          @{{name.id}}_previous = {{attacher_name}}.file if {{attacher_name}}.file && value
          
          if value
            {{attacher_name}}.attach_cached(value)
          else
            {{attacher_name}}.attach(nil)
          end
          @{{name.id}}_changed = true
        end
        
        def {{name.id}}=(value : String | Hash(String, String | Gemma::UploadedFile::MetadataType))
          {{attacher_name}}.attach_cached(value)
          @{{name.id}}_changed = true
        end
        
        def {{name.id}}
          {{attacher_name}}.file
        end
        
        def {{name.id}}_url(**options)
          {{attacher_name}}.url(**options)
        end
        
        def {{name.id}}_changed?
          @{{name.id}}_changed
        end
        
        before_save :_promote_{{name.id}}_attachment
        after_save :_persist_{{name.id}}_attachment
        after_destroy :_destroy_{{name.id}}_attachment
        
        private def _promote_{{name.id}}_attachment
          if {{name.id}}_changed? && {{attacher_name}}.cached?
            {{attacher_name}}.promote
          end
        end
        
        private def _persist_{{name.id}}_attachment
          if {{name.id}}_changed?
            # Delete the previous file if it was replaced
            @{{name.id}}_previous.try(&.delete)
            @{{name.id}}_previous = nil
            
            self.{{column}} = {{attacher_name}}.data
            @{{name.id}}_changed = false
          end
        end
        
        private def _destroy_{{name.id}}_attachment
          {{attacher_name}}.destroy_attached
        end
      end
      
      macro has_many_attached(name, uploader = Gemma)
        {% column = "#{name.id}_data".id %}
        {% singular = name.id.underscore.gsub(/s$/, "").id %}
        {% attachers_name = "_#{name.id}_attachers".id %}
        
        @{{attachers_name}} : Array(Gemma::Attacher)?
        @{{name.id}}_changed = false
        
        def {{attachers_name}}
          @{{attachers_name}} ||= begin
            attachers = [] of Gemma::Attacher
            if data = self.{{column}}
              if data.is_a?(Array)
                data.each do |file_data|
                  attacher = {{uploader}}::Attacher.new
                  attacher.load_data(file_data)
                  attachers << attacher
                end
              end
            end
            attachers
          end
        end
        
        def {{name.id}}=(values : Array(IO))
          {{attachers_name}}.clear
          values.each do |value|
            attacher = {{uploader}}::Attacher.new
            attacher.attach_cached(value)
            {{attachers_name}} << attacher
          end
          @{{name.id}}_changed = true
        end
        
        def {{name.id}}=(values : Array(String | Hash(String, String | Gemma::UploadedFile::MetadataType)))
          {{attachers_name}}.clear
          values.each do |value|
            attacher = {{uploader}}::Attacher.new
            attacher.attach_cached(value)
            {{attachers_name}} << attacher
          end
          @{{name.id}}_changed = true
        end
        
        def {{name.id}}
          {{attachers_name}}.map(&.file).compact
        end
        
        def add_{{singular}}(value : IO)
          attacher = {{uploader}}::Attacher.new
          attacher.attach_cached(value)
          {{attachers_name}} << attacher
          @{{name.id}}_changed = true
        end
        
        def remove_{{singular}}(file : Gemma::UploadedFile)
          {{attachers_name}}.reject! { |attacher| attacher.file == file }
          file.delete
          @{{name.id}}_changed = true
        end
        
        def clear_{{name.id}}
          {{attachers_name}}.each(&.destroy_attached)
          {{attachers_name}}.clear
          @{{name.id}}_changed = true
        end
        
        def {{name.id}}_changed?
          @{{name.id}}_changed
        end
        
        before_save :_promote_{{name.id}}_attachments
        after_save :_persist_{{name.id}}_attachments
        after_destroy :_destroy_{{name.id}}_attachments
        
        private def _promote_{{name.id}}_attachments
          if {{name.id}}_changed?
            {{attachers_name}}.each do |attacher|
              attacher.promote if attacher.cached?
            end
          end
        end
        
        private def _persist_{{name.id}}_attachments
          if {{name.id}}_changed?
            self.{{column}} = {{attachers_name}}.map(&.data).compact
            @{{name.id}}_changed = false
          end
        end
        
        private def _destroy_{{name.id}}_attachments
          {{attachers_name}}.each(&.destroy_attached)
        end
      end
    end
  end
end
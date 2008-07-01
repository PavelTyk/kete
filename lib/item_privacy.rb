# James Stradling <james@katipo.co.nz>
# 2008-04-15

# Item Privacy Modification

# include ItemPrivacy::All

module ItemPrivacy
  
  module All
    
    def self.included(klass)
      klass.class_eval do
        include ActsAsVersionedOverload::InstanceMethods
        extend  ActsAsVersionedOverload::ClassMethods
        include AttachmentFuOverload
        include TaggingOverload
      end
    end
    
  end
    
  module ActsAsVersionedOverload
    
    def self.included(klass)
      klass.class_eval do
        include InstanceMethods
        extend ClassMethods
      end
    end

    module InstanceMethods

    
      # TODO: Work out how to invoke an instance method from an included module..
      # Might need to overload self.non_versioned_columns the method
      # self.non_versioned_columns << "file_private"
    
      # Find the latest public version of the current item
      # Find the latest version of the current item
      # def latest_version
      #   raise "DEPRECATED: latest_version"
      #   versions.last
      # end
    
      def private_version!
        load_private!
      rescue
        nil
      end
    
      def has_private_version?
        respond_to?(:private?) && respond_to?(:private_version_serialized) && !private_version_serialized.blank?
      end
      
      def latest_version_is_private?
        last_version = versions.find(:first, :order => 'id DESC')
        last_version.respond_to?(:private?) && last_version.private?
      end
      
      def private_version(&block)
        private_version!
        result = block.call
        reload
        
        # Return the result of the block, not the reloaded item
        result
      end
      
      def is_private?
        respond_to?(:private) && private?
      end
      
      def save_without_saving_private!
        without_saving_private do
          save!
        end
      end
      
      protected
    
        def latest_public_version
          version = latest_unflagged_version_with_condition do |v|
            !v.private?
          end
        end

        def store_correct_versions_after_save
          if private?
            store_private!
            load_public!
          end
          
          ## Always return true to avoid halting the filter chain
          true
        end
    
        # Using Marshall as.. 
        # YAML is 34.65 times slower in serialization and 5.66 times slower in unserialization.
        # http://significantbits.wordpress.com/2008/01/29/yaml-vs-marshal-performance/
        def store_private!(save_after_serialization = false)

          prepared_array = self.class.versioned_columns.inject(Array.new) do |memo, k|
            memo << [k.name, send(k.name.to_sym)]
          end
          
          # Also save the current version into the private version column
          prepared_array << ["version", version]
          
          # Save the prepared array into the attribute column..
          without_revision do
            without_saving_private do
              self.private_version_serialized = YAML.dump(prepared_array)
              save!
            end
          end
          
        end
      
        # Load the saved private attributes into the current instance.
        def load_private!
          reload
          private_attrs = YAML.load(private_version_serialized)
          raise "No private attributes" if private_attrs.nil? || !private_attrs.kind_of?(Array)
        
          private_attrs.each do |key, value|
            send("#{key}=".to_sym, value)
          end
          
          self
        end
      
        # Revert to the most recent public version and save.
        # We do this after_save via store_correct_versions_after_save in order to keep
        # the latest public version in the 'master' model record.
        def load_public!
          if public_version = latest_public_version
            without_saving_private do
              revert_to!(public_version)
            end

            # At this point, I know from testing that the reverted version
            # and current model are public and appropriate.
          else
            
            update_hash = { 
              :title => NO_PUBLIC_VERSION_TITLE,
              :description => NO_PUBLIC_VERSION_DESCRIPTION,
              :extended_content => nil,
              :tag_list => nil,
              :private => false
            }

            update_hash[:short_summary] = nil if can_have_short_summary?

            # Update without callbacks
            self.update_attributes!(update_hash)
            
            add_as_contributor(User.find(:first))
          end
          
          reload
        # rescue
        #   false
        end
        
        def without_saving_private(&block)
          self.class.without_saving_private(&block)
        end
        
    end
    
    module ClassMethods
      
      def without_saving_private(&block)
        class_eval do 
          alias_method :orig_store_correct_versions_after_save, :store_correct_versions_after_save
          alias_method :store_correct_versions_after_save, :empty_callback
        end
        block.call
      ensure
        class_eval do 
          alias_method :store_correct_versions_after_save, :orig_store_correct_versions_after_save
        end
      end
      
    end
      
  end
  
  module TaggingOverload
    
    # Transparently map tags for the current item to the tags of the correct
    # privacy.
    def tags
      private? ? private_tags : public_tags
    end

    def tag_list
      private? ? private_tag_list : public_tag_list
    end

    def tag_list=(new_tags)
      if private?
        self.private_tag_list = new_tags
      else
        self.public_tag_list = new_tags
      end
    end

    def tag_counts
      private? ? private_tag_counts : public_tag_counts
    end
    
  end
  
  module AttachmentFuOverload
    
    def file_private=(*args)
  
      # File privacy can only go private => public as a public file cannot 
      # be made private at a later time due to the need for previous 
      # versions have file access.
      unless self.file_private === false
        @old_filename ||= full_filename unless !self.respond_to?(:filename) || filename.nil?
        super(*args)
      end
    end
    
    # Override the AttachmentFu default method to ensure we place the attachment
    # in the correct folder.
    def full_filename(thumbnail = nil)
      file_system_path = "#{attachment_path_prefix}/#{self.class.table_name}"
      File.join(RAILS_ROOT, file_system_path, *partitioned_path(thumbnail_name_for(thumbnail)))
    end
    
    # Make sure that the correct base path is stripped off in 
    # AttachmentFu::Backends::FileSystemBackend.public_filename
    # Overridden from AttachmentFu
    def base_path
      @base_path ||= File.join(RAILS_ROOT, attachment_path_prefix)
    end
    
    private
  
      # Get the path we should be using based on the item's
      # privacy
      def attachment_path_prefix
        file_private? ? 'private' : 'public'
      end
      
      # Renames the given file before saving
      # Overridden from AttachmentFu
      def rename_file
        return unless @old_filename && @old_filename != full_filename
        if save_attachment? && File.exists?(@old_filename)
          FileUtils.rm @old_filename
        elsif File.exists?(@old_filename)
          
          # Ensure there a folder to move the file into
          FileUtils.mkdir_p(File.dirname(full_filename))
          FileUtils.mv @old_filename, full_filename
          
          # Remove the directory we moved from too if it's empty
          Dir.rmdir(File.dirname(@old_filename)) if (Dir.entries(File.dirname(@old_filename))-['.','..']).empty?
        end
        @old_filename =  nil
        true
      end
      
  end
  
end
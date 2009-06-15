module ZoomControllerHelpers
  unless included_modules.include? ZoomControllerHelpers
    # set up our helper methods
    def self.included(klass)
      # only intended to add helper methods in app/controllers/application.rb
      if klass.name == 'ApplicationController'
        klass.helper_method :zoom_class_controller, :zoom_class_from_controller, :zoom_class_humanize,
                            :zoom_class_plural_humanize, :zoom_class_humanize_after, :zoom_class_params_key,
                            :zoom_class_params_key_from_item, :zoom_class_params_key_from_controller
      end
    end

    # this keeps the RoR item around, just destroys zoom record
    # doesn't delete zoom records for any relations

    # mainly for cleaning out old zoom record
    # before we generate a new one
    def zoom_destroy_for(item)
      @successful = item.zoom_destroy
    end

    # destroy zoom and then item itself
    def zoom_item_destroy(item)
      @successful = true
      # delete any comments this is on
      item.comments.each do |comment|
        @successful = comment.destroy
        if !@successful
          return @successful
        end
      end

      if @successful
        @successful = item.destroy
      end
    end

    def zoom_destroy_and_redirect(zoom_class,pretty_zoom_class = nil)
      if pretty_zoom_class.nil?
        pretty_zoom_class = zoom_class
      end
      begin
        item = Module.class_eval(zoom_class).find(params[:id])

        related_items = item.related_items

        @successful = zoom_item_destroy(item)
      rescue
        flash[:error], @successful  = $!.to_s, false
      end

      if @successful
        # if destroy went ok, we want to trigger zoom rebuild for related items
        related_items.each do |related_item|
          prepare_and_save_to_zoom(related_item)
        end

        flash[:notice] = I18n.t('zoom_controller_helpers_lib.zoom_destroy_and_redirect.destroyed',
                                :pretty_zoom_class => pretty_zoom_class)
      end
      redirect_to :action => 'list'
    end


    # called by either before filter on destroy
    # or after filter on update
    def update_zoom_record_for_related_items
      if CACHES_CONTROLLERS.include?(params[:controller]) && params[:controller] != 'baskets'
        item = item_from_controller_and_id(false)

        # Walter McGinnis, 2009-05-11
        # this doesn't work because of multiple render calls
        # postponing until 1-3...
        # at that time, it should only be called
        # if item moved to a new basket
        # item.related_items.each do |related_item|
        #   prepare_and_save_to_zoom(related_item)
        # end
      end
    end

    def zoom_class_controller(zoom_class)
      zoom_class_controller = String.new
      case zoom_class
      when "StillImage"
        zoom_class_controller = 'images'
      when "Video"
        zoom_class_controller = 'video'
      when "Comment"
        zoom_class_controller = 'comments'
      when "AudioRecording"
        zoom_class_controller = 'audio'
      else
        zoom_class_controller = zoom_class.tableize
      end
    end

    def zoom_class_from_controller(controller)
      zoom_class = String.new
      case controller
      when "images"
        zoom_class = 'StillImage'
      when "video"
        zoom_class = 'Video'
      when "comments"
        zoom_class = 'Comment'
      when "audio"
        zoom_class = 'AudioRecording'
      else
        zoom_class = controller.classify
      end
    end

    def zoom_class_humanize(zoom_class)
      return I18n.t("zoom_controller_helpers_lib.zoom_class_humanize.#{zoom_class.underscore}")
    end

    def zoom_class_params_key(zoom_class)
      zoom_class.tableize.singularize.to_sym
    end

    def zoom_class_params_key_from_item(item)
      zoom_class_params_key(item.class.name)
    end

    def zoom_class_params_key_from_controller(controller)
      zoom_class_params_key(zoom_class_from_controller(controller))
    end

    def zoom_class_plural_humanize(zoom_class)
      return I18n.t("zoom_controller_helpers_lib.zoom_class_plural_humanize.#{zoom_class.underscore}")
    end

    def zoom_class_humanize_after(count, zoom_class)
      humanized = count + ' '
      if count.to_i != 1
        humanized += zoom_class_plural_humanize(zoom_class)
      else
        humanized += zoom_class_humanize(zoom_class)
      end
    end

    def prepare_zoom(item)
      # only do this for members of ZOOM_CLASSES
      if ZOOM_CLASSES.include?(item.class.name)
        begin
          item.oai_record = render_oai_record_xml(:item => item, :to_string => true)
        rescue
          logger.error("prepare_and_save_to_zoom error: #{$!.to_s}")
        end
      end
    end

    def prepare_and_save_to_zoom(item)

      # This is always the public version..
      unless item.already_at_blank_version? || item.at_placeholder_public_version?
        prepare_zoom(item)
        item.zoom_save
      end

      # Redo the save for the private version
      if item.respond_to?(:private) and item.has_private_version? and !item.private?

        item.private_version do
          unless item.already_at_blank_version?
            prepare_zoom(item)
            item.zoom_save
          end
        end

        raise "Could not return to public version" if item.private?

      end
    end

    protected

    # Evaluate a possibly unsafe string into a zoom class.
    # I.e.  "StillImage" => StillImage
    def only_valid_zoom_class(param)
      if ZOOM_CLASSES.member?(param)
        param.constantize
      else
        raise(ArgumentError, "Zoom class name expected. #{param} is not registered in ZOOM_CLASSES.")
      end
    end
  end
end

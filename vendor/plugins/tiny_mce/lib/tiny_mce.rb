module TinyMCE
  def self.included(base)
    base.extend(ClassMethods)
    base.helper TinyMCEHelper
  end

  module ClassMethods
    def uses_tiny_mce(options = {})
      tiny_mce_options = options.delete(:options) || {}
      tiny_mce_options.reverse_merge!(:spellchecker_rpc_url => "/" + self.controller_name + "/spellchecker")
      proc = Proc.new do |c|
        c.instance_variable_set(:@tiny_mce_options, tiny_mce_options)
        c.instance_variable_set(:@uses_tiny_mce, true)
      end
      before_filter(proc, options)

      self.class_eval do
        include TinyMCE::SpellChecker
      end
    end
  end

  module OptionValidator
    class << self
      cattr_accessor :plugins

      def load
        @@valid_options = File.open(File.dirname(__FILE__) + "/../tiny_mce_options.yml") { |f| YAML.load(f.read) }
      end

      def valid?(option)
        option = option.to_s
        @@valid_options.include?(option) || (plugins && plugins.include?(option.split('_')[0])) || option =~ /theme_advanced_container_/
      end

      def options
        @@valid_options
      end
    end
  end

  module SpellChecker
    require 'net/https'
    require 'uri'
    require 'rexml/document'

    ASPELL_WORD_DATA_REGEX = Regexp.new(/\&\s\w+\s\d+\s\d+(.*)$/)

    # Attempt to dertermine where Aspell is
    # Might be slow and a horrible way to do it, but it works!
    ASPELL_PATH = if (`/usr/bin/aspell`) =~ /Usage/ # usually linux operating systems
      "/usr/bin/aspell"
    elsif (`/usr/local/bin/aspell`) =~ /Usage/ # usually mac operating systems
      "/usr/local/bin/aspell"
    else
      "aspell" # this usally doesn't work depending on permissions but we'll fall back to it
    end

    def spellchecker
      language, words, method = params[:params][0], params[:params][1], params[:method] unless params[:params].blank?
      return render :nothing => true if language.blank? || words.blank? || method.blank?
      headers["Content-Type"] = "text/plain"
      headers["charset"] = "utf-8"
      suggestions = check_spelling(words, method, language)
      results = {"id" => nil, "result" => suggestions, "error" => nil}
      render :json => results
    end

    def check_spelling(spell_check_text, command, lang)
      xml_response_values = Array.new
      spell_check_text = spell_check_text.join(' ') if command == 'checkWords'
      logger.debug("Spellchecking via:  echo \"#{spell_check_text}\" | #{ASPELL_PATH} -a -l #{lang}")
      spell_check_response = `echo "#{spell_check_text}" | #{ASPELL_PATH} -a -l #{lang}`
      return xml_response_values if spell_check_response.blank?
      spelling_errors = spell_check_response.split("\n").slice(1..-1)
      for error in spelling_errors
        error.strip!
        if (match_data = error.match(ASPELL_WORD_DATA_REGEX))
          if (command == 'checkWords')
            arr = match_data[0].split(' ')
            xml_response_values << arr[1]
          elsif (command == 'getSuggestions')
            xml_response_values << error.split(',')[1..-1].collect(&:strip!)
            xml_response_values = xml_response_values.first
          end
        end
      end
      return xml_response_values
    end
  end

end

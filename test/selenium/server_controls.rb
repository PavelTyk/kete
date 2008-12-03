# Clean this up. It works for now, but adopt a more BackgroundRB style of server control

module ServerControls
  class SeleniumRCServer
    def self.start
      begin
        ps = `ps aux | grep selenium`
        self.stop if !ps.scan('selenium-server.jar').blank?
        raise unless system "java -jar #{File.dirname(__FILE__)}/server/selenium-server.jar > #{Rails.root}/log/selenium_rc_server.log &"
        sleep 5
      rescue
        raise "ERROR: Could not start Selenium Server. Please start it manually."
      end
    end

    def self.stop
      # kill the server, wait 5 seconds
    end

    def self.restart
      self.stop
      self.start
    end
  end

  class SeleniumWebServer
    def self.start
      begin
        ps = `ps aux | grep script/server`
        self.stop if !ps.scan("script/server -p #{SELENIUM_WEB_SERVER_PORT} -e test").blank?
        raise unless system "#{Rails.root}/script/server -p #{SELENIUM_WEB_SERVER_PORT} -e test > #{Rails.root}/log/selenium_web_server.log &"
        sleep 10
      rescue
        raise "ERROR: Could not find or start testing web server on port #{SELENIUM_WEB_SERVER_PORT}"
      end
    end

    def self.stop
      # kill the server, wait 5 seconds
    end

    def self.restart
      self.stop
      self.start
    end
  end
end
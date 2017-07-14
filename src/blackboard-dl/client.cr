require "xml"
require "http/client"
require "http/params"

module BlackBoard::Dl
  # Constants
  SEARCH_HOST  = "https://mlcs.medu.com/api/b2_registration/match_schools/?"
  LOGIN        = "/webapps/Bb-mobile-bb_bb60/sslUserLogin?v=2&f=xml&ver=4.1.2"
  COURSE       = "/webapps/Bb-mobile-bb_bb60/courseMap?v=1&f=xml&ver=4.1.2"
  COURSES_PATH = "/webapps/Bb-mobile-bb_bb60/enrollments?v=1&f=xml&ver=4.1.2&course_type=ALL&include_grades=false"

  HEADERS    = HTTP::Headers{"User-Agent" => "Mobile Learn/3333 CFNetwork/758.0.2 Darwin/16.0.0", "Accept-Language" => "en-gb"}
  COOKIES    = {"s_session_id" => "", "session_id" => "", "web_client_cache_guid" => ""}
  BB_VERSION = "4.1.2"

  class Client
    def initialize(@host : String, @username : String, @password : String)
      self
    end

    # Gets a list of available colleges on the Blackboard system.
    def self.search_colleges(q : String)
      client = HTTP::Client.new URI.parse(SEARCH_HOST)
      param_data = {
        "v"               => "1",
        "f"               => "xml",
        "ver"             => BB_VERSION,
        "q"               => q,
        "language"        => "en-GB",
        "platform"        => "ios",
        "device_name"     => "iPhone",
        "carrier_code"    => "12456",
        "carrier_name"    => "BT",
        "registration_id" => "(null)",
      }

      params = HTTP::Params.encode(param_data)
      res = client.get(SEARCH_HOST + params, headers: HEADERS)
      client.close
      response = XML.parse(res.body.to_s).first_element_child.as(XML::Node)

      # Create an array of colleges.
      colleges = [{} of String => String]

      # Parse the response body and select the first element, and only select it's childrens elements.
      # (Ignore text nodes)
      XML.parse(res.body.to_s).first_element_child.as(XML::Node).children.select(&.element?).each do |child|
        # Create a hash of colleges.
        college = {} of String => String

        # Go through each child node only selecting it's childrens elements.
        # (Ignoring text nodes)
        child.children.select(&.element?).each do |c|
          # Set college attributes.
          if c.name == "name"
            college["name"] = c.text
          end
          if c.name == "b2_url"
            college["url"] = c.text
          end
          if c.name == "can_has_ssl_login"
            college["ssl"] = c.text
          end
          if c.name == "display_lms_host"
            college["host"] = c.text
          end
          if c.name == "id"
            college["id"] = c.text
          end
          if c.name == "client_id"
            college["client_id"] = c.text
          end
        end
        # Append college.
        colleges << college
      end
      # Remove the first empty hash.
      colleges.shift
      colleges
    end

    # Signs the student into Blackboard.
    def login
      client = HTTP::Client.new URI.parse(@host)
      data = {"username" => @username, "password" => @password}
      res = client.post_form(LOGIN, headers: HEADERS, form: data)
      client.close

      response = XML.parse(res.body.to_s).first_element_child.as(XML::Node)
      status = response["status"]
      if status == "OK"
        # Save relevant cookies...
        COOKIES["s_session_id"] = res.cookies["s_session_id"].value
        COOKIES["session_id"] = res.cookies["session_id"].value

        if res.cookies.has_key?("web_client_cache_guid")
          COOKIES["web_client_cache_guid"] = res.cookies["web_client_cache_guid"].value
        end
      end
      return status
    end

    # Gets the students courses.
    def get_courses
      course_ids = [] of Hash(String, String | Nil)
      client = HTTP::Client.new URI.parse(@host)

      # Send Cookie header.
      HEADERS["Cookie"] = ("web_client_cache_guid=#{COOKIES["web_client_cache_guid"]}; session_id=#{COOKIES["session_id"]}; s_session_id=#{COOKIES["s_session_id"]}")
      res = client.post(COURSES_PATH, headers: HEADERS)
      client.close
      # Parse courses.
      mobileresponse = XML.parse(res.body.to_s).first_element_child.as(XML::Node).children[0]
      mobileresponse.children.each do |course|
        if course["daysFromTheDateOfEnrollment"] == "0"
          course_ids << {"id" => course["bbid"], "name" => course["name"]}
        end
      end
      # Get rid of the last one. (Most likely the general course name e.g 'English Studies'
      # TODO: Handle this situation...
      course_ids.pop
      course_ids
    end

    # Gets course data for a given course.
    def get_course_data(course_name : String, course_id : String)
      client = HTTP::Client.new URI.parse(@host)

      # Send 'Cookie' header.
      HEADERS["Cookie"] = ("web_client_cache_guid=#{COOKIES["web_client_cache_guid"]}; session_id=#{COOKIES["session_id"]}; s_session_id=#{COOKIES["s_session_id"]}")

      # Get course data and start downloading attachments.
      res = client.post(COURSE + "&course_id=" + course_id, headers: HEADERS)
      response = XML.parse(res.body.to_s).first_element_child.as(XML::Node)
      status = response["status"]
      if status == "OK"
        get_attachments(course_name, response.to_s)
      end
    end

    # Fetches an attachment for a given course.
    def fetch_attachment(course_name, week_name, materials)
      path = "#{Dir.current}/#{course_name.gsub(" ", '_')}"
      # Fetch lectures from Blackboard.
      # (Sometimes lectures are available, and no workshops are available)
      # (Rarely this happens, but only on welcome week)
      path_name = week_name.gsub(" ", '_')
      begin
        download({path_name, materials, path})
      rescue
        puts "  [-] Unable to download #{materials["name"]}".colorize.red
      end
    end

    # Get attachments for a given course name and course data.
    private def get_attachments(course_name : String, course_data : String)
      parsed_data = XML.parse(course_data).first_element_child.as(XML::Node)

      # Workshops
      parsed_data.children[1].children[7].children[1].children.each do |child|
        if child.name == "map-item"
          # We are in the main XML node.
          # Get the week name within that child node.
          week_name = child["name"].to_s
          available = false

          # Lecture Materials.
          child.children[3].children[1].children.each do |inner|
            if inner.type == XML::Type::ELEMENT_NODE
              if inner.name == "attachments"
                puts "  [+] #{course_name} lecture avaliable for #{week_name}.".colorize.green.to_s
                # we need to go deeper.
                inner.children.each do |material|
                  if material.name == "attachment"
                    # There is an available lecture this week!
                    # Download that lecture!
                    available = true
                    fetch_attachment(course_name, week_name, material)
                  end
                end
                # Skip nodes which are descriptions.
              elsif inner.name == "description"
                next
              end
            end
          end

          # Lectures for this week are not available then...
          if available == false
            puts " [-] #{course_name} lecture for #{week_name} is not available yet.".colorize.red
          end
        end
      end

      # Workshops
      begin
        parsed_data.children[1].children[7].children.each do |child|
          child.children.each do |c|
            if c.name == "map-item"
              # We are in the main XML node.
              # Get the week name within that child node.
              week_name = c["name"].to_s
              workshop_available = false

              c.children[3].children[3].children.each do |inner|
                if inner.name == "attachments"
                  # we need to go deeper.
                  inner.children.each do |material|
                    if material.name == "attachment"
                      # There is an available lecture this week!
                      # Download that workshop!
                      workshop_available = true
                      fetch_attachment(course_name, week_name, material)
                    end
                  end
                  # Skip nodes which are descriptions.
                elsif inner.name == "description"
                  next
                end
              end
            end
            # Workshops for this week are not available then...
            if workshop_available == false
              puts " [-] #{course_name} workshop for #{week_name} is not available yet.".colorize.red
            end
          end
        end
      rescue
        puts " [-] No workshop material found. skipping...".colorize.green.mode(:dim).to_s
      end
    end

    # Downloads the attachment.
    private def download(attachment_data)
      # Get the current path and underscore the path.
      dl_path = "#{attachment_data[2]}/#{attachment_data[0]}"
      course_friendly_name = File.basename(attachment_data[2].gsub("_", ' '))
      folder_friendly_name = File.basename(attachment_data[0].gsub("_", ' '))
      attachment_url = attachment_data[1]["url"].to_s
      filename = attachment_data[1]["name"]
      final_path = "#{dl_path}/#{filename.to_s}"

      # Create the course folder if it doesn't exist.
      if !Dir.exists?(dl_path)
        puts "    [+] #{folder_friendly_name} folder does not exist, creating..."
        Dir.mkdir(dl_path)
      end
      if !File.exists?(final_path)
        puts "    [+] Downloading material for #{folder_friendly_name}...".colorize.cyan.mode(:bold).to_s
        # Download attachment.
        client = HTTP::Client.new URI.parse(@host)
        client.close

        HEADERS["Cookie"] = ("web_client_cache_guid=#{COOKIES["web_client_cache_guid"]}; session_id=#{COOKIES["session_id"]}; s_session_id=#{COOKIES["s_session_id"]}")
        location = client.get(attachment_url, headers: HEADERS)
        client.close

        # 302 Found.
        #
        # 1st Location.
        dl_url = URI.parse(location.headers["Location"].to_s)
        client2 = HTTP::Client.new dl_url
        location2 = client2.get(dl_url.path.to_s, headers: HEADERS)
        client2.close

        #
        # 2nd Location. (Should be the attachment)
        location3 = URI.parse(location2.headers["Location"].to_s)
        client3 = HTTP::Client.new location3
        attachment = client3.get(location3.path.to_s, headers: HEADERS)
        client3.close

        #
        # Download material.
        full_length = attachment.headers["Content-Length"]
        File.open(final_path, "wb") do |f|
          f << attachment.body
        end
      else
        puts "  [-] #{filename} exists. skipping...".colorize.green.mode(:dim).to_s
      end
    end
  end
end

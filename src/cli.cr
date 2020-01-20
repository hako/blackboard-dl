require "io/console"
require "http/client"
require "option_parser"
require "readline"
require "uri"
require "daemonize"
require "colorize"
require "json"

module BlackBoard::Dl
  # College JSON structure.
  private class College
    JSON.mapping(
      name: String,
      id: String,
      url: String,
      client_id: String,
      ssl: String,
      host: String,
    )
  end

  # Selected college & current dir (for daemon)
  @@college = {} of String => String

  # Runs the blackboard-dl commandline utility.
  def self.run
    banner = "Blackboard course downloader " + "v#{VERSION}".colorize.green.to_s + " - [c] 2017 Wesley Hill"
    bb_username = Nil
    bb_password = Nil
    daemon = false

    OptionParser.parse do |parser|
      parser.banner = "usage: blackboard-dl [-h] [-d] [-u USERNAME] [-p PASSWORD] [--version]\n\ndownload course files from blackboard.\n\noptional arguments:"
      parser.on("-u USERNAME", "--username", "Blackboard username") { |username| bb_username = username }
      parser.on("-p PASSWORD", "--password", "Blackboard password") { |password| bb_password = password }
      parser.on("-d", "--daemon", "Run as daemon") { daemon = true }
      parser.on("-h", "--help", "Show this help") { puts parser; exit(0) }
      parser.on("-v", "--version", "Show program version") { puts BlackBoard::Dl::VERSION }
    end
    puts banner
    load_selected_college

    # Only search if there is no selected college.
    if @@college.empty?
      search_college
    end

    # 'Login screen'.
    secure_type = if @@college["ssl"] == "true"
                    "[secure ✔]".colorize.mode(:dim).to_s
                  else
                    "[insecure ✖]".colorize.red.mode(:dim).to_s
                  end

    puts "\n#{@@college["name"]}".colorize.green.mode(:bold).to_s + " #{secure_type}"
    puts "#{@@college["host"]}".colorize.green

    # Present a prompt to the student to enter in their course details instead of using the argument parser.
    if (bb_username && bb_password) == Nil
      puts "-Login--------------------------".colorize.green.mode(:dim)
      username = Readline.readline("[?] Blackboard username: ".colorize.green.to_s, add_history = true)
      print "[?] Blackboard password (hidden): ".colorize.green
      password = STDIN.noecho &.gets.to_s.try &.chomp
      print "\n"

      bb_username = username
      bb_password = password
    end

    # Download as normal or as a daemon.
    if daemon == true
      download_as_daemon(bb_username, bb_password)
    else
      download(@@college["url"], bb_username, bb_password)
    end
  end

  # Download course material as a daemon with a username & password.
  def self.download_as_daemon(bb_username, bb_password)
    # Daemonize process.
    puts "Running daemon in the background on pid: #{Process.pid + 2}".colorize.magenta.mode(:bold).to_s
    stdout_log = Dir.current + "/bbdl_output.log"
    stderr_log = Dir.current + "/bbdl_errors.log"

    puts "Daemon log output: #{stdout_log}".colorize.green.to_s
    puts "Daemon error output: #{stderr_log}".colorize.red.to_s

    Daemonize.daemonize(stdout: stdout_log, stderr: stderr_log, dir: Dir.current)

    now = Time.now
    puts ""
    puts "-Blackboard course downloader daemon ---------------[#{now.to_s("%T")}]"
    diff = now.at_end_of_hour - now

    # Loop every n minutes.
    until now == now.at_end_of_hour
      puts "Checking for new course material in #{diff.minutes} minute(s)"
      sleep diff.duration
      puts "Checking new courses at #{Time.now.to_s("%T")}"
      download(@@college["url"], bb_username, bb_password)
      now = Time.now
      diff = now.at_end_of_hour - now
    end
  end

  # Download courses material with a college url, username & password.
  def self.download(bb_url, bb_username, bb_password)
    # Make sure we download to this directory.
    print "\r[+] Logging in...".colorize.green.mode(:dim)
    client = BlackBoard::Dl::Client.new(bb_url.to_s, bb_username.to_s, bb_password.to_s)
    # Login.
    begin
      status = client.login
    rescue error
      puts "\r[x] Unable to login try again later...".colorize.red
      puts "[!] Reason: #{error}".colorize.red
      exit(1)
    end
    if status != "OK"
      puts "Login incorrect, please check your credentials and college and try again.".colorize.red
      puts ("Hint: The college you selected was: %s") % ("#{@@college["name"]}".colorize.green.mode(:bold).to_s)
      exit(1)
    else
      print "\n"
      puts ("[+] Successfully logged into Blackboard as" + " %s!".colorize.green.mode(:bold).to_s) % (bb_username.to_s)
    end

    # Fetch enrolled courses.
    courses = client.get_courses
    courses.each do |course|
      # Get the current path and underscore the path.
      name = course["name"].to_s.split(" -")[0]
      path = "#{Dir.current}/#{name.gsub(" ", '_')}"
      puts "[Course] %s".colorize.cyan.mode(:bold).to_s % name
      # Create the course folder if it doesn't exist.
      if !Dir.exists?(path)
        puts " [+] %s folder does not exist, creating..." % name
        Dir.mkdir(path)
      else
        puts " [+] %s folder exists, continuing..." % name
      end
      # Start to download the attachment.
      begin
        client.get_course_data(name, course["id"].to_s)
      rescue error
        puts "[!] Reason: #{error}".colorize.red
        exit(1)
      end
      puts ""
    end
    puts "[+] Finished downloading courses for #{bb_username}".colorize.green.mode(:bold).to_s
  end

  # Check for yes or no.
  def self.check_y_n(choice)
    exists = false
    # Check for Yeses.
    ["Y", "y", "Yes", "YES", "yes"].each do |y|
      if choice == y
        exists = true
        choice = "Y"
        break
      end
    end
    # Check for Nos.
    ["N", "n", "No", "NO", "no"].each do |n|
      if choice == n
        exists = true
        choice = "N"
        break
      end
    end
    # If the string exists, return Y/N.
    if exists == true
      return choice
    end
  end

  # Load selected college if it exists.
  def self.load_selected_college
    begin
      college = College.from_json(File.open("./selected_college.json", "r"))
      college_hash = {
        "name"      => college.name,
        "id"        => college.id,
        "url"       => college.url,
        "client_id" => college.client_id,
        "ssl"       => college.ssl,
        "host"      => college.host,
      }
      @@college = college_hash
    rescue
    end
  end

  # Save selected college.
  def self.save_selected_college
    File.open("./selected_college.json", "wb") do |c|
      c << @@college.to_json
    end
  end

  # Search for the students college.
  def self.search_college
    # This is a prompt for students to search and select their college details. (assuming they use BlackBoard)
    # Only exit if they have selected a course.
    selected = false
    until selected == true
      query = Readline.readline("[!] Search for your college/university: ".colorize.green.to_s, add_history = true)
      print "\rSearching...".colorize.cyan.mode(:bold)
      # Search colleges.
      colleges = BlackBoard::Dl::Client.search_colleges query.to_s

      # Check empty college.
      if colleges.empty?
        print "\rNo Results found!".colorize.red
        exit(1)
      end

      # Show college results.
      print "\r#{colleges.size} result(s) for \"#{query}\"\n".colorize.green.mode(:bold)
      colleges.each_with_index do |college, i|
        puts "[#{i}]".colorize.yellow.to_s + " #{college["name"]}"
      end
      idx = Readline.readline("[?] What " + "number".colorize.yellow.to_s + " is your college/university?: ".colorize.green.to_s, add_history = true)

      # Error handling...
      begin
        @@college = colleges.at(idx.to_s.to_i)
        selected = true
      rescue
        puts "[x] That didn't work, try again...".colorize.red
      end
    end

    # Choice to save their college.
    choice = check_y_n(Readline.readline("[?] Would you like to save your selected college?: ".colorize.green.to_s, add_history = true))

    # Save only if the student pressed Y.
    if choice == "Y"
      self.save_selected_college
      puts "Selected college " + "\"#{@@college["name"]}\"".colorize.green.to_s + " saved in " + "\"selected_college.json\"".colorize.green.to_s + "."
    end
  end
end

BlackBoard::Dl.run

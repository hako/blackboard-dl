require "io/console"
require "http/client"
require "option_parser"
require "readline"
require "uri"
require "daemonize"

module BlackBoard::Dl
  # Runs the blackboard-dl commandline utility.
  def self.run
    bb_username = Nil
    bb_password = Nil
    daemon = false

    OptionParser.parse! do |parser|
      parser.banner = "usage: blackboard-dl [-h] [-d] [-u USERNAME] [-p PASSWORD] [--version]\n\ndownload course files from blackboard.\n\noptional arguments:"
      parser.on("-u USERNAME", "--username", "Blackboard username") { |username| bb_username = username }
      parser.on("-p PASSWORD", "--password", "Blackboard password") { |password| bb_password = password }
      parser.on("-d", "--daemon", "Run as daemon") { daemon = true }
      parser.on("-h", "--help", "Show this help") { puts parser; exit(0) }
      parser.on("-v", "--version", "Show program version") { puts BlackBoard::Dl::VERSION }
    end

    puts "Blackboard course downloader - [c] 2016 Wesley Hill"
    # Present a prompt to the student to enter in their course details instead of the argument parser.
    if (bb_username && bb_password) == Nil
      username = Readline.readline("[?] Blackboard username: ", add_history = true)
      print "[?] Blackboard password (hidden): "
      password = STDIN.noecho &.gets.to_s.try &.chomp
      print "\n"

      bb_username = username
      bb_password = password
    end

    if daemon == true
      # Daemonize process.
      puts "Running in the background on pid: #{Process.pid}"
      Daemonize.daemonize
      now = Time.now
      diff = now.at_end_of_hour - now
      until now == now.at_end_of_hour
        puts "Checking for an update in #{diff.minutes} minute(s)"
        sleep diff.duration
        download(bb_username, bb_password)
        now = Time.now
      end
    else
      download(bb_username, bb_password)
    end
  end

  def self.download(bb_username, bb_password)
    # Login.
    client = BlackBoard::Dl::Client.new(bb_username.to_s, bb_password.to_s)
    status = client.login
    if status != "OK"
      puts "Login incorrect, please check your credentials and try again."
      exit(1)
    else
      print "\n"
      puts ("[+] Successfully logged into Blackboard as %s") % (bb_username.to_s)
    end

    # Fetch enrolled courses.
    courses = client.get_courses
    courses.each do |course|
      # Get the current path and underscore the path.
      name = course["name"].to_s.split(" -")[0]
      path = "#{Dir.current}/#{name.gsub(" ", '_')}"
      puts "[Course] %s" % name
      # Create the course folder if it doesn't exist.
      if !Dir.exists?(path)
        puts " [+] %s folder does not exist, creating..." % name
        Dir.mkdir(path)
      else
        puts " [+] %s folder exists, continuing..." % name
      end
      # Start to download the attachment.
      client.get_course_data(name, course["id"].to_s)
      puts ""
    end
    puts "[+] Finished downloading courses for #{bb_username}"
  end
end

BlackBoard::Dl.run

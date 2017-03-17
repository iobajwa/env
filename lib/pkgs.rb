
[ 
  "packages\\package_worker"
].each {|req| require "#{File.expand_path(File.dirname(__FILE__))}/#{req}"}

class Packages

    def initialize(command)
        defaults_file = File.dirname(__FILE__) + "/packages/defaults.yaml"
        worker = PackageWorker.new defaults_file 

        if command == "install"
            worker.deploy_packages
        elsif command == "lock"
            worker.lock_packages
        elsif command == "clean"
            worker.clean
        elsif command == "update"
            worker.update_packages
        else
            worker.new_package_list
        end

        puts "Done."
    end



  # Command Line Support ###############################
	
  if ($0 == __FILE__)
      valid_commands = ["install", "lock", "clean", "update"]
      ENV['CD']      = Dir.pwd

      if ARGV.length == 0 || ARGV.length > 1 || !valid_commands.include?(ARGV[0])
          if ARGV[0] != "?"
            puts "Invalid argument" + (ARGV.length > 1 ? "s." : ".") unless ARGV.length == 0
          end
          puts "Usage:\n" + 
               # "new     : setups the project to use default packages\n" +
               "install : pulls in the specified packages from their repos\n" +
               "clean   : deletes all deployed packages\n" +
               "lock    : locks packages configured for bleeding edge versions to the deployed\n" +
               "          revisions\n" + 
               "update  : updates all packages to their latest versions and locks the\n" +
               "          non-bleeding versions"
               # "check_updates : polls the package repos to see if their are any updates available"
          exit 1
      end

      begin
          Packages.new(ARGV[0])
      rescue ToolException => ex
          puts ex
          exit 1
      rescue ToolMessage => ex
          puts ex
          exit 0
      rescue Interrupt => ex
          puts "aborting.."
          exit 0
      end
  end

end


[ 
  "packages\\package_worker"
].each {|req| require "#{File.expand_path(File.dirname(__FILE__))}/#{req}"}

class Packages

    def initialize(command)
        defaults_file = File.dirname(__FILE__) + "/packages/defaults.yaml"
        worker = PackageWorker.new defaults_file 

        if command == "deploy"
            worker.deploy_packages
        elsif command == "lock"
            worker.lock_packages
        elsif command == "clean"
            worker.clean
        else
            worker.new_package_list
        end

        puts "Done."
    end



  # Command Line Support ###############################
	
  if ($0 == __FILE__)
      valid_commands = ["new", "deploy", "lock", "clean"]
      ENV['CD']      = Dir.pwd

      if ARGV.length == 0 || ARGV.length > 1 || !valid_commands.include?(ARGV[0])
          puts "Invalid argument" + (ARGV.length > 1 ? "s." : ".") unless ARGV.length == 0
          puts "Usage:\n" + 
               "new     : setups the project to use default packages\n" +
               "deploy  : pulls in the specified packages from their repos\n" +
               "lock    : locks packages configured for bleeding edge versions to the deployed\n" +
               "          revisions\n"
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

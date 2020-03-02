
[ 
  "packages\\package_worker"
].each {|req| require "#{File.expand_path(File.dirname(__FILE__))}/#{req}"}

class Packages

    def initialize command, args
        worker = PackageWorker.new

        if command == "install"
            worker.deploy_packages
        elsif command == "lock"
            worker.lock_packages
        elsif command == "clean"
            worker.clean
        elsif command == "update"
            worker.update_packages args
        elsif command == "remote-update"
            worker.gen_remote_update_scripts
        end

        puts "Done."
    end



  # Command Line Support ###############################
	
  if ($0 == __FILE__)
      valid_commands = ["install", "lock", "clean", "update", "remote-update"]
      ENV['CD']      = Dir.pwd

      if ARGV.length == 0 || !valid_commands.include?(ARGV[0])
          if ARGV[0] != "?"
            puts "Invalid argument" + (ARGV.length > 1 ? "s." : ".") unless ARGV.length == 0
          end
          puts "Usage:\n" + 
               # "new     : setups the project to use default packages\n" +
               "install    : pulls in the specified packages from their repos\n" +
               "clean      : deletes all deployed packages\n" +
               "lock       : locks packages configured for bleeding edge versions to the deployed\n" +
               "             revisions\n" + 
               "update [p] : updates specified package (or all packages, if [p] not specified) to it's\n" +
               "             latest versions and locks the non-bleeding versions\n" +
               "remote-update : generates a batch-file to update all repo snapshots"
               # "check_updates : polls the package repos to see if their are any updates available"
          exit 1
      end

      begin
          Packages.new(ARGV.shift, ARGV)
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

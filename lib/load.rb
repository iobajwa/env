=begin
	starts a new shell session for the passed embedded project and prepares the environment.
=end
[ 
  "packages/exceptions.rb"
].each {|req| require "#{File.expand_path(File.dirname(__FILE__))}/#{req}"}
require "tempfile"

def create_project_path base_path, project_name
	return "#{base_path}/#{project_name}"
end

def find_env_file path
	["paths.txt", "env.txt"].each {  |f|
		env_file = File.join path, f
		return env_file if File.exist? env_file
	}
	return nil
end

def create_list_of_packages root
	return {} unless Dir.exist? root
	available_packages = Dir.entries("#{root}").select {  |entry| File.directory? File.join("#{root}",entry) and !(entry =='.' || entry == '..') }
	packages = {}
	available_packages.each {  |p|
		path     = File.join root, p
		env_file = find_env_file path
		packages[p] = { :path => path, :env_file => env_file }
	}

	return packages
end

if ($0 == __FILE__)
	begin
		raise ToolException.new "project?" if ARGV.length == 0
		raise ToolException.new "only 1 project at a time please." if ARGV.length > 1

		project_name = ARGV[0]
		project_root = create_project_path "d:/dev", project_name
		raise ToolException.new "'#{project_name}' does not exists!" unless Dir.exist?(project_root)

		# make a list of packages
		packages_folder = File.join project_root, "build/packages"
		packages = create_list_of_packages packages_folder

		# create the boostrapper file
		bootstraper_file = Tempfile.new ['bootstrap', '.bat']
		bootstraper_file.write "d:\n"
		bootstraper_file.write "cd /\n"
		bootstraper_file.write "cd #{project_root}\n"
		bootstraper_file.write "title #{project_name}\n"
		bootstraper_file.write "cls\n"
		# bootstraper_file.write "echo No packages available in #{packages_folder}. Probably a 'pkgs deploy' is required."  if packages == {}
		bootstraper_file.write "environment.bat\n"
		bootstraper_file.close
		
		# build the command line
		cmd_line = "cmd.exe /k #{bootstraper_file.path}"

		# paths discovered from each package
		project_paths = "#{project_root};"
		packages.each {  |name, prop|
			File.readlines("#{prop[:env_file]}").each {  |l| project_paths += "#{l.strip};" } if prop[:env_file]         # presently we only support absolute paths
		}

		paths = "#{project_paths}"
		paths += ENV['PATH']
		exec({"PATH" => paths, "CD" => project_root, "PROJECT_PATHS" => project_paths }, cmd_line)
		exit
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

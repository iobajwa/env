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

def create_list_of_packages root
	return {} unless Dir.exist? root
	available_packages = Dir.entries("#{root}").select {  |entry| File.directory? File.join("#{root}",entry) and !(entry =='.' || entry == '..') }
	packages = {}
	available_packages.each {  |p|
		path = File.join root, p
		path_file = File.join path, "paths.txt"
		path_file = nil unless File.exist? path_file
		packages[p] = { :path => path, :path_file => path_file }
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

		# add the available paths exported by packages
		scripts_path = ""
		packages.each {  |name, prop|
			File.readlines("#{prop[:path_file]}").each {  |l| scripts_path += "#{l.strip};" } if prop[:path_file]         # presently we only support absolute paths
		}

		paths = "#{project_root};"
		paths += "#{scripts_path}" unless scripts_path == ""
		paths += ENV['PATH']
		exec({"PATH" => paths, "CD" => project_root }, cmd_line)
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


[
	"exceptions",
].each {|req| require "#{File.expand_path(File.dirname(__FILE__))}/#{req}"}
require "yaml"
require "erb"
require "fileutils"

class PackageWorker

	attr_accessor :defaults

	def initialize(settings_file=nil)
		@defaults = {}

		if settings_file
			@defaults = YAML.load (ERB.new File.read(settings_file)).result
		end
	end

	# removes the 'packages' folder altogether
	def clean
		packages_folder = @defaults[:package_dump]
		FileUtils.rm_r packages_folder if Dir.exist? packages_folder
	end


	# deploys packages to the project folder
	def deploy_packages
		
		file, packages = find_and_load_packages_from_package_file

		outdated_packages = get_list_of_outdated_packages packages
		raise ToolMessage.new "all packages are up-to-date." if outdated_packages.length == 0
		
		outdated_packages.each_pair {  |name, properties| puts "package '#{name}' is outdated." }
		download_packages outdated_packages, @defaults[:version_file_name]
		install_packages outdated_packages

		length = outdated_packages.length
		status = "deployed #{outdated_packages.length} package"
		status += length > 1 ? "s." : "."
		puts status
	end


	# locks the packages configured for bleeding-edge versions in the .package file
	# to the specific revision number of the deployed package (provided it has been
	# deployed)
	def lock_packages
		file, packages = find_and_load_packages_from_package_file

		bleeding_packages = get_list_of_packages_configured_for_bleeding_edge_versions packages
		raise ToolMessage.new "no packages to lock." if bleeding_packages.length == 0

		deployed_packages = get_list_of_deployed_packages bleeding_packages
		raise ToolException.new "Packages must first be deployed atleast once before using the lock command.\nThere are #{bleeding_packages.length} packages configured for bleeding edge out of which #{deployed_packages.length} are deployed." if bleeding_packages.length != deployed_packages.length

		update_package_file file, deployed_packages
	end


	# unlocks the passed packages locked earlier
	def unlock_packages(pkgs_to_unlock)

		file, packages = find_and_load_packages_from_package_file
		locked_packages = get_list_of_locked_packages packages
		pkgs_to_unlock = locked_packages if pkgs_to_unlock == nil || pkgs_to_unlock == []
		raise ToolMessage.new "no packages to unlock." if locked_packages.length == packages.length

		unlocked_pkgs = unlock_locked_packages locked_packages, pkgs_to_unlock

		write_packages_to_file file, unlocked_pkgs
	end





	####################################################################
	def find_package_file(paths, packages_file)
		file = nil
		
		paths.each {  |p|
			next unless p
			file = p + packages_file
			break if File.exist? file
			file = nil
		} if paths

		return file
	end

	def load_package_file(file)
		packages = {}
		lines = File.readlines file
		lines.each {  |line| packages.merge! parse_package_from_string line }

		return packages
	end

	def find_and_load_packages_from_package_file
		file = find_package_file @defaults[:default_look_up_paths], @defaults[:project_package_file]
		raise ToolException.new "Could not locate the project.packages file." unless file

		packages = load_package_file file
		raise ToolMessage.new "There are no package dependencies!" if packages.length == 0

		return file, packages
	end

	def get_list_of_outdated_packages(packages)
		outdated_packages = {}
		packages.each_pair {  |name, properties|
			version_deployed = get_version_of_deployed_package name, properties[:dump_at], @defaults[:version_file_name]
			version_in_repo  = get_version_of_package_in_repo name, properties
			next if version_deployed == version_in_repo
			properties[:r] = version_in_repo if pkg_configured_for_bleeding_edge_updates( properties )
			outdated_packages[name] = properties
		}

		return outdated_packages
	end

	def download_packages(packages, version_file)
		Dir.mkdir @defaults[:package_dump] unless Dir.exist? @defaults[:package_dump]
		packages.each_pair {  |name, properties|
			write_status_message "downloading package", name, properties

			output_dir = properties[:dump_at]
			FileUtils.rm_r output_dir if Dir.exist? output_dir
			repo_type = properties[:repo_type]

			output, exit_code = nil
			if repo_type == :svn
				pkg_full_path = File.join properties[:repo], properties[:located_at]
				svn_command = "svn export "
				svn_command += "-r #{properties[:r]} " if properties.include?(:r)
				svn_command += "#{pkg_full_path} #{output_dir}"
				output, exit_code = execute_command svn_command
			else
				old_wd = Dir.getwd
				FileUtils.mkdir output_dir
				begin
					Dir.chdir(properties[:repo])
					zip_file = File.join(output_dir, "package.zip")
					branch = "master"
					branch = properties[:v] if properties.include?(:v)
					branch = properties[:r] if properties.include?(:r)
					git_command = "git archive #{branch} --format zip --output \"#{zip_file}\" -0"
					output, exit_code = execute_command git_command
				rescue
					Dir.chdir old_wd
				end
			end

			raise ToolException.new "package download failed. #{repo_type.to_s.upcase} output: #{output}" if exit_code != 0

			if repo_type == :git
				unzip_package zip_file, properties[:located_at], properties[:dump_at]
				File.delete zip_file
			end

			specific_version = properties[:r] if properties.include?(:r)
			specific_version = properties[:v] if properties.include?(:v)
			next unless specific_version

			version_file_full_path = File.join properties[:dump_at], version_file
			File.write version_file_full_path, "#{specific_version}"
		}
	end

	def unzip_package(zip_file, relative_path, destination_path)
		require "zip"

		Zip::File.open(zip_file) {  |zip_file|
			zip_file.each {  |f|
				next unless f.name.start_with? relative_path
				name = f.name[relative_path.length..f.name.length]
				next if name == "" || name == "/" || name == "\\"
				f_path = File.join(destination_path, name)
				FileUtils.mkdir_p(File.dirname(f_path))
				zip_file.extract(f, f_path) unless File.exist?(f_path)
		   }
		}
	end

	def install_packages(packages)
		packages.each_pair{  |name, properties|
			installer = properties[:installer]
			next unless installer
			artifacts_root = properties[:dump_at]
			installer = File.join properties[:dump_at], properties[:installer]
			next unless File.exist? installer

			write_status_message "installing package", name, properties
			require 'open3'

			log = File.new("#{artifacts_root}/installation.log", "w+")
			command = "#{installer} \"#{artifacts_root}\""

			Open3.popen3(command) do |stdin, stdout, stderr|
			     log.puts "[OUTPUT]:\n#{stdout.read}\n"
			     unless (err = stderr.read).empty? then 
			         log.puts "[ERROR]:\n#{err}\n"
			     end
			end
			# output = output.split("\n")
			# output = [output] unless output.class == Array
			# exit_code = $?.exitstatus
			# output, exit_code = execute_command installer
			# raise ToolException.new "package installation failed: #{output}" unless exit_code == 0
		}
	end



	# helpers
	def parse_package_from_string(raw)
		elements = raw.split("--").map(&:strip)
		pkg_name = elements.shift
		pkg_name.strip! unless pkg_name
		raise ToolException.new("Invalid package name: '#{pkg_name}'.") if pkg_name == nil || pkg_name.include?(' ')
		pkg_name = pkg_name.to_sym
		package_properties = parse_package_properties pkg_name, elements

		known_package_properties = @defaults[:known_packages].include?(pkg_name) ? @defaults[:known_packages][pkg_name] : {} 
		repo_type = known_package_properties[:repo_type]
		repo_type = @defaults[:default_repo_type] if repo_type == nil

		default_installer = known_package_properties.include?(:installer) ? known_package_properties[:installer] : @defaults[:default_package_installer]
		default_location  = known_package_properties.include?(:located_at) ? known_package_properties[:located_at] : @defaults[:default_package_location]
		default_dump_at   = @defaults[:package_dump]
		default_dump_at   = File.join(default_dump_at, pkg_name.to_s)
		package_repo      = known_package_properties.include?(:repo) ? known_package_properties[:repo] : package_properties[:repo]

		if repo_type == :svn
			default_server = @defaults[:svn_server_address]
			package_repo = File.join(default_server, "#{pkg_name}") unless package_repo
			deep_path = package_properties.include?(:v) ? "tags/#{package_properties[:v]}" : "trunk"
			package_repo = File.join(package_repo, deep_path)
		elsif repo_type == :git
			default_server    = @defaults[:git_server_address]
		else
			raise ToolException.new "'#{repo_type}' repos are not supported (package: '#{pkg_name}')."
		end

		package_repo = File.join(default_server, "#{pkg_name}") unless package_repo
		package_properties[:repo]       = package_repo
		package_properties[:dump_at]    = default_dump_at unless package_properties.include?(:dump_at)
		package_properties[:installer]  = default_installer unless package_properties.include?(:installer)
		package_properties[:located_at] = default_location unless package_properties.include?(:located_at)
		package_properties[:repo_type]  = repo_type

		return { pkg_name => package_properties }
	end

	def get_version_of_deployed_package(name, path, version_file)
		version_file = File.join path, version_file
		return "" unless File.exist? version_file
		lines = File.readlines version_file
		return lines[0]
	end

	# if the package is configured for bleeding edge versions, 
	# 	the trunk is polled for the latest version and returned.
	# if the package is configured for specific revision (of trunk, or tag), 
	#	the revision number is returned as-is.
	def get_version_of_package_in_repo(name, properties)
		return properties[:v] if properties.include?(:v)
		return properties[:r] if properties.include?(:r)

		puts "polling for latest version of '#{name}'.."
		repo_type = properties[:repo_type]
		if repo_type == :svn
			output, exit_code = execute_command "svn info -rHead #{properties[:repo]}"
			revision = nil
			output.each {  |line|
				next unless line.start_with?("Revision:")
				revision = line.gsub('Revision:', '').strip
				break
			} if exit_code == 0
			raise ToolException.new("failed to receive correct version. SVN output: #{output}") unless revision
		else
			old_wd = Dir.getwd
			Dir.chdir properties[:repo]
			begin				
				output, exit_code = execute_command "git log -n 1 master --pretty=format:\"%H\""
				revision = output[0] if exit_code == 0
			rescue Exception => e
				Dir.chdir old_wd
			end
		end
		return revision
	end

	def execute_command(command)
		# system command
		# return [], $?
		output = `#{command}`
		output = output.split("\n")
		output = [output] unless output.class == Array
		return output, $?.exitstatus
	end

	def write_status_message(message, name, properties)
		status_string = "#{message} '#{name}'"
		status_string += " v #{properties[:v]}" if properties.include?(:v)
		status_string += " r #{properties[:r]}" if properties.include?(:r)
		status_string += ".."
		puts status_string
	end

	def get_list_of_packages_configured_for_bleeding_edge_versions(packages)
		found_packages = {}

		packages.each_pair {  |name, attributes|
			next if attributes.include?(:v) || attributes.include?(:r)
			found_packages[name] = attributes
		}

		return found_packages
	end

	def get_list_of_deployed_packages(packages)
		found_packages = {}
		
		packages.each_pair {  |name, attributes|
			version = get_version_of_deployed_package name, attributes[:dump_at], @defaults[:version_file_name]
			next if version == ""
			attributes[:read_version] = version
			found_packages[name] = attributes
		}

		return found_packages
	end

	def update_package_file(file, packages_to_update)
		lines = File.readlines file
		updated_lines = []
		lines.each {  |line|
			pkg = parse_package_from_string line
			pkg_name = pkg.keys[0]
		 	if packages_to_update.include? pkg_name
		 		updated_lines.push package_to_string( pkg_name.to_s, packages_to_update[pkg_name] )
		 	else
				updated_lines.push line
		 	end
		}

		f = File.new(file, "w")
		updated_lines.each {  |l| f.write l + "\n" }
		f.close
	end

	def package_to_string(pkg_name, attributes)
		if attributes.include?(:read_version) || attributes.include?(:r)
			revision = attributes.include?(:read_version) ? attributes[:read_version] : attributes[:r]
			return pkg_name + " --r = " + revision
		elsif attributes.include?(:v)
			return pkg_name + " --v = " + attributes[:v]
		else
			return pkg_name
		end
	end



	def get_list_of_locked_packages(packages)
		puts "packages are '#{packages}'"
	end



	private
	def parse_package_properties(name, elements)
		known_flags        = ['v', 'located_at', 'installer', 'repo', 'r']
		package_properties = {}

		elements.each {  |e|
			key_value_elements = e.split("=").map(&:strip)
			key   = key_value_elements.shift
			value = ""
			if key_value_elements.class == Array then
				key_value_elements.each {|el| value += el + "="}
			else
				value = key_value_elements
			end
			value = value.chop.strip
			raise ToolException.new("Package '#{name}': '#{key}' switch is not recoganized.") unless known_flags.include?(key)
			package_properties[key.to_sym] = value
		}
		return package_properties
	end

	def pkg_configured_for_bleeding_edge_updates(properties)
		return !(properties.include?(:r) || properties.include?(:v))
	end
end

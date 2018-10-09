
[
	"exceptions",
].each {|req| require "#{File.expand_path(File.dirname(__FILE__))}/#{req}"}
require "fileutils"
require "zip"

class PackageWorker

	attr_accessor :defaults

	@@defaults = {
		:possible_package_installers => [ "unpack.bat", "unpack.rb", "unpack.py", "install.bat", "install.rb", "install.py" ],
		:possible_package_locations => [ "package/", "content/" ],
		:possible_packages_files => [ "pkgs.lock", "project.packages.lock", "project.pkgs.lock", "project.packages", "project.pkgs", ".packages", ".pkgs", ".pkgs.lock" ],
		:default_pkgs_lock_look_up_paths => [ ENV["ProjectRoot"], ENV["CD"] ],
		:version_file_name => "version.lock",
		:default_repo_type => :git,
		:known_packages => [],
		:package_dump => nil,
		:git_server_address => ENV["GIT_SERVER"],
		:svn_server_address => ENV["SVN_SERVER"],
	}

	# removes the 'packages' folder altogether
	def clean
		load_defaults
		packages_folder = @defaults[:package_dump]
		FileUtils.rm_r packages_folder if Dir.exist? packages_folder
	end


	def update_packages
		load_defaults
		file, packages = find_and_load_packages_from_package_file

		outdated_packages, remaining_packages = get_list_of_outdated_packages packages, true
		raise ToolMessage.new "all packages are up-to-date." if outdated_packages.length == 0

		outdated_packages.each_pair {  |name, properties| puts "package '#{name}' is outdated." }
		download_packages outdated_packages, @defaults[:version_file_name]
		install_packages outdated_packages

		all_packages = remaining_packages.merge outdated_packages
		update_package_file file, all_packages

		length = outdated_packages.length
		status = "updated #{outdated_packages.length} package"
		status += length > 1 ? "s." : "."
		puts status
	end


	# deploys packages to the project folder
	def deploy_packages
		load_defaults
		file, packages = find_and_load_packages_from_package_file

		outdated_packages, remaining_packages = get_list_of_outdated_packages packages
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
		load_defaults
		file, packages = find_and_load_packages_from_package_file

		bleeding_packages = get_list_of_packages_configured_for_bleeding_edge_versions packages
		raise ToolMessage.new "already locked." if bleeding_packages.length == 0

		deployed_packages = get_list_of_deployed_packages bleeding_packages
		raise ToolException.new "All packages must first be installed before using the lock command.\n#{bleeding_packages.length} package(s) await installation." if bleeding_packages.length != deployed_packages.length

		update_package_file file, deployed_packages
	end


	# unlocks the passed packages locked earlier
	def unlock_packages pkgs_to_unlock
		load_defaults
		file, packages = find_and_load_packages_from_package_file
		locked_packages = get_list_of_locked_packages packages
		pkgs_to_unlock = locked_packages if pkgs_to_unlock == nil || pkgs_to_unlock == []
		raise ToolMessage.new "no packages to unlock." if locked_packages.length == packages.length

		unlocked_pkgs = unlock_locked_packages locked_packages, pkgs_to_unlock

		write_packages_to_file file, unlocked_pkgs
	end


	# generates a .batch file which can be invoked to update all remote git repositories
	def gen_remote_update_scripts
		repo_root = @@defaults[:git_server_address]
		raise ToolException.new "repo-root does not exists ('#{repo_root}')" unless Dir.exist? repo_root

		# create a list of all git-repos
		dirs = Dir.entries("#{repo_root}").select { |e| File.directory? File.join(repo_root, e) and !(e =='.' || e == '..') }
		found_repos = []
		dirs.each { |d| 
			path = File.join repo_root, d
			next unless Dir.exist? "#{path}/.git" or File.exist? "#{path}/config"
			found_repos.push path.gsub('\\', '/')
		}

		return unless found_repos.length > 0
		code = []
		found_repos.each { |r| code.push "cd #{r}", "git fetch origin master:master" }
		f = File.new "remote-update.bat", "w"
		f.puts code
		f.close
	end





	####################################################################

	def load_defaults
		@defaults = @@defaults
		@defaults[:package_dump] =
		if ENV["PackagesRoot"]
			ENV["PackagesRoot"]
		elsif ENV["ArtifactsRoot"]
			ENV["ArtifactsRoot"]
		else
			raise ToolException.new "Fatal Error: no place to call home.. err.."
		end
	end

	def find_package_file paths, possible_packages_files
		file = nil
		
		paths.each {  |p|
			next unless p
			possible_packages_files.each {  |pkgs_file|
				file = p + pkgs_file
				break if File.exist? file
				file = nil
			} if possible_packages_files
		} if paths

		return file
	end

	def load_package_file(file)
		packages = {}
		lines = File.readlines file
		lines.each {  |line|
			next if line.strip == ""
			packages.merge! parse_package_from_string line 
		}

		return packages
	end

	def find_and_load_packages_from_package_file
		file = find_package_file @defaults[:default_pkgs_lock_look_up_paths], @defaults[:possible_packages_files]
		raise ToolException.new "Could not locate the pkgs lock file." unless file

		packages = load_package_file file
		raise ToolMessage.new "There are no package dependencies!" if packages.length == 0

		return file, packages
	end

	def get_list_of_outdated_packages packages, ignore_versions=false
		outdated_packages = {}
		remaining_packages = {}
		packages.each_pair {  |name, properties|
			version_deployed = get_version_of_deployed_package name, properties[:dump_at], @defaults[:version_file_name]
			version_in_repo  = get_version_of_package_in_repo name, properties, ignore_versions
			if version_deployed == version_in_repo
				remaining_packages[name] = properties
			else
				properties[:r] = version_in_repo if ignore_versions || pkg_configured_for_bleeding_edge_updates( properties )
				outdated_packages[name] = properties
			end
		}

		return outdated_packages, remaining_packages
	end

	def download_packages packages, version_file
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
				folder_to_extract = properties[:located_at]
				unzip_package zip_file, folder_to_extract, properties[:dump_at]
				File.delete zip_file
			end

			specific_version = properties[:r] if properties.include?(:r)
			specific_version = properties[:v] if properties.include?(:v)
			next unless specific_version

			version_file_full_path = File.join properties[:dump_at], version_file
			File.write version_file_full_path, "#{specific_version}"
		}
	end

	def unzip_package(zip_file, relative_paths, destination_path)

		Zip::File.open(zip_file) {  |zip_file|

			# determine if it contains the 'relative package dir' and if yes then which one
			relative_path = find_location zip_file, relative_paths

			zip_file.each {  |f|
				if relative_path
					next unless f != '' and f.name.start_with? relative_path
					name = f.name[relative_path.length..f.name.length]
					next if name == "" || name == "/" || name == "\\"
				else
					name = f.name
				end
				f_path = File.join(destination_path, name)
				FileUtils.mkdir_p(File.dirname(f_path))
				zip_file.extract(f, f_path) unless File.exist? f_path
			}
		}

	end

	def install_packages(packages)

		packages.each_pair{  |name, properties|
			possible_installers = properties[:installer]
			next unless possible_installers
			artifacts_root = properties[:dump_at]

			installer_exists = false
			possible_installers.each {  |installer|
				installer = File.join properties[:dump_at], installer
				installer_exists = File.exist? installer

				if installer_exists
					write_status_message "installing package", name, properties
					require 'open3'

					log = File.new("#{artifacts_root}/installation.log", "w+")
					command = "#{installer} \"#{artifacts_root}\""

					Open3.popen3(command) do |stdin, stdout, stderr|
						log.puts "[OUTPUT]:\n#{stdout.read}\n"
						unless (err = stderr.read).empty?
							write_status_message "error installing package", name, properties
							log.puts "[ERROR]:\n#{err}\n"
						end
					end
					break
				end
			}

			write_status_message "no installer found for", name, properties unless installer_exists
			# output = output.split("\n")
			# output = [output] unless output.class == Array
			# exit_code = $?.exitstatus
			# output, exit_code = execute_command installer
			# raise ToolException.new "package installation failed: #{output}" unless exit_code == 0
		}
	end



	# helpers
	def find_location zip, relative_paths
		path = nil
		zip.each { |f|
			relative_paths.each { |p| return p if f.name.start_with? p }
		}
		return path
	end

	def parse_package_from_string raw
		elements = raw.split("--").map(&:strip)
		pkg_name = elements.shift
		pkg_name.strip! unless pkg_name
		raise ToolException.new("Invalid package name: '#{pkg_name}'.") if pkg_name == nil || pkg_name.include?(' ')
		pkg_name = pkg_name.to_sym
		package_properties = parse_package_properties pkg_name, elements

		known_package_properties = @defaults[:known_packages].include?(pkg_name) ? @defaults[:known_packages][pkg_name] : {} 
		repo_type = known_package_properties[:repo_type]
		repo_type = @defaults[:default_repo_type] if repo_type == nil

		default_installer = known_package_properties.include?(:installer) ? known_package_properties[:installer] : @defaults[:possible_package_installers]
		default_location  = known_package_properties.include?(:located_at) ? known_package_properties[:located_at] : @defaults[:possible_package_locations]
		default_dump_at   = @defaults[:package_dump]
		default_dump_at   = File.join(default_dump_at, pkg_name.to_s)
		package_repo      = known_package_properties.include?(:repo) ? known_package_properties[:repo] : package_properties[:repo]

		if repo_type == :svn
			default_server = @defaults[:svn_server_address]
			package_repo = File.join(default_server, "#{pkg_name}") unless package_repo
			deep_path = package_properties.include?(:v) ? "tags/#{package_properties[:v]}" : "trunk"
			package_repo = File.join(package_repo, deep_path)
		elsif repo_type == :git
			default_server = @defaults[:git_server_address]
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
	# 	the trunk/master is polled for the latest version and returned.
	# if the package is configured for specific revision (of trunk, or tag), 
	#	the revision number is returned as-is.
	def get_version_of_package_in_repo(name, properties, ignore_versions=false)
		unless ignore_versions
			return properties[:v] if properties.include?(:v)
			return properties[:r] if properties.include?(:r)
		end

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

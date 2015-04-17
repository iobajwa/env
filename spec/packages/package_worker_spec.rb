
require "spec_helper"
require "packages\\package_worker"
require "packages\\exceptions"

describe PackageWorker do

	describe "when creating a new instance" do
		it "loads the default configuration from the passed file" do
			dummy_config = { :a => :b }
			expect(File).to receive(:read).with('dummy').and_return('file contents')
			dummy_erb = { 1 => 0 }
			expect(ERB).to receive(:new).with('file contents').and_return(dummy_erb)
			expect(dummy_erb).to receive(:result).and_return('balle!')
			expect(YAML).to receive(:load).with('balle!').and_return( dummy_config )

			worker = PackageWorker.new('dummy')

			worker.defaults.should be == dummy_config
		end
	end

	###############
	describe "when deploying packages" do
		before(:each) do
			$worker = PackageWorker.new
			$dummy_paths = [1, 2]
			$dummy_file = "abc"
			$dummy_version_file = "v.ersion"
			$worker.defaults[:default_look_up_paths] = $dummy_paths
			$worker.defaults[:project_package_file] = $dummy_file
			$worker.defaults[:version_file_name] = $dummy_version_file
		end
		
		describe "raises tool message when" do
			it "all packages are up-to-date" do
				dummy_packages = { :many => :packages }
				expect($worker).to receive(:find_and_load_packages_from_package_file).and_return(['fancy_file', dummy_packages])
				expect($worker).to receive(:get_list_of_outdated_packages).with(dummy_packages).and_return( {} )
				
				expect {
					$worker.deploy_packages
				}.to raise_error(ToolMessage, "all packages are up-to-date.")
			end
		end

		it "deploys all outdated packages" do
			dummy_packages          = { :many => :packages }
			dummy_outdated_packages = { :outdated => :packages }
			expect($worker).to receive(:find_and_load_packages_from_package_file).and_return(['fancy_file', dummy_packages])
			expect($worker).to receive(:get_list_of_outdated_packages).with(dummy_packages).and_return( dummy_outdated_packages )
			expect($worker).to receive(:download_packages).with(dummy_outdated_packages, $dummy_version_file)
			expect($worker).to receive(:install_packages).with(dummy_outdated_packages)
			expect($worker).to receive(:puts).with("package 'outdated' is outdated.")
			expect($worker).to receive(:puts).with("deployed 1 package.")
			
			$worker.deploy_packages
		end
	end

	describe "when looking for packages file" do
		before(:each) do
			$worker = PackageWorker.new
		end

		it "returns nil when it could not find the file in the passed paths" do
			found_file = $worker.find_package_file(nil, "package.file")
			found_file.should be_nil

			found_file = $worker.find_package_file([], "package.file")
			found_file.should be_nil

			expect(File).to receive(:exist?).with("one/package.file").and_return(false)
			expect(File).to receive(:exist?).with("two/package.file").and_return(false)
			found_file = $worker.find_package_file(["one/", "two/", nil], "package.file")
			found_file.should be_nil
		end
	end

	describe "when loading the packages file" do
		before(:each) do
			$worker = PackageWorker.new
			$worker.defaults[:project_package_file] = "package.file"
		end

		it "merges packages read from parse_package_from_string and returns the collection" do
			expect(File).to receive(:readlines).and_return( ['one', 'two'] )
			expect($worker).to receive(:parse_package_from_string).with('one').and_return( {1 => 0} )
			expect($worker).to receive(:parse_package_from_string).with('two').and_return( {2 => 0} )

			packages = $worker.load_package_file('fancy')

			packages.should be == { 1 => 0, 2 => 0}
		end
	end

	describe "when finding and loading package files in a single go" do
		before(:each) do
			$worker = PackageWorker.new
			$worker.defaults[:project_package_file] = "file"
			$worker.defaults[:default_look_up_paths] = 'paths'
		end
		it "raises error when packages file could not be located" do
			expect($worker).to receive(:find_package_file).with('paths', 'file').and_return(nil)
			expect {
				$worker.find_and_load_packages_from_package_file
			}.to raise_error(ToolException, "Could not locate the project.packages file.")
		end
		it "displays message when there are no package dependencies" do
			expect($worker).to receive(:find_package_file).with('paths', 'file').and_return(1)
			expect($worker).to receive(:load_package_file).with(1).and_return([])
			expect {
				$worker.find_and_load_packages_from_package_file
			}.to raise_error(ToolMessage, "There are no package dependencies!")
		end
		it "returns valid file and packages otherwise" do
			expect($worker).to receive(:find_package_file).with('paths', 'file').and_return(1)
			expect($worker).to receive(:load_package_file).with(1).and_return([2])
			
			file, packages = $worker.find_and_load_packages_from_package_file

			file.should be     == 1
			packages.should be == [2]
		end
	end

	describe "when parsing the package from string" do
		before(:each) do
			$worker = PackageWorker.new
			$worker.defaults[:svn_server_address] = "svn_server/"
			$worker.defaults[:git_server_address] = "git_server/"
			$worker.defaults[:package_dump] = "dump_here/"
			$worker.defaults[:default_package_installer] = "default_installer.rb"
			$worker.defaults[:default_package_location] = "default_location"
			$worker.defaults[:known_packages] = {}
			$worker.defaults[:default_repo_type] = :svn
		end

		describe "raises error when" do
			it "the name is invalid" do
				expect { $worker.parse_package_from_string('name with spaces') }.to raise_error(ToolException, "Invalid package name: 'name with spaces'.")
			end

			it "contains invalid flag" do
				expect { $worker.parse_package_from_string('name --some_flag') }.to raise_error(ToolException, "Package 'name': 'some_flag' switch is not recoganized.")
				expect { $worker.parse_package_from_string('name --some_switch = value') }.to raise_error(ToolException, "Package 'name': 'some_switch' switch is not recoganized.")
			end
		end

		describe "returns valid package information when" do
			describe "repo type is svn" do
				it "only package name has been provided" do
					expected_package = { :some_package => 
						{
							:repo => "svn_server/some_package/trunk",
							:dump_at => "dump_here/some_package",
							:located_at => "default_location",
							:installer => "default_installer.rb",
							:repo_type => :svn
						} 
					}
					
					parsed_package = $worker.parse_package_from_string "some_package"

					parsed_package.should be == expected_package
				end

				it "package name and other properties have been provided" do
					expected_package = { :some_package => 
						{
							:v => "1.23",
							:repo => "svn_server/some_package/tags/1.23",
							:dump_at => "dump_here/some_package",
							:located_at => "here",
							:installer => "fancy_installer.rb",
							:repo_type => :svn
						} 
					}
					
					parsed_package = $worker.parse_package_from_string "some_package  -- v = 1.23   -- installer = fancy_installer.rb   -- located_at = here"

					parsed_package.should be == expected_package
				end

				it "package is a known package and user has provided only some of the properties, defaults are used for others" do
					$worker.defaults[:known_packages] = { :some_package => 
						{
							:repo => "some_other_server/fancy_repo",
							:located_at => "default_location/",
							:installer => "custom_installer.rb",
						}
					}
					expected_package = { :some_package => 
						{
							:v => "1.23",
							:located_at => "here",
							:repo => "some_other_server/fancy_repo/tags/1.23",
							:dump_at => "dump_here/some_package",
							:installer => "custom_installer.rb",
							:repo_type => :svn
						} 
					}
					
					parsed_package = $worker.parse_package_from_string "some_package  -- v = 1.23   -- located_at = here"

					parsed_package.should be == expected_package
				end
			end

			describe "repo type is git" do
				before(:each) do
					$worker.defaults[:default_repo_type] = :git
				end

				it "only package name has been provided" do
					expected_package = { :some_package => 
						{
							:repo => "git_server/some_package",
							:dump_at => "dump_here/some_package",
							:located_at => "default_location",
							:installer => "default_installer.rb",
							:repo_type => :git
						} 
					}
					
					parsed_package = $worker.parse_package_from_string "some_package"

					parsed_package.should be == expected_package
				end

				it "package name and other properties have been provided" do
					expected_package = { :some_package => 
						{
							:v => "1.23",
							:repo => "git_server/some_package",
							:dump_at => "dump_here/some_package",
							:located_at => "here",
							:installer => "fancy_installer.rb",
							:repo_type => :git
						} 
					}
					
					parsed_package = $worker.parse_package_from_string "some_package  -- v = 1.23   -- installer = fancy_installer.rb   -- located_at = here"

					parsed_package.should be == expected_package
				end

				it "package is a known package and user has provided only some of the properties, defaults are used for others" do
					$worker.defaults[:known_packages] = { :some_package => 
						{
							:repo => "some_other_server/fancy_repo",
							:located_at => "default_location/",
							:installer => "custom_installer.rb",
						}
					}
					expected_package = { :some_package => 
						{
							:v => "1.23",
							:located_at => "here",
							:repo => "some_other_server/fancy_repo",
							:dump_at => "dump_here/some_package",
							:installer => "custom_installer.rb",
							:repo_type => :git
						} 
					}
					
					parsed_package = $worker.parse_package_from_string "some_package  -- v = 1.23   -- located_at = here"

					parsed_package.should be == expected_package
				end
			end
		end
	end

	describe "when obtaining a list of outdated packages" do
		before(:each) do
			$worker = PackageWorker.new
			$worker.defaults[:version_file_name] = "version_file.txt"
		end

		it "returns empty when all packages are up-to-date" do
			dummy_packages = { :one => { :dump_at => "path1" }, :two => { :dump_at => "path2" } }
			expect($worker).to receive(:get_version_of_deployed_package).with(:one, "path1", "version_file.txt").and_return("1")
			expect($worker).to receive(:get_version_of_package_in_repo).with(:one, { :dump_at => "path1" }).and_return("1")
			expect($worker).to receive(:get_version_of_deployed_package).with(:two, "path2", "version_file.txt").and_return("2")
			expect($worker).to receive(:get_version_of_package_in_repo).with(:two, { :dump_at => "path2" }).and_return("2")
			filtered_packages = $worker.get_list_of_outdated_packages dummy_packages

			filtered_packages.should be_empty
		end

		it "returns empty when all packages are up-to-date" do
			dummy_packages = { :one => { :dump_at => "path1" }, :two => { :dump_at => "path2" }, :three => { :dump_at => "path3" }, }
			expect($worker).to receive(:get_version_of_deployed_package).with(:one, "path1", "version_file.txt").and_return("1")
			expect($worker).to receive(:get_version_of_package_in_repo).with(:one, { :dump_at => "path1" }).and_return("1.1")
			expect($worker).to receive(:get_version_of_deployed_package).with(:two, "path2", "version_file.txt").and_return("2")
			expect($worker).to receive(:get_version_of_package_in_repo).with(:two, { :dump_at => "path2" }).and_return("3")
			expect($worker).to receive(:get_version_of_deployed_package).with(:three, "path3", "version_file.txt").and_return("4")
			expect($worker).to receive(:get_version_of_package_in_repo).with(:three, { :dump_at => "path3" }).and_return("4")
			
			filtered_packages = $worker.get_list_of_outdated_packages dummy_packages

			filtered_packages.should be == { :one => { :dump_at => "path1", :r => "1.1"}, :two => { :dump_at => "path2", :r => "3" } }
		end

		describe "deployed_package.version" do
			it "returns 0 when the package version file does not exists" do
				expect(File).to receive(:exist?).with("path/version_file.txt").and_return(false)
				
				version_name = $worker.get_version_of_deployed_package(:fancy_name, "path", "version_file.txt")

				version_name.should be == ""
			end

			it "returns version info read from the version file" do
				expect(File).to receive(:exist?).with("path/version_file.txt").and_return(true)
				expect(File).to receive(:readlines).with("path/version_file.txt").and_return(['1.3', 'rest', 'are ignored'])
				
				version_name = $worker.get_version_of_deployed_package(:fancy_name, "path", "version_file.txt")

				version_name.should be == "1.3"
			end
		end

		describe "package_repo.version" do
			it "when the package is configured for specific rivision/versions returns the revision/version as-is" do
				version_received = $worker.get_version_of_package_in_repo :my_fancy_repo, { :v => "some version" }
				version_received.should be == "some version"

				version_received = $worker.get_version_of_package_in_repo :my_fancy_repo, { :r => "some version" }
				version_received.should be == "some version"
			end

			describe "when the package is configured for to bleeding edge revisions from the main trunk, should" do
				before(:each) do
					expect($worker).to receive(:puts).with("polling for latest version of 'my_fancy_repo'..")
				end

				describe "raises error when" do
					it "svn command fails" do
						expect($worker).to receive(:execute_command).with("svn info -rHead repo_address").and_return( [['some', 'output'], 0] )
						expect {
							$worker.get_version_of_package_in_repo :my_fancy_repo, { :repo => "repo_address", :repo_type => :svn }
						}.to raise_error(ToolException, 'failed to receive correct version. SVN output: ["some", "output"]')
					
					end

					it "svn command exits with a non-zero exit code" do
						expect($worker).to receive(:execute_command).with("svn info -rHead repo_address").and_return( [['some', 'output'], 4] )
						expect {
							$worker.get_version_of_package_in_repo :my_fancy_repo, { :repo => "repo_address", :repo_type => :svn }
						}.to raise_error(ToolException, 'failed to receive correct version. SVN output: ["some", "output"]')
					end
				end

				it "returns valid revision number otherwise" do
					expect($worker).to receive(:execute_command).with("svn info -rHead repo_address").and_return( [['some', 'output', 'Revision:   	some_fancy_revision	   '], 0] )

					version_received = $worker.get_version_of_package_in_repo :my_fancy_repo, { :repo => "repo_address", :repo_type => :svn }

					version_received.should be == "some_fancy_revision"
				end
			end
		end # package_repo.version
	end

	describe "when downloading" do
		before(:each) do
			$worker = PackageWorker.new
			$worker.defaults[:package_dump] = "dump here"
			expect(Dir).to receive(:exist?).with("dump here").and_return(false)
			expect(Dir).to receive(:mkdir).with("dump here")
		end

		describe "svn packages, it" do
			describe "raises error when" do
				it "svn command exists with a non-zero exit code" do
					dummy_packages = { :one => { :repo_type => :svn, :repo => "repo", :located_at => "loc1", :dump_at => "path 1", :v => "1.23" }, :two => { :repo => "", :dump_at => "path2" } }
					expect($worker).to receive(:puts).with("downloading package 'one' v 1.23..")
					expect($worker). to receive(:execute_command).with("svn export repo/loc1 path 1").and_return( [['some', 'output'], -12] )
					expect(Dir).to receive(:exist?).with("path 1").and_return(false)

					expect {
						$worker.download_packages dummy_packages, "file"
					}.to raise_error(ToolException, "package download failed. SVN output: [\"some\", \"output\"]")
				end
			end

			it "downloads each package otherwise" do
				dummy_packages = { :one   => { :repo => "repo", :repo_type => :svn, :located_at => "loc1", :dump_at => "path 1", :v => "1.23" }, 
								   :two   => { :repo => "repoB", :repo_type => :svn, :located_at => "loc2", :dump_at => "path 2", :r => "123" },
								   :three => { :repo => "repoC", :repo_type => :svn, :located_at => "loc3", :dump_at => "path 3" }, }
				expect($worker).to receive(:puts).with("downloading package 'one' v 1.23..")
				expect(Dir).to receive(:exist?).with('path 1').and_return(false)
				expect($worker).to receive(:execute_command).with("svn export repo/loc1 path 1").and_return( [['some'], 0] )
				expect($worker).to receive(:puts).with("downloading package 'two' r 123..")
				expect(Dir).to receive(:exist?).with('path 2').and_return(true)
				expect(FileUtils).to receive(:rm_r).with('path 2')
				expect($worker).to receive(:execute_command).with("svn export -r 123 repoB/loc2 path 2").and_return( [['output'], 0] )
				expect($worker).to receive(:puts).with("downloading package 'three'..")
				expect(Dir).to receive(:exist?).with('path 3').and_return(true)
				expect(FileUtils).to receive(:rm_r).with('path 3')
				expect($worker).to receive(:execute_command).with("svn export repoC/loc3 path 3").and_return( [['..'], 0] )
				expect(File).to receive(:write).with('path 1/version.file', "1.23")
				expect(File).to receive(:write).with('path 2/version.file', "123")

				$worker.download_packages dummy_packages, "version.file"
			end
		end

		describe "git packages, it" do
			describe "raises error when" do
				xit "git command exists with a non-zero exit code" do
					dummy_packages = { :one => { :repo => "repo", :repo_type => :git, :located_at => "loc1", :dump_at => "path 1", :v => "1.23" }, :two => { :repo => "", :dump_at => "path2" } }
					expect($worker).to receive(:puts).with("downloading package 'one' v 1.23..")
					expect(Dir).to receive(:chdir).with("repo")
					expect($worker).to receive(:execute_command).with("git archive 1.23 --format zip --output \"path 1/package.zip\" -0").and_return( [['some', 'output'], -12] )
					expect(Dir).to receive(:exist?).with("path 1").and_return(false)

					expect {
						$worker.download_packages dummy_packages, "file"
					}.to raise_error(ToolException, "package download failed. GIT output: [\"some\", \"output\"]")
				end
			end

			it "downloads each package otherwise" do
				dummy_packages = { :one   => { :repo => "repo", :repo_type => :git, :located_at => "loc1", :dump_at => "path 1", :v => "1.23" }, 
								   :two   => { :repo => "repoB", :repo_type => :git, :located_at => "loc2", :dump_at => "path 2", :r => "123" },
								   :three => { :repo => "repoC", :repo_type => :git, :located_at => "loc3", :dump_at => "path 3" }, }
				expect($worker).to receive(:puts).with("downloading package 'one' v 1.23..")
				expect(Dir).to receive(:exist?).with('path 1').and_return(false)
				expect(Dir).to receive(:chdir).with("repo")
				expect(FileUtils).to receive(:mkdir).with('path 1')
				expect($worker).to receive(:execute_command).with("git archive 1.23 --format zip --output \"path 1/package.zip\" -0").and_return( [['some'], 0] )
				expect($worker).to receive(:unzip_package).with("path 1/package.zip", "loc1", "path 1")
				expect(File).to receive(:delete).with("path 1/package.zip")
				expect($worker).to receive(:puts).with("downloading package 'two' r 123..")
				expect(Dir).to receive(:exist?).with('path 2').and_return(true)
				expect(FileUtils).to receive(:rm_r).with('path 2')
				expect(Dir).to receive(:chdir).with("repoB")
				expect(FileUtils).to receive(:mkdir).with('path 2')
				expect($worker).to receive(:execute_command).with("git archive 123 --format zip --output \"path 2/package.zip\" -0").and_return( [['output'], 0] )
				expect($worker).to receive(:unzip_package).with("path 2/package.zip", "loc2", "path 2")
				expect(File).to receive(:delete).with("path 2/package.zip")
				expect($worker).to receive(:puts).with("downloading package 'three'..")
				expect(Dir).to receive(:exist?).with('path 3').and_return(true)
				expect(FileUtils).to receive(:rm_r).with('path 3')
				expect(Dir).to receive(:chdir).with("repoC")
				expect(FileUtils).to receive(:mkdir).with('path 3')
				expect($worker).to receive(:execute_command).with("git archive master --format zip --output \"path 3/package.zip\" -0").and_return( [['..'], 0] )
				expect($worker).to receive(:unzip_package).with("path 3/package.zip", "loc3", "path 3")
				expect(File).to receive(:delete).with("path 3/package.zip")
				expect(File).to receive(:write).with('path 1/version.file', "1.23")
				expect(File).to receive(:write).with('path 2/version.file', "123")


				$worker.download_packages dummy_packages, "version.file"
			end
		end
	end

	describe "when unziping package" do
		xit "unpacks only those files/directories which begin with passed path" do

		end
	end

	describe "when installing packages" do
		before(:each) do
			$worker = PackageWorker.new
		end

		describe "raises error when" do
			it "installer fails with non zero exit code" do
				dummy_packages = { :one => { :dump_at => "path 1", :installer => "deep/installer.some_extension" } }
				expect($worker).to receive(:puts).with("installing package 'one'..")
				expect(File).to receive(:exist?).with('path 1/deep/installer.some_extension').and_return(true)
				expect($worker).to receive(:execute_command).with("path 1/deep/installer.some_extension").and_return( [['some'], 23] )

				expect {
					$worker.install_packages dummy_packages
				}.to raise_error(ToolException, 'package installation failed: ["some"]')
			end
		end

		it "invokes installer of each package" do
			dummy_packages = { :one => { :dump_at => "path 1", :v => "123", :installer => "deep/installer.some_extension" }, 
						   	   :two => { :dump_at => "path 2", :r => "12", :installer => "root_installer.exe" }, 
						   	   :three => { :dump_at => "path 3", :installer => "installer" }, 
						   	   :four => { }, }
			expect($worker).to receive(:puts).with("installing package 'one' v 123..")
			expect($worker).to receive(:puts).with("installing package 'two' r 12..")
			expect(File).to receive(:exist?).with('path 1/deep/installer.some_extension').and_return(true)
			expect(File).to receive(:exist?).with('path 2/root_installer.exe').and_return(true)
			expect(File).to receive(:exist?).with('path 3/installer').and_return(false)
			expect($worker).to receive(:execute_command).with("path 1/deep/installer.some_extension").and_return( [['some'], 0] )
			expect($worker).to receive(:execute_command).with("path 2/root_installer.exe").and_return( [['output'], 0] )

			$worker.install_packages dummy_packages
		end
	end




	##############
	describe "when locking packages" do
		before(:each) do
			$worker = PackageWorker.new
			$dummy_paths = [1, 2]
			$dummy_package_file = "package.file"
			$worker.defaults[:default_look_up_paths] = $dummy_paths
			$worker.defaults[:project_package_file] = $dummy_package_file
		end
		it "raises message when there are no packages to lock" do
			expect($worker).to receive(:find_and_load_packages_from_package_file).and_return(['a', {1 => 2}])
			expect($worker).to receive(:get_list_of_packages_configured_for_bleeding_edge_versions).with({1 => 2}).and_return({})

			expect {
				$worker.lock_packages
			}.to raise_error(ToolMessage, "no packages to lock.")
		end

		it "locks the packages configured for bleeding edge to the revision numbers they have been deployed for" do
			$dummy_packages = {1 => 2}
			expect($worker).to receive(:find_and_load_packages_from_package_file).and_return(['a', $dummy_packages])
			expect($worker).to receive(:get_list_of_packages_configured_for_bleeding_edge_versions).with($dummy_packages).and_return({2 => 3})
			expect($worker).to receive(:get_list_of_deployed_packages).with({2 => 3}).and_return({3 => 4})
			expect($worker).to receive(:update_package_file).with('a', {3 => 4})

			$worker.lock_packages
		end
	end

	describe "when finding packages configured for bleeding edge revisions" do
		before(:each) do
			$worker = PackageWorker.new
		end
		it "returns empty when there are no matching packages" do
			dummy_packages = { :one   => { :repo => "repo", :located_at => "loc1", :dump_at => "path 1", :v => "1.23" }, 
							   :two   => { :repo => "repoB", :located_at => "loc2", :dump_at => "path 2", :r => "123" }, }

			packages_found = $worker.get_list_of_packages_configured_for_bleeding_edge_versions dummy_packages

			packages_found.should be_empty
		end
		it "returns those packages which do not have a :v or :r attribute defined" do
			dummy_packages = { :one   => { :repo => "repo", :located_at => "loc1", :dump_at => "path 1", :v => "1.23" }, 
							   :two   => { :repo => "repoB", :located_at => "loc2", :dump_at => "path 2", :r => "123" }, 
							   :three => { :repo => "repoC", :located_at => "loc3", :dump_at => "path 3" },}
			expected_packages = { :three => { :repo => "repoC", :located_at => "loc3", :dump_at => "path 3" } }

			packages_found = $worker.get_list_of_packages_configured_for_bleeding_edge_versions dummy_packages

			packages_found.should be == expected_packages
		end
	end

	describe "when obtaining list of deployed packages returns" do
		before(:each) do
			$worker = PackageWorker.new
			$worker.defaults[:version_file_name] = "version.file"
			$dummy_packages = { 1 => {:dump_at => 'a'}, 
							    2 => {:dump_at => 'b'},
							    3 => {:dump_at => 'c'}, }
		end
		it "empty when no packages exist on disk" do
			expect($worker).to receive(:get_version_of_deployed_package).with(1, 'a', "version.file").and_return('')
			expect($worker).to receive(:get_version_of_deployed_package).with(2, 'b', "version.file").and_return('')
			expect($worker).to receive(:get_version_of_deployed_package).with(3, 'c', "version.file").and_return('')

			packages_found = $worker.get_list_of_deployed_packages $dummy_packages

			packages_found.should be_empty
		end
		it "only those packages which exist on disk (have a valid version in version file)" do
			expect($worker).to receive(:get_version_of_deployed_package).with(1, 'a', "version.file").and_return('a')
			expect($worker).to receive(:get_version_of_deployed_package).with(2, 'b', "version.file").and_return('')
			expect($worker).to receive(:get_version_of_deployed_package).with(3, 'c', "version.file").and_return('c')
			expected_packages = { 1 => {:dump_at => 'a', :read_version => 'a'}, 3 => {:dump_at => 'c', :read_version => 'c'} }

			packages_found = $worker.get_list_of_deployed_packages $dummy_packages

			packages_found.should be == expected_packages
		end
	end

	it "when updating the package file, writes revision information to passed package descriptions" do
		$worker = PackageWorker.new
		expect(File).to receive(:readlines).with("file").and_return(["a", "b", "c", "one some other text", "and", "two\t", "three"])
		expect($worker).to receive(:parse_package_from_string).with("a").and_return({:a => {}})
		expect($worker).to receive(:parse_package_from_string).with("b").and_return({:b => {}})
		expect($worker).to receive(:parse_package_from_string).with("c").and_return({:c => {}})
		expect($worker).to receive(:parse_package_from_string).with("one some other text").and_return({:one => {}})
		expect($worker).to receive(:parse_package_from_string).with("and").and_return({:and => {}})
		expect($worker).to receive(:parse_package_from_string).with("two\t").and_return({:two => {}})
		expect($worker).to receive(:parse_package_from_string).with("three").and_return({:three => {}})
		$dummy_packages = { :one => { :read_version => 'v1' }, :two => { :read_version => 'v2' } }
		expect($worker).to receive(:package_to_string).with( 'one', { :read_version => 'v1' } ).and_return('one')
		expect($worker).to receive(:package_to_string).with( 'two', { :read_version => 'v2' } ).and_return('two')
		$dummy_file = {}
		expect($dummy_file).to receive(:write).with("a\n")
		expect($dummy_file).to receive(:write).with("b\n")
		expect($dummy_file).to receive(:write).with("c\n")
		expect($dummy_file).to receive(:write).with("one\n")
		expect($dummy_file).to receive(:write).with("and\n")
		expect($dummy_file).to receive(:write).with("two\n")
		expect($dummy_file).to receive(:write).with("three\n")
		expect($dummy_file).to receive(:close)
		expect(File).to receive(:new).with("file", "w").and_return($dummy_file)

		$worker.update_package_file "file", $dummy_packages
	end

	describe "when converting a package definition to string" do
		before(:each) do
			$worker = PackageWorker.new
		end
		it "converts correctly for packages configured for bleeding edge" do
			converted_string = $worker.package_to_string( 'pkg', {} )
			converted_string.should be == "pkg"
		end
		describe "converts correctly for packages locked at specific revision using" do
			it ":read_version setting" do
				converted_string = $worker.package_to_string( 'pkg', { :read_version => 'blah' } )
				converted_string.should be == "pkg --r = blah"
			end
			it ":r setting" do
				converted_string = $worker.package_to_string( 'pkg', { :r => 'blah' } )
				converted_string.should be == "pkg --r = blah"
			end
			it ":v setting" do
				converted_string = $worker.package_to_string( 'pkg', { :v => 'blah' } )
				converted_string.should be == "pkg --v = blah"
			end
		end
	end




	################
	describe "when unlocking packages" do
		before(:each) do
			$worker = PackageWorker.new
		end
		describe "raises error when" do
		end
		describe "raises message when" do
			it "there are no packages to unlock" do
				expect($worker).to receive(:find_and_load_packages_from_package_file).and_return([1, [2]])
				expect($worker).to receive(:get_list_of_locked_packages).with([2]).and_return([4])
				expect {
					$worker.unlock_packages ['a', 'b', 'c']
				}.to raise_error(ToolMessage, "no packages to unlock.")
			end
		end
		it "unlocks packages" do
			expect($worker).to receive(:find_and_load_packages_from_package_file).and_return([1, [2, 3]])
			expect($worker).to receive(:get_list_of_locked_packages).with([2, 3]).and_return([4])
			expect($worker).to receive(:unlock_locked_packages).with([4], ['a','b','c']).and_return('pkgs')
			expect($worker).to receive(:write_packages_to_file).with(1, 'pkgs')
			
			$worker.unlock_packages ['a', 'b', 'c']
		end
	end

end

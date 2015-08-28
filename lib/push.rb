
require "fileutils"
require 'open3'

class Push


  def Push.service root, repo_list
    
    # find the list of all valid git repos
    repos = Push.find_list_of_all_valid_git_repos root, repo_list

    
    # push each repo
    system "git config --global credential.helper 'cache --timeout=3600'"   # valid for 1 hour
    faults = {}
    repos.each {  |r| 
      error_code, message = Push.push_repo r
      faults[r] = message if error_code != 0
    }

    
    # display any error messages we obtained
    puts "\n" unless faults.count == 0
    faults.each_pair {  |repo, message|
        puts "'#{File.basename repo}' = #{message}"
    }

    # we're done
    puts "\n\n"
    puts "Pushed #{repos.count} repos."
  end


  # valid git repos are directories which contains '.git' sub directory and whose name does not begin with '_'
  # filtered against the list provided by the user
  def Push.find_list_of_all_valid_git_repos(root, repo_list)
      Dir.chdir root
      repos = Dir.glob('*').select {  |f| File.directory?( f ) && Dir.exist?("#{f}\\.git") && !f.start_with?('_') }
      repos_resolved = []
      repos.each {  |r| 
        # repo_list repos bassed upon passed repo_list
        unless repo_list.length == 1 && repo_list[0] == "all"
          next unless repo_list.include?( File.basename( r ) )
        end
        repos_resolved.push "#{root}\\#{r}" 
      }

      return repos_resolved
  end



  def Push.push_repo(repo)
      puts "#{File.basename repo}"
      Dir.chdir repo

      puts "    Pushing branches.."
      error, output = Push.execute_command "git push -u origin --all"
      # puts "Error, output => #{error}, #{output}"
      return error, output if error != 0
      
      puts "    Pushing tags.."
      error, output = Push.execute_command "git push -u origin --tags"
      # puts "Error, output => #{error}, #{output}"
      return error, output
  end



  def Push.execute_command command
      error   = 0
      output  = ""
      Open3.popen3(command) do |stdin, stdout, stderr|
           unless ( out = stdout.read ).empty? then
            out.strip!
            output = "[OUTPUT]:\n#{out}\n" unless out == ""
           end
           unless (err = stderr.read).empty? then 
            suppress_error = err.include?('unexpected end of file') || err.include?('unexpected EOF while looking for matching') || err.include?('Everything up-to-date')
            unless suppress_error
              output += "[ERROR]:\n#{err}\n"
              error  = 1;
            end
           end
      end
      return error, output
  end



  # Command Line Support ###############################
  
  if ($0 == __FILE__)
      root = 'd:\\dev'
      args = []
      args.push "all" if ARGV.length == 0
      if ARGV.length > 0
        args = ARGV
      end
      if args.include? "?"
        puts "pushes each git repo in root to it's origin by using git credentials.\n"
        puts "Usage:"
        puts "    push ?    : displays usage"
        puts "    push      : pushes all repos found in root."
        puts "    push all  : pushes all repos found in root."
        puts "    push a, b : pushes ['a', 'b'] (if found) in root."
        puts ""
        puts "root is configured to '#{root}'."
        exit
      end

      Push.service root, args
  end


end

# $started, $complete = %w(started.txt complete.txt).map do |filename|
#   Set.new(File.exists?(filename) ? File.open(filename).read.split("\n") : [])
# end

class Repo
  attr_accessor :name, :svn_url
  
  def initialize(name, bs_data = nil)
    @name = name
    @svn_url = bs_data["repository_url"] if bs_data
    @bs_data = bs_data
  end
  
  # Retrieves the repo from Beanstalk and creates a local copy in the svn 
  # directory
  def grab
    raise "Must supply 'svn_url' in order to grab repo" unless svn_url
    
    set_state "svn:started"
    
    cmd "mkdir -p #{svn_dir}"
    cmd "svnadmin create #{svn_dir}"
    cmd "echo '#!/bin/sh\n\nexit 0' > #{svn_dir}/hooks/pre-revprop-change"
    cmd "chmod +x #{svn_dir}/hooks/pre-revprop-change"
    cmd "svnsync init #{local_uri} #{svn_url}"
    cmd "svnsync sync #{local_uri}"
    
    set_state "svn:complete"
    self
  end
  
  # Creates a local git repo from the local svn repo created by grab
  def convert
    set_state "git:started"
    
    cmd "mkdir -p  #{git_dir}"
    cmd "cd #{git_dir} && svn2git #{local_uri} #{git2svn_flags} -v"
    
    set_state "git:complete"
    self
  end
  
  def set_state(state)
    if state
      File.open(state_file, "w") { |f| f.write(state) } 
    else
      File.delete(state_file)
    end
  end
  
  def state
    File.exists?(state_file) ? File.read(state_file) : nil
  end
  
  def delete_svn
    delete_git
    cmd "rm -rf #{svn_dir}"
    set_state nil
  end
  
  def delete_git
    cmd "rm -rf #{git_dir}"
    set_state "svn:complete"
  end
  
  private
  
  # local svn repo uri
  def local_uri
    "file://#{svn_dir}"
  end
  
  # svn dir path
  def svn_dir
    File.expand_path(File.join(File.dirname(__FILE__), '..', 'svn', name))
  end
  
  # git dir path
  def git_dir
    File.expand_path(File.join(File.dirname(__FILE__), '..', 'git', name))
  end
  
  # name of the file where repo state is stored
  def state_file
    fname = "be_repo_#{name}.txt"
    File.expand_path(File.join(File.dirname(__FILE__), '..', 'db', fname))
  end
  
  # flags to pass git2svn, depending on the directory structure
  def git2svn_flags
    if svn_list.include?("trunk/")
      flags = ["--trunk trunk"]
      flags << (svn_list.include?("branches") ? "--branches branches" 
                                             : "--nobranches")
      flags << (svn_list.include?("tags") ? "--tags tags" : "--notags")
      flags.join(" ")
    else
      "--nobranches --notags --rootistrunk"
    end
  end
  
  # run svn list
  def svn_list
    cmd("svn list #{local_uri}").split("\n")
  end
  
  # run a shell command
  def cmd(cmd)
    puts cmd
    `#{cmd}`
  end
  
  class BeanstalkList
    include Beanstalk::API
  
    attr_accessor :min_age
  
    def initialize(creds)
      Base.setup(creds)
    end
  
    def find(name)
      Repository.find(:all).find { |r| r.name == name } or raise "No repo '#{name}' found"
    end
  
    def repos(min_age='2012-06-01'.to_date)
      @repos ||= Repository.find(:all)
        .find_all { |r| r.vcs == "subversion" }
        .find_all { |r| min_age ? r.last_commit_at < min_age : true }
        .sort_by(&:last_commit_at)
        .map { |r| Repo.new(r.name, r.attributes) }
    end
  end
end
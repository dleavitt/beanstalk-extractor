class Repo
  attr_accessor :name, :svn_url
  
  def initialize(name, bs_data = nil)
    @name = name
    @svn_url = bs_data["repository_url"] if bs_data
    @bs_data = bs_data
    bannerize("Initialized repo #{name}@#{state}")
  end
  
  def migrate
    case state
    when "svn:complete"
      convert
      push
    when "git:complete", "gl:started"
      push
    when "gl:complete"
      bannerize "#{name} is already done"
    else
      grab
      convert
      push
    end
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
  
  # Create the project in gitlabhq
  def create_remote
    set_state "gl:started"
    begin
      raise "repo exists #{name}" if GitlabAPI.project_set.include? name
      GitlabAPI.create_project(name, "Full SVN dump of #{name}")
    rescue => ex
      bannerize "Create remote #{name} failed with #{ex}"
    end
  end
  
  # Push the local git repo to gitlabhq
  def push
    create_remote
    begin
      raise "repo does not exist" unless GitlabAPI.project_set.include? name
      puts "#{name} starting push"
      cmd "cd #{git_dir} && git remote add origin #{git_url}"
      cmd "cd #{git_dir} && git push origin master"
      puts "#{name} push complete"
      set_state "gl:complete"
    rescue => ex
      bannerize "#{name} failed with #{ex}"
    end
  end
  
  def set_state(state)
    cmd "mkdir -p db"
    if state
      File.open(state_file, "w") { |f| f.write(state) } 
    else
      File.delete(state_file)
    end
  end
  
  def state
    File.exists?(state_file) ? File.read(state_file) : nil
  end
  
  def self.incomplete_migrations
    states.find_all { |k,v| v == "gl:started" || v == "git:complete" }
          .map      { |a| Repo.new(a[0]) }
  end
  
  def self.states
    Hash[migrations.map { |f| [File.basename(f)[8..-5], File.read(f)] }]
  end
  
  def self.migrations
    dir = File.expand_path(File.join(File.dirname(__FILE__), '..', 'db'))
    Dir[File.join(dir, "be_repo_*.txt")]
  end
  
  def self.base_git_url
    @base_git_url
  end
  
  def self.base_git_url=(url)
    @base_git_url = url
  end
  
  def git_url
    "#{self.class.base_git_url}:#{name}"
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
  
  def bannerize(message)
    puts ""
    puts "##################################################"
    puts message
    puts "##################################################"
    puts ""
  end
  
  class MigrationQueue
    attr_reader :thread_count, :queue
    
    def initialize(thread_count = 12)
      @thread_count = thread_count
      @queue = Queue.new
    end
    
    def add(repo)
      @queue << repo
    end
    
    def start
      threads = @thread_count.times.map do
        Thread.new do
          until @queue.empty?
            repo = @queue.pop(true) rescue nil
            repo.migrate
          end
        end
      end
      threads.map(&:join)
    end
    
  end
  
  class GitlabAPI
    include HTTParty
    
    format :json
    # debug_output $stdout
    
    def self.init(options)
      base_uri "http://#{options[:host]}/api/v2"
      default_params private_token: options[:token]
    end
    
    def self.project_set
      @project_set ||= get_projects.map { |prj| prj["name"] }
    end
  
    def self.get_projects
      get('/projects', query: {per_page: 500})
    end
  
    def self.create_project(name, desc)
      
      r = post '/projects', body: {
        name: name, 
        description: desc,
        issues_enabled: false,
        wiki_enabled: false,
      }
      p r
      @project_set = nil
      r
    end
  end
  
  class BeanstalkAPI
    include HTTParty
  
    format :json
    # debug_output $stdout
  
    def self.init(options)
      base_uri "https://#{options[:domain]}.beanstalkapp.com/api"
      basic_auth options[:login], options[:password]
    end
  
    def self.get_repos
      get("/repositories.json").map { |r| Hashie::Mash.new(r["repository"]) }
    end
  end
  
  class BeanstalkList
    attr_accessor :min_age
  
    def initialize(creds)
      BeanstalkAPI.init(creds)
    end
  
    def find(name)
      BeanstalkAPI.get_repos.find { |r| r.name == name } or raise "No repo '#{name}' found"
    end
  
    def repos(min_age=nil)
      min_age ||= Date.parse('2012-06-01')
      @repos ||= BeanstalkAPI.get_repos
        .find_all { |r| r.vcs == "subversion" }
        .find_all { |r| min_age ? Date.parse(r.last_commit_at) < min_age : true }
        .sort_by(&:last_commit_at)
        .map { |r| Repo.new(r.name, r) }
    end
  end
end
require "rubygems"
require "bundler"
require "yaml"
require "thread"
Bundler.require
require "./lib/beanstalk-extractor"

class BE < Thor
  desc "migrate REPO", "do full migration on a repo repo"
  def migrate(name)
    init_gitlab
    repo = repo_lister.find(name)
    r = Repo.new(repo.name, repo)
    r.grab
    r.convert
    r.create_remote
  end
  
  desc "delete REPO", "deletes the local stuff from a migrated repo"
  def delete(name)
    r = Repo.new(name)
    r.delete_svn
  end
  
  desc "batch_migrate", "migrates a bunch of repos"
  def batch_migrate
    init_gitlab
    queue = Queue.new
    
    repo_lister.repos.each { |r| queue << r }
    
    threads = 12.times.map do
      Thread.new do
        until queue.empty?
          repo = queue.pop(true) rescue nil
          migrate(repo)
        end
      end
    end
    
    threads.map(&:join)
  end
  
  desc "list", "print a list of repos"
  def list
    pp repo_lister.repos(nil)
  end
  
  desc "console", "run a console in this context"
  def console
    binding.pry
  end
  
  desc "init gitlab", "blah"
  def init_gitlab
    return if @gitlab_inited
    
    settings = YAML.load_file('settings.yml')
    Repo::GitlabAPI.init settings["gitlab"]
    Repo::GitlabAPI.project_set
    Repo.base_git_url = "git@gitlab.dev.hyfn.com"
    @gitlab_inited = true
  end
  
  no_tasks do
    
    def repo_lister
      settings = YAML.load_file('settings.yml')
      repo_lister = Repo::BeanstalkList.new(settings["beanstalk"])
    end
  end
end
require "rubygems"
require "bundler"
require "yaml"
require "thread"
Bundler.require
require "./lib/beanstalk-extractor"

class BE < Thor
  desc "migrate REPO", "do full migration on a repo repo"
  def migrate(name)
    repo = repo_lister.find(name)
    ex = RepoMigrator.new(repo)
    ex.migrate
  end
  
  desc "batch_migrate", "migrates a bunch of repos"
  def batch_migrate
    queue = Queue.new
    
    repo_lister.repos.each { |r| queue << r }
    
    threads = 12.times.map do
      Thread.new do
        until queue.empty?
          repo = queue.pop(true) rescue nil
          $started << repo.name
          ex = RepoMigrator.new(repo)
          ex.migrate
        end
      end
    end
    
    threads.map(&:join)
  end
  
  desc "list", "print a list of repos"
  def list
    pp repo_lister.repos(nil)
  end
  
  no_tasks do
    def repo_lister
      settings = YAML.load_file('settings.yml')
      repo_lister = RepoLister.new(settings["beanstalk"])
    end
  end
end
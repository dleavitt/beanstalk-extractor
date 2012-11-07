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
    repo.migrate
  end
  
  desc "delete REPO", "deletes the local stuff from a migrated repo"
  def delete(name)
    r = Repo.new(name)
    r.delete_svn
  end
  
  desc "resume", "resumes incomplete migrations"
  def resume
    init_gitlab
    Repo.incomplete_migrations.each(&:migrate)
  end
  
  desc "batch_migrate", "migrates a bunch of repos"
  def batch_migrate
    init_gitlab
    repo_lister.repos.each(&:migrate)
  end
  
  desc "list", "print a list of repos"
  def list
    pp repo_lister.repos(nil)
  end
  
  desc "console", "run a console in this context"
  def console
    init_gitlab
    binding.pry
  end
  
  no_tasks do
    
    def init_gitlab
      return if @gitlab_inited
    
      settings = YAML.load_file('settings.yml')
      Repo::GitlabAPI.init settings["gitlab"]
      Repo::GitlabAPI.project_set
      Repo.base_git_url = "git@gitlab.dev.hyfn.com"
      @gitlab_inited = true
    end
    
    def repo_lister
      settings = YAML.load_file('settings.yml')
      repo_lister = Repo::BeanstalkList.new(settings["beanstalk"])
    end
  end
end
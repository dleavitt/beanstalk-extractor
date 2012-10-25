$started, $complete = %w(started.txt complete.txt).map do |filename|
  Set.new(File.exists?(filename) ? File.open(filename).read.split("\n") : [])
end

class RepoLister
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
      .reject   { |r| ($started | $complete).include? r.name }
      .sort_by(&:last_commit_at)
  end
end

class Repo
  attr_accessor :repo
  
  def initialize(repo)
    @repo = repo
  end
  
  def local_uri
    "file://#{svn_dir}"
  end
  
  def svn_dir
    File.expand_path(File.join(File.dirname(__FILE__), '..', 'svn', repo.name))
  end
  
  def git_dir
    File.expand_path(File.join(File.dirname(__FILE__), '..', 'git', repo.name))
  end
  
  private
  
  def cmd(cmd)
    puts cmd
    `#{cmd}`
  end
end

class RepoMigrator < Repo
  def migrate
    grab
    convert
  end
  
  def grab
    grabber = RepoGrabber.new(repo)
    grabber.setup
    grabber.sync
  end
  
  def convert
    converter = RepoConverter.new(repo)
    converter.setup
    converter.convert
  end
end

class RepoGrabber < Repo
  def setup
    cmd("mkdir -p #{svn_dir}")
    cmd("svnadmin create #{svn_dir}")
    cmd("echo '#!/bin/sh\n\nexit 0' > #{svn_dir}/hooks/pre-revprop-change")
    cmd("chmod +x #{svn_dir}/hooks/pre-revprop-change")
  end
  
  def sync
    cmd("svnsync init #{local_uri} #{repo.repository_url}")
    cmd("svnsync sync #{local_uri}")
  end
end

class RepoConverter < Repo
  def setup
    cmd("mkdir -p  #{git_dir}")
  end
  
  def convert
    cmd("cd #{git_dir} && svn2git #{local_uri} #{structure} -v")
  end
  
  def structure
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
  
  def svn_list
    cmd("svn list #{local_uri}").split("\n")
  end
end

# class ArchiveGenerator
#   attr_accessor :repo, :creds
#   
#   def initialize(creds, repo)
#     @repo = repo
#     @creds = creds
#   end
# end
# vim: sw=2:ts=2:sts=1:ft=ruby:et
require 'yaml'

module RepoSync
  extend self

  GITOSIS_SERVER = "git.example.com"
  GITHUB_SERVER  = "github.example.com"
  REDIS_SERVER   = GITHUB_SERVER

  def debug?
    # Get verbose output to figure out why things aren't syncing...
    false
  end

  REPOS = {
    # GitHub:FI    => Gitosis
    "example/repo" => "my_repo",
  }
  REPOS.dup.each { |k, v| REPOS[v] = k }

  def prepare_for_sync!
    if sync?
      debug "Preparing to sync..."
    else
      debug "Repo not setup for syncing..."
      return
    end

    if lock!
      debug "Succeeded"
    else
      debug "Failed"

      if permanently_locked? && !receiving_sync?
        abort "ERROR: Syncing may have failed irrecoverably. Pushes prevented to avoid corruption. Manual resolution required..."
      else
        debug "Locked references: #{locked_refs.inspect}"
        abort("Another push is in progress, please wait and try again...") unless receiving_sync?
      end
    end
  end

  def sync!
    return unless sync?
    unlock! and return if receiving_sync?

    if push_to_remote!
      debug "Unlocking..."
      unlock!
    else
      debug "Permanently locking..."
      permanent_lock!
    end
  end

  def lock!
    debug "Acquiring lock #{lock_keys[:repo]} with refs #{refs.inspect}... "

    if redis.setnx(lock_keys[:repo], YAML.dump(refs))
      redis.set(lock_keys[:src], current_server)
      true
    else
      false
    end
  end

  def receiving_sync?
    refs == locked_refs && src != current_server
  end

  def locked_refs
    YAML.load(redis.get(lock_keys[:repo]).to_s) || {}
  end

  def permanently_locked?
    !!redis.get(lock_keys[:fail])
  end

  def counterpart
    REPOS[repo]
  end

  def src
    redis.get(lock_keys[:src])
  end

  def sync?
    REPOS.keys.include? repo
  end

  def lock_keys
    {
      :repo => "sync/#{repo_key}/refs",
      :fail => "sync/#{repo_key}/failed",
      :src  => "sync/#{repo_key}/source"
    }
  end

  def repo_key
    github? ? counterpart : repo
  end

  def git_root
    Dir.pwd.gsub(%r|\.git(/.*)?$|, '.git')
  end

  def repo
    path_segments = -1
    path_segments -= 1 if github?

    git_root.gsub(".git","").
      split("/")[path_segments, 2].
      join("/")
  end

  def github?
    File.directory?("/opt/github")
  end

  def push_to_remote!
    command = "git push --mirror --repo=#{git_root.inspect} #{remote}:#{counterpart}.git"

    debug "Running #{command.inspect}"

    push_messages do
      IO.popen("#{command} 2>&1") do |pipe|
        while line = pipe.gets
          debug(line)

          # You can let through lines of output if you like. E.g. I do:
          # puts line if line =~ /Kicking off Jenkins build of/
        end
      end
    end

    $?.success?
  end

  def push_messages
    print "Syncing to #{remote_server}... "

    yield

    puts $?.success? ? "Succeeded" : "Failed"
  end

  def remote_server
    github? ? "Gitosis" : "Github:FI"
  end

  def current_server
    github? ? "Github:FI" : "Gitosis"
  end

  def remote
    if github?
      "git@#{GITOSIS_SERVER}"
    else
      "git@#{GITHUB_SERVER}"
    end
  end

  def refs
    @refs ||= begin
      refs = {}
      $stdin.each_line do |line|
        _, sha, ref = *line.split(/\s/)
        refs[ref]   = sha
      end
      refs
    end
  end

  def unlock!
    redis.del(lock_keys[:repo])
    redis.del(lock_keys[:fail])
    redis.del(lock_keys[:src])
  end

  def permanent_lock!
    redis.set(lock_keys[:fail], Time.now.to_i)
  end

  def redis
    @redis ||= begin
      if github?
        $: << '/opt/GitHubFI-2.7/github/vendor/gems/jruby/1.8/gems/redis-2.0.1/lib'
      else
        require 'rubygems'
      end

      require 'redis'

      Redis.new(:host => REDIS_SERVER)
    end
  end

  def debug(*args)
    print *args.map { |a| "DEBUG (#{current_server}): #{a}" } if debug?
    log(*args)
  end

  def log(*args)
    `mkdir -p #{File.dirname(log_file)}`
    File.open(log_file, 'a+') do |file|
      file.puts *args
    end
  end

  def log_file
    @log_file ||= "/var/log/git-sync/#{repo_key}/#{Time.now.to_i}.log"
  end
end


at_exit { RepoSync.redis.client.disconnect }

require 'yaml'
require 'capistrano/recipes/deploy/scm'
require 'capistrano/recipes/deploy/strategy'

def _cset(name, *args, &block)
  unless exists?(name)
    set(name, *args, &block)
  end
end

# =========================================================================
# These variables MUST be set in the client capfiles. If they are not set,
# the deploy will fail with an error.
# =========================================================================

_cset(:application) { abort "Please specify the name of your application, set :application, 'foo'" }
_cset(:repository)  { abort "Please specify the repository that houses your application's code, set :repository, 'foo'" }

# =========================================================================
# These variables may be set in the client capfile if their default values
# are not sufficient.
# =========================================================================

_cset :scm, :subversion
_cset :deploy_via, :checkout

_cset(:deploy_to) { "/u/apps/#{application}" }
_cset(:revision)  { source.head }

# =========================================================================
# These variables should NOT be changed unless you are very confident in
# what you are doing. Make sure you understand all the implications of your
# changes if you do decide to muck with these!
# =========================================================================

_cset(:source)            { Capistrano::Deploy::SCM.new(scm, self) }
_cset(:real_revision)     { source.local.query_revision(revision) { |cmd| with_env("LC_ALL", "C") { run_locally(cmd) } } }

_cset(:strategy)          { Capistrano::Deploy::Strategy.new(deploy_via, self) }

_cset(:release_name)      { set :deploy_timestamped, true; Time.now.utc.strftime("%Y%m%d%H%M%S") }

_cset :version_dir,       "releases"
_cset :shared_dir,        "shared"
_cset :shared_children,   %w(log tmp)
_cset :current_dir,       "current"

_cset(:releases_path)     { File.join(deploy_to, version_dir) }
_cset(:shared_path)       { File.join(deploy_to, shared_dir) }
_cset(:current_path)      { File.join(deploy_to, current_dir) }
_cset(:release_path)      { File.join(releases_path, release_name) }

_cset(:releases)          { capture("ls -xt #{releases_path}").split.reverse }
_cset(:current_release)   { File.join(releases_path, releases.last) }
_cset(:previous_release)  { releases.length > 1 ? File.join(releases_path, releases[-2]) : nil }

_cset(:current_revision)  { capture("cat #{current_path}/REVISION").chomp }
_cset(:latest_revision)   { capture("cat #{current_release}/REVISION").chomp }
_cset(:previous_revision) { capture("cat #{previous_release}/REVISION").chomp }

_cset(:run_method)        { fetch(:use_sudo, true) ? :sudo : :run }

# some tasks, like symlink, need to always point at the latest release, but
# they can also (occassionally) be called standalone. In the standalone case,
# the timestamped release_path will be inaccurate, since the directory won't
# actually exist. This variable lets tasks like symlink work either in the
# standalone case, or during deployment.
_cset(:latest_release) { exists?(:deploy_timestamped) ? release_path : current_release }

# =========================================================================
# Variables for bundler
# =========================================================================
_cset(:use_bundler, true)

# =========================================================================
# These are helper methods that will be available to your recipes.
# =========================================================================

# Auxiliary helper method for the `deploy:check' task. Lets you set up your
# own dependencies.
def depend(location, type, *args)
  deps = fetch(:dependencies, {})
  deps[location] ||= {}
  deps[location][type] ||= []
  deps[location][type] << args
  set :dependencies, deps
end

# Temporarily sets an environment variable, yields to a block, and restores
# the value when it is done.
def with_env(name, value)
  saved, ENV[name] = ENV[name], value
  yield
ensure
  ENV[name] = saved
end

# logs the command then executes it locally.
# returns the command output as a string
def run_locally(cmd)
  logger.trace "executing locally: #{cmd.inspect}" if logger
  `#{cmd}`
end

# If a command is given, this will try to execute the given command, as
# described below. Otherwise, it will return a string for use in embedding in
# another command, for executing that command as described below.
#
# If :run_method is :sudo (or :use_sudo is true), this executes the given command
# via +sudo+. Otherwise is uses +run+. If :as is given as a key, it will be
# passed as the user to sudo as, if using sudo. If the :as key is not given,
# it will default to whatever the value of the :admin_runner variable is,
# which (by default) is unset.
#
# THUS, if you want to try to run something via sudo, and what to use the
# root user, you'd just to try_sudo('something'). If you wanted to try_sudo as
# someone else, you'd just do try_sudo('something', :as => "bob"). If you
# always wanted sudo to run as a particular user, you could do
# set(:admin_runner, "bob").
def try_sudo(*args)
  options = args.last.is_a?(Hash) ? args.pop : {}
  command = args.shift
  raise ArgumentError, "too many arguments" if args.any?

  as = options.fetch(:as, fetch(:admin_runner, nil))
  via = fetch(:run_method, :sudo)
  if command
    invoke_command(command, :via => via, :as => as)
  elsif via == :sudo
    sudo(:as => as)
  else
    ""
  end
end

# Same as sudo, but tries sudo with :as set to the value of the :runner
# variable (which defaults to "app").
def try_runner(*args)
  options = args.last.is_a?(Hash) ? args.pop : {}
  args << options.merge(:as => fetch(:runner, "app"))
  try_sudo(*args)
end

# =========================================================================
# These are the tasks that are available to help with deploying web apps,
# and specifically, Rails applications. You can have cap give you a summary
# of them with `cap -T'.
# =========================================================================

namespace :deploy do
  desc <<-DESC
    Deploys your project. This calls both `update' and `restart'. Note that \
    this will generally only work for applications that have already been deployed \
    once. For a "cold" deploy, you'll want to take a look at the `deploy:cold' \
    task, which handles the cold start specifically.
  DESC
  task :default do
    update
    restart
  end

  desc <<-DESC
    Prepares one or more servers for deployment. Before you can use any \
    of the Capistrano deployment tasks with your project, you will need to \
    make sure all of your servers have been prepared with `cap deploy:setup'. When \
    you add a new server to your cluster, you can easily run the setup task \
    on just that server by specifying the HOSTS environment variable:

      $ cap HOSTS=new.server.com deploy:setup

    It is safe to run this task on servers that have already been set up; it \
    will not destroy any deployed revisions or data.
  DESC
  task :setup, :except => { :no_release => true } do
    dirs = [deploy_to, releases_path, shared_path]
    dirs += shared_children.map { |d| File.join(shared_path, d) }
    run "#{try_sudo} mkdir -p #{dirs.join(' ')} && #{try_sudo} chmod g+w #{dirs.join(' ')}"
  end

  desc <<-DESC
    Copies your project and updates the symlink. It does this in a \
    transaction, so that if either `update_code' or `symlink' fail, all \
    changes made to the remote servers will be rolled back, leaving your \
    system in the same state it was in before `update' was invoked. Usually, \
    you will want to call `deploy' instead of `update', but `update' can be \
    handy if you want to deploy, but not immediately restart your application.
  DESC
  task :update do
    transaction do
      update_code
      symlink
    end
  end

  desc <<-DESC
    Copies your project to the remote servers. This is the first stage \
    of any deployment; moving your updated code and assets to the deployment \
    servers. You will rarely call this task directly, however; instead, you \
    should call the `deploy' task (to do a complete deploy) or the `update' \
    task (if you want to perform the `restart' task separately).

    You will need to make sure you set the :scm variable to the source \
    control software you are using (it defaults to :subversion), and the \
    :deploy_via variable to the strategy you want to use to deploy (it \
    defaults to :checkout).

    Your bundles will also be installed/updated as part of this step. \
    You can disable bundler on remote reployments with the :user_bundler \
    variable.
  DESC
  task :update_code, :except => { :no_release => true } do
    on_rollback { run "rm -rf #{release_path}; true" }
    strategy.deploy!
    finalize_update
    bundler.bundle_new_release if fetch(:use_bundler, true)
  end

  desc <<-DESC
    [internal] Touches up the released code. This is called by update_code \
    after the basic deploy finishes. It assumes a Rails project was deployed, \
    so if you are deploying something else, you may want to override this \
    task with your own environment's requirements.

    This task will make the release group-writable (if the :group_writable \
    variable is set to true, which is the default). It will then set up \
    symlinks to the shared directory for the :shared_children \
    directories, and will lastly touch all assets in public/images, \
    public/stylesheets, and public/javascripts so that the times are \
    consistent (so that asset timestamping works).  This touch process \
    is only carried out if the :normalize_asset_timestamps variable is \
    set to true, which is the default.
  DESC
  task :finalize_update, :except => { :no_release => true } do
    run "chmod -R g+w #{latest_release}" if fetch(:group_writable, true)

    # mkdir -p is making sure that the directories are there for some SCM's that don't
    # save empty folders
    dirs = fetch(:shared_children, [])
    cmd = dirs.inject([]) do |c,d|
      c.push "rm -rf #{latest_release}/#{d}"
      c.push "ln -s #{shared_path}/#{d} #{latest_release}/#{d}"
      c
    end

    run cmd.join( ' && ' )

    if fetch(:normalize_asset_timestamps, false)
      stamp = Time.now.utc.strftime("%Y%m%d%H%M.%S")
      asset_paths = %w(images stylesheets javascripts).map { |p| "#{latest_release}/public/#{p}" }.join(" ")
      run "find #{asset_paths} -exec touch -t #{stamp} {} ';'; true", :env => { "TZ" => "UTC" }
    end

    copy_configs
  end

  desc <<-DESC
    Copies any shared configuration files from :deploy_to/config into \
    the current release's config directory. Original files, if present, \
    are renamed to the same name with .orig appended.

    Specify a list of files by setting :config_files to an array in your \
    deployment configuration.
  DESC
  task :copy_configs do
    fetch(:config_files, []).each do |f|
      run "[ -f #{release_path}/config/#{f} ]; mv #{release_path}/config/#{f} #{release_path}/config/#{f}.orig"
      run "[ -f #{deploy_to}/config/#{f} ]; cp #{deploy_to}/config/#{f} #{release_path}/config/#{f}"
    end
  end

  desc <<-DESC
    Updates the symlink to the most recently deployed version. Capistrano works \
    by putting each new release of your application in its own directory. When \
    you deploy a new version, this task's job is to update the `current' symlink \
    to point at the new version. You will rarely need to call this task \
    directly; instead, use the `deploy' task (which performs a complete \
    deploy, including `restart') or the 'update' task (which does everything \
    except `restart').
  DESC
  task :symlink, :except => { :no_release => true } do
    on_rollback do
      if previous_release
        run "rm -f #{current_path}; ln -s #{previous_release} #{current_path}; true"
      else
        logger.important "no previous release to rollback to, rollback of symlink skipped"
      end
    end

    run "rm -f #{current_path} && ln -s #{latest_release} #{current_path}"
  end

  desc <<-DESC
    Copy files to the currently deployed version. This is useful for updating \
    files piecemeal, such as when you need to quickly deploy only a single \
    file. Some files, such as updated templates, images, or stylesheets, \
    might not require a full deploy, and especially in emergency situations \
    it can be handy to just push the updates to production, quickly.

    To use this task, specify the files and directories you want to copy as a \
    comma-delimited list in the FILES environment variable. All directories \
    will be processed recursively, with all files being pushed to the \
    deployment servers.

      $ cap deploy:upload FILES=templates,controller.rb

    Dir globs are also supported:

      $ cap deploy:upload FILES='config/apache/*.conf'
  DESC
  task :upload, :except => { :no_release => true } do
    files = (ENV["FILES"] || "").split(",").map { |f| Dir[f.strip] }.flatten
    abort "Please specify at least one file or directory to update (via the FILES environment variable)" if files.empty?

    files.each { |file| top.upload(file, File.join(current_path, file)) }
  end

  desc <<-DESC
    Restarts your application. This works by calling 'stop' task, \
    followed by the 'start' task.

    See the descriptions for the 'start' and 'stop' tasks for any \
    additional info.
  DESC
  task :restart, :except => { :no_release => true } do
    stop
    start
  end

  namespace :rollback do
    desc <<-DESC
      [internal] Points the current symlink at the previous revision.
      This is called by the rollback sequence, and should rarely (if
      ever) need to be called directly.
    DESC
    task :revision, :except => { :no_release => true } do
      if previous_release
        run "rm #{current_path}; ln -s #{previous_release} #{current_path}"
      else
        abort "could not rollback the code because there is no prior release"
      end
    end

    desc <<-DESC
      [internal] Removes the most recently deployed release.
      This is called by the rollback sequence, and should rarely
      (if ever) need to be called directly.
    DESC
    task :cleanup, :except => { :no_release => true } do
      run "if [ `readlink #{current_path}` != #{current_release} ]; then rm -rf #{current_release}; fi"
    end

    desc <<-DESC
      Rolls back to the previously deployed version. The `current' symlink will \
      be updated to point at the previously deployed version, and then the \
      current release will be removed from the servers. You'll generally want \
      to call `rollback' instead, as it performs a `restart' as well.
    DESC
    task :code, :except => { :no_release => true } do
      revision
      cleanup
    end

    desc <<-DESC
      Rolls back to a previous version and restarts. This is handy if you ever \
      discover that you've deployed a lemon; `cap rollback' and you're right \
      back where you were, on the previously deployed version.
    DESC
    task :default do
      revision
      restart
      cleanup
    end
  end

  desc <<-DESC
    Clean up old releases. By default, the last 5 releases are kept on each \
    server (though you can change this with the keep_releases variable). All \
    other deployed revisions are removed from the servers. By default, this \
    will use sudo to clean up the old releases, but if sudo is not available \
    for your environment, set the :use_sudo variable to false instead.
  DESC
  task :cleanup, :except => { :no_release => true } do
    count = fetch(:keep_releases, 5).to_i
    if count >= releases.length
      logger.important "no old releases to clean up"
    else
      logger.info "keeping #{count} of #{releases.length} deployed releases"

      directories = (releases - releases.last(count)).map { |release|
        File.join(releases_path, release) }.join(" ")

      try_sudo "rm -rf #{directories}"
    end
  end

  desc <<-DESC
    Test deployment dependencies. Checks things like directory permissions, \
    necessary utilities, and so forth, reporting on the things that appear to \
    be incorrect or missing. This is good for making sure a deploy has a \
    chance of working before you actually run `cap deploy'.

    You can define your own dependencies, as well, using the `depend' method:

      depend :remote, :gem, "tzinfo", ">=0.3.3"
      depend :local, :command, "svn"
      depend :remote, :directory, "/u/depot/files"
  DESC
  task :check, :except => { :no_release => true } do
    dependencies = strategy.check!

    depend( :remote, :gem, "bundler", ">= 0.9.26" ) if fetch(:use_bundler, true)

    other = fetch(:dependencies, {})
    other.each do |location, types|
      types.each do |type, calls|
        if type == :gem
          dependencies.send(location).command(fetch(:gem_command, "gem")).or("`gem' command could not be found. Try setting :gem_command")
        end

        calls.each do |args|
          dependencies.send(location).send(type, *args)
        end
      end
    end

    if dependencies.pass?
      puts "You appear to have all necessary dependencies installed"
    else
      puts "The following dependencies failed. Please check them and try again:"
      dependencies.reject { |d| d.pass? }.each do |d|
        puts "--> #{d.message}"
      end
      abort
    end
  end

  desc <<-DESC
    Deploys and starts a `cold' application. This is useful if you have not \
    deployed your application before, or if your application is (for some \
    other reason) not currently running. It will deploy the code, and then \
    instead of invoking `deploy:restart', it will invoke `deploy:start' to \
    fire up the application servers.
  DESC
  task :cold do
    update
    start
  end

  desc <<-DESC
    Start the daemon processes. This will attempt to invoke a script \
    in your application called `bin/:application', with the 'start' parameter.

    By default, the script will be executed via sudo as the `app' user. If \
    you wish to run it as a different user, set the :runner variable to \
    that user. If you are in an environment where you can't use sudo, set \
    the :use_sudo variable to false.
  DESC
  task :start do
    try_runner "/usr/bin/env DAEMON_ENV=#{fetch(:daemon_env)} #{current_path}/bin/#{application} start"
  end

  desc <<-DESC
    Stop the daemon processes. This will call 'bin/:application stop'.

    By default, the script will be executed via sudo as the `app' user. If \
    you wish to run it as a different user, set the :runner variable to \
    that user. If you are in an environment where you can't use sudo, set \
    the :use_sudo variable to false.
  DESC
  task :stop do
    try_runner "/usr/bin/env DAEMON_ENV=#{fetch(:daemon_env)} #{current_path}/bin/#{application} stop"
  end

  namespace :pending do
    desc <<-DESC
      Displays the `diff' since your last deploy. This is useful if you want \
      to examine what changes are about to be deployed. Note that this might \
      not be supported on all SCM's.
    DESC
    task :diff, :except => { :no_release => true } do
      system(source.local.diff(current_revision))
    end

    desc <<-DESC
      Displays the commits since your last deploy. This is good for a summary \
      of the changes that have occurred since the last deploy. Note that this \
      might not be supported on all SCM's.
    DESC
    task :default, :except => { :no_release => true } do
      from = source.next_revision(current_revision)
      system(source.local.log(from))
    end
  end
end

namespace :bundler do
  task :create_symlink, :roles => :app do
    shared_dir = File.join(shared_path, 'bundle')
    release_dir = File.join(current_release, '.bundle')
    run("mkdir -p #{shared_dir} && ln -s #{shared_dir} #{release_dir}")
  end

  task :bundle_new_release, :roles => :app do
    bundler.create_symlink
    run "cd #{release_path} && bundle install .bundle --without test"
  end

  task :lock, :roles => :app do
    run "cd #{current_release} && bundle lock;"
  end

  task :unlock, :roles => :app do
    run "cd #{current_release} && bundle unlock;"
  end
end

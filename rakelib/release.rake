require_relative "task_helpers"
include ReactOnRails::TaskHelpers
require_relative File.join(gem_root, "lib", "react_on_rails", "version_syntax_converter")
require_relative File.join(gem_root, "lib", "react_on_rails", "git_utils")
require_relative File.join(gem_root, "lib", "react_on_rails", "utils")

desc("Releases both the gem and node package using the given version.

IMPORTANT: the gem version must be in valid rubygem format (no dashes).
It will be automatically converted to a valid npm semver by the rake task
for the node package version. This only makes a difference for pre-release
versions such as `3.0.0.beta.1` (npm version would be `3.0.0-beta.1`).

This task depends on the gem-release (ruby gem) and release-it (node package)
which are installed via `bundle install` and `npm install`

1st argument: The new version in rubygem format (no dashes). Pass no argument to
              automatically perform a patch version bump.
2nd argument: Perform a dry run by passing 'true' as a second argument.

Example: `rake release[2.1.0,false]`")

task :release, [:gem_version, :dry_run, :tools_install] do |_t, args|
  class MessageHandler
    def add_error(error)
      fail error
    end
  end

  # Check if there are uncommited changes
  ReactOnRails::GitUtils.uncommitted_changes?(MessageHandler.new)
  args_hash = args.to_hash

  is_dry_run = ReactOnRails::Utils.object_to_boolean(args_hash[:dry_run])
  should_install_tools = ReactOnRails::Utils.object_to_boolean(args_hash.fetch(:tools_install, true))

  gem_version = args_hash.fetch(:gem_version, "")

  npm_version = if gem_version.strip.empty?
                  ""
                else
                  VersionSyntaxConverter.new.rubygem_to_npm(gem_version)
                end

  # Having the examples prevents publishing
  Rake::Task["examples:clobber"].invoke

  # See https://github.com/svenfuchs/gem-release
  sh_in_dir(gem_root, "git pull --rebase")
  sh_in_dir(gem_root, "gem bump --no-commit #{gem_version.strip.empty? ? '' : %(--version #{gem_version})}")

  # Update dummy app's Gemfile.lock
  bundle_install_in(dummy_app_dir)

  # Stage changes so far
  sh_in_dir(gem_root, "git add .")

  # Will bump the npm version, commit, tag the commit, push to repo, and release on npm
  release_it_command = "$(npm bin)/release-it --non-interactive --npm.publish"
  release_it_command << " --dry-run --verbose" if is_dry_run
  release_it_command << " #{npm_version}" unless npm_version.strip.empty?
  sh_in_dir(gem_root, release_it_command)

  # Release the new gem version
  sh_in_dir(gem_root, "gem release") unless is_dry_run
end

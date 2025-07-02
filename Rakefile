# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/extensiontask"

task build: :compile

GEMSPEC = Gem::Specification.load("cocoadock.gemspec")

Rake::ExtensionTask.new("cocoadock", GEMSPEC) do |ext|
  ext.lib_dir = "lib/cocoadock"
end

task default: %i[clobber compile]

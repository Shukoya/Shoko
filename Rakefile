# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

desc 'Run all quality checks'
task quality: %i[spec rubocop]

task default: :quality

namespace :test do
  desc 'Run tests with coverage'
  task :coverage do
    ENV['COVERAGE'] = 'true'
    Rake::Task['spec'].invoke
  end
end

desc 'Console with library loaded'
task :console do
  require 'irb'
  require 'shoko'
  ARGV.clear
  IRB.start
end

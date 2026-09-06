# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |task|
  task.libs << "lib" << "test"
  task.pattern = "test/**/*_test.rb"
  task.verbose = true
end

Rake::TestTask.new(:property) do |task|
  task.libs << "lib" << "test"
  task.pattern = "test/property/**/*_test.rb"
  task.verbose = true
end

Rake::TestTask.new(:model) do |task|
  task.libs << "lib" << "test"
  task.pattern = "test/model/**/*_test.rb"
  task.verbose = true
end

Rake::TestTask.new(:concurrency) do |task|
  task.libs << "lib" << "test"
  task.pattern = "test/concurrency/**/*_test.rb"
  task.verbose = true
end

Rake::TestTask.new(:fault) do |task|
  task.libs << "lib" << "test"
  task.pattern = "test/scenario/**/*_test.rb"
  task.verbose = true
end

task :benchmark do
  ruby "-Ilib", "benchmark/baseline.rb"
end

task :load_10k do
  ruby "-Ilib", "benchmark/load_10k.rb"
end

task :degradation_metrics do
  ruby "-Ilib", "benchmark/degradation_metrics.rb"
end

task default: :test

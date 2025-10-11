# frozen_string_literal: true

# SimpleCov depends on the json gem, whose newer versions expect JSON::Fragment
# to exist. Ruby 3.4 ships an older default gem without that struct, so we
# provide the minimal implementation to keep the suite bootable.
unless defined?(JSON::Fragment)
  module JSON
    Fragment = Struct.new(:json) do
      def initialize(json)
        string = String.try_convert(json)
        raise TypeError, " no implicit conversion of #{json.class} into String" unless string

        super(string)
      end

      def to_json(*)
        json
      end
    end
  end
end

ENV['EBOOK_READER_TEST_MODE'] ||= '1'
ENV['READER_SKIP_PROGRESS_OVERLAY'] ||= '1'

require 'json'
require 'tmpdir'
require 'simplecov'
SimpleCov.start do
  track_files 'lib/ebook_reader/infrastructure/**/*.rb'
  add_filter '/spec/'
  add_filter '/vendor/'
  # Exclude TUI-heavy surface/terminal rendering and legacy UI directories from coverage
  add_filter '/lib/ebook_reader/components/'
  add_filter '/lib/ebook_reader/reader_modes/'
  add_filter '/lib/ebook_reader/terminal'
  add_filter '/lib/ebook_reader/terminal_' # buffer/input/output
  add_filter '/lib/ebook_reader/controllers/'
  add_filter '/lib/ebook_reader/application/'
  add_filter '/lib/ebook_reader/main_menu.rb'
  add_filter '/lib/ebook_reader/mouseable_reader.rb'
  add_filter '/lib/ebook_reader/ui/'
  add_filter '/lib/ebook_reader/presenters/'
  add_filter '/lib/ebook_reader/services/'
  add_filter '/lib/ebook_reader/epub_'
  add_filter '/lib/ebook_reader/models/'
  add_filter '/lib/ebook_reader/constants/'
  add_filter '/lib/ebook_reader/builders/'
  add_filter '/lib/ebook_reader/errors.rb'
  add_filter '/lib/ebook_reader/helpers/'
  add_filter '/lib/ebook_reader/rendering/'
  add_filter '/lib/ebook_reader/annotations/'
  add_filter '/lib/ebook_reader/recent_files.rb'
  add_filter '/lib/ebook_reader/progress_manager.rb'
  add_filter '/lib/ebook_reader/bookmark_manager.rb'
end

require_relative '../lib/ebook_reader'
require 'fakefs/spec_helpers'
require_relative 'support/test_helpers'
require_relative 'support/zip_builder'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = 'doc' if config.files_to_run.one?

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  # Clean up state between tests
  config.before(:each) do
    EbookReader.reset! if EbookReader.respond_to?(:reset!)
    EbookReader::TestSupport::TerminalDouble.reset! if defined?(EbookReader::TestSupport::TerminalDouble)
    if defined?(EbookReader::Infrastructure::Logger) && defined?(EbookReader::TestSupport::TestMode)
      null_io = EbookReader::TestSupport::TestMode.logger_null_io
      EbookReader::Infrastructure::Logger.output = null_io if null_io
      EbookReader::Infrastructure::Logger.level = :fatal
    end
  end

  # Include FakeFS for file system tests
  config.include FakeFS::SpecHelpers, :fakefs
end

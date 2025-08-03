# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_filter '/vendor/'
  add_filter '/bin/'
end

require 'rspec'
require 'fakefs/spec_helpers'
require 'zip'

# Load all application files
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'ebook_reader'
require 'ebook_reader/constants'
require 'ebook_reader/models/chapter'
require 'ebook_reader/models/bookmark'
require 'ebook_reader/terminal'
require 'ebook_reader/config'
require 'ebook_reader/epub_finder'
require 'ebook_reader/recent_files'
require 'ebook_reader/progress_manager'
require 'ebook_reader/bookmark_manager'
require 'ebook_reader/main_menu'
require 'ebook_reader/epub_document'
require 'ebook_reader/reader'
require 'ebook_reader/cli'
require 'ebook_reader/concerns/input_handler'
require 'ebook_reader/services/library_scanner'
require 'ebook_reader/helpers/html_processor'
require 'ebook_reader/helpers/opf_processor'
require 'ebook_reader/helpers/reader_helpers'
require 'ebook_reader/ui/screens/browse_screen'
require 'ebook_reader/ui/main_menu_renderer'
require 'ebook_reader/ui/reader_renderer'
require 'ebook_reader/infrastructure/logger'
require 'ebook_reader/infrastructure/performance_monitor'
require 'ebook_reader/validators/file_path_validator'
require 'ebook_reader/validators/terminal_size_validator'
require 'ebook_reader/services/reader_navigation'
require 'ebook_reader/services/navigation_service'
require 'ebook_reader/services/bookmark_service'
require 'ebook_reader/services/state_service'
require 'ebook_reader/reader_modes/base_mode'
require 'ebook_reader/reader_modes/reading_mode'
require 'ebook_reader/reader_modes/toc_mode'
require 'ebook_reader/reader_modes/bookmarks_mode'
require 'ebook_reader/reader_modes/help_mode'
require 'ebook_reader/renderers/components/text_renderer'
require 'ebook_reader/errors'
require 'ebook_reader/core/reader_state'

RSpec.configure do |config|
  config.default_formatter = 'doc'
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include FakeFS::SpecHelpers, fake_fs: true

  # Ensure Terminal doesn't interfere with tests
  config.before(:each) do
    allow(EbookReader::Terminal).to receive(:setup)
    allow(EbookReader::Terminal).to receive(:cleanup)
    allow(EbookReader::Terminal).to receive(:clear)
    allow(EbookReader::Terminal).to receive(:write)
    allow(EbookReader::Terminal).to receive(:start_frame)
    allow(EbookReader::Terminal).to receive(:end_frame)
    allow(EbookReader::Terminal).to receive(:size).and_return([24, 80])
    allow(EbookReader::Terminal).to receive(:read_key).and_return(nil)
    allow(IO).to receive_message_chain(:console, :getch).and_return("\n")
  end

  # Mock $stdout for tests that print
  config.before(:each) do
    allow($stdout).to receive(:print)
    allow($stdout).to receive(:flush)
    allow($stdout).to receive(:sync=)
  end
end

# frozen_string_literal: true

require 'optparse'

module EbookReader
  # The command-line interface for the Ebook Reader application.
  class CLI
    class << self
      def run(argv = ARGV)
        options, args = parse_options(argv)
        setup_logger(options[:debug] || ENV.fetch('DEBUG', nil))

        Application::UnifiedApplication.new(args.first).run
      end

      private

      def parse_options(argv)
        options = { debug: false }
        parser = OptionParser.new
        parser.banner = 'Usage: ebook_reader [options] [file]'
        parser.on('-d', '--debug', 'Enable debug logging') { options[:debug] = true }
        parser.on('-h', '--help', 'Prints this help') do
          puts parser
          exit
        end
        parser.parse!(argv)
        [options, argv]
      end

      def setup_logger(debug)
        Infrastructure::Logger.output = debug ? $stdout : File.open(File::NULL, 'w')
        Infrastructure::Logger.level = debug ? :debug : :error
      end
    end
  end
end

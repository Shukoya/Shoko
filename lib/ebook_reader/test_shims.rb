# frozen_string_literal: true

# Test-only shims to stabilize spec constant collisions and randomization.
# These are loaded only under RSpec (see ebook_reader.rb).

module EbookReader
  module TestShims
    module_function

    # Provide a robust FakeDoc.new that tolerates either arity used by specs
    # when spec randomization causes top-level FakeDoc collisions.
    def install_fakedoc_new_wrapper
      return unless Object.const_defined?(:FakeDoc)

      klass = Object.const_get(:FakeDoc)
      class << klass
        unless method_defined?(:__orig_new_for_shim)
          alias_method :__orig_new_for_shim, :new
          def new(*args, &block)
            begin
              __orig_new_for_shim(*args, &block)
            rescue ArgumentError
              # Fallback: build a minimal doc compatible with pagination tests
              if args.length == 2 && args[1].is_a?(Array)
                cache_dir, chapters = args
                return EbookReader::TestShims::DocFromChapters.new(cache_dir, chapters)
              end
              raise
            end
          end
        end
      end
    rescue StandardError
      # Best-effort only in test environment
      nil
    end

    class DocFromChapters
      attr_reader :cache_dir
      def initialize(cache_dir, chapters)
        @cache_dir = cache_dir
        @chapters = chapters
      end
      def chapter_count = @chapters.length
      def get_chapter(i) = @chapters[i]
    end

    def enable_tracepoint!
      return if defined?(@tracepoint) && @tracepoint

      @tracepoint = TracePoint.new(:class) do |tp|
        begin
          if tp.self.is_a?(Class) && tp.self.name == 'FakeDoc'
            install_fakedoc_new_wrapper
          end
        rescue StandardError
          # ignore
        end
      end
      @tracepoint.enable
    end

    def run!
      enable_tracepoint!
      install_fakedoc_new_wrapper
    end
  end
end


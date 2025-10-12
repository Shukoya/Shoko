# frozen_string_literal: true

module EbookReader
  module Infrastructure
    # Collects per-open performance timings when DEBUG_PERF=1.
    module PerfTracer
      SESSION_KEY = :ebook_reader_perf_session
      STAGES = [
        'open.invoke',
        'cache.lookup',
        'zip.read',
        'opf.parse',
        'xhtml.normalize',
        'page_map.hydrate',
        'render.first_paint.ttfp',
      ].freeze

      module_function

      def enabled?
        return @enabled unless @enabled.nil?

        raw = ENV.fetch('DEBUG_PERF', nil)
        @enabled = raw && raw.to_s.strip == '1'
      end

      alias active? enabled?

      def start_open(path)
        return unless enabled?

        session = Session.new(path)
        Thread.current[SESSION_KEY] = session
        session
      end

      def current_session
        Thread.current[SESSION_KEY]
      end

      def measure(stage, &)
        session = current_session
        return yield unless session

        session.measure(stage, &)
      end

      def record(stage, duration)
        session = current_session
        session&.record(stage, duration)
      end

      def complete(open_type:, total_duration: nil)
        session = current_session
        return unless session

        session.record('open.invoke', total_duration) if total_duration
        session.open_type = open_type
        session.emit
      ensure
        clear_session
      end

      def clear_session
        Thread.current[SESSION_KEY] = nil
      end

      def cancel
        clear_session
      end

      # Internal per-open timing tracker.
      class Session
        attr_accessor :open_type

        def initialize(path)
          @path = path
          @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @timings = Hash.new(0.0)
          @open_type = 'unknown'
        end

        def measure(stage)
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          yield
        ensure
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          @timings[stage] += duration if duration
        end

        def record(stage, duration)
          @timings[stage] += duration.to_f
        end

        def emit
          total = @timings['open.invoke']
          total = elapsed unless total.positive?
          fields = ["perf open=#{open_type_label}"]
          PerfTracer::STAGES.each do |stage|
            duration = stage == 'open.invoke' ? total : @timings[stage]
            fields << "#{stage}=#{format_ms(duration)}"
          end
          $stdout.puts(fields.join(' '))
        end

        private

        def open_type_label
          label = @open_type.to_s.strip
          label.empty? ? 'unknown' : label
        end

        def elapsed
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at
        end

        def format_ms(seconds)
          ms = (seconds.to_f * 1000.0)
          "#{ms.round}ms"
        end
      end
    end
  end
end

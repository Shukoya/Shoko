# frozen_string_literal: true

require_relative 'base_screen_component'
require_relative '../../constants/ui_constants'
require_relative '../../infrastructure/epub_cache'
require_relative '../../infrastructure/cache_paths'
require_relative '../../helpers/opf_processor'
require_relative '../../recent_files'

module EbookReader
  module Components
    module Screens
      class LibraryScreenComponent < BaseScreenComponent
        include EbookReader::Constants

        Item = Struct.new(:title, :authors, :year, :last_accessed, :size_bytes, :open_path, :epub_path,
                          keyword_init: true)

        def initialize(state)
          super()
          @state = state
          @items = nil
          # Observe selection changes to support scrolling
          @state.add_observer(self, %i[menu browse_selected])
        end

        def state_changed(_path, _old, _new)
          invalidate
        end

        def do_render(surface, bounds)
          items = load_items
          selected = EbookReader::Domain::Selectors::MenuSelectors.browse_selected(@state) || 0

          render_header(surface, bounds)

          if items.empty?
            render_empty(surface, bounds)
          else
            render_library(surface, bounds, items, selected)
          end

          render_footer(surface, bounds)
        end

        private

        def reader_cache_dir
          EbookReader::Infrastructure::CachePaths.reader_root
        end

        def load_items
          return @items if @items
          list = []
          dir = reader_cache_dir
          return [] unless File.directory?(dir)

          recent_index = index_recent_by_path

          Dir.children(dir).sort.each do |sha|
            entry = File.join(dir, sha)
            next unless File.directory?(entry)
            manifest = %w[manifest.msgpack manifest.json].map { |f| File.join(entry, f) }.find { |p| File.exist?(p) }
            next unless manifest
            data = read_manifest(manifest)
            next unless data && data['spine'].is_a?(Array)

            title = (data['title'] || 'Unknown').to_s
            authors = (data['author'] || '').to_s
            epub_path = (data['epub_path'] || '').to_s
            year = extract_year_from_opf(entry, data['opf_path'])
            last_accessed = recent_index[epub_path]
            size_bytes = calculate_size_bytes(epub_path, entry)

            list << Item.new(title: title, authors: authors, year: year, last_accessed: last_accessed,
                             size_bytes: size_bytes, open_path: entry, epub_path: epub_path)
          end
          @items = list
        end

        # Public accessor for items to avoid reflective access from MainMenu
        public def items
          load_items
        end

        def read_manifest(path)
          if path.end_with?('.msgpack')
            begin
              require 'msgpack'
              return MessagePack.unpack(File.binread(path))
            rescue LoadError
              # fall through to JSON attempt
            end
          end
          JSON.parse(File.read(path))
        rescue StandardError
          nil
        end

        def render_header(surface, bounds)
          write_header(surface, bounds, "#{UIConstants::COLOR_TEXT_ACCENT}📚 Library (Cached)#{Terminal::ANSI::RESET}")
        end

        def render_empty(surface, bounds)
          write_empty_message(surface, bounds, "#{UIConstants::COLOR_TEXT_DIM}No cached books yet#{Terminal::ANSI::RESET}")
        end

        def render_library(surface, bounds, items, selected)
          list_start = 4
          list_height = bounds.height - list_start - 2
          return if list_height <= 0

          draw_list_header(surface, bounds, bounds.width, list_start)
          list_start += 2
          list_height -= 2

          items_per_page = list_height
          start_index, visible_items = calculate_visible_range(items.length, items_per_page, selected)

          current_row = list_start
          visible_items.each_with_index do |book, i|
            break if current_row >= bounds.height - 1
            render_library_item(surface, bounds, current_row, bounds.width, book, start_index + i, selected)
            current_row += 1
          end
        end

        def calculate_visible_range(total_items, per_page, selected)
          start_index = 0
          start_index = selected - per_page + 1 if selected >= per_page
          start_index = [start_index, total_items - per_page].min if total_items > per_page
          end_index = [start_index + per_page - 1, total_items - 1].min
          [start_index, (load_items[start_index..end_index] || [])]
        end

        def draw_list_header(surface, bounds, width, row)
          pointer_w = 2
          gap = 2
          remaining = width - pointer_w - (gap * 4)
          year_w = 6
          last_w = 16
          size_w = 8
          author_w = [[(remaining * 0.25).to_i, 12].max,
                      remaining - 20 - year_w - last_w - size_w].min
          title_w = [remaining - author_w - year_w - last_w - size_w, 20].max

          headers = [
            'Title'.ljust(title_w),
            'Author(s)'.ljust(author_w),
            'Year'.ljust(year_w),
            'Last accessed'.ljust(last_w),
            'Size'.rjust(size_w),
          ].join(' ' * gap)
          header_style = Terminal::ANSI::BOLD + Terminal::ANSI::LIGHT_GREY
          surface.write(bounds, row, 1, header_style + (' ' * pointer_w) + headers + Terminal::ANSI::RESET)
          divider = ('─' * [width - 2, 1].max)
          surface.write(bounds, row + 1, 1, UIConstants::COLOR_TEXT_DIM + divider + Terminal::ANSI::RESET)
        end

        def render_library_item(surface, bounds, row, width, book, index, selected)
          is_selected = (index == selected)
          pointer_w = 2
          gap = 2
          remaining = width - pointer_w - (gap * 4)
          year_w = 6
          last_w = 16
          size_w = 8
          author_w = [[(remaining * 0.25).to_i, 12].max,
                      remaining - 20 - year_w - last_w - size_w].min
          title_w = [remaining - author_w - year_w - last_w - size_w, 20].max

          pointer = is_selected ? '▸ ' : '  '
          title_col = truncate_text((book.title || 'Unknown').to_s, title_w).ljust(title_w)
          author_col = truncate_text((book.authors || '').to_s, author_w).ljust(author_w)
          year_col = (book.year || '').to_s[0, 4].ljust(year_w)
          last_col = truncate_text(relative_accessed_label(book.last_accessed), last_w).ljust(last_w)
          size_col = format_size(book.size_bytes).rjust(size_w)

          line = [title_col, author_col, year_col, last_col, size_col].join(' ' * gap)
          style = is_selected ? UIConstants::SELECTION_HIGHLIGHT : UIConstants::COLOR_TEXT_PRIMARY
          surface.write(bounds, row, 1, style + pointer + line + Terminal::ANSI::RESET)
        end

        def truncate_text(text, max_length)
          str = text.to_s
          return str if str.length <= max_length
          "#{str[0...(max_length - 3)]}..."
        end

        def format_size(bytes)
          mb = (bytes.to_f / (1024 * 1024)).round(1)
          format('%.1f MB', mb)
        end

        def relative_accessed_label(iso)
          return '' unless iso
          t = begin
            Time.parse(iso)
          rescue StandardError
            nil
          end
          return '' unless t

          seconds = (Time.now - t).to_i
          minutes = seconds / 60
          hours = seconds / 3600
          days = seconds / 86_400
          weeks = days / 7

          if hours < 1
            minutes <= 1 ? 'a minute ago' : "#{minutes} minutes ago"
          elsif days < 1
            hours == 1 ? 'an hour ago' : "#{hours} hours ago"
          elsif days == 1
            'yesterday'
          elsif days < 7
            days == 1 ? 'a day ago' : "#{days} days ago"
          else
            weeks == 1 ? 'a week ago' : "#{weeks} weeks ago"
          end
        end

        def calculate_size_bytes(epub_path, cache_dir)
          return File.size(epub_path) if epub_path && !epub_path.empty? && File.exist?(epub_path)
          # Fallback: sum cache dir files
          sum = 0
          Dir.glob(File.join(cache_dir, '**', '*')).each do |p|
            sum += File.size(p) if File.file?(p)
          end
          sum
        rescue StandardError
          0
        end

        def extract_year_from_opf(cache_dir, opf_rel)
          return '' unless opf_rel
          opf = File.join(cache_dir, opf_rel)
          return '' unless File.exist?(opf)
          meta = EbookReader::Helpers::OPFProcessor.new(opf).extract_metadata
          (meta[:year] || '').to_s
        rescue StandardError
          ''
        end

        def index_recent_by_path
          begin
            items = EbookReader::RecentFiles.load
          rescue StandardError
            items = []
          end
          (items || []).each_with_object({}) do |it, h|
            path = it['path']
            acc = it['accessed']
            h[path] = acc if path && acc
          end
        end

        def render_footer(surface, bounds)
          write_footer(surface, bounds, "#{UIConstants::COLOR_TEXT_DIM}↑↓ Navigate • Enter Open • ESC Back#{Terminal::ANSI::RESET}")
        end
      end
    end
  end
end

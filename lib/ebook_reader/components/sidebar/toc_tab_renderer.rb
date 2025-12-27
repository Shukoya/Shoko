# frozen_string_literal: true

require_relative '../base_component'
require_relative '../ui/list_helpers'
require_relative '../ui/text_utils'
require_relative '../../domain/models/toc_entry'

module EbookReader
  module Components
    module Sidebar
      # TOC tab renderer for sidebar
      # Orchestrates rendering of table of contents with filtering and navigation
      class TocTabRenderer < BaseComponent
        include Constants::UIConstants

        def initialize(state, dependencies = nil)
          super()
          @state = state
          @dependencies = dependencies
        end

        def do_render(surface, bounds)
          context = RenderContext.new(surface, bounds, @state, document)
          ComponentOrchestrator.new(context).render
        end

        private

        def document
          @document ||= DocumentResolver.new(@dependencies).resolve
        end
      end

      # Orchestrates rendering of all components
      class ComponentOrchestrator
        def initialize(context)
          @context = context
        end

        def render
          return EmptyStateRenderer.new(@context).render if @context.entries.empty?

          HeaderRenderer.new(@context).render
          FilterInputRenderer.new(@context).render if @context.filter_active?
          EntriesListRenderer.new(@context).render
          FooterRenderer.new(@context).render
        end
      end

      # Encapsulates all rendering context and state
      class RenderContext
        include Constants::UIConstants

        attr_reader :surface, :bounds, :state, :document, :metrics

        def initialize(surface, bounds, state, document)
          @surface = surface
          @bounds = bounds
          @state = state
          @document = document
          @metrics = calculate_metrics
          @entries_cache = nil
          @selected_index_cache = nil
        end

        def entries
          @entries ||= EntriesCalculator.new(self).calculate
        end

        def selected_index
          @selected_index ||= SelectedIndexCalculator.new(self).calculate
        end

        def filter_active?
          state.get(%i[reader sidebar_toc_filter_active])
        end

        def filter_text
          state.get(%i[reader sidebar_toc_filter]) || ''
        end

        def write(row, col, text)
          surface.write(bounds, row, col, text)
        end

        private

        def calculate_metrics
          Metrics.new(
            x: 1,
            y: 1,
            width: bounds.width,
            height: bounds.height
          )
        end
      end

      # Calculates the selected index in filtered list
      class SelectedIndexCalculator
        def initialize(context)
          @context = context
        end

        def calculate
          entries = @context.entries
          selected_entry = entries.full[entries.selected_full_index]
          index = selected_entry ? entries.filtered.index(selected_entry) : 0
          index || 0
        end
      end

      # Calculates entries collection with filtering
      class EntriesCalculator
        def initialize(context)
          @context = context
        end

        def calculate
          full_entries = DocumentEntriesExtractor.new(@context.document).extract
          filtered = filter_entries(full_entries)

          EntriesCollection.new(
            full: full_entries,
            filtered: filtered,
            selected_full_index: calculate_selected_full_index(full_entries)
          )
        end

        private

        def filter_entries(entries)
          return entries unless @context.filter_active?

          EntryFilter.new(entries, @context.filter_text).filter
        end

        def calculate_selected_full_index(entries)
          index = (@context.state.get(%i[reader sidebar_toc_selected]) || 0).to_i
          max_index = [entries.length - 1, 0].max
          index.clamp(0, max_index)
        end
      end

      # Extracts entries from document
      class DocumentEntriesExtractor
        def initialize(document)
          @document = document
        end

        def extract
          return [] unless @document

          toc_entries = extract_toc_entries
          return toc_entries unless toc_entries.empty?

          create_fallback_entries
        end

        private

        def extract_toc_entries
          return [] unless @document.respond_to?(:toc_entries)

          entries = @document.toc_entries
          entries.nil? || entries.empty? ? [] : entries
        end

        def create_fallback_entries
          return [] unless @document.respond_to?(:chapters)

          chapters = @document.chapters
          FallbackEntriesBuilder.build(chapters)
        end
      end

      # Builds fallback entries from chapters
      module FallbackEntriesBuilder
        def self.build(chapters)
          chapters.each_with_index.map do |chapter, idx|
            Domain::Models::TOCEntry.new(
              title: chapter.title || "Chapter #{idx + 1}",
              href: nil,
              level: 1,
              chapter_index: idx,
              navigable: true
            )
          end
        end
      end

      # Metrics for layout calculations
      Metrics = Struct.new(:x, :y, :width, :height, keyword_init: true)

      # Collection of entries with selection state
      class EntriesCollection
        attr_reader :full, :filtered, :selected_full_index

        def initialize(full:, filtered:, selected_full_index:)
          @full = full
          @filtered = filtered
          @selected_full_index = selected_full_index
        end

        def empty?
          filtered.empty?
        end

        def count
          full.length
        end
      end

      # Resolves document from dependencies
      class DocumentResolver
        def initialize(dependencies)
          @dependencies = dependencies
        end

        def resolve
          return nil unless @dependencies.respond_to?(:resolve)

          @dependencies.resolve(:document)
        rescue StandardError
          nil
        end
      end

      # Filters TOC entries based on search term
      class EntryFilter
        def initialize(entries, filter_text)
          @entries = entries
          @filter_text = filter_text
        end

        def filter
          stripped = @filter_text&.strip
          return @entries if stripped.nil? || stripped.empty?

          matching_indices = MatchingIndicesFinder.new(@entries, @filter_text).find
          return [] if matching_indices.empty?

          @entries.select.with_index { |_, idx| matching_indices.include?(idx) }
        end
      end

      # Finds indices of matching entries and their ancestors
      class MatchingIndicesFinder
        def initialize(entries, filter_text)
          @entries = entries
          @filter_text = filter_text
        end

        def find
          term = @filter_text.downcase
          required = Set.new

          @entries.each_with_index do |entry, idx|
            next unless entry.title.to_s.downcase.include?(term)

            required << idx
            add_ancestor_indices(idx, required)
          end

          required
        end

        private

        def add_ancestor_indices(start_idx, required)
          entry = @entries[start_idx]
          entry_level = entry.level
          target_level = entry_level - 1
          current_idx = start_idx - 1

          while current_idx >= 0 && target_level >= 0
            ancestor = @entries[current_idx]
            ancestor_level = ancestor.level

            if ancestor_level < entry_level
              required << current_idx
              entry_level = ancestor_level
              target_level = entry_level - 1
            end

            current_idx -= 1
          end
        end
      end

      # Renders empty state message
      class EmptyStateRenderer
        include Constants::UIConstants

        MESSAGES = [
          'No chapters found',
          '',
          'Content may still be loading',
        ].freeze

        def initialize(context)
          @context = context
        end

        def render
          MESSAGES.each_with_index do |message, index|
            write_centered_message(message, index)
          end
        end

        private

        def write_centered_message(message, offset)
          msg_width = EbookReader::Helpers::TextMetrics.visible_length(message)
          x_pos = [(@context.metrics.width - msg_width) / 2, 2].max
          y_pos = start_y + offset

          text = "#{COLOR_TEXT_DIM}#{message}#{Terminal::ANSI::RESET}"
          @context.write(y_pos, x_pos, text)
        end

        def start_y
          ((@context.metrics.height - MESSAGES.length) / 2) + 1
        end
      end

      # Renders header with title and entry count
      class HeaderRenderer
        include Constants::UIConstants

        def initialize(context)
          @context = context
        end

        def render
          writer = HeaderWriter.new(@context)
          writer.write_title(title_content)
          writer.write_subtitle(subtitle_content) if should_show_subtitle?
          writer.write_divider

          @context.metrics.y + 2
        end

        private

        def title_content
          TitleExtractor.new(@context.document).extract
        end

        def subtitle_content
          SubtitleFormatter.new(@context.entries.count).format
        end

        def should_show_subtitle?
          metrics = @context.metrics
          subtitle_width = EbookReader::Helpers::TextMetrics.visible_length(subtitle_content.plain)
          metrics.width > subtitle_width + 2
        end
      end

      # Extracts and formats title from document
      class TitleExtractor
        DEFAULT_TITLE = 'CONTENTS'

        def initialize(document)
          @document = document
        end

        def extract
          return default_content unless @document

          title = extract_title_text
          return default_content unless title_valid?(title)

          TitleContent.new(title.strip.upcase)
        end

        private

        def default_content
          @default_content ||= TitleContent.new(DEFAULT_TITLE)
        end

        def extract_title_text
          metadata_title = extract_from_metadata
          metadata_title || extract_from_document
        end

        def extract_from_metadata
          return nil unless @document.respond_to?(:metadata)

          @document.metadata&.fetch(:title, nil)
        end

        def extract_from_document
          @document.respond_to?(:title) ? @document.title : nil
        end

        def title_valid?(title)
          return false unless title

          stripped = title.to_s.strip
          !stripped.empty?
        end
      end

      # Represents styled title content
      class TitleContent
        include Constants::UIConstants

        attr_reader :plain

        def initialize(plain_text)
          @plain = plain_text
        end

        def styled
          "#{Terminal::ANSI::BOLD}#{COLOR_TEXT_ACCENT}#{@plain}#{Terminal::ANSI::RESET}"
        end

        def width
          EbookReader::Helpers::TextMetrics.visible_length(@plain)
        end
      end

      # Formats subtitle with entry count
      class SubtitleFormatter
        def initialize(count)
          @count = count
        end

        def format
          SubtitleContent.new("#{@count} entries")
        end
      end

      # Represents styled subtitle content
      class SubtitleContent
        include Constants::UIConstants

        attr_reader :plain

        def initialize(plain_text)
          @plain = plain_text
        end

        def styled
          "#{COLOR_TEXT_DIM}#{@plain}#{Terminal::ANSI::RESET}"
        end

        def width
          EbookReader::Helpers::TextMetrics.visible_length(@plain)
        end
      end

      # Writes header components to surface
      class HeaderWriter
        include Constants::UIConstants

        def initialize(context)
          @context = context
          @metrics = context.metrics
          @last_title_width = 0
        end

        def write_title(title_content)
          @context.write(y_pos, x_pos + 1, title_content.styled)
          @last_title_width = title_content.width
        end

        def write_subtitle(subtitle_content)
          col = calculate_subtitle_column(subtitle_content)
          @context.write(y_pos, col, subtitle_content.styled)
        end

        def write_divider
          width = [@metrics.width - 2, 0].max
          divider = "#{COLOR_TEXT_DIM}#{'─' * width}#{Terminal::ANSI::RESET}"
          @context.write(y_pos + 1, x_pos + 1, divider)
        end

        private

        def calculate_subtitle_column(subtitle_content)
          min_col = x_pos + 1 + @last_title_width + 2
          right_col = x_pos + @metrics.width - subtitle_content.width - 1
          [right_col, min_col].max
        end

        def y_pos
          @metrics.y
        end

        def x_pos
          @metrics.x
        end
      end

      # Renders filter input field
      class FilterInputRenderer
        include Constants::UIConstants

        def initialize(context)
          @context = context
        end

        def render
          write_input_line
          write_help_text

          start_y + 2
        end

        private

        def write_input_line
          prompt = "#{COLOR_TEXT_ACCENT}SEARCH ▸#{Terminal::ANSI::RESET} "
          input = styled_input_text

          @context.write(start_y, x_pos, "#{prompt}#{input}")
        end

        def write_help_text
          help = "#{COLOR_TEXT_DIM}ESC cancel#{Terminal::ANSI::RESET}"
          @context.write(start_y + 1, x_pos, help)
        end

        def styled_input_text
          reset = Terminal::ANSI::RESET
          text = "#{COLOR_TEXT_PRIMARY}#{@context.filter_text}#{reset}"
          text += "#{Terminal::ANSI::REVERSE} #{reset}" if @context.filter_active?
          text
        end

        def start_y
          @context.metrics.y + 2
        end

        def x_pos
          @context.metrics.x + 1
        end
      end

      # Renders list of TOC entries
      class EntriesListRenderer
        def initialize(context)
          @context = context
        end

        def render
          return if @context.entries.empty? || available_height <= 0

          visible_items.each do |item|
            render_entry_item(item)
          end
        end

        private

        def render_entry_item(item)
          EntryRenderer.new(@context, item).render
        end

        def visible_items
          calculator = VisibleItemsCalculator.new(
            @context.entries.filtered,
            @context.selected_index,
            content_start_y,
            available_height,
            max_width
          )
          calculator.calculate
        end

        def content_start_y
          metrics = @context.metrics
          base = metrics.y + 2
          base += 2 if @context.filter_active?
          base
        end

        def available_height
          metrics = @context.metrics
          total = metrics.height - (content_start_y - metrics.y) - footer_height
          [total, 0].max
        end

        def max_width
          [@context.metrics.width - 2, 0].max
        end

        def footer_height
          2
        end
      end

      # Calculates which entries are visible in viewport
      class VisibleItemsCalculator
        def initialize(entries, selected_index, start_y, height, max_width)
          @entries = entries
          @selected_index = selected_index
          @start_y = start_y
          @height = height
          @max_width = max_width
        end

        def calculate
          return [] if @entries.empty?

          items = create_all_items
          visible_items = find_visible_items(items)
          assign_screen_positions(visible_items)
        end

        private

        def create_all_items
          y_position = 0

          @entries.each_with_index.map do |entry, idx|
            item = VisibleEntryItem.new(
              entries: @entries,
              entry: entry,
              index: idx,
              selected_index: @selected_index,
              logical_y: y_position,
              max_width: @max_width
            )

            y_position += item.height
            item
          end
        end

        def find_visible_items(items)
          selected_item = items[@selected_index]
          return [] unless selected_item

          # Calculate viewport to include selected item
          viewport_start = calculate_viewport_start(selected_item, items)
          viewport_end = viewport_start + @height

          items.select do |item|
            item_end = item.logical_y + item.height
            # Item is visible if it overlaps with viewport
            item.logical_y < viewport_end && item_end > viewport_start
          end
        end

        def calculate_viewport_start(selected_item, items)
          # Try to center selected item
          ideal_start = selected_item.logical_y - (@height / 2)

          # Don't scroll past start
          ideal_start = [ideal_start, 0].max

          # Don't scroll past end
          total_height = items.last.logical_y + items.last.height
          max_start = [total_height - @height, 0].max

          [ideal_start, max_start].min
        end

        def assign_screen_positions(visible_items)
          return [] if visible_items.empty?

          viewport_start = visible_items.first.logical_y

          visible_items.each do |item|
            item.screen_y = @start_y + (item.logical_y - viewport_start)
          end

          visible_items
        end
      end

      # Represents a single entry item with rendering info
      class VisibleEntryItem
        attr_reader :entries, :entry, :index, :selected_index, :logical_y, :max_width
        attr_accessor :screen_y

        def initialize(entries:, entry:, index:, selected_index:, logical_y:, max_width:)
          @entries = entries
          @entry = entry
          @index = index
          @selected_index = selected_index
          @logical_y = logical_y
          @max_width = max_width
          @screen_y = 0
          @height = nil
        end

        def selected?
          index == selected_index
        end

        def height
          @height ||= calculate_height
        end

        private

        def calculate_height
          components = EntryComponents.new(entries, entry, index)
          available_width = max_width - components.width_without_title - 1
          available_width = [available_width, 10].max # Minimum 10 chars

          lines = wrap_text(components.title, available_width)
          lines.length
        end

        def wrap_text(text, width)
          return [text] if text.length <= width

          lines = []
          remaining = text

          while remaining.length > width
            # Find last space before width
            break_point = remaining[0...width].rindex(' ') || width
            lines << remaining[0...break_point]
            remaining = remaining[break_point..].lstrip
          end

          lines << remaining unless remaining.empty?
          lines
        end
      end

      # Renders a single TOC entry with text wrapping
      class EntryRenderer
        include Constants::UIConstants

        def initialize(context, item)
          @context = context
          @item = item
        end

        def render
          @item.height.times do |line_num|
            render_line(line_num)
          end
        end

        private

        def render_line(line_num)
          y_pos = @item.screen_y + line_num

          write_gutter(y_pos)
          write_content(y_pos, line_num)
        end

        def write_gutter(y_pos)
          gutter = @item.selected? ? "#{COLOR_TEXT_ACCENT}▎" : "#{COLOR_TEXT_DIM}│"
          gutter += Terminal::ANSI::RESET
          @context.write(y_pos, @context.metrics.x, gutter)
        end

        def write_content(y_pos, line_num)
          formatter = EntryFormatter.new(@item)
          line = formatter.format_line(line_num)
          @context.write(y_pos, @context.metrics.x + 2, line)
        end
      end

      # Formats entry text with tree structure and wrapping
      class EntryFormatter
        include Constants::UIConstants

        def initialize(item)
          @item = item
          @components = EntryComponents.new(item.entries, item.entry, item.index)
          @lines = calculate_wrapped_lines
        end

        def format_line(line_num)
          return '' if line_num >= @lines.length

          line_text = @lines[line_num]

          if @item.selected?
            format_selected_line(line_text, line_num)
          else
            format_normal_line(line_text, line_num)
          end
        end

        private

        def calculate_wrapped_lines
          available = @item.max_width - @components.width_without_title - 1
          available = [available, 10].max
          wrap_text(@components.title, available)
        end

        def wrap_text(text, width)
          return [text] if text.length <= width

          lines = []
          remaining = text

          while remaining.length > width
            break_point = remaining[0...width].rindex(' ') || width
            lines << remaining[0...break_point]
            remaining = remaining[break_point..].lstrip
          end

          lines << remaining unless remaining.empty?
          lines
        end

        def format_selected_line(text, line_num)
          prefix = line_num.zero? ? @components.prefix : indent_for_continuation
          icon = line_num.zero? ? @components.icon : ''
          spacer = line_num.zero? && !icon.empty? ? ' ' : ''

          "#{Terminal::ANSI::BG_GREY}#{Terminal::ANSI::WHITE}#{prefix}#{icon}#{spacer}#{text}#{Terminal::ANSI::RESET}"
        end

        def format_normal_line(text, line_num)
          if line_num.zero?
            format_first_line(text)
          else
            format_continuation_line(text)
          end
        end

        def format_first_line(text)
          parts = []

          prefix = @components.prefix
          parts << colorize(prefix, COLOR_TEXT_DIM) unless prefix.empty?
          parts << colorize(@components.icon, icon_color)
          parts << ' ' unless @components.icon.empty?
          parts << colorize(text, title_color)

          parts.join
        end

        def format_continuation_line(text)
          indent = indent_for_continuation
          indent_colored = colorize(indent, COLOR_TEXT_DIM)
          text_colored = colorize(text, title_color)

          "#{indent_colored}#{text_colored}"
        end

        def indent_for_continuation
          prefix_width = EbookReader::Helpers::TextMetrics.visible_length(@components.prefix)
          icon_width = EbookReader::Helpers::TextMetrics.visible_length(@components.icon)
          spacer_width = @components.icon.empty? ? 0 : 1

          ' ' * (prefix_width + icon_width + spacer_width)
        end

        def colorize(text, color)
          return text unless color

          "#{color}#{text}#{Terminal::ANSI::RESET}"
        end

        def icon_color
          EntryStyler.icon_color(@item.entry)
        end

        def title_color
          EntryStyler.title_color(@item.entry)
        end
      end

      # Calculates components of an entry (prefix, icon, title)
      class EntryComponents
        attr_reader :prefix, :icon, :title

        def initialize(entries, entry, index)
          @prefix = TreeFormatter.prefix(entries, index)
          @icon = IconSelector.select(entries, entry, index)
          @title = EntryTitleFormatter.format(entry)
        end

        def width_without_title
          prefix_width + icon_width
        end

        private

        def prefix_width
          EbookReader::Helpers::TextMetrics.visible_length(@prefix)
        end

        def icon_width
          EbookReader::Helpers::TextMetrics.visible_length(@icon)
        end
      end

      # Formats entry titles
      module EntryTitleFormatter
        def self.format(entry)
          text = entry.title || 'Untitled'
          entry.level.zero? ? text.upcase : text
        end
      end

      # Formats tree structure prefix for entries
      class TreeFormatter
        def self.prefix(entries, index)
          entry = entries[index]
          level = entry.level
          return '' if level <= 0

          (1..level).map do |depth|
            TreeSegment.new(entries, index, depth, level).format
          end.join
        end
      end

      # Represents a single tree segment
      class TreeSegment
        def initialize(entries, index, depth, current_level)
          @entries = entries
          @index = index
          @depth = depth
          @current_level = current_level
        end

        def format
          at_current_level? ? branch_segment : continuation_segment
        end

        private

        def at_current_level?
          @depth == @current_level
        end

        def branch_segment
          last_sibling? ? '└─' : '├─'
        end

        def continuation_segment
          ancestor_continues? ? '│ ' : '  '
        end

        def last_sibling?
          TreeAnalyzer.last_child?(@entries, @index)
        end

        def ancestor_continues?
          TreeAnalyzer.ancestor_continues?(@entries, @index, @depth)
        end
      end

      # Analyzes tree structure relationships
      class TreeAnalyzer
        def self.last_child?(entries, index)
          current = entries[index]
          current_level = current.level

          next_index = index + 1
          while next_index < entries.length
            next_entry = entries[next_index]
            return false if next_entry.level == current_level
            return true if next_entry.level < current_level

            next_index += 1
          end

          true
        end

        def self.ancestor_continues?(entries, index, depth)
          next_index = index + 1

          while next_index < entries.length
            next_entry = entries[next_index]
            return true if next_entry.level == depth
            return false if next_entry.level < depth

            next_index += 1
          end

          false
        end
      end

      # Selects appropriate icon for entry
      class IconSelector
        def self.select(entries, entry, index)
          return '📘' if entry.level.zero?

          has_children?(entries, index) ? '📂' : '📄'
        end

        def self.has_children?(entries, index)
          next_entry = entries[index + 1]
          return false unless next_entry

          next_entry.level > entries[index].level
        end
      end

      # Provides styling colors for entries
      class EntryStyler
        include Constants::UIConstants

        def self.icon_color(entry)
          case entry.level
          when 0 then COLOR_TEXT_ACCENT
          when 1 then COLOR_TEXT_SECONDARY
          else COLOR_TEXT_DIM
          end
        end

        def self.title_color(entry)
          case entry.level
          when 0 then "#{Terminal::ANSI::BOLD}#{COLOR_TEXT_PRIMARY}"
          when 1 then COLOR_TEXT_PRIMARY
          else COLOR_TEXT_SECONDARY
          end
        end
      end

      # Renders footer with keyboard hints
      class FooterRenderer
        include Constants::UIConstants

        HINTS = [
          ['↑↓', 'navigate'],
          ['↩', 'jump'],
          ['/', 'filter'],
        ].freeze

        def initialize(context)
          @context = context
          @metrics = context.metrics
        end

        def render
          write_divider
          write_hints
        end

        private

        def write_divider
          width = [@metrics.width - 2, 0].max
          divider = "#{COLOR_TEXT_DIM}#{'─' * width}#{Terminal::ANSI::RESET}"
          @context.write(footer_y, x_pos, divider)
        end

        def write_hints
          reset = Terminal::ANSI::RESET
          hints_line = HINTS.map do |icon, label|
            "#{COLOR_TEXT_DIM}#{icon}#{reset} #{COLOR_TEXT_PRIMARY}#{label}#{reset}"
          end.join('  ')

          @context.write(footer_y + 1, x_pos, hints_line)
        end

        def footer_y
          @metrics.y + @metrics.height - 2
        end

        def x_pos
          @metrics.x + 1
        end
      end
    end
  end
end

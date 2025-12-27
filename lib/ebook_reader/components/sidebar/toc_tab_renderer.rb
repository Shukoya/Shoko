# frozen_string_literal: true

require_relative '../base_component'
require_relative '../ui/list_helpers'
require_relative '../ui/text_utils'
require_relative '../../domain/models/toc_entry'

module EbookReader
  module Components
    module Sidebar
      # TOC tab renderer for sidebar
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

        attr_reader :surface, :bounds, :state, :document

        def initialize(surface, bounds, state, document)
          @surface = surface
          @bounds = bounds
          @state = state
          @document = document
        end

        def entries
          @entries ||= EntriesCalculator.new(self).calculate
        end

        def selected_index
          @selected_index ||= SelectedIndexCalculator.new(entries).calculate
        end

        def filter_active?
          state.get(%i[reader sidebar_toc_filter_active])
        end

        def filter_text
          state.get(%i[reader sidebar_toc_filter]) || ''
        end

        def metrics
          @metrics ||= calculate_metrics
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
        def initialize(entries)
          @entries = entries
        end

        def calculate
          selected_entry = full_entries[selected_full_index]
          find_filtered_index(selected_entry)
        end

        private

        def full_entries
          @entries.full
        end

        def filtered_entries
          @entries.filtered
        end

        def selected_full_index
          @entries.selected_full_index
        end

        def find_filtered_index(selected_entry)
          return 0 unless selected_entry

          filtered_entries.index(selected_entry) || 0
        end
      end

      # Calculates entries collection with filtering
      class EntriesCalculator
        def initialize(context)
          @context = context
        end

        def calculate
          full_entries = DocumentEntriesExtractor.new(@context.document).extract
          filtered = apply_filter(full_entries)

          EntriesCollection.new(
            full: full_entries,
            filtered: filtered,
            selected_full_index: calculate_selected_index(full_entries)
          )
        end

        private

        def apply_filter(entries)
          return entries unless @context.filter_active?

          EntryFilter.new(entries, @context.filter_text).filter
        end

        def calculate_selected_index(entries)
          raw_index = @context.state.get(%i[reader sidebar_toc_selected]) || 0
          max_index = [entries.length - 1, 0].max
          raw_index.to_i.clamp(0, max_index)
        end
      end

      # Extracts entries from document
      class DocumentEntriesExtractor
        def initialize(document)
          @document = NullDocument.wrap(document)
        end

        def extract
          toc_entries = @document.toc_entries
          return toc_entries unless toc_entries.empty?

          create_fallback_entries
        end

        private

        def create_fallback_entries
          chapters = @document.chapters
          FallbackEntriesBuilder.build(chapters)
        end
      end

      # Null object pattern for missing documents
      class NullDocument
        EMPTY_ARRAY = [].freeze
        EMPTY_HASH = {}.freeze

        def self.wrap(document)
          return document if document

          new
        end

        def toc_entries
          EMPTY_ARRAY
        end

        def chapters
          EMPTY_ARRAY
        end

        def metadata
          EMPTY_HASH
        end

        def title
          nil
        end
      end

      # Builds fallback entries from chapters
      module FallbackEntriesBuilder
        def self.build(chapters)
          chapters.each_with_index.map do |chapter, idx|
            create_entry(chapter, idx)
          end
        end

        def self.create_entry(chapter, index)
          Domain::Models::TOCEntry.new(
            title: chapter.title || "Chapter #{index + 1}",
            href: nil,
            level: 1,
            chapter_index: index,
            navigable: true
          )
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
          @dependencies = NullDependencies.wrap(dependencies)
        end

        def resolve
          @dependencies.resolve(:document)
        end
      end

      # Null object for dependencies
      class NullDependencies
        def self.wrap(dependencies)
          return dependencies if dependencies

          new
        end

        def resolve(_key)
          nil
        end
      end

      # Filters TOC entries based on search term
      class EntryFilter
        def initialize(entries, filter_text)
          @entries = entries
          @filter_text = filter_text.to_s.strip
        end

        def filter
          return @entries if @filter_text.empty?

          matching_indices = MatchingIndicesFinder.new(@entries, @filter_text).find
          return [] if matching_indices.empty?

          select_matching_entries(matching_indices)
        end

        private

        def select_matching_entries(matching_indices)
          @entries.select.with_index { |_, idx| matching_indices.include?(idx) }
        end
      end

      # Finds indices of matching entries and their ancestors
      class MatchingIndicesFinder
        def initialize(entries, filter_text)
          @entries = entries
          @filter_text = filter_text.downcase
        end

        def find
          required = Set.new
          find_matches(required)
          required
        end

        private

        def find_matches(required)
          @entries.each_with_index do |entry, idx|
            next unless entry_matches?(entry)

            required << idx
            add_ancestor_indices(idx, required)
          end
        end

        def entry_matches?(entry)
          entry.title.to_s.downcase.include?(@filter_text)
        end

        def add_ancestor_indices(start_idx, required)
          ancestor_finder = AncestorFinder.new(@entries, start_idx)
          ancestor_finder.find_all.each { |idx| required << idx }
        end
      end

      # Finds ancestor entries in tree structure
      class AncestorFinder
        def initialize(entries, start_idx)
          @entries = entries
          @start_idx = start_idx
          @start_level = entries[start_idx].level
        end

        def find_all
          ancestors = []
          tracker = LevelTracker.new(@start_level)

          scan_backwards do |idx|
            break if tracker.finished?

            process_ancestor(idx, tracker, ancestors)
          end

          ancestors
        end

        private

        def scan_backwards(&)
          (@start_idx - 1).downto(0, &)
        end

        def process_ancestor(idx, tracker, ancestors)
          ancestor_level = @entries[idx].level
          return unless tracker.ancestor?(ancestor_level)

          ancestors << idx
          tracker.descend_to(ancestor_level)
        end
      end

      # Tracks level traversal for ancestor finding
      class LevelTracker
        def initialize(start_level)
          @current_level = start_level
          @target_level = start_level - 1
        end

        def finished?
          @target_level.negative?
        end

        def ancestor?(level)
          level < @current_level
        end

        def descend_to(level)
          @current_level = level
          @target_level = level - 1
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
          x_pos = calculate_x_position(message)
          y_pos = start_y + offset
          styled_text = "#{COLOR_TEXT_DIM}#{message}#{Terminal::ANSI::RESET}"

          @context.write(y_pos, x_pos, styled_text)
        end

        def calculate_x_position(message)
          msg_width = EbookReader::Helpers::TextMetrics.visible_length(message)
          [(@context.metrics.width - msg_width) / 2, 2].max
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
          subtitle_width = EbookReader::Helpers::TextMetrics.visible_length(subtitle_content.plain)
          @context.metrics.width > subtitle_width + 2
        end
      end

      # Extracts and formats title from document
      class TitleExtractor
        DEFAULT_TITLE = 'CONTENTS'

        def initialize(document)
          @document = NullDocument.wrap(document)
        end

        def extract
          title = extract_title_text
          return default_content if title.empty?

          TitleContent.new(title.strip.upcase)
        end

        private

        def default_content
          @default_content ||= TitleContent.new(DEFAULT_TITLE)
        end

        def extract_title_text
          metadata_title = @document.metadata.fetch(:title, nil)
          metadata_title || @document.title || ''
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
          @context.write(start_y, x_pos, "#{prompt}#{styled_input_text}")
        end

        def write_help_text
          help = "#{COLOR_TEXT_DIM}ESC cancel#{Terminal::ANSI::RESET}"
          @context.write(start_y + 1, x_pos, help)
        end

        def styled_input_text
          base = "#{COLOR_TEXT_PRIMARY}#{@context.filter_text}#{Terminal::ANSI::RESET}"
          cursor = @context.filter_active? ? "#{Terminal::ANSI::REVERSE} #{Terminal::ANSI::RESET}" : ''
          base + cursor
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

          visible_items.each { |item| render_entry_item(item) }
        end

        private

        def render_entry_item(item)
          EntryRenderer.new(@context, item).render
        end

        def visible_items
          viewport = create_viewport_config
          calculator = VisibleItemsCalculator.new(
            @context.entries.filtered,
            @context.selected_index,
            viewport
          )
          calculator.calculate
        end

        def create_viewport_config
          ViewportConfig.new(
            start_y: content_start_y,
            height: available_height,
            max_width: max_width
          )
        end

        def content_start_y
          base = @context.metrics.y + 2
          base += 2 if @context.filter_active?
          base
        end

        def available_height
          metrics = @context.metrics
          total = metrics.height - (content_start_y - metrics.y) - 2
          [total, 0].max
        end

        def max_width
          [@context.metrics.width - 2, 0].max
        end
      end

      # Configuration for viewport
      ViewportConfig = Struct.new(:start_y, :height, :max_width, keyword_init: true)

      # Calculates which entries are visible in viewport
      class VisibleItemsCalculator
        def initialize(entries, selected_index, viewport)
          @entries = entries
          @selected_index = selected_index
          @viewport = viewport
        end

        def calculate
          return [] if @entries.empty?

          items = create_all_items
          visible_items = find_visible_items(items)
          position_items_on_screen(visible_items)
        end

        private

        def create_all_items
          ItemCollectionBuilder.new(@entries, @selected_index, @viewport.max_width).build
        end

        def find_visible_items(items)
          ViewportSelector.new(items, @selected_index, @viewport.height).select
        end

        def position_items_on_screen(visible_items)
          ScreenPositioner.new(visible_items, @viewport.start_y).position
        end
      end

      # Builds collection of visible entry items
      class ItemCollectionBuilder
        def initialize(entries, selected_index, max_width)
          @entries = entries
          @selected_index = selected_index
          @max_width = max_width
        end

        def build
          y_position = 0

          @entries.each_with_index.map do |entry, idx|
            item = create_item(entry, idx, y_position)
            y_position += item.height
            item
          end
        end

        private

        def create_item(entry, index, y_position)
          config = ItemConfig.new(
            item_entries: @entries,
            entry: entry,
            index: index,
            selected_index: @selected_index,
            logical_y: y_position,
            max_width: @max_width
          )
          VisibleEntryItem.new(config)
        end
      end

      # Configuration for creating visible entry items
      ItemConfig = Struct.new(
        :item_entries, :entry, :index, :selected_index, :logical_y, :max_width,
        keyword_init: true
      )

      # Selects items visible in viewport
      class ViewportSelector
        def initialize(items, selected_index, viewport_height)
          @items = items
          @selected_index = selected_index
          @viewport_height = viewport_height
        end

        def select
          selected_item = @items[@selected_index]
          return [] unless selected_item

          viewport_range = calculate_viewport_range(selected_item)
          ItemRangeSelector.new(@items, viewport_range).select
        end

        private

        def calculate_viewport_range(selected_item)
          viewport_start = ViewportStartCalculator.new(
            selected_item,
            @items,
            @viewport_height
          ).calculate
          viewport_end = viewport_start + @viewport_height
          viewport_start..viewport_end
        end
      end

      # Calculates viewport start position
      class ViewportStartCalculator
        def initialize(selected_item, items, viewport_height)
          @selected_item = selected_item
          @items = items
          @viewport_height = viewport_height
        end

        def calculate
          ideal_start = calculate_ideal_start
          max_start = calculate_max_start
          [ideal_start, max_start].min
        end

        private

        def calculate_ideal_start
          raw_start = @selected_item.logical_y - (@viewport_height / 2)
          [raw_start, 0].max
        end

        def calculate_max_start
          last_item = @items.last
          total_height = last_item.logical_y + last_item.height
          [total_height - @viewport_height, 0].max
        end
      end

      # Selects items within a range
      class ItemRangeSelector
        def initialize(items, range)
          @items = items
          @range = range
        end

        def select
          @items.select { |item| item_overlaps_range?(item) }
        end

        private

        def item_overlaps_range?(item)
          logical_y = item.logical_y
          item_end = logical_y + item.height
          logical_y < @range.end && item_end > @range.begin
        end
      end

      # Positions items on screen coordinates
      class ScreenPositioner
        def initialize(visible_items, start_y)
          @visible_items = visible_items
          @start_y = start_y
        end

        def position
          return [] if @visible_items.empty?

          viewport_start = @visible_items.first.logical_y

          @visible_items.map do |item|
            screen_y = @start_y + (item.logical_y - viewport_start)
            item.with_screen_position(screen_y)
          end
        end
      end

      # Represents a single entry item with rendering info
      class VisibleEntryItem
        attr_reader :entry, :index, :logical_y, :max_width

        def initialize(config)
          @config = config
          @entry = config.entry
          @index = config.index
          @logical_y = config.logical_y
          @max_width = config.max_width
        end

        def with_screen_position(screen_y)
          PositionedEntryItem.new(self, screen_y)
        end

        def selected?
          index == @config.selected_index
        end

        def height
          @height ||= calculate_height
        end

        def components
          @components ||= EntryComponents.new(@config.item_entries, @entry, @index)
        end

        private

        def calculate_height
          available_width = @max_width - components.width_without_title - 1
          available_width = [available_width, 10].max

          TextWrapper.new(components.title, available_width).line_count
        end
      end

      # Item with screen position
      class PositionedEntryItem
        attr_reader :screen_y

        def initialize(item, screen_y)
          @item = item
          @screen_y = screen_y
        end

        def entry
          @item.entry
        end

        def index
          @item.index
        end

        def logical_y
          @item.logical_y
        end

        def max_width
          @item.max_width
        end

        def selected?
          @item.selected?
        end

        def height
          @item.height
        end

        def components
          @item.components
        end
      end

      # Wraps text to fit within width
      class TextWrapper
        def initialize(text, width)
          @text = text
          @width = width
        end

        def line_count
          wrap_lines.length
        end

        def wrap_lines
          @wrap_lines ||= calculate_wrapped_lines
        end

        private

        def calculate_wrapped_lines
          return [@text] if fits_in_width?

          LineBuilder.new(@text, @width).build
        end

        def fits_in_width?
          @text.length <= @width
        end
      end

      # Builds wrapped lines from text
      class LineBuilder
        def initialize(text, width)
          @text = text
          @width = width
        end

        def build
          lines = []
          text = @text

          text = wrap_iteration(text, lines) while should_continue_wrapping?(text)
          finalize_lines(lines, text)
        end

        private

        def should_continue_wrapping?(text)
          text.length > @width
        end

        def wrap_iteration(text, lines)
          break_point = find_break_point(text)
          lines << text[0...break_point]
          text[break_point..].lstrip
        end

        def finalize_lines(lines, text)
          lines << text unless text.empty?
          lines
        end

        def find_break_point(text)
          text[0...@width].rindex(' ') || @width
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
          @item.height.times { |line_num| render_line(line_num) }
        end

        private

        def render_line(line_num)
          y_pos = @item.screen_y + line_num
          write_gutter(y_pos)
          write_content(y_pos, line_num)
        end

        def write_gutter(y_pos)
          gutter = gutter_symbol + Terminal::ANSI::RESET
          @context.write(y_pos, @context.metrics.x, gutter)
        end

        def gutter_symbol
          @item.selected? ? "#{COLOR_TEXT_ACCENT}▎" : "#{COLOR_TEXT_DIM}│"
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
          @components = item.components
          @lines = TextWrapper.new(@components.title, available_width).wrap_lines
        end

        def format_line(line_num)
          return '' if line_num >= @lines.length

          line_text = @lines[line_num]
          formatter = line_formatter(line_num)
          formatter.format(line_text)
        end

        private

        def available_width
          width = @item.max_width - @components.width_without_title - 1
          [width, 10].max
        end

        def line_formatter(line_num)
          if @item.selected?
            SelectedLineFormatter.new(@components, line_num)
          elsif line_num.zero?
            FirstLineFormatter.new(@components)
          else
            ContinuationLineFormatter.new(@components)
          end
        end
      end

      # Formats selected entry lines
      class SelectedLineFormatter
        include Constants::UIConstants

        def initialize(components, line_num)
          @components = components
          @is_first_line = line_num.zero?
        end

        def format(text)
          prefix = determine_prefix
          icon = determine_icon
          spacer = determine_spacer

          styled_text = "#{prefix}#{icon}#{spacer}#{text}"
          "#{Terminal::ANSI::BG_GREY}#{Terminal::ANSI::WHITE}#{styled_text}#{Terminal::ANSI::RESET}"
        end

        private

        def determine_prefix
          @is_first_line ? @components.prefix : calculate_indent
        end

        def determine_icon
          @is_first_line ? @components.icon : ''
        end

        def determine_spacer
          @is_first_line && !@components.icon.empty? ? ' ' : ''
        end

        def calculate_indent
          IndentCalculator.new(@components).calculate
        end
      end

      # Formats first line of normal entries
      class FirstLineFormatter
        include Constants::UIConstants

        def initialize(components)
          @components = components
          @entry = components.entry
        end

        def format(text)
          assembler = FirstLinePartAssembler.new(@components, @entry)
          parts = assembler.assemble(text)
          parts.join
        end
      end

      # Assembles parts for first line formatting
      class FirstLinePartAssembler
        include Constants::UIConstants

        def initialize(components, entry)
          @components = components
          @entry = entry
        end

        def assemble(text)
          parts = []
          add_prefix_part(parts)
          add_icon_part(parts)
          add_text_part(parts, text)
          parts
        end

        private

        def add_prefix_part(parts)
          prefix = @components.prefix
          parts << colorize(prefix, COLOR_TEXT_DIM) unless prefix.empty?
        end

        def add_icon_part(parts)
          icon = @components.icon
          return if icon.empty?

          parts << colorize(icon, EntryStyler.icon_color(@entry))
          parts << ' '
        end

        def add_text_part(parts, text)
          parts << colorize(text, EntryStyler.title_color(@entry))
        end

        def colorize(text, color)
          return text unless color

          "#{color}#{text}#{Terminal::ANSI::RESET}"
        end
      end

      # Formats continuation lines
      class ContinuationLineFormatter
        include Constants::UIConstants

        def initialize(components)
          @components = components
          @entry = components.entry
        end

        def format(text)
          indent = IndentCalculator.new(@components).calculate
          indent_colored = colorize(indent, COLOR_TEXT_DIM)
          text_colored = colorize(text, EntryStyler.title_color(@entry))

          "#{indent_colored}#{text_colored}"
        end

        private

        def colorize(text, color)
          return text unless color

          "#{color}#{text}#{Terminal::ANSI::RESET}"
        end
      end

      # Calculates indentation for continuation lines
      class IndentCalculator
        def initialize(components)
          @components = components
        end

        def calculate
          total_width = prefix_width + icon_width + spacer_width
          ' ' * total_width
        end

        private

        def prefix_width
          EbookReader::Helpers::TextMetrics.visible_length(@components.prefix)
        end

        def icon_width
          EbookReader::Helpers::TextMetrics.visible_length(@components.icon)
        end

        def spacer_width
          @components.icon.empty? ? 0 : 1
        end
      end

      # Calculates components of an entry (prefix, icon, title)
      class EntryComponents
        attr_reader :prefix, :icon, :title, :entry

        def initialize(item_entries, entry, index)
          @entry = entry
          @prefix = TreeFormatter.prefix(item_entries, index, entry.level)
          @icon = IconSelector.select(item_entries, entry, index)
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
        def self.prefix(item_entries, index, level)
          return '' if level <= 0

          PrefixBuilder.new(item_entries, index, level).build
        end
      end

      # Builds tree prefix from segments
      class PrefixBuilder
        def initialize(item_entries, index, level)
          @item_entries = item_entries
          @index = index
          @level = level
        end

        def build
          (1..@level).map { |depth| segment_for_depth(depth) }.join
        end

        private

        def segment_for_depth(depth)
          TreeSegment.new(@item_entries, @index, depth, @level).format
        end
      end

      # Represents a single tree segment
      class TreeSegment
        def initialize(item_entries, index, depth, current_level)
          @item_entries = item_entries
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
          TreeAnalyzer.last_child?(@item_entries, @index) ? '└─' : '├─'
        end

        def continuation_segment
          TreeAnalyzer.ancestor_continues?(@item_entries, @index, @depth) ? '│ ' : '  '
        end
      end

      # Analyzes tree structure relationships
      class TreeAnalyzer
        def self.last_child?(item_entries, index)
          analyzer = SiblingAnalyzer.new(item_entries, index)
          analyzer.last_child?
        end

        def self.ancestor_continues?(item_entries, index, depth)
          analyzer = AncestorContinuationAnalyzer.new(item_entries, index, depth)
          analyzer.continues?
        end
      end

      # Analyzes sibling relationships
      class SiblingAnalyzer
        def initialize(item_entries, index)
          @item_entries = item_entries
          @index = index
          @current_level = item_entries[index].level
        end

        def last_child?
          (@index + 1).upto(@item_entries.length - 1) do |next_index|
            next_level = @item_entries[next_index].level
            return false if next_level == @current_level
            return true if next_level < @current_level
          end

          true
        end
      end

      # Analyzes ancestor continuation
      class AncestorContinuationAnalyzer
        def initialize(item_entries, index, depth)
          @item_entries = item_entries
          @index = index
          @depth = depth
        end

        def continues?
          (@index + 1).upto(@item_entries.length - 1) do |next_index|
            next_level = @item_entries[next_index].level
            return true if next_level == @depth
            return false if next_level < @depth
          end

          false
        end
      end

      # Selects appropriate icon for entry
      class IconSelector
        def self.select(item_entries, entry, index)
          return '📘' if entry.level.zero?

          children?(item_entries, index) ? '📂' : '📄'
        end

        def self.children?(item_entries, index)
          next_entry = item_entries[index + 1]
          return false unless next_entry

          next_entry.level > item_entries[index].level
        end
      end

      # Provides styling colors for entries
      class EntryStyler
        include Constants::UIConstants

        def self.icon_color(entry)
          ICON_COLORS[entry.level] || COLOR_TEXT_DIM
        end

        def self.title_color(entry)
          TITLE_COLORS[entry.level] || COLOR_TEXT_SECONDARY
        end

        ICON_COLORS = {
          0 => COLOR_TEXT_ACCENT,
          1 => COLOR_TEXT_SECONDARY,
        }.freeze

        TITLE_COLORS = {
          0 => "#{Terminal::ANSI::BOLD}#{COLOR_TEXT_PRIMARY}",
          1 => COLOR_TEXT_PRIMARY,
        }.freeze
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
          hints_line = format_hints
          @context.write(footer_y + 1, x_pos, hints_line)
        end

        def format_hints
          reset = Terminal::ANSI::RESET
          HINTS.map do |icon, label|
            "#{COLOR_TEXT_DIM}#{icon}#{reset} #{COLOR_TEXT_PRIMARY}#{label}#{reset}"
          end.join('  ')
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

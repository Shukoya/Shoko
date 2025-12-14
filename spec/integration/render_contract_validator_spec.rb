# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Render contract validator' do
  class ContractFixtureChapter
    attr_reader :lines, :title

    def initialize(lines)
      @lines = lines
      @title = 'Fixture'
    end
  end

  class ContractFixtureDoc
    def initialize(lines)
      @chapter = ContractFixtureChapter.new(lines)
    end

    def chapter_count = 1

    def get_chapter(_idx) = @chapter
  end

  class ContractCaptureOutput
    attr_reader :writes

    def initialize
      @writes = []
    end

    def write(row, col, text)
      @writes << { row: row.to_i, col: col.to_i, text: text.to_s }
    end
  end

  def validate_terminal_writes!(writes, bounds)
    csi = EbookReader::Helpers::TextMetrics::CSI_REGEX

    writes.each do |w|
      row = w.fetch(:row)
      col = w.fetch(:col)
      text = w.fetch(:text)

      expect(row).to be_between(bounds.y, bounds.bottom).inclusive, "row out of bounds: #{w.inspect}"
      expect(col).to be_between(bounds.x, bounds.right).inclusive, "col out of bounds: #{w.inspect}"

      expect(text).not_to include("\t"), "tab leaked into output: #{w.inspect}"
      expect(text).not_to include("\n"), "newline leaked into output: #{w.inspect}"
      expect(text).not_to include("\r"), "carriage return leaked into output: #{w.inspect}"

      non_csi = text.gsub(csi, '')
      expect(non_csi).not_to include("\e"), "non-CSI escape leaked into output: #{w.inspect}"

      visible = EbookReader::Helpers::TextMetrics.visible_length(text)
      remaining = bounds.right - col + 1
      expect(visible).to be <= remaining, "text overflows bounds: #{w.inspect}"
    end
  end

  def validate_split_columns!(writes, bounds, col_width:, left_start:, right_start:, divider_col:)
    abs_left_start = bounds.x + left_start - 1
    abs_left_end = abs_left_start + col_width - 1
    abs_right_start = bounds.x + right_start - 1
    abs_right_end = abs_right_start + col_width - 1
    abs_divider_col = bounds.x + divider_col - 1
    abs_content_top = bounds.y + 3 - 1

    gap_left = abs_left_end + 1
    gap_right = abs_right_start - 1

    writes.each do |w|
      row = w.fetch(:row)
      col = w.fetch(:col)
      next if row < abs_content_top

      visible = EbookReader::Helpers::TextMetrics.visible_length(w.fetch(:text))

      if col.between?(abs_left_start, abs_left_end)
        allowed = abs_left_end - col + 1
        expect(visible).to be <= allowed, "left column overflow: #{w.inspect}"
      elsif col.between?(abs_right_start, abs_right_end)
        allowed = abs_right_end - col + 1
        expect(visible).to be <= allowed, "right column overflow: #{w.inspect}"
      elsif col == abs_divider_col
        expect(visible).to be <= 1, "divider overflow: #{w.inspect}"
      elsif col.between?(gap_left, gap_right)
        raise "unexpected write in split column gap: #{w.inspect}"
      end
    end
  end

  def build_geometry(text, row:, col_origin:)
    cell_data = EbookReader::Helpers::TextMetrics.cell_data_for(text)
    cells = cell_data.map do |cell|
      EbookReader::Models::LineCell.new(
        cluster: cell[:cluster],
        char_start: cell[:char_start],
        char_end: cell[:char_end],
        display_width: cell[:display_width],
        screen_x: cell[:screen_x]
      )
    end

    EbookReader::Models::LineGeometry.new(
      page_id: 0,
      column_id: 0,
      row: row,
      column_origin: col_origin,
      line_offset: 0,
      plain_text: text,
      styled_text: text,
      cells: cells
    )
  end

  it 'keeps split-view content inside its columns (renderer + selection highlight)' do
    container = EbookReader::Domain::ContainerFactory.create_default_container
    state = container.resolve(:global_state)

    # Force-disable kitty images so output is strictly Surface-driven.
    state.update(
      %i[config view_mode] => :split,
      %i[config page_numbering_mode] => :absolute,
      %i[config kitty_images] => false,
      %i[reader current_chapter] => 0,
      %i[reader current_page_index] => 0,
      %i[reader left_page] => 0
    )

    lines = Array.new(200) do |i|
      payload = case (i % 5)
                when 0 then "漢字🙂\tTabbed content " * 8
                when 1 then ("Combining e\u0301 " * 20)
                when 2 then ('ASCII words ' * 30)
                when 3 then ('🙂emoji🙂 ' * 25)
                else "plain line #{i} " * 20
                end
      "#{i.to_s.rjust(3, '0')}: #{payload}"
    end

    container.register(:document, ContractFixtureDoc.new(lines))

    bounds = EbookReader::Components::Rect.new(x: 7, y: 4, width: 90, height: 24)
    layout = container.resolve(:layout_service)
    col_width, = layout.calculate_metrics(bounds.width, bounds.height, :split)
    left_start = EbookReader::Components::Reading::SplitViewRenderer::LEFT_MARGIN + 1
    right_start = left_start + col_width + EbookReader::Components::Reading::SplitViewRenderer::COLUMN_GAP
    divider_col = left_start + col_width + 1

    output = ContractCaptureOutput.new
    surface = EbookReader::Components::Surface.new(output)
    renderer = EbookReader::Components::Reading::SplitViewRenderer.new(container)
    renderer.render(surface, bounds)

    expect(output.writes).not_to be_empty
    validate_terminal_writes!(output.writes, bounds)
    validate_split_columns!(
      output.writes,
      bounds,
      col_width: col_width,
      left_start: left_start,
      right_start: right_start,
      divider_col: divider_col
    )

    rendered_lines = EbookReader::Domain::Selectors::ReaderSelectors.rendered_lines(state)
    geometries = rendered_lines.values.map { |entry| entry[:geometry] }.compact
    left_geo = geometries.select { |g| g.column_id == 0 }.max_by(&:line_offset)
    right_geo = geometries.select { |g| g.column_id == 1 }.min_by(&:line_offset)

    expect(left_geo).not_to be_nil
    expect(right_geo).not_to be_nil

    start_anchor = EbookReader::Models::SelectionAnchor.new(
      page_id: left_geo.page_id,
      column_id: left_geo.column_id,
      geometry_key: left_geo.key,
      line_offset: left_geo.line_offset,
      cell_index: 0,
      row: left_geo.row,
      column_origin: left_geo.column_origin
    )

    end_cell = [right_geo.cells.length, 6].min
    end_anchor = EbookReader::Models::SelectionAnchor.new(
      page_id: right_geo.page_id,
      column_id: right_geo.column_id,
      geometry_key: right_geo.key,
      line_offset: right_geo.line_offset,
      cell_index: end_cell,
      row: right_geo.row,
      column_origin: right_geo.column_origin
    )

    state.update(%i[reader selection] => { start: start_anchor.to_h, end: end_anchor.to_h })

    controller = double('Controller', state: state)
    overlay = EbookReader::Components::TooltipOverlayComponent.new(
      controller,
      coordinate_service: container.resolve(:coordinate_service)
    )

    highlight_output = ContractCaptureOutput.new
    highlight_surface = EbookReader::Components::Surface.new(highlight_output)
    overlay.send(:render_active_selection, highlight_surface, bounds)

    highlight_writes = highlight_output.writes.select do |w|
      w[:text].include?(EbookReader::Components::TooltipOverlayComponent::HIGHLIGHT_BG_ACTIVE)
    end

    expect(highlight_writes.length).to be >= 2
    validate_terminal_writes!(highlight_output.writes, bounds)
    validate_split_columns!(
      highlight_output.writes,
      bounds,
      col_width: col_width,
      left_start: left_start,
      right_start: right_start,
      divider_col: divider_col
    )
  end

  it 'renders the popup menu using absolute coordinates inside offset bounds' do
    bounds = EbookReader::Components::Rect.new(x: 10, y: 6, width: 60, height: 20)

    coord = Class.new do
      def calculate_popup_position(_end_pos, _w, _h) = { x: 25, y: 12 }
      def within_bounds?(*_args) = true
      def normalize_selection_range(r, _rendered_lines = nil) = r
    end.new

    clipboard = double('Clipboard', available?: false)
    geometry = build_geometry('popup range', row: 8, col_origin: 20)
    rendered_lines = {
      geometry.key => {
        geometry: geometry,
      },
    }

    start_anchor = EbookReader::Models::SelectionAnchor.new(
      page_id: geometry.page_id,
      column_id: geometry.column_id,
      geometry_key: geometry.key,
      line_offset: geometry.line_offset,
      cell_index: 0,
      row: geometry.row,
      column_origin: geometry.column_origin
    )
    selection = { start: start_anchor.to_h, end: start_anchor.with_cell_index(3).to_h }

    menu = EbookReader::Components::EnhancedPopupMenu.new(selection, nil, coord, clipboard, rendered_lines)

    output = ContractCaptureOutput.new
    surface = EbookReader::Components::Surface.new(output)
    menu.render(surface, bounds)

    expect(output.writes).not_to be_empty
    expect(output.writes.map { |w| [w[:row], w[:col]] }).to include([12, 25])
    validate_terminal_writes!(output.writes, bounds)
  end

  it 'centers overlays correctly within offset bounds' do
    bounds = EbookReader::Components::Rect.new(x: 11, y: 5, width: 70, height: 28)

    editor = EbookReader::Components::AnnotationEditorOverlayComponent.new(
      selected_text: 'text',
      range: { start: { x: 0, y: 0 }, end: { x: 1, y: 0 } },
      chapter_index: 0
    )
    allow(editor).to receive(:calculate_width).and_return(30)
    allow(editor).to receive(:calculate_height).and_return(12)

    editor_output = ContractCaptureOutput.new
    editor_surface = EbookReader::Components::Surface.new(editor_output)
    editor.render(editor_surface, bounds)

    expected_origin_x = bounds.x + ((bounds.width - 30) / 2)
    expected_origin_y = bounds.y + ((bounds.height - 12) / 2)
    bg = EbookReader::Components::AnnotationEditorOverlayComponent::POPUP_BG_DEFAULT

    bg_write = editor_output.writes.find do |w|
      w[:row] == expected_origin_y && w[:col] == expected_origin_x && w[:text].start_with?(bg)
    end
    expect(bg_write).not_to be_nil
    validate_terminal_writes!(editor_output.writes, bounds)

    regions = editor.instance_variable_get(:@button_regions)
    expect(regions).to be_a(Hash)
    expect(regions[:save]).to be_a(Hash)
    expect(editor.handle_click(regions[:save][:col], regions[:save][:row])).to eq(type: :save, note: editor.note)
    expect(editor.handle_click(regions[:cancel][:col], regions[:cancel][:row])).to eq(type: :cancel)

    container = EbookReader::Domain::ContainerFactory.create_default_container
    state = container.resolve(:global_state)
    state.update(
      %i[reader annotations] => [
        {
          id: 1,
          text: "Line with 漢字 and tabs\tinside",
          note: 'Note',
          chapter_index: 0,
          created_at: '2024-01-01T00:00:00Z',
        },
      ],
      %i[reader sidebar_annotations_selected] => 0
    )

    annotations = EbookReader::Components::AnnotationsOverlayComponent.new(state)
    allow(annotations).to receive(:calculate_width).and_return(50)
    allow(annotations).to receive(:calculate_height).and_return(14)

    ann_output = ContractCaptureOutput.new
    ann_surface = EbookReader::Components::Surface.new(ann_output)
    annotations.render(ann_surface, bounds)

    expected_ann_origin_x = bounds.x + ((bounds.width - 50) / 2)
    expected_ann_origin_y = bounds.y + ((bounds.height - 14) / 2)
    ann_bg_write = ann_output.writes.find do |w|
      w[:row] == expected_ann_origin_y && w[:col] == expected_ann_origin_x && w[:text].start_with?(bg)
    end

    expect(ann_bg_write).not_to be_nil
    validate_terminal_writes!(ann_output.writes, bounds)
  end
end

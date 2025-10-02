# frozen_string_literal: true

require 'spec_helper'
require 'ebook_reader/components/annotation_editor_overlay_component'

RSpec.describe EbookReader::Components::AnnotationEditorOverlayComponent do
  let(:component) do
    described_class.new(selected_text: 'text', range: nil, chapter_index: 0)
  end

  let(:bounds) { EbookReader::Components::Rect.new(x: 1, y: 1, width: 60, height: 30) }

  let(:surface) do
    Class.new do
      attr_reader :writes

      def initialize
        @writes = []
      end

      def write(_bounds, row, col, text)
        @writes << [row, col, text]
      end
    end.new
  end

  it 'appends characters via handle_character' do
    component.handle_character('a')
    component.handle_character('b')
    expect(component.note).to eq('ab')
  end

  it 'removes characters via handle_backspace' do
    component.handle_character('a')
    component.handle_character('b')
    component.handle_backspace
    expect(component.note).to eq('a')
  end

  it 'inserts newlines via handle_enter' do
    component.handle_character('a')
    component.handle_enter
    expect(component.note).to eq("a\n")
  end

  it 'renders note text anchored near the top of the overlay' do
    overlay = described_class.new(selected_text: '', range: nil, chapter_index: 0)
    allow(overlay).to receive(:calculate_width).and_return(20)
    allow(overlay).to receive(:calculate_height).and_return(10)

    overlay.handle_character('a')
    overlay.handle_character('b')
    overlay.render(surface, bounds)

    origin_x = bounds.x + [(bounds.width - 20) / 2, 1].max
    origin_y = bounds.y + [(bounds.height - 10) / 2, 1].max
    text_col = origin_x + 2
    note_row = origin_y + 2

    note_line = surface.writes.find do |row, col, text|
      row == note_row && col == text_col && text.include?('ab')
    end

    expect(note_line).not_to be_nil
  end

  it 'positions cursor according to the current insertion point' do
    overlay = described_class.new(selected_text: '', range: nil, chapter_index: 0)
    allow(overlay).to receive(:calculate_width).and_return(20)
    allow(overlay).to receive(:calculate_height).and_return(10)

    %w[a b].each { |ch| overlay.handle_character(ch) }
    overlay.render(surface, bounds)

    origin_x = bounds.x + [(bounds.width - 20) / 2, 1].max
    origin_y = bounds.y + [(bounds.height - 10) / 2, 1].max
    text_col = origin_x + 2
    note_row = origin_y + 2

    cursor_write = surface.writes.reverse.find { |_, _, text| text.include?('_') }
    expect(cursor_write).not_to be_nil
    expect(cursor_write[0]).to eq(note_row)
    expect(cursor_write[1]).to eq(text_col + 2)
  end

  it 'returns cancel events when escape is pressed' do
    expect(component.handle_key("\e")).to eq({ type: :cancel })
  end

  it 'tints the background rows using the popup background color' do
    allow(component).to receive(:calculate_width).and_return(20)
    allow(component).to receive(:calculate_height).and_return(10)

    component.render(surface, bounds)

    bg_present = surface.writes.any? do |_, _, text|
      text.start_with?(EbookReader::Components::AnnotationEditorOverlayComponent::POPUP_BG_DEFAULT)
    end

    expect(bg_present).to be(true)
  end
end

# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::ReaderController do
  before do
    mock_terminal(width: 80, height: 24)

    chapter_struct = Struct.new(:title, :lines)
    chapters = [chapter_struct.new('Ch1', ['line one', 'line two'])]
    stub_document_service(chapters:)

    # Spy overlay component to ensure it renders during draw_screen
    overlay_class = Class.new do
      class << self
        attr_accessor :render_calls
      end
      def initialize(*); end

      def render(_surface, _bounds)
        self.class.render_calls = (self.class.render_calls || 0) + 1
      end
    end
    stub_const('EbookReader::Components::TooltipOverlayComponent', overlay_class)
  end

  it 'renders overlay and ends frame exactly once per draw' do
    expect(EbookReader::Terminal).to receive(:end_frame).once
    controller = described_class.new('/tmp/fake.epub')
    controller.draw_screen
    expect(EbookReader::Components::TooltipOverlayComponent.render_calls).to eq(1)
  end
end

# frozen_string_literal: true

require 'spec_helper'
RSpec.describe EbookReader::ReaderDisplay::ColumnRenderer do
  let(:config) do
    Struct.new(:show_page_numbers, :highlight_quotes, :line_spacing)
          .new(true, false, :compact)
  end

  let(:renderer_class) do
    Class.new do
      include EbookReader::ReaderDisplay

      attr_accessor :config

      def initialize(config)
        @config = config
      end
    end
  end

  let(:renderer) { renderer_class.new(config) }

  let(:context) do
    EbookReader::Models::PageRenderingContext.new(
      lines: ['short line', 'another very long line'],
      offset: 0,
      dimensions: EbookReader::Models::Dimensions.new(width: 15, height: 2),
      position: EbookReader::Models::Position.new(row: 1, col: 1),
      show_page_num: true
    )
  end

  before do
    allow(EbookReader::Terminal).to receive(:size).and_return([24, 80])
  end

  it 'delegates to internal helpers' do
    expect(renderer).to receive(:render_column_content).with(context).and_call_original
    expect(renderer).to receive(:draw_page_number).with(context).and_call_original
    renderer.draw_column(context)
  end

  it 'renders page number at the bottom of the column' do
    calls = []
    allow(EbookReader::Terminal).to receive(:write) do |row, col, text|
      calls << [row, col, text]
    end

    renderer.draw_column(context)

    page_call = calls.find { |_, _, text| text.include?('1/1') || text.include?('1/2') }
    expect(page_call).not_to be_nil
    expect(page_call[0]).to eq(context.position.row + context.dimensions.height - 1)
  end

  it 'skips rendering for invalid parameters' do
    bad_context = EbookReader::Models::PageRenderingContext.new(
      lines: [],
      offset: 0,
      dimensions: EbookReader::Models::Dimensions.new(width: 5, height: 0),
      position: EbookReader::Models::Position.new(row: 1, col: 1),
      show_page_num: true
    )

    expect(renderer).not_to receive(:render_column_content)
    renderer.draw_column(bad_context)
  end
end

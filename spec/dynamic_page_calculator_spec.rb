# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::DynamicPageCalculator do
  let(:dummy_chapters) do
    [
      EbookReader::Models::Chapter.new(number: '1', title: 'C1',
                                       lines: Array.new(20, 'line'), metadata: nil),
      EbookReader::Models::Chapter.new(number: '2', title: 'C2',
                                       lines: Array.new(20, 'line'), metadata: nil),
    ]
  end

  let(:dummy_doc) do
    instance_double('EPUBDocument', chapter_count: dummy_chapters.size)
  end

  before do
    allow(dummy_doc).to receive(:get_chapter) { |idx| dummy_chapters[idx] }
  end

  let(:config) do
    instance_double(EbookReader::Config,
                    show_page_numbers: true,
                    view_mode: :single)
  end

  let(:calculator) do
    Class.new do
      include EbookReader::DynamicPageCalculator

      attr_accessor :doc, :config, :single_page, :left_page, :current_chapter

      def initialize(doc, config)
        @doc = doc
        @config = config
        @single_page = 0
        @left_page = 0
        @current_chapter = 0
      end

      def get_layout_metrics(_width, _height)
        [10, 20]
      end

      def adjust_for_line_spacing(height)
        height
      end

      def wrap_lines(lines, _width)
        lines
      end
    end.new(dummy_doc, config)
  end

  before do
    allow(EbookReader::Terminal).to receive(:size).and_return([24, 80])
    allow(EbookReader::Infrastructure::Logger).to receive(:debug)
  end

  it 'calculates total and current pages' do
    result = calculator.calculate_dynamic_pages
    expect(result).to eq(current: 1, total: 2)

    calculator.current_chapter = 1
    calculator.single_page = 5
    result = calculator.calculate_dynamic_pages
    expect(result).to eq(current: 2, total: 2)
  end

  it 'returns zeros when show_page_numbers is false' do
    allow(config).to receive(:show_page_numbers).and_return(false)
    expect(calculator.calculate_dynamic_pages).to eq(current: 0, total: 0)
  end
end

# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::ReaderController do
  before do
    mock_terminal(width: 80, height: 24)

    # Stub DocumentService to avoid filesystem and provide many lines
    stub_const('EbookReader::Infrastructure::DocumentService', Class.new do
      FakeChapter = Struct.new(:title, :lines)
      class FakeDoc
        def initialize(ch) = (@ch = ch)
        def chapter_count = 1
        def chapters = [@ch]
        def get_chapter(_i) = @ch
        def title = 'Doc'
        def language = 'en'
      end

      def initialize(_path); end

      def load_document
        # generate 500 words so wrapping works
        text = (1..500).map { |i| "word#{i}" }.each_slice(10).map { |arr| arr.join(' ') }
        ch = FakeChapter.new('Ch1', text)
        FakeDoc.new(ch)
      end
    end)
  end

  it 'prefetches ±20 pages around current page when fetching window' do
    # Spy wrapping service to assert prefetch arguments
    wrapping = instance_double('WrappingService')
    allow(wrapping).to receive(:wrap_window).and_return(Array.new(10, 'x'))
    allow(wrapping).to receive(:prefetch_windows)

    container = EbookReader::Domain::ContainerFactory.create_default_container
    container.register(:wrapping_service, wrapping)

    ctrl = described_class.new('/tmp/fake.epub', nil, container)

    # Call wrapped_window_for with display_height = 10, offset = 100
    chapter_index = 0
    col_width = 30
    offset = 100
    display_height = 10

    ctrl.send(:wrapped_window_for, chapter_index, col_width, offset, display_height)
    # Give background prefetch thread a tick
    sleep 0.01

    # Expect prefetch for 20 pages back and forth
    pre_pages = 20
    prefetch_start = [offset - (pre_pages * display_height), 0].max
    prefetch_end = offset + (pre_pages * display_height) + (display_height - 1)
    prefetch_len = prefetch_end - prefetch_start + 1

    expect(wrapping).to have_received(:prefetch_windows).with(instance_of(Array), chapter_index,
                                                              col_width, prefetch_start, prefetch_len)
  end
end

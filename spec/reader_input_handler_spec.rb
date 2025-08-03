# frozen_string_literal: true

require 'spec_helper'

class DummyReader
  attr_accessor :mode, :toc_selected, :bookmark_selected, :bookmarks, :current_chapter
  attr_reader :doc

  def initialize
    @doc = double('doc', chapter_count: 2,
                         get_chapter: EbookReader::Models::Chapter.new(number: '1', title: 'Ch', lines: %w[a b c], metadata: nil))
    @mode = :read
    @toc_selected = 0
    @bookmark_selected = 0
    @bookmarks = [EbookReader::Models::Bookmark.new(chapter_index: 0, line_offset: 0,
                                                    text_snippet: 'b', created_at: Time.now)]
    @current_chapter = 0
  end

  def method_missing(name, *args)
    # allow any method call for expectations
  end

  def respond_to_missing?(*_args)
    true
  end
end

RSpec.describe EbookReader::Services::ReaderInputHandler do
  let(:reader) { DummyReader.new }
  subject(:handler) { described_class.new(reader) }

  before do
    allow(EbookReader::Terminal).to receive(:size).and_return([24, 80])
    allow(reader).to receive(:get_layout_metrics).and_return([40, 20])
    allow(reader).to receive(:adjust_for_line_spacing).and_return(20)
    allow(reader).to receive(:wrap_lines).and_return(%w[a b c])
  end

  describe '#process_input' do
    it 'exits help mode' do
      reader.mode = :help
      expect(reader).to receive(:switch_mode).with(:read)
      handler.process_input('x')
    end

    it 'delegates toc input' do
      reader.mode = :toc
      expect(handler).to receive(:handle_toc_input).with('j')
      handler.process_input('j')
    end

    it 'delegates bookmarks input' do
      reader.mode = :bookmarks
      expect(handler).to receive(:handle_bookmarks_input).with('j')
      handler.process_input('j')
    end

    it 'handles reading input otherwise' do
      expect(handler).to receive(:handle_reading_input).with('q')
      handler.process_input('q')
    end
  end

  describe '#handle_reading_input' do
    it 'maps keys to reader actions' do
      expect(reader).to receive(:quit_to_menu)
      handler.handle_reading_input('q')

      expect(reader).to receive(:switch_mode).with(:help)
      handler.handle_reading_input('?')

      expect(reader).to receive(:toggle_view_mode)
      handler.handle_reading_input('v')

      expect(handler).to receive(:handle_navigation_input).with('x')
      handler.handle_reading_input('x')
    end
  end

  describe '#handle_navigation_input' do
    it 'updates page offsets and calls reader methods' do
      expect(reader).to receive(:scroll_down)
      handler.handle_navigation_input('j')

      expect(reader).to receive(:scroll_up)
      handler.handle_navigation_input('k')
    end
  end

  describe '#handle_toc_input' do
    it 'navigates toc and selects chapter' do
      handler.handle_toc_input('j')
      expect(reader.toc_selected).to eq(1)

      expect(reader).to receive(:jump_to_chapter).with(1)
      expect(reader).to receive(:switch_mode).with(:read)
      handler.handle_toc_input("\r")
    end
  end

  describe '#handle_bookmarks_input' do
    it 'deletes bookmark and jumps' do
      expect(reader).to receive(:delete_selected_bookmark)
      handler.handle_bookmarks_input('d')

      expect(reader).to receive(:jump_to_bookmark)
      handler.handle_bookmarks_input("\r")
    end
  end
end

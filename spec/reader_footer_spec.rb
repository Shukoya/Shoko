# frozen_string_literal: true

require 'spec_helper'

class DummyReader
  include EbookReader::ReaderDisplay

  attr_accessor :doc, :current_chapter, :config, :bookmarks, :mode

  def initialize(renderer, config, doc)
    @renderer = renderer
    @config = config
    @doc = doc
    @bookmarks = []
    @current_chapter = 0
    @mode = :read
  end
end

RSpec.describe DummyReader do
  let(:config) do
    cfg = EbookReader::Config.new
    cfg.show_page_numbers = false
    cfg
  end
  let(:renderer) { EbookReader::UI::ReaderRenderer.new(config) }
  let(:doc) do
    instance_double(EbookReader::EPUBDocument, title: 'Test Book', chapter_count: 1, language: 'en')
  end
  subject(:reader) { described_class.new(renderer, config, doc) }

  before do
    allow(EbookReader::Terminal).to receive(:write)
  end

  it 'delegates footer rendering to the renderer' do
    expect(renderer).to receive(:render_footer)
    reader.draw_footer(24, 80)
  end

  it 'does not raise when drawing the footer' do
    expect { reader.draw_footer(24, 80) }.not_to raise_error
  end
end

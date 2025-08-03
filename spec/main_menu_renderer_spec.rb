# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::UI::MainMenuRenderer do
  let(:config) { instance_double(EbookReader::Config) }
  let(:renderer) { described_class.new(config) }

  before do
    allow(EbookReader::Terminal).to receive(:write)
  end

  describe '#render_logo' do
    it 'renders ASCII art logo' do
      expect(EbookReader::Terminal).to receive(:write).at_least(6).times
      menu_start = renderer.render_logo(24, 80)
      expect(menu_start).to be > 0
    end

    it 'includes version number' do
      stub_const('EbookReader::VERSION', 'v1.0.0')
      expect(EbookReader::Terminal).to receive(:write).with(anything, anything, /v1.0.0/)
      renderer.render_logo(24, 80)
    end
  end

  describe '#render_menu_item' do
    let(:item) do
      { key: 'f', icon: '📚', text: 'Find Book', desc: 'Browse all EPUBs' }
    end

    it 'renders selected item with highlight' do
      expect(EbookReader::Terminal).to receive(:write).with(10, 20, /▸/)
      expect(EbookReader::Terminal).to receive(:write).with(10, 22, /Find Book/)

      context = described_class::MenuItemContext.new(row: 10, pointer_col: 20,
                                                     text_col: 22, item: item,
                                                     selected: true)
      renderer.render_menu_item(context)
    end

    it 'renders unselected item normally' do
      expect(EbookReader::Terminal).to receive(:write).with(10, 20, /  /)
      expect(EbookReader::Terminal).to receive(:write).with(10, 22, /Find Book/)

      context = described_class::MenuItemContext.new(row: 10, pointer_col: 20,
                                                     text_col: 22, item: item,
                                                     selected: false)
      renderer.render_menu_item(context)
    end
  end

  describe '#render_footer' do
    it 'renders footer text centered' do
      text = 'Test footer'
      expect(EbookReader::Terminal).to receive(:write).with(23, anything, /Test footer/)

      renderer.render_footer(24, 80, text)
    end
  end
end

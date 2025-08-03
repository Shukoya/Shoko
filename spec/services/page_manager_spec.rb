# frozen_string_literal: true

require 'spec_helper'
require 'ebook_reader/services/page_manager'

RSpec.describe EbookReader::Services::PageManager do
  it 'exposes a public find_page_index method used for restoring progress' do
    doc = double('doc', chapters: [double(lines: %w[line1 line2 line3])])
    config = double('config', page_numbering_mode: :dynamic, view_mode: :single, line_spacing: :normal)
    pm = described_class.new(doc, config)
    pm.build_page_map(80, 10)
    expect(pm.find_page_index(0, 0)).to eq(0)
  end
end

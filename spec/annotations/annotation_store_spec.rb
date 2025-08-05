# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Annotations::AnnotationStore, fake_fs: true do
  let(:epub_path) { '/books/book.epub' }
  let(:range) { { 'start' => { 'x' => 0, 'y' => 0 }, 'end' => { 'x' => 1, 'y' => 0 } } }

  it 'adds and retrieves annotations' do
    described_class.add(epub_path, 'quote', 'note', range, 1)
    annotations = described_class.get(epub_path)
    expect(annotations.length).to eq(1)
    expect(annotations.first['text']).to eq('quote')
  end

  it 'updates an existing annotation' do
    described_class.add(epub_path, 'quote', 'note', range, 1)
    id = described_class.get(epub_path).first['id']
    described_class.update(epub_path, id, 'new note')
    annotations = described_class.get(epub_path)
    expect(annotations.first['note']).to eq('new note')
  end

  it 'deletes an annotation' do
    described_class.add(epub_path, 'quote', 'note', range, 1)
    id = described_class.get(epub_path).first['id']
    described_class.delete(epub_path, id)
    expect(described_class.get(epub_path)).to be_empty
  end
end

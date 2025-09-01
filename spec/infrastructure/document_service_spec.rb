# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Infrastructure::DocumentService do
  it 'returns error document when loading fails' do
    svc = described_class.new('/nonexistent/file.epub')
    allow(EbookReader::EPUBDocument).to receive(:new).and_raise(StandardError.new('boom'))
    doc = svc.load_document
    expect(doc).to be_a(EbookReader::Infrastructure::ErrorDocument)
    chapter = doc.get_chapter(0)
    expect(chapter.title).to include('Error')
  end

  it 'provides wrapped content for error document' do
    svc = described_class.new('/nonexistent/file.epub')
    allow(EbookReader::EPUBDocument).to receive(:new).and_raise(StandardError.new('boom'))
    svc.load_document
    content = svc.get_wrapped_page_content(0, 0, 10, 5)
    expect(content).to be_a(Array)
  end

  it 'exposes page content and line counts on error doc' do
    svc = described_class.new('/nonexistent/file.epub')
    allow(EbookReader::EPUBDocument).to receive(:new).and_raise(StandardError.new('boom'))
    svc.load_document
    page = svc.get_page_content(0, 0, 3)
    expect(page).to be_a(Array)
    lines = svc.get_chapter_wrapped_line_count(0, 10)
    expect(lines).to be_a(Integer)
    expect(lines).to be >= 0
  end
end

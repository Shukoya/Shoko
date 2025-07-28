require "spec_helper"

RSpec.describe EbookReader::Reader, 'dynamic navigation' do
  let(:epub_path) { '/dynamic.epub' }
  let(:config) { EbookReader::Config.new }
  let(:lines) { (1..100).map { |i| "Line #{i}" } }
  let(:chapter) do
    EbookReader::Models::Chapter.new(number: '1', title: 'Ch1', lines: lines, metadata: nil)
  end
  let(:doc) do
    instance_double(EbookReader::EPUBDocument,
                    title: 'Dynamic Test',
                    language: 'en',
                    chapter_count: 1,
                    chapters: [chapter])
  end
  subject(:reader) { described_class.new(epub_path, config) }

  before do
    allow(EbookReader::EPUBDocument).to receive(:new).and_return(doc)
    allow(doc).to receive(:get_chapter).with(0).and_return(chapter)
    allow(EbookReader::BookmarkManager).to receive(:get).and_return([])
    allow(EbookReader::ProgressManager).to receive(:load).and_return(nil)
    allow(EbookReader::ProgressManager).to receive(:save)
  end

  it 'advances pages without skipping content in dynamic mode' do
    config.view_mode = :single
    config.page_numbering_mode = :dynamic
    reader.send(:update_page_map, 80, 24)

    first_page = reader.current_page_lines.dup
    reader.next_page
    second_page = reader.current_page_lines

    expect(first_page.last).to eq('Line 22')
    expect(second_page.first).to eq('Line 23')

    reader.next_page
    third_page = reader.current_page_lines

    expect(second_page.last).to eq('Line 44')
    expect(third_page.first).to eq('Line 45')
  end
end

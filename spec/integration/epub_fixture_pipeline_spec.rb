# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'EPUB fixture pipeline' do
  FIXTURES_DIR = File.expand_path('../../testing epubs', __dir__)

  def fixture_paths
    Dir.glob(File.join(FIXTURES_DIR, '*.epub')).sort
  end

  def import_fixture(path)
    importer = EbookReader::Infrastructure::EpubImporter.new
    data = importer.import(path)
    # Resource bytes are irrelevant for these regression tests and can be large.
    data.resources.clear if data.respond_to?(:resources) && data.resources.is_a?(Hash)
    data
  end

  def assemble_lines(blocks, width: 80)
    assembler = EbookReader::Domain::Services::FormattingService::LineAssembler.new(width)
    assembler.build(blocks)
  end

  def first_content_chapter_samples(data, limit: 2)
    samples = []
    data.chapters.each_with_index do |chapter, idx|
      blocks = EbookReader::Infrastructure::Parsers::XHTMLContentParser.new(chapter.raw_content).parse
      next if blocks.empty?

      samples << [idx, blocks]
      break if samples.length >= limit
    end
    samples
  end

  it 'loads fixture epubs from testing epubs/' do
    expect(File.directory?(FIXTURES_DIR)).to be(true)
    expect(fixture_paths).not_to be_empty
  end

  it 'imports every fixture with a usable, navigable TOC' do
    aggregate_failures do
      fixture_paths.each do |path|
        data = import_fixture(path)
        filename = File.basename(path)

        expect(data.chapters).not_to be_empty, filename
        expect(data.toc_entries).not_to be_empty, filename

        navigable = data.toc_entries.select(&:navigable)
        expect(navigable).not_to be_empty, filename

        navigable.each do |entry|
          expect(entry.chapter_index).to be_a(Integer), filename
          expect(entry.chapter_index).to be_between(0, data.chapters.length - 1), filename
        end
      end
    end
  end

  it 'handles fragment hrefs by mapping them to spine chapters' do
    aggregate_failures do
      [
        'Der Alchimist  (German Edition) -- Coelho, Paulo.epub',
        'Worte des Vortsitzenden Mao Tsetung.epub',
      ].each do |filename|
        path = File.join(FIXTURES_DIR, filename)
        data = import_fixture(path)

        fragment_entries = data.toc_entries.select { |e| e.href.to_s.include?('#') }
        expect(fragment_entries).not_to be_empty, filename

        fragment_entries.each do |entry|
          expect(entry.navigable).to be(true), filename
          expect(entry.chapter_index).not_to be_nil, filename
        end
      end
    end
  end

  it 'parses EPUB3 nav.xhtml (nested TOC levels)' do
    path = File.join(FIXTURES_DIR, 'The Art of War (Sun Tzu).epub')
    data = import_fixture(path)

    expect(data.toc_entries).not_to be_empty
    expect(data.toc_entries.map(&:level).max).to be > 0
  end

  it 'preserves many-to-one TOC mappings (duplicate chapter indexes)' do
    path = File.join(FIXTURES_DIR, 'Der Alchimist  (German Edition) -- Coelho, Paulo.epub')
    data = import_fixture(path)

    duplicates = data.toc_entries
      .select(&:navigable)
      .group_by(&:chapter_index)
      .values
      .any? { |entries| entries.length > 1 }

    expect(duplicates).to be(true)
  end

  it 'parses and lays out representative chapters across all fixtures' do
    aggregate_failures do
      fixture_paths.each do |path|
        data = import_fixture(path)
        filename = File.basename(path)
        samples = first_content_chapter_samples(data, limit: 2)
        expect(samples).not_to be_empty, filename

        samples.each do |idx, blocks|
          lines = assemble_lines(blocks, width: 80)
          expect(lines).not_to be_empty, "#{filename} chapter=#{idx}"
        end
      end
    end
  end

  it 'renders image placeholders for <img> content' do
    path = File.join(FIXTURES_DIR, 'Momo (Michael Ende).epub')
    data = import_fixture(path)

    idx = data.chapters.find_index { |ch| ch.raw_content.to_s.downcase.include?('<img') }
    expect(idx).not_to be_nil

    blocks = EbookReader::Infrastructure::Parsers::XHTMLContentParser.new(data.chapters[idx].raw_content).parse
    expect(blocks.any? { |b| b.type == :image || b.text.include?('[Image') }).to be(true)

    lines = assemble_lines(blocks, width: 80)
    expect(lines.map(&:text).join("\n")).to include('[Image')
  end

  it 'decodes HTML entities like &nbsp; during parsing and layout' do
    path = File.join(FIXTURES_DIR, 'Der_Prozess.epub')
    data = import_fixture(path)

    idx = data.chapters.find_index { |ch| ch.raw_content.to_s.include?('&nbsp;') } || 1
    blocks = EbookReader::Infrastructure::Parsers::XHTMLContentParser.new(data.chapters[idx].raw_content).parse
    lines = assemble_lines(blocks, width: 80)

    rendered = lines.map(&:text).join("\n")
    expect(rendered).not_to include('&nbsp;')
  end
end

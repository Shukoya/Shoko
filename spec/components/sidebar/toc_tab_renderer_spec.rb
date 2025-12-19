# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Components::Sidebar::TocTabRenderer do
  let(:state) { instance_double('State') }
  let(:renderer) { described_class.new(state) }

  let(:doc) do
    double('Document', chapters: chapters, toc_entries: toc_entries)
  end

  let(:chapters) do
    [
      double('Chapter', title: 'Chapter One'),
      double('Chapter', title: 'Chapter Two'),
    ]
  end

  let(:toc_entries) do
    [
      EbookReader::Domain::Models::TOCEntry.new(title: 'Part One', href: 'part1.xhtml', level: 0,
                                                chapter_index: nil, navigable: false),
      EbookReader::Domain::Models::TOCEntry.new(title: 'Chapter One', href: 'chapter1.xhtml', level: 1,
                                                chapter_index: 0, navigable: true),
      EbookReader::Domain::Models::TOCEntry.new(title: 'Chapter Two', href: 'chapter2.xhtml', level: 1,
                                                chapter_index: 1, navigable: true),
    ]
  end

  it 'keeps ancestor part headings when filtering chapters' do
    allow(state).to receive(:get).with(%i[reader sidebar_toc_filter]).and_return('Chapter Two')

    filtered = renderer.send(:get_filtered_entries, toc_entries, state)
    expect(filtered.map(&:title)).to eq(['Part One', 'Chapter Two'])
  end

  it 'renders selected TOC rows without crashing' do
    segments = [
      ['├─', 'dim'],
      ['', 'primary'],
      [' ', nil],
      ['Chapter One', 'primary'],
    ]

    line = renderer.send(:compose_line, segments, true)

    expect(line).to start_with("#{EbookReader::Terminal::ANSI::BG_GREY}#{EbookReader::Terminal::ANSI::WHITE}")
    expect(line).to include('├─ Chapter One')
    expect(line).to end_with(EbookReader::Terminal::ANSI::RESET)
  end
end

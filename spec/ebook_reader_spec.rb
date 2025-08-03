# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader do
  it 'has a version number' do
    expect(EbookReader::VERSION).not_to be nil
  end

  it 'loads the necessary classes' do
    expect(defined?(EbookReader::CLI)).to be_truthy
    expect(defined?(EbookReader::MainMenu)).to be_truthy
    expect(defined?(EbookReader::Reader)).to be_truthy
    expect(defined?(EbookReader::Config)).to be_truthy
    expect(defined?(EbookReader::Terminal)).to be_truthy
    expect(defined?(EbookReader::EPUBDocument)).to be_truthy
    expect(defined?(EbookReader::EPUBFinder)).to be_truthy
    expect(defined?(EbookReader::RecentFiles)).to be_truthy
    expect(defined?(EbookReader::ProgressManager)).to be_truthy
    expect(defined?(EbookReader::BookmarkManager)).to be_truthy
  end

  it 'loads UI components' do
    expect(defined?(EbookReader::UI)).to be_truthy
    expect(defined?(EbookReader::UI::Screens::BrowseScreen)).to be_truthy
    expect(defined?(EbookReader::UI::MainMenuRenderer)).to be_truthy
    expect(defined?(EbookReader::UI::ReaderRenderer)).to be_truthy
  end

  it 'loads services' do
    expect(defined?(EbookReader::Services)).to be_truthy
    expect(defined?(EbookReader::Services::LibraryScanner)).to be_truthy
    expect(defined?(EbookReader::Helpers::HTMLProcessor)).to be_truthy
    expect(defined?(EbookReader::Helpers::OPFProcessor)).to be_truthy
    expect(defined?(EbookReader::Helpers::ReaderHelpers)).to be_truthy
  end

  it 'loads concerns' do
    expect(defined?(EbookReader::Concerns)).to be_truthy
    expect(defined?(EbookReader::Concerns::InputHandler)).to be_truthy
  end

  it 'defines constants module' do
    expect(defined?(EbookReader::Constants)).to be_truthy
  end
end

# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Browse library respects current selection', :fakefs do
  let(:home) { '/home/test' }
  let(:books_dir) { File.join(home, 'books') }
  let(:book_a_path) { File.join(books_dir, 'book_a.epub') }
  let(:book_b_path) { File.join(books_dir, 'book_b.epub') }
  let(:entries) do
    [
      { 'path' => book_a_path, 'name' => 'Alpha', 'size' => 1 },
      { 'path' => book_b_path, 'name' => 'Beta', 'size' => 1 },
    ]
  end

  before do
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = File.join(home, '.cache')
    ENV['XDG_CONFIG_HOME'] = File.join(home, '.config')

    FileUtils.mkdir_p(books_dir)
    File.write(book_a_path, 'stub-a')
    File.write(book_b_path, 'stub-b')

    allow(EbookReader::RecentFiles).to receive(:add)
    allow(EbookReader::RecentFiles).to receive(:load).and_return([])
    allow(EbookReader::RecentFiles).to receive(:clear)
  end

  after do
    ENV.delete('READER_SKIP_PROGRESS_OVERLAY')
  end

  def build_menu
    menu = EbookReader::MainMenu.new
    menu.catalog.library_scanner.epubs = entries
    menu.filtered_epubs = entries
    menu.main_menu_component.browse_screen.filtered_epubs = entries

    state = menu.state
    state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(mode: :browse, browse_selected: 0))
    menu
  end

  def drive_sequence(menu)
    terminal = menu.terminal_service

    terminal.queue_input('q')
    menu.open_selected_book

    menu.main_menu_component.browse_screen.navigate(:down)

    terminal.queue_input('q')
    menu.open_selected_book

    document = menu.dependencies.resolve(:document)
    expect(document).to respond_to(:canonical_path)
    expect(document.canonical_path).to eq(book_b_path)
  end

  context 'with progress overlay' do
    it 'opens the newly selected book' do
      ENV.delete('READER_SKIP_PROGRESS_OVERLAY')
      allow_any_instance_of(EbookReader::Controllers::Menu::PaginationBuilder).to receive(:build)

      menu = build_menu
      drive_sequence(menu)
    end
  end

  context 'when skipping the progress overlay' do
    it 'opens the newly selected book' do
      ENV['READER_SKIP_PROGRESS_OVERLAY'] = '1'

      menu = build_menu
      drive_sequence(menu)
    end
  end
end

# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MainMenu search mode integration' do
  before do
    # Mock terminal so no real IO is attempted
    mock_terminal(width: 80, height: 24)
  end

  def build_menu_with_books(books)
    deps = EbookReader::Domain::ContainerFactory.create_default_container
    menu = EbookReader::MainMenu.new(deps)
    # Inject fake scanner data
    scanner = menu.instance_variable_get(:@scanner)
    scanner.epubs = books
    menu
  end

  it 'toggles search with /, edits text, navigates results with arrows, and exits with /' do
    books = [
      { 'name' => 'Alpha', 'author' => 'A', 'path' => '/alpha.epub' },
      { 'name' => 'Beta', 'author' => 'B', 'path' => '/beta.epub' },
      { 'name' => 'Gamma', 'author' => 'G', 'path' => '/gamma.epub' },
    ]
    menu = build_menu_with_books(books)
    dispatcher = menu.instance_variable_get(:@dispatcher)
    state = menu.state

    # Ensure we are in browse mode first
    menu.switch_to_browse
    expect(EbookReader::Domain::Selectors::MenuSelectors.mode(state)).to eq(:browse)

    # Press '/' to start search
    dispatcher.handle_key('/')
    expect(EbookReader::Domain::Selectors::MenuSelectors.mode(state)).to eq(:search)
    expect(state.get(%i[menu search_active])).to eq(true)

    # Type a query: 'a'
    dispatcher.handle_key('a')
    expect(state.get(%i[menu search_query])).to eq('a')
    # Cursor advances
    expect(state.get(%i[menu search_cursor])).to eq(1)

    # Add another char 'l'
    dispatcher.handle_key('l')
    expect(state.get(%i[menu search_query])).to eq('al')
    expect(state.get(%i[menu search_cursor])).to eq(2)

    # Navigate results with down arrow and up arrow
    dispatcher.handle_key("\e[B") # down
    expect(state.get(%i[menu browse_selected])).to be >= 0
    dispatcher.handle_key("\e[A") # up
    expect(state.get(%i[menu browse_selected])).to be >= 0

    # Press '/' again to exit search
    dispatcher.handle_key('/')
    expect(EbookReader::Domain::Selectors::MenuSelectors.mode(state)).to eq(:browse)
    expect(state.get(%i[menu search_active])).to eq(false)
  end

  it 'opens the currently selected filtered book with Enter (not the first browse item)', :fakefs do
    books = [
      { 'name' => 'American Psycho', 'author' => 'Bret Easton Ellis', 'path' => '/ap.epub' },
      { 'name' => 'Gamma', 'author' => 'G', 'path' => '/gamma.epub' },
      { 'name' => 'Alpha', 'author' => 'A', 'path' => '/alpha.epub' },
    ]
    menu = build_menu_with_books(books)
    dispatcher = menu.instance_variable_get(:@dispatcher)
    state = menu.state

    menu.switch_to_browse
    expect(EbookReader::Domain::Selectors::MenuSelectors.mode(state)).to eq(:browse)

    # Start search and type 'a' which will match American Psycho, Gamma, Alpha
    dispatcher.handle_key('/')
    dispatcher.handle_key('a')
    expect(state.get(%i[menu search_query])).to eq('a')

    # Create the files on the fake filesystem for selection to succeed
    FileUtils.mkdir_p('/'); File.write('/ap.epub', ''); File.write('/gamma.epub', ''); File.write('/alpha.epub', '')

    # Move selection down once (should point to the second filtered match)
    dispatcher.handle_key("\e[B")

    # Expect run_reader to be invoked with the selected book path, not the first default
    expect(menu).to receive(:run_reader).with('/gamma.epub')
    dispatcher.handle_key("\r")
  end
end

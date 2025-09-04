# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Library navigation and open via keys' do
  include FakeFS::SpecHelpers

  let(:home) { '/home/test' }
  let(:xdg_cache) { File.join(home, '.cache') }
  let(:reader_cache_root) { File.join(xdg_cache, 'reader') }
  let(:book1_dir) { File.join(reader_cache_root, 'booksha1') }
  let(:book2_dir) { File.join(reader_cache_root, 'booksha2') }

  before do
    ENV['HOME'] = home
    ENV['XDG_CACHE_HOME'] = xdg_cache
    # Book 1
    FileUtils.mkdir_p(File.join(book1_dir, 'META-INF'))
    FileUtils.mkdir_p(File.join(book1_dir, 'OEBPS'))
    File.write(File.join(book1_dir, 'manifest.json'), JSON.generate({
      'title' => 'Cached One',
      'author' => 'Author A',
      'authors' => ['Author A'],
      'opf_path' => 'OEBPS/content.opf',
      'spine' => ['OEBPS/ch1.xhtml']
    }))
    File.write(File.join(book1_dir, 'META-INF', 'container.xml'), '<c/>')
    File.write(File.join(book1_dir, 'OEBPS', 'content.opf'), '<opf/>')
    File.write(File.join(book1_dir, 'OEBPS', 'ch1.xhtml'), '<html><body><p>Hi</p></body></html>')
    # Book 2
    FileUtils.mkdir_p(File.join(book2_dir, 'META-INF'))
    FileUtils.mkdir_p(File.join(book2_dir, 'OEBPS'))
    File.write(File.join(book2_dir, 'manifest.json'), JSON.generate({
      'title' => 'Cached Two',
      'author' => 'Author B',
      'authors' => ['Author B'],
      'opf_path' => 'OEBPS/content.opf',
      'spine' => ['OEBPS/ch1.xhtml']
    }))
    File.write(File.join(book2_dir, 'META-INF', 'container.xml'), '<c/>')
    File.write(File.join(book2_dir, 'OEBPS', 'content.opf'), '<opf/>')
    File.write(File.join(book2_dir, 'OEBPS', 'ch1.xhtml'), '<html><body><p>Yo</p></body></html>')
  end

  it 'navigates with arrow keys and opens selected with Enter' do
    # Stub MouseableReader to capture open path without launching terminal
    reader = class_double('EbookReader::MouseableReader').as_stubbed_const
    # Expect open of book 2 after navigating down
    expect(reader).to receive(:new).with(book2_dir, anything, anything).and_return(double(run: true))

    mm = EbookReader::MainMenu.new
    mm.switch_to_mode(:library)
    expect(mm.main_menu_component.current_screen.items.length).to eq(2)
    dispatcher = mm.instance_variable_get(:@dispatcher)

    # Down (vi key) to second item
    dispatcher.handle_key('j')
    # Enter to open
    dispatcher.handle_key("\r")
  end

  it 'moves selection up and down within bounds' do
    mm = EbookReader::MainMenu.new
    mm.switch_to_mode(:library)

    state = mm.state
    dispatcher = mm.instance_variable_get(:@dispatcher)

    expect(EbookReader::Domain::Selectors::MenuSelectors.browse_selected(state)).to eq(0)

    # Sanity: direct call updates selection
    mm.library_down
    expect(EbookReader::Domain::Selectors::MenuSelectors.browse_selected(state)).to eq(1)
    mm.library_up
    expect(EbookReader::Domain::Selectors::MenuSelectors.browse_selected(state)).to eq(0)

    # Move down to 1 (vi key)
    dispatcher.handle_key('j')
    expect(EbookReader::Domain::Selectors::MenuSelectors.browse_selected(state)).to eq(1)

    # Move up back to 0 (vi key)
    dispatcher.handle_key('k')
    expect(EbookReader::Domain::Selectors::MenuSelectors.browse_selected(state)).to eq(0)

    # Move up stays at 0 (no negative)
    dispatcher.handle_key('k')
    expect(EbookReader::Domain::Selectors::MenuSelectors.browse_selected(state)).to eq(0)
  end
end

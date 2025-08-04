# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/ebook_reader/models/line_drawing_context'

RSpec.describe 'Comprehensive Coverage Tests' do
  describe EbookReader::Reader do
    let(:epub_path) { '/test.epub' }
    let(:config) { EbookReader::Config.new }
    let(:doc) do
      instance_double(EbookReader::EPUBDocument,
                      title: 'Test Book',
                      language: 'en',
                      chapter_count: 2,
                      chapters: [
                        EbookReader::Models::Chapter.new(number: '1', title: 'Ch1',
                                                         lines: Array.new(100, 'Line'), metadata: nil),
                        EbookReader::Models::Chapter.new(number: '2', title: 'Ch2',
                                                         lines: Array.new(50, 'Line'), metadata: nil),
                      ])
    end
    let(:reader) { described_class.new(epub_path, config) }

    before do
      allow(EbookReader::EPUBDocument).to receive(:new).and_return(doc)
      allow(doc).to receive(:get_chapter) { |i| doc.chapters[i] }
      allow(EbookReader::Terminal).to receive(:size).and_return([24, 80])
      allow(EbookReader::Terminal).to receive(:write)
      allow(EbookReader::BookmarkManager).to receive(:get).and_return([])
      allow(EbookReader::ProgressManager).to receive(:load).and_return(nil)
      allow(EbookReader::ProgressManager).to receive(:save)
    end

    describe 'edge case handling' do
      it 'handles terminal resize during operation' do
        allow(EbookReader::Terminal).to receive(:size).and_return([24, 80], [30, 100])

        reader.send(:update_page_map, 80, 24)
        expect(reader.instance_variable_get(:@last_width)).to eq(80)

        reader.send(:update_page_map, 100, 30)
        expect(reader.instance_variable_get(:@last_width)).to eq(100)
      end

      it 'handles empty chapter lines gracefully' do
        allow(doc).to receive(:get_chapter).and_return(
          EbookReader::Models::Chapter.new(number: '1', title: 'Empty', lines: [], metadata: nil)
        )
        expect { reader.send(:draw_single_screen, 24, 80) }.not_to raise_error
      end

      it 'handles nil chapter gracefully' do
        allow(doc).to receive(:get_chapter).and_return(nil)
        expect { reader.send(:draw_split_screen, 24, 80) }.not_to raise_error
      end

      it 'handles very small terminal dimensions' do
        allow(EbookReader::Terminal).to receive(:size).and_return([5, 20])
        expect { reader.send(:update_page_map, 20, 5) }.not_to raise_error
      end

      it 'handles page navigation at boundaries' do
        reader.instance_variable_set(:@current_chapter, 1)
        reader.instance_variable_set(:@single_page, 0)

        reader.prev_page
        expect(reader.instance_variable_get(:@current_chapter)).to eq(0)
      end

      it 'handles bookmark operations with invalid data' do
        allow(doc).to receive(:get_chapter).and_return(nil)
        expect { reader.send(:add_bookmark) }.not_to raise_error
      end

      it 'calculates line spacing adjustments correctly' do
        config.line_spacing = :compact
        expect(reader.send(:adjust_for_line_spacing, 20)).to eq(20)

        config.line_spacing = :relaxed
        expect(reader.send(:adjust_for_line_spacing, 20)).to eq(10)

        config.line_spacing = :normal
        expect(reader.send(:adjust_for_line_spacing, 20)).to eq(20)
      end

      it 'handles all navigation keys properly' do
        keys = %w[j k l h n p g G Space]
        keys.each do |key|
          expect { reader.send(:handle_navigation_input, key) }.not_to raise_error
        end
      end

      it 'properly formats help screen content' do
        lines = reader.send(:build_help_lines)
        expect(lines).to include('Navigation Keys:')
        expect(lines).to include('View Options:')
        expect(lines).to include('Features:')
      end

      it 'handles ToC navigation with many chapters' do
        allow(doc).to receive(:chapter_count).and_return(50)
        reader.instance_variable_set(:@toc_selected, 25)

        range = reader.send(:calculate_toc_visible_range, 10, 50)
        expect(range.size).to eq(10)
      end

      it 'handles message display timeout' do
        reader.send(:set_message, 'Test', 0.1)
        expect(reader.instance_variable_get(:@message)).to eq('Test')
        sleep 0.2
        expect(reader.instance_variable_get(:@message)).to be_nil
      end
    end

    describe 'split view specific behavior' do
      before { config.view_mode = :split }

      it 'scrolls both pages together' do
        reader.instance_variable_set(:@max_page, 10)
        reader.scroll_down
        expect(reader.instance_variable_get(:@left_page)).to eq(1)
        expect(reader.instance_variable_get(:@right_page)).to eq(1)
      end

      it 'handles split view page transitions' do
        reader.instance_variable_set(:@right_page, 10)
        reader.send(:handle_split_next_page, 5, 10)
        expect(reader.instance_variable_get(:@left_page)).to eq(10)
      end

      it 'draws divider between columns' do
        expect(reader).to receive(:draw_divider)
        reader.send(:draw_split_screen, 24, 80)
      end
    end

    describe 'progress and state management' do
      it 'saves progress with correct data' do
        expect(EbookReader::ProgressManager).to receive(:save).with(epub_path, 0, 0)
        reader.send(:save_progress)
      end

      it 'loads progress from previous session' do
        allow(EbookReader::ProgressManager).to receive(:load).and_return({
                                                                           'chapter' => 1,
                                                                           'line_offset' => 25,
                                                                         })

        new_reader = described_class.new(epub_path, config)
        expect(new_reader.instance_variable_get(:@current_chapter)).to eq(1)
        expect(new_reader.instance_variable_get(:@single_page)).to eq(25)
      end

      it 'handles corrupted progress data' do
        allow(EbookReader::ProgressManager).to receive(:load).and_return({
                                                                           'chapter' => 999,
                                                                           'line_offset' => -5,
                                                                         })

        new_reader = described_class.new(epub_path, config)
        expect(new_reader.instance_variable_get(:@current_chapter)).to eq(0)
      end
    end
  end

  describe EbookReader::MainMenu do
    let(:menu) { described_class.new }
    let(:scanner) { menu.instance_variable_get(:@scanner) }

    before do
      allow(EbookReader::Terminal).to receive(:setup)
      allow(EbookReader::Terminal).to receive(:cleanup)
      allow(EbookReader::Terminal).to receive(:write)
      allow(EbookReader::Terminal).to receive(:size).and_return([24, 80])
      allow(menu).to receive(:loop).and_yield
    end

    describe 'comprehensive navigation' do
      it 'handles all menu navigation patterns' do
        menu.instance_variable_set(:@mode, :menu)

        # Test wrap around
        menu.instance_variable_set(:@selected, 4)
        menu.send(:handle_menu_input, 'j')
        expect(menu.instance_variable_get(:@selected)).to eq(0)

        menu.send(:handle_menu_input, 'k')
        expect(menu.instance_variable_get(:@selected)).to eq(4)
      end

      it 'handles search with regex special characters properly' do
        scanner.epubs = [
          { 'name' => 'Book (1)', 'path' => '/book1.epub' },
          { 'name' => 'Book [2]', 'path' => '/book2.epub' },
          { 'name' => 'Book $3', 'path' => '/book3.epub' },
        ]

        menu.instance_variable_set(:@search_query, '[2]')
        menu.send(:filter_books)
        filtered = menu.instance_variable_get(:@filtered_epubs)
        expect(filtered.size).to eq(1)
      end

      it 'handles rapid key input' do
        menu.instance_variable_set(:@mode, :browse)
        menu.instance_variable_set(:@filtered_epubs, Array.new(10) do |i|
          { 'name' => "Book #{i}" }
        end)

        5.times { menu.send(:handle_browse_input, 'j') }
        expect(menu.instance_variable_get(:@browse_selected)).to eq(5)
      end

      it 'handles empty search results gracefully' do
        scanner.epubs = [{ 'name' => 'Book', 'path' => '/book.epub' }]
        menu.instance_variable_set(:@search_query, 'xyz')

        menu.send(:filter_books)
        expect(menu.instance_variable_get(:@filtered_epubs)).to be_empty
      end
    end

    describe 'file dialog edge cases' do
      it 'handles various path formats' do
        paths = [
          '"/path with spaces/book.epub"',
          "'/another path/book.epub'",
          '/normal/path/book.epub',
          '"nested ""quotes"" path.epub"',
        ]

        paths.each do |path|
          sanitized = menu.send(:sanitize_input_path, "#{path}\n")
          expect(sanitized).not_to include('"')
          expect(sanitized).not_to end_with("\n")
        end
      end

      it 'handles cancel during file input' do
        menu.send(:open_file_dialog)
        expect { menu.send(:handle_open_file_input, "\e") }.not_to raise_error
      end
    end

    describe 'settings management' do
      it 'cycles through all line spacing options' do
        config = menu.instance_variable_get(:@config)

        # Test full cycle
        original = config.line_spacing
        3.times { menu.send(:cycle_line_spacing) }
        expect(config.line_spacing).to eq(original)
      end

      it 'handles all settings changes' do
        expect { menu.send(:handle_setting_change, '1') }.to(change do
          menu.instance_variable_get(:@config).view_mode
        end)

        expect { menu.send(:handle_setting_change, '2') }.to(change do
          menu.instance_variable_get(:@config).show_page_numbers
        end)
      end
    end

    describe 'rendering edge cases' do
      it 'handles very long book titles' do
        scanner.epubs = [{ 'name' => 'A' * 200, 'path' => '/book.epub' }]
        menu.instance_variable_set(:@mode, :browse)
        menu.send(:filter_books)
        allow(EbookReader::Terminal).to receive(:start_frame)
        allow(EbookReader::Terminal).to receive(:end_frame)
        allow(EbookReader::Terminal).to receive(:size).and_return([24, 80])

        expect { menu.send(:draw_screen) }.not_to raise_error
      end

      it 'handles terminal resize during operation' do
        allow(EbookReader::Terminal).to receive(:size).and_return([24, 80], [30, 100])

        expect { menu.send(:draw_screen) }.not_to raise_error
      end
    end
  end

  describe EbookReader::EPUBDocument do
    let(:epub_path) { '/test.epub' }

    describe 'comprehensive parsing' do
      it 'handles all error conditions gracefully' do
        error_conditions = [
          Zip::Error.new('Corrupted'),
          Errno::ENOENT.new('Not found'),
          REXML::ParseException.new('Invalid XML'),
          StandardError.new('Generic error'),
        ]

        error_conditions.each do |error|
          allow(Zip::File).to receive(:open).and_raise(error)
          doc = described_class.new(epub_path)
          expect(doc.chapters).not_to be_empty
          expect(doc.chapters.first[:title]).to match(/Error|Empty/)
        end
      end

      it 'handles malformed OPF files' do
        allow(Dir).to receive(:mktmpdir).and_yield('/tmp/test')
        allow(Zip::File).to receive(:open).and_yield(double('zip', each: nil))

        # Create malformed OPF
        FileUtils.mkdir_p('/tmp/test/META-INF')
        File.write('/tmp/test/META-INF/container.xml', <<-XML)
          <container>
            <rootfiles>
              <rootfile full-path="content.opf"/>
            </rootfiles>
          </container>
        XML

        File.write('/tmp/test/content.opf', '<invalid>')

        doc = described_class.new(epub_path)
        expect(doc.chapters).not_to be_empty
      end
    end
  end

  describe EbookReader::EPUBFinder do
    describe 'comprehensive scanning' do
      it 'handles all skip directory patterns' do
        EbookReader::Constants::SKIP_DIRS.each do |dir|
          expect(described_class.send(:skip_directory?, "/path/#{dir}")).to be true
        end
      end

      it 'handles symbolic links properly' do
        allow(File).to receive(:directory?).and_return(false)
        allow(File).to receive(:symlink?).and_return(true)

        result = described_class.send(:epub_file?, '/link.epub')
        expect(result).to be false
      end

      it 'validates file size requirements' do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:readable?).and_return(true)
        allow(File).to receive(:size).and_return(0)

        result = described_class.send(:epub_file?, '/empty.epub')
        expect(result).to be false
      end
    end
  end

  describe EbookReader::Helpers::HTMLProcessor do
    describe 'comprehensive HTML handling' do
      it 'handles all HTML entities' do
        entities = {
          '&lt;' => '<',
          '&gt;' => '>',
          '&amp;' => '&',
          '&quot;' => '"',
          '&apos;' => "'",
          '&#8212;' => '—',
          '&#x2014;' => '—',
        }

        entities.each do |entity, expected|
          result = described_class.clean_html(entity)
          expect(result).to eq(expected)
        end
      end

      it 'handles nested and malformed tags' do
        cases = [
          '<p><div><span>Text</span></div></p>',
          '<p>Unclosed paragraph',
          '<p><p><p>Triple nested</p></p></p>',
          '<P>Mixed <p>case</P> tags</p>',
        ]

        cases.each do |html|
          result = described_class.html_to_text(html)
          expect(result).to include('Text').or include('Unclosed').or include('Triple').or include('Mixed')
        end
      end
    end
  end

  describe EbookReader::Terminal do
    describe 'comprehensive terminal handling' do
      it 'handles all ANSI sequences' do
        # Test all color combinations
        colors = %w[BLACK RED GREEN YELLOW BLUE MAGENTA CYAN WHITE GRAY]
        colors.each do |color|
          const = described_class::ANSI.const_get(color)
          expect(const).to match(/\e\[\d+m/)
        end

        # Test bright colors
        bright_colors = %w[BRIGHT_RED BRIGHT_GREEN BRIGHT_YELLOW BRIGHT_BLUE BRIGHT_MAGENTA
                           BRIGHT_CYAN BRIGHT_WHITE]
        bright_colors.each do |color|
          const = described_class::ANSI.const_get(color)
          expect(const).to match(/\e\[9\dm/)
        end
      end

      it 'handles control sequences properly' do
        control = described_class::ANSI::Control
        expect(control::CLEAR).to eq("\e[2J")
        expect(control::HOME).to eq("\e[H")
        expect(control::HIDE_CURSOR).to eq("\e[?25l")
        expect(control::SHOW_CURSOR).to eq("\e[?25h")
      end

      it 'handles buffer overflow gracefully' do
        described_class.start_frame
        1000.times { |i| described_class.write(i % 24, i % 80, 'X') }
        expect { described_class.end_frame }.not_to raise_error
      end
    end
  end
end

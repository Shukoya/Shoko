# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Repository Service Integration' do
  let(:dependencies) { EbookReader::Domain::ContainerFactory.create_test_container }
  let(:mock_event_bus) { dependencies.resolve(:event_bus) }
  let(:mock_state_store) { dependencies.resolve(:state_store) }
  let(:book_path) { '/path/to/integration_test.epub' }
  
  before do
    # Register test repositories with mocked storage
    dependencies.register(:bookmark_repository, test_bookmark_repository)
    dependencies.register(:annotation_repository, test_annotation_repository)
    dependencies.register(:progress_repository, test_progress_repository)
    dependencies.register(:config_repository, test_config_repository)
  end

  let(:test_bookmark_repository) do
    instance_double(EbookReader::Domain::Repositories::BookmarkRepository).tap do |repo|
      allow(repo).to receive(:add_for_book).and_return(test_bookmark)
      allow(repo).to receive(:find_by_book_path).and_return([test_bookmark])
      allow(repo).to receive(:delete_for_book).and_return(true)
      allow(repo).to receive(:exists_at_position?).and_return(false)
      allow(repo).to receive(:find_at_position).and_return(nil)
    end
  end

  let(:test_annotation_repository) do
    instance_double(EbookReader::Domain::Repositories::AnnotationRepository).tap do |repo|
      allow(repo).to receive(:add_for_book).and_return(test_annotation)
      allow(repo).to receive(:find_by_book_path).and_return([test_annotation])
      allow(repo).to receive(:update_note).and_return(true)
      allow(repo).to receive(:delete_by_id).and_return(true)
      allow(repo).to receive(:find_all).and_return({book_path => [test_annotation]})
    end
  end

  let(:test_progress_repository) do
    instance_double(EbookReader::Domain::Repositories::ProgressRepository).tap do |repo|
      allow(repo).to receive(:save_for_book).and_return(test_progress)
      allow(repo).to receive(:find_by_book_path).and_return(test_progress)
      allow(repo).to receive(:find_all).and_return({book_path => test_progress})
      allow(repo).to receive(:exists_for_book?).and_return(true)
    end
  end

  let(:test_config_repository) do
    instance_double(EbookReader::Domain::Repositories::ConfigRepository).tap do |repo|
      allow(repo).to receive(:get_view_mode).and_return(:split)
      allow(repo).to receive(:update_view_mode).and_return(true)
      allow(repo).to receive(:get_line_spacing).and_return(:normal)
      allow(repo).to receive(:get_all_config).and_return(default_config)
    end
  end

  let(:test_bookmark) do
    instance_double(EbookReader::Domain::Models::Bookmark,
                    chapter_index: 2,
                    line_offset: 100,
                    text_snippet: 'Integration test bookmark',
                    created_at: Time.now)
  end

  let(:test_annotation) do
    {
      'id' => 'test_id_123',
      'text' => 'Selected text',
      'note' => 'Test annotation note',
      'range' => { 'start' => 100, 'end' => 120 },
      'chapter_index' => 2,
      'created_at' => Time.now.iso8601
    }
  end

  let(:test_progress) do
    EbookReader::Domain::Repositories::ProgressRepository::ProgressData.new(
      chapter_index: 3,
      line_offset: 250,
      timestamp: Time.now.iso8601
    )
  end

  let(:default_config) do
    {
      view_mode: :split,
      line_spacing: :normal,
      show_page_numbers: true,
      page_numbering_mode: :absolute
    }
  end

  describe 'BookmarkService Integration' do
    let(:bookmark_service) { EbookReader::Domain::Services::BookmarkService.new(dependencies) }

    before do
      allow(mock_state_store).to receive(:get).with([:reader, :book_path]).and_return(book_path)
      allow(mock_state_store).to receive(:current_state).and_return({
        reader: {
          book_path: book_path,
          current_chapter: 2,
          left_page: 100
        },
        config: {
          view_mode: :split
        }
      })
      allow(mock_state_store).to receive(:update)
    end

    it 'successfully adds bookmark through repository' do
      expect(test_bookmark_repository).to receive(:add_for_book).with(
        book_path,
        chapter_index: 2,
        line_offset: 100,
        text_snippet: 'Custom snippet'
      ).and_return(test_bookmark)

      expect(mock_event_bus).to receive(:emit_event).with(:bookmark_added, { bookmark: test_bookmark })

      result = bookmark_service.add_bookmark('Custom snippet')
      expect(result).to eq(test_bookmark)
    end

    it 'retrieves bookmarks through repository' do
      expect(test_bookmark_repository).to receive(:find_by_book_path).with(book_path)

      result = bookmark_service.get_bookmarks
      expect(result).to eq([test_bookmark])
    end

    it 'removes bookmark through repository' do
      expect(test_bookmark_repository).to receive(:delete_for_book).with(book_path, test_bookmark)
      expect(mock_event_bus).to receive(:emit_event).with(:bookmark_removed, { bookmark: test_bookmark })

      bookmark_service.remove_bookmark(test_bookmark)
    end

    it 'checks bookmark existence through repository' do
      expect(test_bookmark_repository).to receive(:exists_at_position?).with(book_path, 2, 100)

      bookmark_service.current_position_bookmarked?
    end
  end

  describe 'AnnotationService Integration' do
    let(:annotation_service) { EbookReader::Domain::Services::AnnotationService.new(dependencies) }

    before do
      allow(mock_state_store).to receive(:dispatch)
    end

    it 'successfully adds annotation through repository' do
      expect(test_annotation_repository).to receive(:add_for_book).with(
        book_path,
        text: 'Selected text',
        note: 'Test note',
        range: { start: 100, end: 120 },
        chapter_index: 2,
        page_meta: nil
      ).and_return(test_annotation)

      expect(mock_state_store).to receive(:dispatch).with(
        an_instance_of(EbookReader::Domain::Actions::UpdateAnnotationsAction)
      )

      result = annotation_service.add(book_path, 'Selected text', 'Test note', { start: 100, end: 120 }, 2)
      expect(result).to eq(test_annotation)
    end

    it 'retrieves annotations through repository' do
      expect(test_annotation_repository).to receive(:find_by_book_path).with(book_path)

      result = annotation_service.list_for_book(book_path)
      expect(result).to eq([test_annotation])
    end

    it 'updates annotation through repository' do
      expect(test_annotation_repository).to receive(:update_note).with(book_path, 'test_id_123', 'Updated note')
      expect(mock_state_store).to receive(:dispatch).with(
        an_instance_of(EbookReader::Domain::Actions::UpdateAnnotationsAction)
      )

      result = annotation_service.update(book_path, 'test_id_123', 'Updated note')
      expect(result).to be true
    end

    it 'deletes annotation through repository' do
      expect(test_annotation_repository).to receive(:delete_by_id).with(book_path, 'test_id_123')
      expect(mock_state_store).to receive(:dispatch).with(
        an_instance_of(EbookReader::Domain::Actions::UpdateAnnotationsAction)
      )

      result = annotation_service.delete(book_path, 'test_id_123')
      expect(result).to be true
    end

    it 'retrieves all annotations through repository' do
      expect(test_annotation_repository).to receive(:find_all)

      result = annotation_service.list_all
      expect(result).to eq({book_path => [test_annotation]})
    end
  end

  describe 'Cross-Service Integration' do
    let(:bookmark_service) { EbookReader::Domain::Services::BookmarkService.new(dependencies) }
    let(:annotation_service) { EbookReader::Domain::Services::AnnotationService.new(dependencies) }

    before do
      allow(mock_state_store).to receive(:get).with([:reader, :book_path]).and_return(book_path)
      allow(mock_state_store).to receive(:current_state).and_return({
        reader: {
          book_path: book_path,
          current_chapter: 2,
          left_page: 100
        },
        config: {
          view_mode: :split
        }
      })
      allow(mock_state_store).to receive(:update)
      allow(mock_state_store).to receive(:dispatch)
    end

    it 'services can work independently without conflicts' do
      # Add bookmark
      expect(test_bookmark_repository).to receive(:add_for_book).and_return(test_bookmark)
      expect(mock_event_bus).to receive(:emit_event).with(:bookmark_added, { bookmark: test_bookmark })
      
      bookmark_result = bookmark_service.add_bookmark('Test bookmark')

      # Add annotation
      expect(test_annotation_repository).to receive(:add_for_book).and_return(test_annotation)
      expect(mock_state_store).to receive(:dispatch)

      annotation_result = annotation_service.add(book_path, 'Selected text', 'Test note', { start: 100, end: 120 }, 2)

      expect(bookmark_result).to eq(test_bookmark)
      expect(annotation_result).to eq(test_annotation)
    end

    it 'services share the same dependency container' do
      expect(bookmark_service.send(:dependencies)).to eq(dependencies)
      expect(annotation_service.send(:dependencies)).to eq(dependencies)
    end
  end

  describe 'Error Handling Integration' do
    let(:bookmark_service) { EbookReader::Domain::Services::BookmarkService.new(dependencies) }

    before do
      allow(mock_state_store).to receive(:get).with([:reader, :book_path]).and_return(book_path)
      allow(mock_state_store).to receive(:current_state).and_return({
        reader: {
          book_path: book_path,
          current_chapter: 2,
          left_page: 100
        },
        config: {
          view_mode: :split
        }
      })
    end

    it 'handles repository errors gracefully' do
      allow(test_bookmark_repository).to receive(:add_for_book).and_raise(
        EbookReader::Domain::Repositories::BaseRepository::PersistenceError, 'Storage failed'
      )

      expect {
        bookmark_service.add_bookmark('Test')
      }.to raise_error(EbookReader::Domain::Repositories::BaseRepository::PersistenceError)
    end

    it 'handles missing book path gracefully' do
      allow(mock_state_store).to receive(:get).with([:reader, :book_path]).and_return(nil)

      result = bookmark_service.add_bookmark('Test')
      expect(result).to be_nil
    end
  end

  describe 'State Management Integration' do
    let(:bookmark_service) { EbookReader::Domain::Services::BookmarkService.new(dependencies) }

    before do
      allow(mock_state_store).to receive(:get).with([:reader, :book_path]).and_return(book_path)
      allow(mock_state_store).to receive(:current_state).and_return(current_state)
      allow(test_bookmark_repository).to receive(:find_by_book_path).and_return([test_bookmark])
    end

    let(:current_state) do
      {
        reader: {
          book_path: book_path,
          current_chapter: 2,
          left_page: 100
        },
        config: {
          view_mode: :split
        }
      }
    end

    it 'updates state after adding bookmark' do
      allow(test_bookmark_repository).to receive(:add_for_book).and_return(test_bookmark)
      allow(mock_event_bus).to receive(:emit_event)

      expect(mock_state_store).to receive(:update).with(
        { [:reader, :bookmarks] => [test_bookmark] }
      )

      bookmark_service.add_bookmark('Test')
    end

    it 'updates state after removing bookmark' do
      allow(test_bookmark_repository).to receive(:delete_for_book).and_return(true)
      allow(mock_event_bus).to receive(:emit_event)

      expect(mock_state_store).to receive(:update).with(
        { [:reader, :bookmarks] => [test_bookmark] }
      )

      bookmark_service.remove_bookmark(test_bookmark)
    end
  end
end
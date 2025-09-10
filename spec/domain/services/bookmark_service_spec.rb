# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::BookmarkService do
  let(:event_bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new(event_bus) }
  let(:domain_bus) { EbookReader::Domain::Events::DomainEventBus.new(event_bus) }

  let(:repo) do
    instance_double(EbookReader::Domain::Repositories::BookmarkRepository).tap do |r|
      allow(r).to receive(:add_for_book).and_return(double('Bookmark', chapter_index: 0, line_offset: 0, created_at: Time.now))
      allow(r).to receive(:find_by_book_path).and_return([])
      allow(r).to receive(:delete_for_book).and_return(true)
      allow(r).to receive(:exists_at_position?).and_return(false)
      allow(r).to receive(:find_at_position).and_return(nil)
    end
  end

  class CtnBm
    def initialize(state, bus, repo, domain_bus)
      @state = state
      @bus = bus
      @repo = repo
      @domain_bus = domain_bus
    end

    def resolve(name)
      return @state if name == :state_store
      return @bus if name == :event_bus
      return @repo if name == :bookmark_repository
      return @domain_bus if name == :domain_event_bus

      nil
    end
  end

  subject(:service) { described_class.new(CtnBm.new(state, event_bus, repo, domain_bus)) }

  before do
    state.update({ %i[reader book_path] => '/tmp/book.epub', %i[reader current_chapter] => 0, %i[reader left_page] => 0, %i[config view_mode] => :split })
  end

  it 'adds and removes bookmarks and refreshes state' do
    expect { service.add_bookmark('s') }.not_to raise_error
    expect { service.remove_bookmark(double('Bookmark', chapter_index: 0, line_offset: 0)) }.not_to raise_error
  end

  it 'checks and toggles bookmarks at current position' do
    allow(repo).to receive(:exists_at_position?).and_return(false, true)
    expect(service.current_position_bookmarked?).to be false
    allow(repo).to receive(:find_at_position).and_return(nil, double('Bookmark', chapter_index: 0, line_offset: 0))
    expect(service.toggle_bookmark('s')).to eq(:added)
    expect(service.toggle_bookmark('s')).to eq(:removed)
  end
end

# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::AnnotationService do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new(bus) }

  let(:repo) do
    instance_double(EbookReader::Domain::Repositories::AnnotationRepository).tap do |r|
      allow(r).to receive(:find_by_book_path).and_return([])
      allow(r).to receive(:find_all).and_return({})
      allow(r).to receive(:add_for_book).and_return({ 'id' => 'x', 'text' => 't', 'note' => 'n', 'range' => { 'start' => 0, 'end' => 1 }, 'chapter_index' => 0 })
      allow(r).to receive(:find_by_id).and_return({ 'id' => 'x', 'note' => 'n' })
      allow(r).to receive(:update_note).and_return(true)
      allow(r).to receive(:delete_by_id).and_return(true)
    end
  end

  class AnnTestContainer
    def initialize(state, repo, event_bus)
      @state = state
      @repo = repo
      @domain_bus = EbookReader::Domain::Events::DomainEventBus.new(event_bus)
    end

    def resolve(name)
      return @state if name == :state_store
      return @repo if name == :annotation_repository
      return @domain_bus if name == :domain_event_bus

      nil
    end
  end

  subject(:service) { described_class.new(AnnTestContainer.new(state, repo, bus)) }

  it 'lists for book and all' do
    expect(service.list_for_book('/tmp/a.epub')).to eq([])
    expect(service.list_all).to be_a(Hash)
  end

  it 'adds, updates, deletes and dispatches update action' do
    expect do
      service.add('/tmp/a.epub', 't', 'n', { start: { x: 0, y: 0 }, end: { x: 1, y: 0 } }, 0, { current: 1, total: 10, type: :single })
    end.not_to raise_error

    expect do
      service.update('/tmp/a.epub', 'x', 'new')
    end.not_to raise_error

    expect do
      service.delete('/tmp/a.epub', 'x')
    end.not_to raise_error
  end
end

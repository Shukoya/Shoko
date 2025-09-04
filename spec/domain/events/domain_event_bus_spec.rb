# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Events::DomainEventBus do
  let(:mock_infrastructure_bus) do
    instance_double(EbookReader::Infrastructure::EventBus).tap do |bus|
      allow(bus).to receive(:emit_event)
    end
  end

  subject { described_class.new(mock_infrastructure_bus) }

  let(:test_event) do
    EbookReader::Domain::Events::BookmarkAdded.new(
      book_path: '/test/book.epub',
      bookmark: double('bookmark', chapter_index: 1, line_offset: 50)
    )
  end

  describe '#publish' do
    it 'publishes domain event through infrastructure bus' do
      expect(mock_infrastructure_bus).to receive(:emit_event).with(
        :BookmarkAdded,
        event_data: hash_including(
          event_type: 'BookmarkAdded',
          data: hash_including(book_path: '/test/book.epub')
        )
      )

      subject.publish(test_event)
    end

    it 'notifies direct subscribers' do
      handler_called = false
      subject.subscribe(EbookReader::Domain::Events::BookmarkAdded) do |event|
        handler_called = true
        expect(event).to eq(test_event)
      end

      subject.publish(test_event)
      expect(handler_called).to be true
    end

    it 'raises error for non-domain events' do
      expect { subject.publish('not an event') }.to raise_error(ArgumentError, /BaseDomainEvent/)
    end
  end

  describe '#subscribe' do
    it 'adds subscriber for event type' do
      handler = proc { |event| }
      
      subject.subscribe(EbookReader::Domain::Events::BookmarkAdded, handler)
      
      expect(subject.subscriber_count(EbookReader::Domain::Events::BookmarkAdded)).to eq(1)
    end

    it 'accepts block as handler' do
      subject.subscribe(EbookReader::Domain::Events::BookmarkAdded) { |event| }
      
      expect(subject.subscriber_count(EbookReader::Domain::Events::BookmarkAdded)).to eq(1)
    end
  end

  describe '#unsubscribe' do
    it 'removes specific handler' do
      handler = proc { |event| }
      subject.subscribe(EbookReader::Domain::Events::BookmarkAdded, handler)
      
      subject.unsubscribe(EbookReader::Domain::Events::BookmarkAdded, handler)
      
      expect(subject.subscriber_count(EbookReader::Domain::Events::BookmarkAdded)).to eq(0)
    end

    it 'removes all handlers for event type' do
      subject.subscribe(EbookReader::Domain::Events::BookmarkAdded) { |event| }
      subject.subscribe(EbookReader::Domain::Events::BookmarkAdded) { |event| }
      
      subject.unsubscribe(EbookReader::Domain::Events::BookmarkAdded)
      
      expect(subject.subscriber_count(EbookReader::Domain::Events::BookmarkAdded)).to eq(0)
    end
  end

  describe '#add_middleware' do
    it 'applies middleware to events before publishing' do
      processed_events = []
      
      subject.add_middleware do |event|
        processed_events << event
        event # Pass through unchanged
      end

      subject.publish(test_event)
      
      expect(processed_events).to include(test_event)
    end

    it 'can filter events by returning nil' do
      subject.add_middleware { |event| nil } # Filter out all events
      
      expect(mock_infrastructure_bus).not_to receive(:emit_event)
      subject.publish(test_event)
    end
  end

  it 'exposes subscriber lists and counts' do
    h = proc { |e| }
    subject.subscribe(EbookReader::Domain::Events::BookmarkAdded, h)
    expect(subject.subscribers_for(EbookReader::Domain::Events::BookmarkAdded)).to include(h)
    expect(subject.subscriber_count(EbookReader::Domain::Events::BookmarkAdded)).to eq(1)
    expect(subject.total_subscribers).to be >= 1
  end
end

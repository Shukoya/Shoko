# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Infrastructure::EventBus do
  let(:event_bus) { described_class.new }
  let(:subscriber) { double('Subscriber') }

  describe '#subscribe' do
    it 'subscribes to single event type' do
      event_bus.subscribe(subscriber, :test_event)

      expect(event_bus.instance_variable_get(:@subscribers)[:test_event]).to include(subscriber)
    end

    it 'subscribes to multiple event types' do
      event_bus.subscribe(subscriber, :event1, :event2)

      subscribers = event_bus.instance_variable_get(:@subscribers)
      expect(subscribers[:event1]).to include(subscriber)
      expect(subscribers[:event2]).to include(subscriber)
    end

    it 'does not duplicate subscribers' do
      event_bus.subscribe(subscriber, :test_event)
      event_bus.subscribe(subscriber, :test_event)

      subscribers = event_bus.instance_variable_get(:@subscribers)[:test_event]
      expect(subscribers.count(subscriber)).to eq(1)
    end
  end

  describe '#unsubscribe' do
    before do
      event_bus.subscribe(subscriber, :event1, :event2)
    end

    it 'removes subscriber from all event types' do
      event_bus.unsubscribe(subscriber)

      subscribers = event_bus.instance_variable_get(:@subscribers)
      expect(subscribers[:event1]).not_to include(subscriber)
      expect(subscribers[:event2]).not_to include(subscriber)
    end
  end

  describe '#emit' do
    let(:event) { EbookReader::Infrastructure::Event.new(type: :test_event, data: { message: 'test' }) }

    before do
      event_bus.subscribe(subscriber, :test_event)
    end

    it 'notifies subscribed listeners' do
      expect(subscriber).to receive(:handle_event).with(event)

      event_bus.emit(event)
    end

    it 'does not notify unrelated subscribers' do
      other_subscriber = double('Other Subscriber')
      event_bus.subscribe(other_subscriber, :other_event)

      expect(subscriber).to receive(:handle_event).with(event)
      expect(other_subscriber).not_to receive(:handle_event)

      event_bus.emit(event)
    end

    it 'handles subscriber errors gracefully' do
      Thread.current[:suppress_event_errors] = true

      expect(subscriber).to receive(:handle_event).and_raise(StandardError.new('test error'))
      expect(EbookReader::Infrastructure::Logger).to receive(:error)

      expect { event_bus.emit(event) }.not_to raise_error

      Thread.current[:suppress_event_errors] = false
    end

    it 're-raises errors in test environment' do
      expect(subscriber).to receive(:handle_event).and_raise(StandardError.new('test error'))

      expect { event_bus.emit(event) }.to raise_error(StandardError, 'test error')
    end
  end

  describe '#emit_event' do
    before do
      event_bus.subscribe(subscriber, :test_type)
    end

    it 'creates and emits event' do
      data = { key: 'value' }

      expect(subscriber).to receive(:handle_event) do |event|
        expect(event.type).to eq(:test_type)
        expect(event.data).to eq(data)
        expect(event.timestamp).to be_a(Time)
      end

      event_bus.emit_event(:test_type, data)
    end

    it 'handles empty data' do
      expect(subscriber).to receive(:handle_event) do |event|
        expect(event.data).to eq({})
      end

      event_bus.emit_event(:test_type)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent subscriptions' do
      threads = Array.new(10) do |i|
        Thread.new do
          subscriber = double("Subscriber#{i}")
          event_bus.subscribe(subscriber, :test_event)
        end
      end

      threads.each(&:join)

      subscribers = event_bus.instance_variable_get(:@subscribers)[:test_event]
      expect(subscribers.size).to eq(10)
    end
  end
end

RSpec.describe EbookReader::Infrastructure::Event do
  describe 'initialization' do
    it 'creates immutable event' do
      event = described_class.new(type: :test, data: { key: 'value' }, timestamp: Time.now)

      expect(event).to be_frozen
      expect(event.type).to eq(:test)
      expect(event.data).to eq({ key: 'value' })
    end

    it 'requires keyword arguments' do
      expect do
        described_class.new(:test, { key: 'value' })
      end.to raise_error(ArgumentError)
    end
  end
end

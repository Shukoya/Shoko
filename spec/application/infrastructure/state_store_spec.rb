# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Infrastructure::StateStore do
  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  it 'emits state change events when updates occur' do
    bus = Shoko::Application::Infrastructure::EventBus.new
    events = []
    subscriber = Class.new do
      def initialize(events)
        @events = events
      end

      def handle_event(event)
        @events << event
      end
    end
    bus.subscribe(subscriber.new(events), :state_changed)

    store = described_class.new(bus)
    store.update(%i[config view_mode] => :single)

    expect(events.length).to eq(1)
    expect(events.first.type).to eq(:state_changed)
  end

  it 'validates update values' do
    store = described_class.new(Shoko::Application::Infrastructure::EventBus.new)
    expect { store.update(%i[config view_mode] => :unknown) }.to raise_error(ArgumentError)
  end

  it 'persists config to disk' do
    store = described_class.new(Shoko::Application::Infrastructure::EventBus.new)
    store.update(%i[config view_mode] => :single)
    store.save_config
    expect(File).to exist(described_class.config_file)
  end
end

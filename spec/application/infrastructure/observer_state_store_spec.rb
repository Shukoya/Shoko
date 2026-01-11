# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Infrastructure::ObserverStateStore do
  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  it 'notifies observers for specific paths' do
    store = described_class.new(Shoko::Application::Infrastructure::EventBus.new)
    observer = double('Observer')
    allow(observer).to receive(:state_changed)

    store.add_observer(observer, %i[reader mode])
    store.update(%i[reader mode] => :help)

    expect(observer).to have_received(:state_changed).at_least(:once)
  end

  it 'notifies observers for parent paths' do
    store = described_class.new(Shoko::Application::Infrastructure::EventBus.new)
    observer = double('Observer')
    allow(observer).to receive(:state_changed)

    store.add_observer(observer, %i[reader])
    store.update(%i[reader mode] => :help)

    expect(observer).to have_received(:state_changed).at_least(:once)
  end
end

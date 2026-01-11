# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Commands::MenuCommand do
  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  it 'updates menu selection indices' do
    state = Shoko::Application::Infrastructure::ObserverStateStore.new(
      Shoko::Application::Infrastructure::EventBus.new
    )
    context = Struct.new(:state).new(state)

    command = described_class.new(:menu_down)
    result = command.execute(context, key: "\n", triggered_by: :input)
    expect(result).to eq(:handled)
    expect(state.get(%i[menu selected])).to eq(1)
  end

  it 'invokes settings actions based on selection' do
    state = Shoko::Application::Infrastructure::ObserverStateStore.new(
      Shoko::Application::Infrastructure::EventBus.new
    )
    state.update(%i[menu settings_selected] => 1)

    context = Class.new do
      attr_reader :state, :called

      def initialize(state)
        @state = state
        @called = false
      end

      def toggle_view_mode
        @called = true
      end
    end.new(state)

    command = described_class.new(:settings_select)
    command.execute(context, key: "\n", triggered_by: :input)
    expect(context.called).to be(true)
  end
end

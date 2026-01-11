# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Components::Screens::SettingsScreenComponent do
  let(:terminal) { Shoko::TestSupport::TerminalDouble }
  let(:surface) { Shoko::Adapters::Output::Ui::Components::Surface.new(terminal) }
  let(:bounds) { Shoko::Adapters::Output::Ui::Components::Rect.new(x: 1, y: 1, width: 60, height: 20) }

  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  it 'renders the settings title' do
    terminal.reset!
    state = Shoko::Application::Infrastructure::ObserverStateStore.new(
      Shoko::Application::Infrastructure::EventBus.new
    )
    component = described_class.new(state)

    component.render(surface, bounds)

    titles = terminal.writes.map { |entry| entry[:text] }.select { |text| text.include?('Settings') }
    expect(titles).not_to be_empty
  end
end

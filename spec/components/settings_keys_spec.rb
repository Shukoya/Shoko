# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Settings key bindings' do
  it "maps '6' to wipe_cache action" do
    mm = EbookReader::MainMenu.new
    dispatcher = mm.instance_variable_get(:@dispatcher)
    dispatcher.activate(:settings)

    allow(mm).to receive(:wipe_cache)
    dispatcher.handle_key('6')
    expect(mm).to have_received(:wipe_cache)
  end
end

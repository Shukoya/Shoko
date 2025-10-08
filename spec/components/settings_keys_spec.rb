# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Settings key bindings' do
  it "maps '6' to wipe_cache action" do
    container = EbookReader::Domain::ContainerFactory.create_default_container
    settings_service = instance_double('SettingsService',
                                       wipe_cache: EbookReader::Domain::Services::SettingsService::WIPE_CACHE_MESSAGE)
    container.register(:settings_service, settings_service)

    mm = EbookReader::MainMenu.new(container)
    dispatcher = mm.instance_variable_get(:@dispatcher)
    dispatcher.activate(:settings)

    dispatcher.handle_key('6')
    expect(settings_service).to have_received(:wipe_cache)
  end
end

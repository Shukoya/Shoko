# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Settings key bindings' do
  it 'calls wipe_cache when confirming the wipe cache option' do
    container = EbookReader::Domain::ContainerFactory.create_default_container
    settings_service = instance_double('SettingsService',
                                       wipe_cache: EbookReader::Domain::Services::SettingsService::WIPE_CACHE_MESSAGE)
    container.register(:settings_service, settings_service)

    mm = EbookReader::MainMenu.new(container)
    dispatcher = mm.instance_variable_get(:@dispatcher)
    dispatcher.activate(:settings)

    5.times { dispatcher.handle_key('j') }
    dispatcher.handle_key(' ')
    expect(settings_service).to have_received(:wipe_cache)
  end
end

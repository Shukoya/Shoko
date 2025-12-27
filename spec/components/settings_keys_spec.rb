# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'

RSpec.describe 'Settings key bindings' do
  around do |example|
    Dir.mktmpdir do |dir|
      old_home = Dir.home
      old_cache = ENV.fetch('XDG_CACHE_HOME', nil)
      ENV['HOME'] = dir
      ENV['XDG_CACHE_HOME'] = File.join(dir, '.cache')
      example.run
    ensure
      ENV['HOME'] = old_home
      if old_cache
        ENV['XDG_CACHE_HOME'] = old_cache
      else
        ENV.delete('XDG_CACHE_HOME')
      end
    end
  end

  it 'calls wipe_cache when confirming the wipe cache option' do
    container = EbookReader::Domain::ContainerFactory.create_default_container
    settings_service = instance_double('SettingsService',
                                       wipe_cache: EbookReader::Domain::Services::SettingsService::WIPE_CACHE_MESSAGE)
    container.register(:settings_service, settings_service)

    mm = EbookReader::MainMenu.new(container)
    dispatcher = mm.instance_variable_get(:@dispatcher)
    dispatcher.activate(:settings)

    6.times { dispatcher.handle_key('j') }
    dispatcher.handle_key(' ')
    expect(settings_service).to have_received(:wipe_cache)
  end
end

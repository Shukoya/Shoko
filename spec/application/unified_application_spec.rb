# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Application::UnifiedApplication do
  describe '#run' do
    it 'opens reader mode with terminal setup/cleanup and passes dependencies' do
      deps = instance_double(EbookReader::Domain::DependencyContainer)
      term = instance_double(EbookReader::Domain::Services::TerminalService)

      allow(EbookReader::Domain::ContainerFactory).to receive(:create_default_container).and_return(deps)
      allow(deps).to receive(:resolve).with(:terminal_service).and_return(term)
      allow(term).to receive(:setup)
      allow(term).to receive(:cleanup)

      reader_double = instance_double('Reader', run: true)
      reader_class = class_double('EbookReader::MouseableReader').as_stubbed_const
      expect(reader_class).to receive(:new).with('/tmp/book.epub', nil, deps).and_return(reader_double)

      app = described_class.new('/tmp/book.epub')
      expect(term).to receive(:setup).once
      expect(term).to receive(:cleanup).once
      app.run
    end

    it 'opens menu mode and runs main menu without terminal setup' do
      deps = instance_double(EbookReader::Domain::DependencyContainer)
      allow(EbookReader::Domain::ContainerFactory).to receive(:create_default_container).and_return(deps)

      menu_double = instance_double('MainMenu', run: true)
      menu_class = class_double('EbookReader::MainMenu').as_stubbed_const
      expect(menu_class).to receive(:new).with(deps).and_return(menu_double)

      app = described_class.new(nil)
      app.run
    end

    it 'ensures terminal cleanup even if reader raises' do
      deps = instance_double(EbookReader::Domain::DependencyContainer)
      term = instance_double(EbookReader::Domain::Services::TerminalService)
      allow(EbookReader::Domain::ContainerFactory).to receive(:create_default_container).and_return(deps)
      allow(deps).to receive(:resolve).with(:terminal_service).and_return(term)
      allow(term).to receive(:setup)
      expect(term).to receive(:cleanup).once

      reader_class = class_double('EbookReader::MouseableReader').as_stubbed_const
      reader = instance_double('Reader')
      expect(reader_class).to receive(:new).and_return(reader)
      expect(reader).to receive(:run).and_raise(StandardError, 'boom')

      app = described_class.new('/tmp/book.epub')
      expect { app.run }.to raise_error(StandardError)
    end
  end
end

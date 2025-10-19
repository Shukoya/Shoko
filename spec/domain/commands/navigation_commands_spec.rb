# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Commands::NavigationCommand do
  let(:navigation_service) { instance_double(EbookReader::Domain::Services::NavigationService) }
  let(:state_store) { instance_double(EbookReader::Infrastructure::StateStore) }
  let(:dependencies) { create_test_dependencies }
  let(:logger) { instance_double('Logger', error: nil, debug: nil) }
  let(:context) { double('Context', dependencies: dependencies) }

  before do
    dependencies.register(:navigation_service, navigation_service)
    dependencies.register(:state_store, state_store)
    dependencies.register(:logger, logger)
  end

  describe '#execute' do
    context 'with next_page action' do
      let(:command) { described_class.new(:next_page) }

      it 'calls navigation service next_page' do
        expect(navigation_service).to receive(:next_page)

        result = command.execute(context)

        expect(result).to eq(:handled)
      end
    end

    context 'with prev_page action' do
      let(:command) { described_class.new(:prev_page) }

      it 'calls navigation service prev_page' do
        expect(navigation_service).to receive(:prev_page)

        result = command.execute(context)

        expect(result).to eq(:handled)
      end
    end

    context 'with next_chapter action' do
      let(:command) { described_class.new(:next_chapter) }

      before do
        allow(state_store).to receive(:current_state).and_return({
                                                                   reader: { current_chapter: 2 },
                                                                 })
      end

      it 'jumps to next chapter' do
        expect(navigation_service).to receive(:jump_to_chapter).with(3)

        result = command.execute(context)

        expect(result).to eq(:handled)
      end
    end

    context 'with invalid action' do
      let(:command) { described_class.new(:invalid_action) }

      it 'handles error gracefully' do
        expect(logger).to receive(:error)

        result = command.execute(context)

        expect(result).to eq(:error)
      end
    end
  end

  describe 'validation' do
    let(:command) { described_class.new(:next_page) }

    it 'requires context with dependencies' do
      context_without_deps = double('Context')

      expect do
        command.execute(context_without_deps)
      end.to raise_error(EbookReader::Domain::Commands::BaseCommand::ValidationError)
    end

    it 'checks service availability' do
      dependencies.clear!
      allow(dependencies).to receive(:registered?).with(:navigation_service).and_return(false)
      allow(dependencies).to receive(:registered?).with(:state_store).and_return(false)

      result = command.execute(context)

      expect(result).to eq(:pass)
    end
  end
end

RSpec.describe EbookReader::Domain::Commands::ScrollCommand do
  let(:navigation_service) { instance_double(EbookReader::Domain::Services::NavigationService) }
  let(:dependencies) { create_test_dependencies }
  let(:context) { double('Context', dependencies: dependencies) }

  before do
    dependencies.register(:navigation_service, navigation_service)
  end

  describe '#execute' do
    it 'calls navigation service scroll with direction and lines' do
      command = described_class.new(:up, lines: 3)

      expect(navigation_service).to receive(:scroll).with(:up, 3)

      result = command.execute(context)

      expect(result).to eq(:handled)
    end
  end

  describe 'validation' do
    it 'validates direction' do
      # Validation happens at execute time
      expect do
        described_class.new(:invalid_direction)
      end.not_to raise_error

      command = described_class.new(:invalid_direction)

      expect do
        command.execute(context)
      end.to raise_error(EbookReader::Domain::Commands::BaseCommand::ValidationError, /Direction must be one of/)
    end

    it 'validates lines is positive integer' do
      expect do
        command = described_class.new(:up, lines: -1)
        command.execute(context)
      end.to raise_error(EbookReader::Domain::Commands::BaseCommand::ValidationError, /Lines must be a positive integer/)
    end
  end
end

RSpec.describe EbookReader::Domain::Commands::JumpToChapterCommand do
  let(:navigation_service) { instance_double(EbookReader::Domain::Services::NavigationService) }
  let(:dependencies) { create_test_dependencies }
  let(:context) { double('Context', dependencies: dependencies) }

  before do
    dependencies.register(:navigation_service, navigation_service)
  end

  describe '#execute' do
    it 'jumps to specified chapter' do
      command = described_class.new(5)

      expect(navigation_service).to receive(:jump_to_chapter).with(5)

      result = command.execute(context)

      expect(result).to eq(:handled)
    end

    it 'accepts chapter index from params' do
      command = described_class.new

      expect(navigation_service).to receive(:jump_to_chapter).with(3)

      result = command.execute(context, { chapter_index: 3 })

      expect(result).to eq(:handled)
    end
  end

  describe 'validation' do
    it 'validates chapter index is non-negative integer' do
      command = described_class.new(-1)

      expect do
        command.execute(context)
      end.to raise_error(EbookReader::Domain::Commands::BaseCommand::ValidationError, /Chapter index must be a non-negative integer/)
    end
  end
end

RSpec.describe EbookReader::Domain::Commands::NavigationCommandFactory do
  let(:dependencies) { create_test_dependencies }
  let(:context) { double('Context', dependencies: dependencies) }
  let(:navigation_service) { instance_double(EbookReader::Domain::Services::NavigationService) }

  before do
    dependencies.register(:navigation_service, navigation_service)
    allow(navigation_service).to receive(:next_page)
    allow(navigation_service).to receive(:prev_page)
    allow(navigation_service).to receive(:go_to_start)
    allow(navigation_service).to receive(:go_to_end)
    allow(navigation_service).to receive(:scroll)
    allow(navigation_service).to receive(:jump_to_chapter)
  end

  describe 'factory methods' do
    it 'creates next_page command' do
      command = described_class.next_page

      expect(command.execute(context)).to eq(:handled)
      expect(navigation_service).to have_received(:next_page)
    end

    it 'creates prev_page command' do
      command = described_class.prev_page

      expect(command.execute(context)).to eq(:handled)
      expect(navigation_service).to have_received(:prev_page)
    end

    it 'creates scroll commands' do
      up_command = described_class.scroll_up(2)
      down_command = described_class.scroll_down(3)

      up_command.execute(context)
      down_command.execute(context)

      expect(navigation_service).to have_received(:scroll).with(:up, 2)
      expect(navigation_service).to have_received(:scroll).with(:down, 3)
    end

    it 'creates jump_to_chapter command' do
      command = described_class.jump_to_chapter(7)

      command.execute(context)

      expect(navigation_service).to have_received(:jump_to_chapter).with(7)
    end
  end
end

# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Infrastructure::StateStore do
  let(:event_bus) { instance_double(EbookReader::Infrastructure::EventBus) }
  let(:state_store) { described_class.new(event_bus) }

  before do
    allow(event_bus).to receive(:emit_event)
  end

  describe '#initialize' do
    it 'creates initial state' do
      expect(state_store.get(%i[reader current_chapter])).to eq(0)
      expect(state_store.get(%i[reader view_mode])).to eq(:split)
      expect(state_store.get(%i[config theme])).to eq(:dark)
    end
  end

  describe '#get' do
    it 'retrieves values by path' do
      expect(state_store.get(%i[reader current_chapter])).to eq(0)
      expect(state_store.get(%i[menu selected_index])).to eq(0)
    end

    it 'returns nil for non-existent paths' do
      expect(state_store.get(%i[non existent path])).to be_nil
    end

    it 'handles single symbol paths' do
      expect(state_store.get([:reader])).to be_a(Hash)
    end
  end

  describe '#set' do
    it 'updates single path' do
      state_store.set(%i[reader current_chapter], 5)

      expect(state_store.get(%i[reader current_chapter])).to eq(5)
    end

    it 'emits change event' do
      expect(event_bus).to receive(:emit_event).with(:state_changed, {
                                                       path: %i[reader current_chapter],
                                                       old_value: 0,
                                                       new_value: 5,
                                                       full_state: anything,
                                                     })

      state_store.set(%i[reader current_chapter], 5)
    end

    it 'does not emit event for same value' do
      expect(event_bus).not_to receive(:emit_event)

      state_store.set(%i[reader current_chapter], 0) # Same as initial value
    end
  end

  describe '#update' do
    it 'updates multiple paths' do
      updates = {
        %i[reader current_chapter] => 3,
        %i[reader current_page] => 10,
        %i[config view_mode] => :single,
      }

      state_store.update(updates)

      expect(state_store.get(%i[reader current_chapter])).to eq(3)
      expect(state_store.get(%i[reader current_page])).to eq(10)
      expect(state_store.get(%i[config view_mode])).to eq(:single)
    end

    it 'emits change events for each updated path' do
      expect(event_bus).to receive(:emit_event).exactly(2).times

      updates = {
        %i[reader current_chapter] => 3,
        %i[reader current_page] => 10,
      }

      state_store.update(updates)
    end

    it 'does not emit events for unchanged values' do
      expect(event_bus).to receive(:emit_event).once

      updates = {
        %i[reader current_chapter] => 0, # Same as current
        %i[reader current_page] => 10, # Different
      }

      state_store.update(updates)
    end
  end

  describe '#current_state' do
    it 'returns immutable copy of current state' do
      state = state_store.current_state

      expect(state).to be_frozen
      expect(state[:reader]).to be_a(Hash)
      expect(state[:config]).to be_a(Hash)
    end

    it 'reflects updates' do
      state_store.set(%i[reader current_chapter], 7)

      state = state_store.current_state
      expect(state.dig(:reader, :current_chapter)).to eq(7)
    end
  end

  describe '#reset!' do
    it 'resets to initial state' do
      state_store.set(%i[reader current_chapter], 10)

      state_store.reset!

      expect(state_store.get(%i[reader current_chapter])).to eq(0)
    end

    it 'emits reset event' do
      expect(event_bus).to receive(:emit_event).with(:state_reset, anything)

      state_store.reset!
    end
  end

  describe 'validation' do
    it 'validates chapter index is non-negative' do
      expect do
        state_store.set(%i[reader current_chapter], -1)
      end.to raise_error(ArgumentError, 'current_chapter must be non-negative')
    end

    it 'validates view mode is valid' do
      expect do
        state_store.set(%i[reader view_mode], :invalid)
      end.to raise_error(ArgumentError, 'invalid view_mode')
    end

    it 'validates terminal dimensions are positive' do
      expect do
        state_store.set(%i[ui terminal_width], 0)
      end.to raise_error(ArgumentError, 'terminal dimensions must be positive')
    end
  end

  describe 'immutability' do
    it 'maintains state immutability for external access' do
      state_store.set(%i[reader current_chapter], 1)

      # External state access should be immutable
      external_state = state_store.current_state
      expect(external_state).to be_frozen
    end

    it 'prevents external state mutation' do
      state = state_store.current_state

      expect do
        state[:reader][:current_chapter] = 999
      end.to raise_error(FrozenError)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent updates safely' do
      threads = Array.new(10) do |i|
        Thread.new do
          state_store.set(%i[reader current_chapter], i)
        end
      end

      threads.each(&:join)

      # Should not crash and state should be consistent
      chapter = state_store.get(%i[reader current_chapter])
      expect(chapter).to be_between(0, 9)
    end
  end
end

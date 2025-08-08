# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Annotations::MouseHandler do
  let(:handler) { described_class.new }

  describe '#parse_mouse_event' do
    it 'parses valid events' do
      event = handler.parse_mouse_event("\e[<0;10;5M")
      expect(event).to eq(button: 0, x: 9, y: 4, released: false)
    end

    it 'returns nil for invalid data' do
      expect(handler.parse_mouse_event('abc')).to be_nil
    end
  end

  describe 'selection lifecycle' do
    it 'tracks selection from press to release' do
      handler.handle_event(button: 0, x: 1, y: 2, released: false)
      handler.handle_event(button: 32, x: 3, y: 2, released: false)
      handler.handle_event(button: 0, x: 3, y: 2, released: true)
      range = handler.selection_range
      expect(range[:start]).to eq(x: 1, y: 2)
      expect(range[:end]).to eq(x: 3, y: 2)
      handler.reset
      expect(handler.selection_range).to be_nil
    end
  end
end

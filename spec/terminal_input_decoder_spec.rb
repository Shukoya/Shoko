# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::TerminalInput::Decoder do
  describe '#next_token' do
    it 'decodes multibyte UTF-8 characters' do
      decoder = described_class.new(esc_timeout: 0.05, sequence_timeout: 0.2)

      decoder.feed("\xC3".b)
      expect(decoder.next_token(now: 0.0)).to be_nil

      decoder.feed("\xA9".b)
      expect(decoder.next_token(now: 0.0)).to eq('é')
    end

    it 'returns full CSI sequences' do
      decoder = described_class.new(esc_timeout: 0.05, sequence_timeout: 0.2)

      decoder.feed("\e[1;5".b)
      expect(decoder.next_token(now: 0.0)).to be_nil

      decoder.feed('D'.b)
      expect(decoder.next_token(now: 0.0)).to eq("\e[1;5D")
    end

    it 'returns full mouse CSI sequences' do
      decoder = described_class.new
      decoder.feed("\e[<0;10;20M".b)
      expect(decoder.next_token(now: 0.0)).to eq("\e[<0;10;20M")
    end

    it 'emits a lone ESC after the timeout' do
      decoder = described_class.new(esc_timeout: 0.05, sequence_timeout: 0.2)
      decoder.feed("\e".b)

      expect(decoder.next_token(now: 0.0)).to be_nil
      expect(decoder.next_token(now: 0.04)).to be_nil
      expect(decoder.next_token(now: 0.06)).to eq("\e")
    end

    it 'does not collapse ESC ESC into an alt sequence' do
      decoder = described_class.new(esc_timeout: 0.05, sequence_timeout: 0.2)
      decoder.feed("\e\e".b)

      expect(decoder.next_token(now: 0.0)).to eq("\e")
      expect(decoder.next_token(now: 0.0)).to be_nil
      expect(decoder.next_token(now: 0.06)).to eq("\e")
    end

    it 'keeps CSI intact when bytes arrive before timeout' do
      decoder = described_class.new(esc_timeout: 0.05, sequence_timeout: 0.2)

      decoder.feed("\e".b)
      expect(decoder.next_token(now: 0.0)).to be_nil

      decoder.feed("[A".b)
      expect(decoder.next_token(now: 0.0)).to eq("\e[A")
    end
  end
end


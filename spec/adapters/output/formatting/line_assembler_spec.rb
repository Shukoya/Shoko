# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Formatting::FormattingService::LineAssembler do
  let(:tokenizer) { described_class::Tokenizer }

  it 'tokenizes newlines into explicit newline tokens' do
    segments = [Shoko::Core::Models::TextSegment.new(text: "a\nb")]
    tokens = tokenizer.tokenize(segments, image_rendering: false, renderable_image_src: ->(_src) { false })
    expect(tokens.any? { |t| t[:newline] }).to be(true)
  end

  it 'creates image tokens when inline image rendering is enabled' do
    segments = [Shoko::Core::Models::TextSegment.new(text: 'img', styles: { inline_image: { src: 'x' } })]
    tokens = tokenizer.tokenize(segments, image_rendering: true, renderable_image_src: ->(_src) { true })
    expect(tokens.any? { |t| t[:image] }).to be(true)
  end

  it 'wraps lines with list prefixes and continuation indentation' do
    segments = [Shoko::Core::Models::TextSegment.new(text: 'one two three four')]
    tokens = tokenizer.tokenize(segments, image_rendering: false, renderable_image_src: ->(_src) { false })
    wrapper = described_class::TextWrapper.new(10, image_builder: double('ImageBuilder'))

    lines = wrapper.wrap(tokens, metadata: {}, prefix: '* ', continuation_prefix: nil)

    expect(lines.length).to be > 1
    expect(lines.first.text).to start_with('* ')
    expect(lines[1].text).to start_with('  ')
  end
end

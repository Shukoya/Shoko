# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Components::Reading::LineContentComposer do
  def build_store(data)
    Struct.new(:data) do
      def get(path)
        data[path]
      end
    end.new(data)
  end

  let(:composer) { described_class.new }
  let(:render_style) { Shoko::Adapters::Output::Ui::Components::RenderStyle }

  it 'highlights keywords in plain lines when enabled' do
    store = build_store(
      { %i[config highlight_keywords] => true, %i[config highlight_quotes] => false }
    )

    plain, styled = composer.compose('fragrance', 40, store)

    expect(plain).to eq('fragrance')
    expect(styled).to include(render_style.color(:accent))
  end

  it 'highlights quotes in plain lines when enabled' do
    store = build_store({ %i[config highlight_quotes] => true })

    plain, styled = composer.compose('He said "quote"', 40, store)

    expect(plain).to eq('He said "quote"')
    expect(styled).to include(render_style.color(:quote))
    expect(styled).to include(Shoko::Terminal::ANSI::ITALIC)
  end

  it 'uses primary color for quote blocks when highlighting is disabled' do
    store = build_store({ %i[config highlight_quotes] => false })
    line = Shoko::Core::Models::DisplayLine.new(
      text: '"quote"',
      segments: [Shoko::Core::Models::TextSegment.new(text: '"quote"')],
      metadata: { block_type: :quote }
    )

    _plain, styled = composer.compose(line, 20, store)

    expect(styled).to include(render_style.color(:primary))
    expect(styled).not_to include(render_style.color(:quote))
  end

  it 'adds accent styling for keywords in display lines' do
    store = build_store(
      { %i[config highlight_keywords] => true, %i[config highlight_quotes] => false }
    )
    line = Shoko::Core::Models::DisplayLine.new(
      text: 'fragrance',
      segments: [Shoko::Core::Models::TextSegment.new(text: 'fragrance')],
      metadata: {}
    )

    _plain, styled = composer.compose(line, 20, store)

    expect(styled).to include(render_style.color(:accent))
  end
end

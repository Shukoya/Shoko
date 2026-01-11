# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Components::RenderStyle do
  it 'uses quote color when highlighting is enabled' do
    styled = described_class.styled_segment('quote', { quote: true }, metadata: { block_type: :quote, highlight_enabled: true })
    expect(styled).to start_with(described_class.color(:quote))
  end

  it 'falls back to primary color when highlighting is disabled' do
    styled = described_class.styled_segment('quote', { quote: true }, metadata: { block_type: :quote, highlight_enabled: false })
    expect(styled).to start_with(described_class.color(:primary))
  end

  it 'uses accent color for keyword segments' do
    styled = described_class.styled_segment('word', { accent: true }, metadata: {})
    expect(styled).to start_with(described_class.color(:accent))
  end
end

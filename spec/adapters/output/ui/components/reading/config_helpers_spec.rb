# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Ui::Components::Reading::ConfigHelpers do
  def build_store(data)
    Struct.new(:data) do
      def get(path)
        data[path]
      end
    end.new(data)
  end

  it 'defaults to highlighting quotes when unset' do
    store = build_store({})
    expect(described_class.highlight_quotes?(store)).to be(true)
  end

  it 'defaults to not highlighting keywords when unset' do
    store = build_store({})
    expect(described_class.highlight_keywords?(store)).to be(false)
  end

  it 'extracts store from config objects exposing state' do
    state = build_store({})
    config = Struct.new(:state).new(state)
    expect(described_class.config_store(config)).to eq(state)
  end
end

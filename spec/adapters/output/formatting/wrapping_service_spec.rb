# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Formatting::WrappingService do
  class NullDependencies
    def registered?(_name)
      false
    end

    def resolve(_name)
      nil
    end
  end

  it 'does not reuse window cache across different line sets' do
    service = described_class.new(NullDependencies.new)

    lines_a = ['alpha beta']
    lines_b = ['gamma']

    wrapped_a = service.wrap_window(lines_a, 0, 5, 0, 2)
    wrapped_b = service.wrap_window(lines_b, 0, 5, 0, 2)

    expect(wrapped_a).not_to eq(wrapped_b)
    expect(wrapped_b).to eq(['gamma'])
  end

  it 'reuses cached windows for identical line sets' do
    service = described_class.new(NullDependencies.new)

    lines = ['alpha beta']
    first = service.wrap_window(lines, 0, 5, 0, 2)
    second = service.wrap_window(lines, 0, 5, 0, 2)

    expect(second).to eq(first)
  end
end

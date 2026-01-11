# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Zip::LimitResolver do
  it 'uses the provided value when valid' do
    expect(described_class.resolve(10, env: 'SHOKO_ZIP_UNUSED', default: 5)).to eq(10)
  end

  it 'falls back to env when value is nil' do
    with_env('SHOKO_ZIP_TEST_LIMIT' => '12') do
      expect(described_class.resolve(nil, env: 'SHOKO_ZIP_TEST_LIMIT', default: 5)).to eq(12)
    end
  end

  it 'falls back to default for invalid values' do
    with_env('SHOKO_ZIP_TEST_LIMIT' => 'nope') do
      expect(described_class.resolve(nil, env: 'SHOKO_ZIP_TEST_LIMIT', default: 5)).to eq(5)
    end
  end
end

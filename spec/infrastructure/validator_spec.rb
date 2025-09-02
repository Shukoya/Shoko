# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Infrastructure::Validator do
  class DummyValidator < EbookReader::Infrastructure::Validator; end

  let(:validator) { DummyValidator.new }

  it 'validates presence' do
    expect(validator.presence_valid?('', :name)).to be false
    expect(validator.errors).not_to be_empty
    validator.clear_errors
    expect(validator.presence_valid?('x', :name)).to be true
  end

  it 'validates range' do
    ctx = EbookReader::Infrastructure::Validator::RangeValidationContext.new(5, 1..3, :age, 'bad')
    expect(validator.range_valid?(ctx)).to be false
  end

  it 'validates format' do
    ctx = EbookReader::Infrastructure::Validator::FormatValidationContext.new('abc', /\A\d+\z/, :id, 'bad')
    expect(validator.format_valid?(ctx)).to be false
  end
end

# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Infrastructure::Validator do
  let(:validator) { described_class.new }

  it 'adds and clears errors' do
    validator.add_error(:field, 'bad')
    expect(validator.errors).not_to be_empty
    validator.clear_errors
    expect(validator.errors).to be_empty
  end

  it 'validates numeric range' do
    context1 = EbookReader::Infrastructure::Validator::RangeValidationContext.new(5, 1..10, :num)
    expect(validator.range_valid?(context1)).to be true

    context2 = EbookReader::Infrastructure::Validator::RangeValidationContext.new(0, 1..10, :num)
    expect(validator.range_valid?(context2)).to be false
    expect(validator.errors.last[:message]).to include('between')
  end

  it 'validates format with regex' do
    context1 = EbookReader::Infrastructure::Validator::FormatValidationContext.new('abc', /\A[a-z]+\z/, :name)
    expect(validator.format_valid?(context1)).to be true

    context2 = EbookReader::Infrastructure::Validator::FormatValidationContext.new('123', /\A[a-z]+\z/, :name)
    expect(validator.format_valid?(context2)).to be false
    expect(validator.errors.last[:field]).to eq(:name)
  end
end

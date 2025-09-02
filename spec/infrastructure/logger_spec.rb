# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe EbookReader::Infrastructure::Logger do
  let(:io) { StringIO.new }

  before do
    described_class.output = io
    described_class.level = :debug
  end

  after do
    described_class.clear
  end

  it 'writes structured JSON logs with context and metadata' do
    described_class.with_context(user_id: 42) do
      described_class.info('Hello', request_id: 'abc')
    end
    io.rewind
    line = io.gets
    data = JSON.parse(line)
    expect(data['message']).to eq('Hello')
    expect(data['severity']).to eq('INFO')
    expect(data['context']).to include('user_id' => 42)
    expect(data['metadata']).to include('request_id' => 'abc')
  end

  it 'respects log level filtering' do
    described_class.level = :error
    described_class.info('Skip me')
    io.rewind
    expect(io.string).to be_empty
  end
end

# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe 'CLI smoke' do
  def with_captured_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield $stdout
  ensure
    $stdout = original_stdout
  end

  it 'prints help without touching the real terminal' do
    with_captured_stdout do |buffer|
      expect { EbookReader::CLI.run(['--help']) }.to raise_error(SystemExit)
      expect(buffer.string).to include('Usage: ebook_reader')
    end
  end
end

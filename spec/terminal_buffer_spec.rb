# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe EbookReader::TerminalBuffer do
  let(:io) { StringIO.new }
  let(:output) { EbookReader::TerminalOutput.new(io) }
  let(:buffer) { described_class.new(output) }

  def drain_io
    io.rewind
    io.read
  ensure
    io.truncate(0)
    io.rewind
  end

  it 'does not clear the whole screen when starting a frame' do
    buffer.start_frame(width: 10, height: 3)
    buffer.write(1, 1, 'Hello')
    buffer.end_frame

    out = drain_io
    expect(out).not_to include(EbookReader::TerminalOutput::ANSI::Control::CLEAR)
    expect(out).to include(EbookReader::TerminalOutput::ANSI.clear_line)
  end

  it 'emits no output when the rendered rows are unchanged' do
    buffer.start_frame(width: 10, height: 3)
    buffer.write(1, 1, 'Hello')
    buffer.end_frame
    drain_io

    buffer.start_frame(width: 10, height: 3)
    buffer.write(1, 1, 'Hello')
    buffer.end_frame

    expect(drain_io).to eq('')
  end

  it 'only repaints rows that change' do
    buffer.start_frame(width: 10, height: 3)
    buffer.write(1, 1, 'Hello')
    buffer.end_frame
    drain_io

    buffer.start_frame(width: 10, height: 3)
    buffer.write(1, 1, 'Hello')
    buffer.write(2, 1, 'X')
    buffer.end_frame

    out = drain_io
    expect(out).to include(EbookReader::TerminalOutput::ANSI.move(2, 1))
    expect(out).to include(EbookReader::TerminalOutput::ANSI.clear_line)
    expect(out).to include('X')
    expect(out).not_to include(EbookReader::TerminalOutput::ANSI.move(1, 1))
    expect(out).not_to include(EbookReader::TerminalOutput::ANSI.move(3, 1))
  end

  it 'emits raw control sequences before row diffs' do
    buffer.start_frame(width: 10, height: 3)
    buffer.raw('RAWSEQ')
    buffer.write(1, 1, 'Hello')
    buffer.end_frame

    out = drain_io
    expect(out).to start_with('RAWSEQ')
  end

  it 'repaints after clearing the buffer cache' do
    buffer.start_frame(width: 10, height: 3)
    buffer.write(1, 1, 'Hello')
    buffer.end_frame
    drain_io

    buffer.clear_buffer_cache

    buffer.start_frame(width: 10, height: 3)
    buffer.write(1, 1, 'Hello')
    buffer.end_frame

    expect(drain_io).to include(EbookReader::TerminalOutput::ANSI.move(1, 1))
  end
end


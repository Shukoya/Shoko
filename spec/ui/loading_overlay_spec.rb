# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::UI::LoadingOverlay do
  class OverlayFakeOutput
    attr_reader :writes
    def initialize = (@writes = [])
    def write(row, col, text)
      @writes << [row, col, text]
    end
  end

  class OverlayFakeTerminalService
    attr_reader :surface_out, :started, :ended
    def initialize(out)
      @surface_out = out
      @started = 0
      @ended = 0
    end
    def size = [10, 40]
    def start_frame = (@started += 1)
    def end_frame = (@ended += 1)
    def create_surface = EbookReader::Components::Surface.new(@surface_out)
  end

  it 'draws a progress bar line with expected characters' do
    out = OverlayFakeOutput.new
    term = OverlayFakeTerminalService.new(out)
    bus = EbookReader::Infrastructure::EventBus.new
    state = EbookReader::Infrastructure::ObserverStateStore.new(bus)
    state.update({ %i[ui loading_progress] => 0.5 })

    described_class.render(term, state)

    # One start/end frame pair
    expect(term.started).to eq(1)
    expect(term.ended).to eq(1)
    # At least one write containing heavy line chars
    written = out.writes.map(&:last).join
    expect(written).to include('━')
  end
end

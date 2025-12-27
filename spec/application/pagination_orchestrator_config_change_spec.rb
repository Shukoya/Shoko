# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Application::PaginationOrchestrator do
  let(:container) { EbookReader::Domain::ContainerFactory.create_default_container }
  let(:state) { container.resolve(:global_state) }
  let(:page_calculator) { container.resolve(:page_calculator) }
  let(:orchestrator) { described_class.new(container) }

  class FakeDoc
    attr_reader :lines

    def initialize(lines)
      @lines = lines
    end

    def chapter_count = 1

    def get_chapter(_idx)
      EbookReader::Domain::Models::Chapter.new(number: '1', title: 'Demo', lines: lines, metadata: nil,
                                               blocks: nil, raw_content: '<p></p>')
    end
  end

  let(:doc) { FakeDoc.new(Array.new(50) { |i| "L#{i}" }) }

  before do
    state.update({ %i[config page_numbering_mode] => :dynamic,
                   %i[config view_mode] => :single,
                   %i[config line_spacing] => :compact,
                   %i[ui terminal_width] => 80,
                   %i[ui terminal_height] => 24,
                   %i[reader current_chapter] => 0,
                   %i[reader current_page_index] => 1 })
    page_calculator.build_dynamic_map!(80, 24, doc, state)
  end

  it 'rebuilds pagination and preserves position when layout-affecting config changes' do
    # Sanity: compact spacing groups 21 lines per page -> 3 pages for 50 lines
    expect(page_calculator.total_pages).to eq(3)

    state.update(%i[config line_spacing] => :relaxed)

    orchestrator.rebuild_after_config_change(doc, state, page_calculator, [80, 24])

    # Relaxed spacing cuts capacity to 11 lines per page -> 5 pages for 50 lines
    expect(page_calculator.total_pages).to eq(5)
    expect(state.get(%i[reader current_page_index])).to eq(1) # restored to same line offset
  end
end

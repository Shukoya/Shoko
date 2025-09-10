# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Repositories::ConfigRepository do
  let(:state) { EbookReader::Infrastructure::StateStore.new }
  let(:test_logger) { double('Logger', error: nil, debug: nil, info: nil) }

  class CtnCfg
    def initialize(state, logger)
      (@state = state
       @logger = logger)
    end

    def resolve(name)
      return @state if name == :global_state
      return @logger if name == :logger

      nil
    end
  end

  subject(:repo) { described_class.new(CtnCfg.new(state, test_logger)) }

  it 'reads and updates core config values' do
    expect(repo.get_view_mode).to eq(:split)
    expect(repo.update_view_mode(:single)).to be true
    expect(repo.get_view_mode).to eq(:single)

    expect(repo.get_page_numbering_mode).to eq(:absolute)
    expect(repo.update_page_numbering_mode(:dynamic)).to be true
    expect(repo.get_page_numbering_mode).to eq(:dynamic)

    expect(repo.get_show_page_numbers).to be true
    expect(repo.update_show_page_numbers(false)).to be true
    expect(repo.get_show_page_numbers).to be false

    expect(repo.get_line_spacing).to eq(:normal)
    expect(repo.update_line_spacing(:wide)).to be true
    expect(repo.get_line_spacing).to eq(:wide)
  end

  it 'updates multiple and resets to defaults' do
    expect(repo.update_multiple({ view_mode: :single, show_page_numbers: false })).to be true
    expect(repo.get_view_mode).to eq(:single)
    expect(repo.get_show_page_numbers).to be false

    expect(repo.reset_to_defaults).to be true
    expect(repo.get_view_mode).to eq(:split)
    expect(repo.get_show_page_numbers).to be true
  end

  it 'detects customized values' do
    expect(repo.customized?(:view_mode)).to be false
    repo.update_view_mode(:single)
    expect(repo.customized?(:view_mode)).to be true
  end

  it 'validates invalid values' do
    expect { repo.update_view_mode(:bad) }.to raise_error(described_class::ValidationError)
    expect { repo.update_page_numbering_mode(:weird) }.to raise_error(described_class::ValidationError)
    expect { repo.update_show_page_numbers(nil) }.to raise_error(described_class::ValidationError)
    expect { repo.update_line_spacing(:foo) }.to raise_error(described_class::ValidationError)
    expect { repo.update_input_debounce_ms(0) }.to raise_error(described_class::ValidationError)
    expect { repo.update_multiple(nil) }.to raise_error(described_class::ValidationError)
    expect { repo.update_multiple({ theme: 'dark' }) }.to raise_error(described_class::ValidationError)
    # Unknown keys are allowed and only logged
    expect(repo.update_multiple({ custom_key: 123 })).to be true
  end
end

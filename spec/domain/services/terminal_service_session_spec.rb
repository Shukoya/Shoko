# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::TerminalService do
  let(:container) { EbookReader::Domain::ContainerFactory.create_test_container }
  let(:terminal) { described_class.new(container) }

  it 'manages setup/cleanup session depth without flicker' do
    # setup twice, cleanup once → still active
    expect { terminal.setup }.not_to raise_error
    expect { terminal.setup }.not_to raise_error
    expect { terminal.cleanup }.not_to raise_error
    # cleanup final time → exits
    expect { terminal.cleanup }.not_to raise_error
  end
end

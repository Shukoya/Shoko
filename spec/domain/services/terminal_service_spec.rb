# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::TerminalService do
  let(:svc) { described_class.new(EbookReader::Domain::ContainerFactory.create_test_container) }

  it 'creates a surface for rendering' do
    surface = svc.create_surface
    expect(surface).to respond_to(:write)
  end
end

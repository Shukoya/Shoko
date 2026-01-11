# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Zip::SizeLimits do
  it 'raises when entry sizes exceed limits' do
    with_env(
      'SHOKO_ZIP_MAX_ENTRY_BYTES' => '5',
      'SHOKO_ZIP_MAX_ENTRY_COMPRESSED_BYTES' => '5',
      'SHOKO_ZIP_MAX_TOTAL_BYTES' => '10'
    ) do
      limits = described_class.new(
        max_entry_uncompressed: nil,
        max_entry_compressed: nil,
        max_total_uncompressed: nil
      )
      entry = Zip::Entry.new(
        name: 'test',
        compressed_size: 10,
        uncompressed_size: 10,
        compression_method: 0,
        gp_flags: 0,
        local_header_offset: 0
      )

      expect { limits.enforce_entry_limits(entry, requested_name: 'test') }.to raise_error(Zip::Error)
    end
  end
end

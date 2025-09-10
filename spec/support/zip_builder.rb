# frozen_string_literal: true

require 'zlib'
require 'stringio'

# Minimal ZIP builder for tests. Produces a valid ZIP archive with
# Central Directory and EOCD. Supports :store and :deflate methods.
module ZipTestBuilder
  module_function

  # entries: [ { name: 'path/in/zip', data: String, method: :deflate|:store|Integer }, ... ]
  # comment: optional String for EOCD comment (to test EOCD scanning)
  def build_zip(entries, comment: nil)
    io = StringIO.new(''.b)
    central = StringIO.new(''.b)
    entries.each do |e|
      name = e[:name].to_s
      data = String(e[:data]).dup
      data.force_encoding(Encoding::BINARY)
      method = normalize_method(e[:method])
      gp_flags = 0
      crc = Zlib.crc32(data)
      compressed = method == 0 ? data : deflate_raw(data)
      lfh_off = io.string.bytesize

      # Local File Header
      io << [0x04034B50].pack('V')
      io << [20, gp_flags, method, 0, 0].pack('v v v v v')
      io << [crc, compressed.bytesize, data.bytesize].pack('V V V')
      io << [name.bytesize, 0].pack('v v')
      io << name
      io << compressed

      # Central Directory Header
      central << [0x02014B50].pack('V')
      central << [20, 20, gp_flags, method, 0, 0].pack('v v v v v v')
      central << [crc, compressed.bytesize, data.bytesize].pack('V V V')
      central << [name.bytesize, 0, 0, 0, 0].pack('v v v v v')
      central << [0, lfh_off].pack('V V')
      central << name
    end

    cd_start = io.string.bytesize
    cd_size = central.string.bytesize

    io << central.string

    # Duplicate to avoid modifying frozen string literals passed into builder
    comment = comment ? String(comment).dup : ''.dup
    comment.force_encoding(Encoding::BINARY)
    # End of Central Directory
    io << [0x06054B50].pack('V')
    count = entries.length
    io << [0, 0, count, count].pack('v v v v')
    io << [cd_size, cd_start].pack('V V')
    io << [comment.bytesize].pack('v')
    io << comment

    io.string
  end

  def deflate_raw(data)
    deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
    begin
      out = deflater.deflate(data)
      out << deflater.finish
    ensure
      begin
        deflater.close
      rescue StandardError
        nil
      end
    end
    out
  end

  def normalize_method(m)
    return 0 if m.nil? || m == :store || m == 0
    return 8 if [:deflate, 8].include?(m)

    m.to_i
  end
end

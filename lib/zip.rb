# frozen_string_literal: true

# Minimal, read-only ZIP reader compatible with the subset of rubyzip API
# used by this project. Supports STORE (0) and DEFLATE (8) entries.
#
# Public API:
#   Zip::File.open(path) { |zip| ... }
#   zip.read(entry_path) -> String (binary)
#   zip.find_entry(entry_path) -> entry or nil
#   zip.close ; zip.closed?
#   Zip::Error raised for malformed/unsupported archives or missing entries

require 'zlib'

module Zip
  class Error < StandardError; end

  # Metadata for a Central Directory entry.
  Entry = Struct.new(
    :name,
    :compressed_size,
    :uncompressed_size,
    :compression_method,
    :gp_flags,
    :local_header_offset,
    keyword_init: true
  )

  EOCD_SIG = [0x06054B50].pack('V').freeze # "PK\x05\x06"
  CDH_SIG  = [0x02014B50].pack('V').freeze # "PK\x01\x02"
  LFH_SIG  = [0x04034B50].pack('V').freeze # "PK\x03\x04"
  MAX_EOCD_SCAN = 66_560 # 64 KiB comment + 2 KiB buffer
  DEFAULT_MAX_ENTRY_COMPRESSED_BYTES = 64 * 1024 * 1024
  DEFAULT_MAX_ENTRY_UNCOMPRESSED_BYTES = 64 * 1024 * 1024
  DEFAULT_MAX_TOTAL_UNCOMPRESSED_BYTES = 256 * 1024 * 1024
  READ_CHUNK_BYTES = 16 * 1024

  # Helpers for indexing entries via the Central Directory.
  module IndexBuilder
    private

    def build_index!
      cd_offset, cd_size = locate_central_directory
      @io.seek(cd_offset, ::IO::SEEK_SET)
      stop = cd_offset + cd_size
      while @io.pos < stop
        entry = read_central_directory_entry
        @entries[entry.name] = entry
      end
    end

    def read_central_directory_entry
      verify_signature!(CDH_SIG, 'invalid central directory header signature')
      fixed = read_exact(42, error_message: 'truncated central directory header')

      gp_flags, method, csize, usize, name_len, extra_len, comment_len, lfh_off =
        parse_central_directory_fixed_header(fixed)

      name = @io.read(name_len) || ''
      skip_bytes(extra_len + comment_len)
      normalized = normalize_name(name)
      Entry.new(
        name: normalized,
        compressed_size: csize,
        uncompressed_size: usize,
        compression_method: method,
        gp_flags: gp_flags,
        local_header_offset: lfh_off
      )
    end

    def parse_central_directory_fixed_header(fixed)
      fields = fixed.unpack('v v v v v v V V V v v v v v V V')
      gp_flags = fields[2]
      method = fields[3]
      csize = fields[7]
      usize = fields[8]
      name_len = fields[9]
      extra_len = fields[10]
      comment_len = fields[11]
      lfh_off = fields[15]
      [gp_flags, method, csize, usize, name_len, extra_len, comment_len, lfh_off]
    end

    def locate_central_directory
      size = @io.stat.size
      scan = [size, MAX_EOCD_SCAN].min
      @io.seek(size - scan, ::IO::SEEK_SET)
      tail = @io.read(scan)
      raise Error, 'unable to read file tail' unless tail

      idx = tail.rindex(EOCD_SIG)
      raise Error, 'end of central directory not found' unless idx

      eocd = tail.byteslice(idx, 22)
      raise Error, 'truncated EOCD' unless eocd && eocd.bytesize == 22

      cd_size = eocd.byteslice(12, 4).unpack1('V')
      cd_offset = eocd.byteslice(16, 4).unpack1('V')
      [cd_offset, cd_size]
    end

    def skip_bytes(byte_count)
      return if byte_count.to_i <= 0

      @io.seek(byte_count, ::IO::SEEK_CUR)
    end

    def normalize_name(name)
      s = name.is_a?(String) ? name.dup : name.to_s
      s.force_encoding(Encoding::BINARY)
      s.tr!('\\', '/')
      s.sub!(%r{^\./}, '')
      s
    end
  end

  # Read-only ZIP archive reader with explicit size safeguards.
  class File
    include IndexBuilder

    def self.open(path, **)
      z = new(path, **)
      return z unless block_given?

      begin
        yield z
      ensure
        begin
          z.close
        rescue StandardError
          # ignore close errors
        end
      end
    end

    def initialize(path,
                   max_entry_uncompressed_bytes: nil,
                   max_entry_compressed_bytes: nil,
                   max_total_uncompressed_bytes: nil)
      @path = path
      @io = ::File.open(path, 'rb')
      @entries = {}
      @closed = false
      @max_entry_uncompressed_bytes = resolve_limit(max_entry_uncompressed_bytes,
                                                    env: 'READER_ZIP_MAX_ENTRY_BYTES',
                                                    default: DEFAULT_MAX_ENTRY_UNCOMPRESSED_BYTES)
      @max_entry_compressed_bytes = resolve_limit(max_entry_compressed_bytes,
                                                  env: 'READER_ZIP_MAX_ENTRY_COMPRESSED_BYTES',
                                                  default: DEFAULT_MAX_ENTRY_COMPRESSED_BYTES)
      @max_total_uncompressed_bytes = resolve_limit(max_total_uncompressed_bytes,
                                                    env: 'READER_ZIP_MAX_TOTAL_BYTES',
                                                    default: DEFAULT_MAX_TOTAL_UNCOMPRESSED_BYTES)
      @total_uncompressed_bytes = 0
      build_index!
    rescue StandardError
      close
      raise
    end

    def close
      return if @closed

      @io&.close
      @closed = true
    end

    def closed?
      @closed || !@io || @io.closed?
    end

    def find_entry(path)
      @entries[normalize_name(path)]
    end

    def read(path)
      entry = find_entry!(path)
      ensure_entry_readable!(entry)
      enforce_entry_limits!(entry, requested_name: path)

      seek_to_entry_data(entry)
      data = read_entry_payload(entry)
      verify_uncompressed_size!(entry, data)
      register_uncompressed_bytes!(entry, data.bytesize)
      data.force_encoding(Encoding::BINARY)
    end

    private

    def find_entry!(path)
      entry = find_entry(path)
      raise Error, "entry not found: #{path}" unless entry

      entry
    end

    def ensure_entry_readable!(entry)
      raise Error, "cannot read directory entry: #{entry.name}" if entry.name.end_with?('/')
      raise Error, "unsupported encrypted entry: #{entry.name}" if entry.gp_flags.to_i.anybits?(0x1)
    end

    def seek_to_entry_data(entry)
      @io.seek(entry.local_header_offset, ::IO::SEEK_SET)
      verify_signature!(LFH_SIG, 'invalid local file header signature')
      name_len, extra_len = local_file_header_variable_lengths
      @io.seek(name_len + extra_len, ::IO::SEEK_CUR)
    end

    def local_file_header_variable_lengths
      header = read_exact(26, error_message: 'truncated local file header')
      fields = header.unpack('v v v v v V V V v v')
      [fields[-2], fields[-1]]
    end

    def read_entry_payload(entry)
      case entry.compression_method
      when 0 then read_stored_entry(entry)
      when 8 then inflate_deflated_entry(entry)
      else raise Error, "unsupported compression method: #{entry.compression_method}"
      end
    end

    def read_stored_entry(entry)
      data = @io.read(entry.compressed_size)
      return data if data && data.bytesize == entry.compressed_size

      raise Error, 'truncated compressed data'
    end

    def verify_uncompressed_size!(entry, data)
      expected = entry.uncompressed_size
      return unless expected&.positive?
      return if data.bytesize == expected

      raise Error, 'size mismatch after decompression'
    end

    def register_uncompressed_bytes!(entry, byte_count)
      enforce_uncompressed_budget!(entry, byte_count)
      @total_uncompressed_bytes += byte_count
    end

    def verify_signature!(expected, error_message)
      sig = @io.read(expected.bytesize)
      raise Error, error_message unless sig == expected
    end

    def read_exact(byte_count, error_message:)
      data = @io.read(byte_count)
      return data if data && data.bytesize == byte_count

      raise Error, error_message
    end

    def resolve_limit(value, env:, default:)
      candidate = value
      candidate = ENV.fetch(env, nil) if candidate.nil?
      parsed = begin
        Integer(candidate)
      rescue StandardError
        nil
      end
      parsed = default if parsed.nil? || parsed <= 0
      parsed
    end

    def enforce_entry_limits!(entry, requested_name:)
      csize = entry.compressed_size.to_i
      usize = entry.uncompressed_size.to_i

      raise Error, "entry too large (compressed): #{requested_name}" if csize > @max_entry_compressed_bytes

      if usize.positive? && usize > @max_entry_uncompressed_bytes
        raise Error, "entry too large (uncompressed): #{requested_name}"
      end

      return unless usize.positive? && (@total_uncompressed_bytes + usize) > @max_total_uncompressed_bytes

      raise Error, "archive exceeds total uncompressed limit: #{requested_name}"
    end

    def enforce_uncompressed_budget!(entry, bytes)
      raise Error, "entry too large after decompression: #{entry.name}" if bytes > @max_entry_uncompressed_bytes

      return unless (@total_uncompressed_bytes + bytes) > @max_total_uncompressed_bytes

      raise Error, "archive exceeds total uncompressed limit: #{entry.name}"
    end

    def inflate_deflated_entry(entry)
      remaining = entry.compressed_size.to_i
      with_inflater do |inflater|
        inflate_from_io(inflater, entry, remaining)
      end
    end

    def with_inflater
      inflater = ::Zlib::Inflate.new(-::Zlib::MAX_WBITS)
      yield inflater
    rescue ::Zlib::DataError => e
      raise Error, "invalid deflate data: #{e.message}"
    ensure
      begin
        inflater&.close
      rescue StandardError
        nil
      end
    end

    def inflate_from_io(inflater, entry, remaining)
      output = +''
      remaining_bytes = remaining.to_i
      while remaining_bytes.positive?
        chunk = read_deflate_chunk(remaining_bytes)
        remaining_bytes -= chunk.bytesize
        output << inflater.inflate(chunk)
        enforce_uncompressed_budget!(entry, output.bytesize)
      end
      output << inflater.finish
    end

    def read_deflate_chunk(remaining_bytes)
      chunk = @io.read([remaining_bytes, READ_CHUNK_BYTES].min)
      raise Error, 'truncated compressed data' unless chunk && !chunk.empty?

      chunk
    end
  end
end

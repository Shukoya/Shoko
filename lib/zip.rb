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

  class File
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

    def self.open(path)
      z = new(path)
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

    def initialize(path)
      @path = path
      @io = ::File.open(path, 'rb')
      @entries = {}
      @closed = false
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
      entry = find_entry(path)
      raise Error, "entry not found: #{path}" unless entry
      raise Error, "cannot read directory entry: #{entry.name}" if entry.name.end_with?('/')

      # Seek to local file header
      @io.seek(entry.local_header_offset, ::IO::SEEK_SET)
      sig = @io.read(4)
      raise Error, 'invalid local file header signature' unless sig == LFH_SIG

      lfh = @io.read(26)
      raise Error, 'truncated local file header' unless lfh && lfh.bytesize == 26

      _ver_needed, _, _method_local, _time, _date, _crc32_local,
        _csize_local, _usize_local, name_len, extra_len = lfh.unpack('v v v v v V V V v v')

      # Skip name + extra to reach data start
      @io.seek(name_len + extra_len, ::IO::SEEK_CUR)

      compressed = @io.read(entry.compressed_size)
      unless compressed && compressed.bytesize == entry.compressed_size
        raise Error,
              'truncated compressed data'
      end

      case entry.compression_method
      when 0 # STORE
        data = compressed
      when 8 # DEFLATE
        inflater = ::Zlib::Inflate.new(-::Zlib::MAX_WBITS)
        begin
          data = inflater.inflate(compressed)
        ensure
          begin
            inflater.close
          rescue StandardError
            nil
          end
        end
      else
        raise Error, "unsupported compression method: #{entry.compression_method}"
      end

      # Optional sanity check on size
      if entry.uncompressed_size&.positive? && data.bytesize != entry.uncompressed_size
        # Some archives may omit sizes in local header and rely on data descriptor;
        # we trust Central Directory sizes; mismatch indicates corruption.
        raise Error, 'size mismatch after decompression'
      end

      # Return binary string
      data.force_encoding(Encoding::BINARY)
    end

    private

    def build_index!
      cd_offset, cd_size, _entries = locate_central_directory
      @io.seek(cd_offset, ::IO::SEEK_SET)
      stop = cd_offset + cd_size
      while @io.pos < stop
        sig = @io.read(4)
        raise Error, 'invalid central directory header signature' unless sig == CDH_SIG

        fixed = @io.read(42)
        raise Error, 'truncated central directory header' unless fixed && fixed.bytesize == 42

        _ver_made, _, gp_flags, method, _time, _date, _crc32,
          csize, usize, name_len, extra_len, comment_len,
          _disk_start, _int_attr, _ext_attr, lfh_off = fixed.unpack('v v v v v v V V V v v v v v V V')

        name = @io.read(name_len) || ''
        # Skip extra + comment
        skip_bytes(extra_len + comment_len)

        name = normalize_name(name)
        @entries[name] = Entry.new(
          name: name,
          compressed_size: csize,
          uncompressed_size: usize,
          compression_method: method,
          gp_flags: gp_flags,
          local_header_offset: lfh_off
        )
      end
    end

    def locate_central_directory
      size = @io.stat.size
      scan = [size, MAX_EOCD_SCAN].min
      @io.seek(size - scan, ::IO::SEEK_SET)
      tail = @io.read(scan)
      raise Error, 'unable to read file tail' unless tail

      idx = tail.rindex(EOCD_SIG)
      raise Error, 'end of central directory not found' unless idx

      eocd = tail.byteslice(idx, tail.bytesize - idx)
      raise Error, 'truncated EOCD' if eocd.bytesize < 22

      # Parse EOCD (22 bytes fixed + comment)
      # struct:
      #  4  signature
      #  2  disk_no
      #  2  cd_start_disk
      #  2  entries_on_disk
      #  2  entries_total
      #  4  cd_size
      #  4  cd_offset
      #  2  comment_len
      _disk_no      = eocd.byteslice(4, 2).unpack1('v')
      _cd_disk      = eocd.byteslice(6, 2).unpack1('v')
      _entries_disk = eocd.byteslice(8, 2).unpack1('v')
      _entries_tot  = eocd.byteslice(10, 2).unpack1('v')
      cd_size       = eocd.byteslice(12, 4).unpack1('V')
      cd_offset     = eocd.byteslice(16, 4).unpack1('V')
      _comment_len  = eocd.byteslice(20, 2).unpack1('v')

      [cd_offset, cd_size, _entries_tot]
    end

    def skip_bytes(n)
      return if n.to_i <= 0

      @io.seek(n, ::IO::SEEK_CUR)
    end

    def normalize_name(name)
      s = name.is_a?(String) ? name.dup : name.to_s
      s.force_encoding(Encoding::BINARY)
      s.tr!('\\', '/')
      s.sub!(%r{^\./}, '')
      s
    end
  end
end

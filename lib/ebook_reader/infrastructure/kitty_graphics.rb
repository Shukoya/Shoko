# frozen_string_literal: true

require 'base64'

module EbookReader
  module Infrastructure
    # Minimal support for the Kitty graphics protocol.
    #
    # This module intentionally keeps all logic in-process (no external commands)
    # and suppresses terminal responses (q=2) to avoid corrupting raw input reads.
    module KittyGraphics
      module_function

      ESC = "\e"
      APC_START = "#{ESC}_G"
      APC_END = "#{ESC}\\"
      MAX_CHUNK_BYTES = 4096

      def supported?
        return true if env_present?('KITTY_WINDOW_ID')
        return true if ENV.fetch('TERM', '').include?('kitty')
        return true if ENV.fetch('TERM_PROGRAM', '') == 'kitty'

        false
      rescue StandardError
        false
      end

      def enabled_for?(config_store)
        return false unless supported?
        return false unless config_store && config_store.respond_to?(:get)

        !!config_store.get(%i[config kitty_images])
      rescue StandardError
        false
      end

      def transmit_png(image_id, png_bytes, quiet: true)
        bytes = String(png_bytes).dup
        bytes.force_encoding(Encoding::BINARY)
        payload = Base64.strict_encode64(bytes)
        chunks = chunk_payload(payload)
        chunks.map.with_index do |chunk, index|
          more = index < chunks.length - 1 ? 1 : 0
          control = if index.zero?
                      keys = { a: 't', f: 100, t: 'd', i: image_id.to_i, m: more }
                      keys[:q] = 2 if quiet
                      serialize_keys(keys)
                    else
                      keys = { m: more }
                      keys[:q] = 2 if quiet
                      serialize_keys(keys)
                    end
          "#{APC_START}#{control};#{chunk}#{APC_END}"
        end
      end

      def place(image_id, placement_id:, cols:, rows:, quiet: true, z: nil)
        keys = {
          a: 'p',
          i: image_id.to_i,
          p: placement_id.to_i,
          c: cols.to_i,
          r: rows.to_i,
          C: 1,
        }
        keys[:q] = 2 if quiet
        keys[:z] = z.to_i if z
        "#{APC_START}#{serialize_keys(keys)}#{APC_END}"
      end

      def delete_visible(quiet: true)
        keys = { a: 'd' }
        keys[:q] = 2 if quiet
        "#{APC_START}#{serialize_keys(keys)}#{APC_END}"
      end

      def chunk_payload(payload)
        return [] if payload.nil? || payload.empty?

        max = MAX_CHUNK_BYTES
        payload.scan(/.{1,#{max}}/m)
      end
      private_class_method :chunk_payload

      def serialize_keys(hash)
        hash.map { |k, v| "#{k}=#{v}" }.join(',')
      end
      private_class_method :serialize_keys

      def env_present?(key)
        value = ENV[key].to_s
        !value.empty?
      end
      private_class_method :env_present?
    end
  end
end

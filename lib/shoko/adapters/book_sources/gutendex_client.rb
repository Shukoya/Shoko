# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module Shoko
  module Adapters::BookSources
    # Thin HTTP client for the Gutendex API.
    class GutendexClient
      class Error < StandardError; end

      API_ROOT = 'https://gutendex.com/books'

      def initialize(logger: nil, open_timeout: 5, read_timeout: 15)
        @logger = logger
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def search(query:, page_url: nil)
        uri = page_url ? normalize_uri(page_url, base: API_ROOT) : build_query_uri(query)
        request_json(uri)
      end

      def download(url, dest_path, &)
        uri = normalize_uri(url, base: API_ROOT)
        request_download(uri, dest_path, &)
      end

      private

      def build_query_uri(query)
        uri = URI.parse(API_ROOT)
        q = query.to_s.strip
        uri.query = URI.encode_www_form(search: q) unless q.empty?
        uri
      end

      def request_json(uri, limit = 2)
        response = request(uri)
        return parse_json(response) if response.is_a?(Net::HTTPSuccess)

        if response.is_a?(Net::HTTPRedirection) && limit.positive?
          redirect = resolve_redirect_uri(uri, response['location'])
          return request_json(redirect, limit - 1)
        end

        raise Error, "Request failed (#{response.code})"
      end

      def parse_json(response)
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise Error, "Invalid JSON response: #{e.message}"
      end

      def request_download(uri, dest_path, limit = 2, &on_progress)
        response = request(uri) do |http|
          http.request(Net::HTTP::Get.new(uri)) do |resp|
            if resp.is_a?(Net::HTTPSuccess)
              stream_response(resp, dest_path, &on_progress)
            else
              resp
            end
          end
        end

        if response.is_a?(Net::HTTPRedirection) && limit.positive?
          redirect = resolve_redirect_uri(uri, response['location'])
          return request_download(redirect, dest_path, limit - 1, &on_progress)
        end

        return response if response.is_a?(Net::HTTPSuccess)

        raise Error, "Download failed (#{response.code})"
      end

      def stream_response(response, dest_path)
        return response unless response.is_a?(Net::HTTPSuccess)

        total = response['Content-Length'].to_i
        downloaded = 0
        File.open(dest_path, 'wb') do |file|
          response.read_body do |chunk|
            file.write(chunk)
            downloaded += chunk.bytesize
            yield(downloaded, total) if block_given?
          end
        end
        response
      end

      def request(uri, &)
        uri = normalize_uri(uri, base: API_ROOT)
        raise Error, "Invalid URL: #{uri}" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout
        if block_given?
          http.start(&)
        else
          http.get(uri.request_uri)
        end
      rescue StandardError => e
        @logger&.error('Gutendex request failed', error: e.message, url: uri.to_s)
        raise Error, e.message
      end

      def normalize_uri(input, base: nil)
        uri = input.is_a?(URI) ? input : URI.parse(input.to_s)
        return uri if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

        if base
          base_uri = base.is_a?(URI) ? base : URI.parse(base.to_s)
          begin
            joined = URI.join(base_uri.to_s, uri.to_s)
            return joined if joined.is_a?(URI::HTTP) || joined.is_a?(URI::HTTPS)
          rescue URI::Error
            # fall through
          end
        end

        if uri.scheme.nil? && uri.host.nil?
          candidate = uri.to_s
          if candidate.start_with?('//')
            candidate = "https:#{candidate}"
          elsif /\A[a-z0-9.-]+\.[a-z]{2,}/i.match?(candidate)
            candidate = "https://#{candidate}"
          end

          begin
            parsed = URI.parse(candidate)
            return parsed if parsed.is_a?(URI::HTTP) || parsed.is_a?(URI::HTTPS)
          rescue URI::Error
            # fall through
          end
        end

        uri
      end

      def resolve_redirect_uri(base_uri, location)
        normalize_uri(location, base: base_uri)
      end
    end
  end
end

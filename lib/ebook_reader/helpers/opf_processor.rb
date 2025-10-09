# frozen_string_literal: true

require 'rexml/document'
require 'cgi'

require_relative '../infrastructure/perf_tracer'
require_relative 'html_processor'

module EbookReader
  module Helpers
    # Processes OPF files
    class OPFProcessor
      SpineContext = Struct.new(:manifest, :chapter_titles)

      attr_reader :toc_entries

      def initialize(opf_path, zip: nil)
        @opf_path = opf_path
        @opf_dir = File.dirname(opf_path)
        @zip = zip
        content = if zip
                    EbookReader::Infrastructure::PerfTracer.measure('zip.read') { zip.read(opf_path) }
                  else
                    File.read(opf_path)
                  end
        @opf = EbookReader::Infrastructure::PerfTracer.measure('opf.parse') do
          REXML::Document.new(content)
        end
        @toc_entries = []
        @document_anchor_map = {}
        @document_heading_queue = {}
      end

      def extract_metadata
        metadata = {}
        if (meta_elem = @opf.elements['//metadata'])
          elems = meta_elem.elements

          raw_title = elems['*[local-name()="title"]']&.text
          metadata[:title] = HTMLProcessor.clean_html(raw_title.to_s).strip if raw_title

          if (lang_text = elems['*[local-name()="language"]']&.text)
            metadata[:language] = lang_text.include?('_') ? lang_text : "#{lang_text}_#{lang_text.upcase}"
          end

          # dc:creator (authors) — may be multiple
          authors = []
          elems.each('*[local-name()="creator"]') do |creator|
            txt = HTMLProcessor.clean_html(creator.text.to_s).strip
            authors << txt unless txt.empty?
          end
          metadata[:authors] = authors unless authors.empty?

          # dc:date — parse year if present
          if (date_elem = elems['*[local-name()="date"]'])
            date_text = date_elem.text.to_s
            if !date_text.empty? && (m = date_text.match(/(\d{4})/))
              metadata[:year] = m[1]
            end
          end
        end
        metadata
      end

      def build_manifest_map
        manifest = {}
        @opf.elements.each('//manifest/item') do |item|
          attrs = item.attributes
          id = attrs['id']
          href = attrs['href']
          manifest[id] = CGI.unescape(href) if id && href
        end
        manifest
      end

      def extract_chapter_titles(manifest)
        ncx_path = find_ncx_path(manifest)
        return {} unless ncx_path

        extract_titles_from_ncx(ncx_path)
      end

      def process_spine(manifest, chapter_titles)
        chapter_num = 1
        spine_context = SpineContext.new(manifest, chapter_titles)

        @opf.elements.each('//spine/itemref') do |itemref|
          chapter_num = process_itemref(itemref, chapter_num, spine_context) do |*args|
            yield(*args)
          end
        end
      end

      private

      def find_ncx_path(manifest)
        ncx_id = @opf.elements['//spine']&.attributes&.[]('toc')
        return nil unless ncx_id

        ncx_href = manifest[ncx_id]
        return nil unless ncx_href

        path = join_path(ncx_href)
        entry_exists?(path) ? path : nil
      end

      def extract_titles_from_ncx(ncx_path)
        chapter_titles = {}
        ncx_content = read_entry(ncx_path)
        ncx = REXML::Document.new(ncx_content)
        nav_map = ncx.elements['//navMap']
        return chapter_titles unless nav_map

        traverse_nav_points(nav_map, chapter_titles, 0)
        chapter_titles
      end

      def process_itemref(itemref, chapter_num, spine_context)
        idref = itemref.attributes['idref']
        manifest = spine_context.manifest
        return chapter_num unless valid_itemref?(idref, manifest)

        href = manifest[idref]
        file_path = join_path(href)
        exists = entry_exists?(file_path)
        return chapter_num unless exists

        title = spine_context.chapter_titles[href]
        yield(file_path, chapter_num, title, href)
        chapter_num + 1
      end

      def valid_itemref?(idref, manifest)
        idref && manifest[idref]
      end

      def join_path(href)
        File.join(@opf_dir, href).sub(%r{^\./}, '')
      end

      def use_zip?
        !@zip.nil?
      end

      def entry_exists?(path)
        use_zip? ? !!@zip.find_entry(path) : File.exist?(path)
      end

      def read_entry(path)
        use_zip? ? @zip.read(path) : File.read(path)
      end

      def traverse_nav_points(node, chapter_titles, level)
        node.each_element('navPoint') do |nav_point|
          label = nav_point.elements['navLabel/text']
          # Some NCX files omit navLabel or replace it with generated ids; recover from target doc
          href_attr = nav_point.elements['content']&.attributes&.[]('src')
          title = label ? clean_label(label.text) : ''
          title = fallback_nav_label(href_attr, title)

          @toc_entries << {
            title: title,
            href: href_attr,
            level: level,
          }

          resolved_href = href_attr&.split('#')&.first
          if resolved_href && (level.positive? || !chapter_titles.key?(resolved_href))
            chapter_titles[resolved_href] = title
          end

          traverse_nav_points(nav_point, chapter_titles, level + 1)
        end
      end

      def clean_label(text)
        HTMLProcessor.clean_html(text.to_s).strip
      end

      def fallback_nav_label(href, title)
        stripped = title.to_s.strip
        return stripped unless placeholder_label?(stripped)
        return stripped unless href

        base, anchor = href.split('#', 2)
        document_path = join_path(base)
        ensure_document_index(document_path)

        candidate = nil
        if anchor
          candidate = @document_anchor_map[document_path][anchor]
          remove_heading_from_queue(document_path, candidate)
        end

        candidate = next_heading_for(document_path) if candidate.nil? || candidate.strip.empty?
        candidate = stripped if candidate.nil? || candidate.strip.empty?

        clean_label(candidate)
      rescue StandardError
        stripped
      end

      def placeholder_label?(label)
        stripped = label.to_s.strip
        return true if stripped.empty?

        stripped.match?(/\A[cC][0-9A-Za-z]{2,}\z/)
      end

      def extract_anchor_text(content, anchor)
        regex = %r{<(?<tag>[^>\s]+)[^>]*\s(?:id|name|xml:id)\s*=\s*["']#{Regexp.escape(anchor)}["'][^>]*>(?<text>.*?)</\k<tag>>}im
        match = content.match(regex)
        match && match[:text]
      end

      def extract_following_link_text(content, anchor)
        regex = %r{(?:id|name|xml:id)\s*=\s*["']#{Regexp.escape(anchor)}["'][^>]*>\s*<[^>]*>(?<text>[^<]+)</[^>]+>}im
        match = content.match(regex)
        match && match[:text]
      end

      def ensure_document_index(path)
        return if @document_anchor_map.key?(path)

        content = safe_read_entry(path)
        @document_anchor_map[path] = {}
        @document_heading_queue[path] = []
        return unless content

        content.scan(%r{<(h[1-6])[^>]*?(?:id|name|xml:id)\s*=\s*["']([^"']+)["'][^>]*>(.*?)</\1>}im) do |_tag, anchor, text|
          label = clean_label(text)
          @document_anchor_map[path][anchor] = label unless label.empty?
        end

        content.scan(%r{<(h[1-6])[^>]*>(.*?)</\1>}im) do |_tag, text|
          label = clean_label(text)
          @document_heading_queue[path] << label unless label.empty?
        end
      end

      def next_heading_for(path)
        queue = @document_heading_queue[path]
        return '' unless queue

        queue.shift.to_s
      end

      def remove_heading_from_queue(path, text)
        return if text.nil? || text.strip.empty?

        queue = @document_heading_queue[path]
        return unless queue

        idx = queue.index(text)
        queue.delete_at(idx) if idx
      end

      def safe_read_entry(path)
        read_entry(path)
      rescue StandardError
        nil
      end
    end
  end
end

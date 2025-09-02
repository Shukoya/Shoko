# frozen_string_literal: true

require 'rexml/document'
require 'cgi'

module EbookReader
  module Helpers
    # Processes OPF files
    class OPFProcessor
      SpineContext = Struct.new(:manifest, :chapter_titles)

      def initialize(opf_path, zip: nil)
        @opf_path = opf_path
        @opf_dir = File.dirname(opf_path)
        @zip = zip
        content = zip ? zip.read(opf_path) : File.read(opf_path)
        @opf = REXML::Document.new(content)
      end

      def extract_metadata
        metadata = {}
        if (meta_elem = @opf.elements['//metadata'])
          raw_title = meta_elem.elements['*[local-name()="title"]']&.text
          metadata[:title] = HTMLProcessor.clean_html(raw_title.to_s).strip if raw_title
          if (lang = meta_elem.elements['*[local-name()="language"]']&.text)
            metadata[:language] = lang.include?('_') ? lang : "#{lang}_#{lang.upcase}"
          end

          # dc:creator (authors) — may be multiple
          authors = []
          meta_elem.elements.each('*[local-name()="creator"]') do |creator|
            txt = HTMLProcessor.clean_html(creator.text.to_s).strip
            authors << txt unless txt.empty?
          end
          metadata[:authors] = authors unless authors.empty?

          # dc:date — parse year if present
          if (date_elem = meta_elem.elements['*[local-name()="date"]']) && date_elem.text
            if (m = date_elem.text.to_s.match(/(\d{4})/))
              metadata[:year] = m[1]
            end
          end
        end
        metadata
      end

      def build_manifest_map
        manifest = {}
        @opf.elements.each('//manifest/item') do |item|
          id = item.attributes['id']
          href = item.attributes['href']
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
        if @zip
          @zip.find_entry(path) ? path : nil
        else
          File.exist?(path) ? path : nil
        end
      end

      def extract_titles_from_ncx(ncx_path)
        chapter_titles = {}
        ncx_content = @zip ? @zip.read(ncx_path) : File.read(ncx_path)
        ncx = REXML::Document.new(ncx_content)

        ncx.elements.each('//navMap/navPoint/navLabel/text') do |label|
          process_nav_point(label, chapter_titles)
        end

        chapter_titles
      end

      def process_nav_point(label, chapter_titles)
        nav_point = label.parent.parent
        content_src = nav_point.elements['content']&.attributes&.[]('src')
        return unless content_src

        key = content_src.split('#').first
        chapter_titles[key] = HTMLProcessor.clean_html(label.text)
      end

      def process_itemref(itemref, chapter_num, spine_context)
        idref = itemref.attributes['idref']
        return chapter_num unless valid_itemref?(idref, spine_context.manifest)

        href = spine_context.manifest[idref]
        file_path = join_path(href)
        exists = @zip ? @zip.find_entry(file_path) : File.exist?(file_path)
        return chapter_num unless exists

        title = spine_context.chapter_titles[href]
        yield(file_path, chapter_num, title)
        chapter_num + 1
      end

      def valid_itemref?(idref, manifest)
        idref && manifest[idref]
      end

      def join_path(href)
        File.join(@opf_dir, href).sub(%r{^\./}, '')
      end
    end
  end
end

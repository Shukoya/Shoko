# frozen_string_literal: true

require 'rexml/document'
require 'cgi'

module EbookReader
  module Helpers
    # Processes OPF files
    class OPFProcessor
      def initialize(opf_path)
        @opf_path = opf_path
        @opf_dir = File.dirname(opf_path)
        @opf = REXML::Document.new(File.read(opf_path))
      end

      def extract_metadata
        metadata = {}
        if (meta_elem = @opf.elements['//metadata'])
          metadata[:title] = meta_elem.elements['*[local-name()="title"]']&.text
          if (lang = meta_elem.elements['*[local-name()="language"]']&.text)
            metadata[:language] = lang.include?('_') ? lang : "#{lang}_#{lang.upcase}"
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

        @opf.elements.each('//spine/itemref') do |itemref|
          chapter_num = process_itemref(itemref, manifest, chapter_titles, chapter_num) do |*args|
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

        path = File.join(@opf_dir, ncx_href)
        File.exist?(path) ? path : nil
      end

      def extract_titles_from_ncx(ncx_path)
        chapter_titles = {}
        ncx = REXML::Document.new(File.read(ncx_path))

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

      def process_itemref(itemref, manifest, chapter_titles, chapter_num)
        idref = itemref.attributes['idref']
        return chapter_num unless valid_itemref?(idref, manifest)

        href = manifest[idref]
        file_path = File.join(@opf_dir, href)
        return chapter_num unless File.exist?(file_path)

        title = chapter_titles[href]
        yield(file_path, chapter_num, title)
        chapter_num + 1
      end

      def valid_itemref?(idref, manifest)
        idref && manifest[idref]
      end
    end
  end
end

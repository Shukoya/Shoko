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
        manifest = spine_context.manifest
        return chapter_num unless valid_itemref?(idref, manifest)

        href = manifest[idref]
        file_path = join_path(href)
        exists = entry_exists?(file_path)
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

      def use_zip?
        !@zip.nil?
      end

      def entry_exists?(path)
        use_zip? ? !!@zip.find_entry(path) : File.exist?(path)
      end

      def read_entry(path)
        use_zip? ? @zip.read(path) : File.read(path)
      end
    end
  end
end

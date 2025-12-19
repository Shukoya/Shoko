# frozen_string_literal: true

require 'rexml/document'
require 'cgi'
require 'pathname'

require_relative '../infrastructure/perf_tracer'
require_relative 'html_processor'
require_relative 'terminal_sanitizer'

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
        content = normalize_xml_text(content)
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
          next unless id && href

          decoded = CGI.unescape(href)
          normalized = normalize_opf_relative_href(decoded)
          manifest[id] = normalized if normalized
        end
        manifest
      end

      def extract_chapter_titles(manifest)
        @toc_entries = []

        nav_bundle = extract_navigation_from_nav
        ncx_bundle = extract_navigation_from_ncx(manifest)

        chosen_entries, chosen_titles = choose_navigation_source(
          nav_entries: nav_bundle.toc_entries,
          nav_titles: nav_bundle.titles,
          ncx_entries: ncx_bundle.toc_entries,
          ncx_titles: ncx_bundle.titles,
          manifest: manifest
        )

        @toc_entries = chosen_entries
        chosen_titles
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

      NavigationBundle = Struct.new(:toc_entries, :titles, keyword_init: true)
      private_constant :NavigationBundle

      def find_ncx_path(manifest)
        ncx_id = @opf.elements['//spine']&.attributes&.[]('toc')
        if ncx_id && (ncx_href = manifest[ncx_id])
          path = join_path(ncx_href)
          return path if path && entry_exists?(path)
        end

        candidates = []
        @opf.elements.each('//manifest/item') do |item|
          attrs = item.attributes
          href = attrs['href']
          next unless href

          media_type = attrs['media-type'].to_s.downcase
          decoded = CGI.unescape(href)
          candidates << decoded if media_type.include?('ncx') || decoded.downcase.end_with?('.ncx')
        end

        candidates.each do |href|
          path = join_path(href)
          return path if path && entry_exists?(path)
        end

        nil
      end

      def find_nav_path
        @opf.elements.each('//manifest/item') do |item|
          attrs = item.attributes
          props = attrs['properties'].to_s.split
          next unless props.include?('nav')

          href = attrs['href']
          next unless href

          path = join_path(CGI.unescape(href))
          return path if path && entry_exists?(path)
        end

        nil
      end

      def extract_navigation_from_nav
        nav_path = find_nav_path
        return NavigationBundle.new(toc_entries: [], titles: {}) unless nav_path

        content = safe_read_entry(nav_path)
        return NavigationBundle.new(toc_entries: [], titles: {}) unless content

        doc = REXML::Document.new(content)
        nav = find_nav_toc_node(doc)
        return NavigationBundle.new(toc_entries: [], titles: {}) unless nav

        list = nav.elements['.//*[local-name()="ol"]'] || nav.elements['.//*[local-name()="ul"]']
        return NavigationBundle.new(toc_entries: [], titles: {}) unless list

        titles = {}
        entries = []
        traverse_nav_list(list, titles, entries, level: 0, source_path: nav_path)
        NavigationBundle.new(toc_entries: entries, titles: titles)
      rescue REXML::ParseException
        NavigationBundle.new(toc_entries: [], titles: {})
      end

      def extract_navigation_from_ncx(manifest)
        ncx_path = find_ncx_path(manifest)
        return NavigationBundle.new(toc_entries: [], titles: {}) unless ncx_path

        chapter_titles = {}
        entries = []
        ncx_content = read_entry(ncx_path)
        ncx = REXML::Document.new(ncx_content)
        nav_map = ncx.elements['//navMap']
        return NavigationBundle.new(toc_entries: [], titles: {}) unless nav_map

        traverse_nav_points(nav_map, chapter_titles, entries, level: 0, source_path: ncx_path)
        NavigationBundle.new(toc_entries: entries, titles: chapter_titles)
      rescue StandardError
        NavigationBundle.new(toc_entries: [], titles: {})
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
        return nil unless href

        if use_zip?
          File.expand_path(File.join('/', @opf_dir, href), '/').sub(%r{^/}, '')
        else
          File.expand_path(File.join(@opf_dir, href))
        end
      end

      def use_zip?
        !@zip.nil?
      end

      def entry_exists?(path)
        use_zip? ? !!@zip.find_entry(path) : File.exist?(path)
      end

      def read_entry(path)
        raw = use_zip? ? @zip.read(path) : File.read(path)
        normalize_xml_text(raw)
      end

      def traverse_nav_points(node, chapter_titles, entries, level:, source_path:)
        node.each_element('navPoint') do |nav_point|
          label = nav_point.elements['navLabel/text']
          # Some NCX files omit navLabel or replace it with generated ids; recover from target doc
          href_attr = nav_point.elements['content']&.attributes&.[]('src')
          title = label ? clean_label(label.text) : ''
          title = fallback_nav_label(href_attr, title, source_path: source_path)

          target_path, opf_href = toc_target_for(source_path, href_attr)

          entries << {
            title: title,
            href: href_attr,
            level: level,
            source_path: source_path,
            target: target_path,
            opf_href: opf_href,
          }

          chapter_titles[opf_href] = title if opf_href && (level.positive? || !chapter_titles.key?(opf_href))

          traverse_nav_points(nav_point, chapter_titles, entries, level: level + 1, source_path: source_path)
        end
      end

      def clean_label(text)
        HTMLProcessor.clean_html(text.to_s).strip
      end

      def fallback_nav_label(href, title, source_path:)
        stripped = title.to_s.strip
        return stripped unless placeholder_label?(stripped)
        return stripped unless href

        document_path, anchor = href_document_and_anchor(source_path, href)
        return stripped unless document_path

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

      def normalize_opf_relative_href(href)
        return nil if href.nil? || href.to_s.empty?

        joined = join_path(href)
        return nil unless joined

        Pathname.new(joined).relative_path_from(Pathname.new(@opf_dir)).to_s
      rescue ArgumentError
        href.to_s
      end

      def toc_target_for(source_path, href)
        document_path, = href_document_and_anchor(source_path, href)
        return [nil, nil] unless document_path

        opf_href = Pathname.new(document_path).relative_path_from(Pathname.new(@opf_dir)).to_s
        [document_path, opf_href]
      rescue ArgumentError
        [document_path, nil]
      end

      def href_document_and_anchor(source_path, href)
        return [nil, nil] unless href

        decoded = CGI.unescape(href.to_s)
        base, anchor = decoded.split('#', 2)
        base = base.to_s
        return [nil, anchor] if base.empty?

        base_dir = File.dirname(source_path || @opf_path)
        document_path = if use_zip?
                          File.expand_path(File.join('/', base_dir, base), '/').sub(%r{^/}, '')
                        else
                          File.expand_path(File.join(base_dir, base))
                        end
        [document_path, anchor]
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

      def find_nav_toc_node(doc)
        doc.elements.each('//*[local-name()="nav"]') do |nav|
          type = nav_attribute(nav, 'epub:type') || nav_attribute(nav, 'type') || nav_attribute(nav, 'role')
          next unless type

          normalized = type.to_s.strip.downcase
          return nav if %w[toc doc-toc].include?(normalized)
        end

        nil
      end

      def nav_attribute(element, name)
        element.attributes.each_attribute do |attr|
          return attr.value if attr.expanded_name == name || attr.name == name
        end
        nil
      end

      def traverse_nav_list(list, titles, entries, level:, source_path:)
        list.each_element do |child|
          next unless child.is_a?(REXML::Element)
          next unless child.name.casecmp('li').zero?

          anchor = child.elements['./*[local-name()="a"]'] || child.elements['.//*[local-name()="a"]']
          href_attr = anchor&.attributes&.[]('href')
          title = anchor ? clean_label(anchor.texts.join) : clean_label(nav_li_label_text(child))
          title = fallback_nav_label(href_attr, title, source_path: source_path)

          target_path, opf_href = toc_target_for(source_path, href_attr)

          entries << {
            title: title,
            href: href_attr,
            level: level,
            source_path: source_path,
            target: target_path,
            opf_href: opf_href,
          }

          titles[opf_href] = title if opf_href && (level.positive? || !titles.key?(opf_href))

          nested = child.elements['./*[local-name()="ol"]'] || child.elements['./*[local-name()="ul"]']
          traverse_nav_list(nested, titles, entries, level: level + 1, source_path: source_path) if nested
        end
      end

      def nav_li_label_text(list_item)
        buffer = +''
        list_item.children.each do |child|
          case child
          when REXML::Text
            buffer << child.value.to_s
          when REXML::Element
            break if child.name.casecmp('ol').zero? || child.name.casecmp('ul').zero?

            buffer << child.texts.join
          end
        end
        buffer
      end

      def choose_navigation_source(nav_entries:, nav_titles:, ncx_entries:, ncx_titles:, manifest:)
        return [nav_entries, ncx_titles.merge(nav_titles)] if nav_entries.any? && ncx_entries.empty?
        return [ncx_entries, ncx_titles.merge(nav_titles)] if ncx_entries.any? && nav_entries.empty?
        return [[], {}] if nav_entries.empty? && ncx_entries.empty?

        spine = spine_href_set(manifest)
        nav_covered = count_spine_coverage(nav_entries, spine)
        ncx_covered = count_spine_coverage(ncx_entries, spine)

        if nav_covered >= ncx_covered
          [nav_entries, ncx_titles.merge(nav_titles)]
        else
          [ncx_entries, ncx_titles.merge(nav_titles)]
        end
      end

      def spine_href_set(manifest)
        hrefs = []
        @opf.elements.each('//spine/itemref') do |itemref|
          idref = itemref.attributes['idref']
          href = manifest[idref]
          next unless href

          hrefs << href
        end
        hrefs.to_set
      end

      def count_spine_coverage(entries, spine_set)
        entries.count do |entry|
          href = entry.is_a?(Hash) ? entry[:opf_href] : nil
          href && spine_set.include?(href)
        end
      end

      def normalize_xml_text(content)
        bytes = String(content).dup
        bytes.force_encoding(Encoding::BINARY)
        bytes = bytes.delete_prefix("\xEF\xBB\xBF".b)

        declared = bytes[/\A\s*<\?xml[^>]*encoding=["']([^"']+)["']/i, 1]
        encoding = begin
          declared ? Encoding.find(declared) : Encoding::UTF_8
        rescue StandardError
          Encoding::UTF_8
        end

        text = bytes.dup
        text.force_encoding(encoding)
        text = text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "\uFFFD")
        text = text.delete_prefix("\uFEFF")
        TerminalSanitizer.sanitize_xml_source(text, preserve_newlines: true, preserve_tabs: true)
      rescue StandardError
        TerminalSanitizer.sanitize_xml_source(content.to_s, preserve_newlines: true, preserve_tabs: true)
      end
    end
  end
end

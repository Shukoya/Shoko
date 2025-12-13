# frozen_string_literal: true

require 'zip'
require 'rexml/document'

require_relative '../errors'
require_relative '../helpers/html_processor'
require_relative '../helpers/opf_processor'
require_relative '../domain/models/chapter'
require_relative '../domain/models/toc_entry'
require_relative 'perf_tracer'

module EbookReader
  module Infrastructure
    # Imports an EPUB archive into an in-memory representation that can be
    # serialized using {EpubCache}. Responsible for extracting metadata,
    # chapters, and table-of-contents entries in a consistent schema.
    #
    # Binary resources (images, stylesheets, etc.) are intentionally not extracted
    # by default since the reader currently renders image placeholders and does
    # not consume the raw bytes. Optional consumers (e.g. Kitty image rendering)
    # should load resources on-demand.
    class EpubImporter
      DEFAULT_LANGUAGE = 'en_US'
      CONTAINER_PATH   = 'META-INF/container.xml'

      def initialize(formatting_service: nil, extract_resources: false)
        @formatting_service = formatting_service
        @extract_resources = !!extract_resources
      end

      def import(epub_path)
        @epub_path = File.expand_path(epub_path)
        raise EbookReader::FileNotFoundError, epub_path unless File.file?(@epub_path)

        Zip::File.open(@epub_path) do |zip|
          container_xml = read_container(zip)
          opf_path      = locate_opf_path(zip, container_xml)
          processor     = Helpers::OPFProcessor.new(opf_path, zip: zip)

          metadata = processor.extract_metadata
          manifest = processor.build_manifest_map
          chapter_titles = processor.extract_chapter_titles(manifest)

          chapters_data = build_chapters(zip, opf_path, processor, manifest, chapter_titles)
          chapters      = chapters_data[:chapters]
          chapter_hrefs = chapters_data[:hrefs]
          spine         = chapters_data[:spine]

          toc_entries = build_toc_entries(chapters, processor.toc_entries, chapter_hrefs, opf_path)
          resources   = @extract_resources ? extract_resources(zip, opf_path, manifest) : {}

          EpubCache::BookData.new(
            title: metadata[:title] || fallback_title(@epub_path),
            language: metadata[:language] || DEFAULT_LANGUAGE,
            authors: Array(metadata[:authors]).map(&:to_s),
            chapters: chapters,
            toc_entries: toc_entries,
            opf_path: opf_path,
            spine: spine,
            chapter_hrefs: chapter_hrefs,
            resources: resources,
            metadata: metadata,
            container_path: CONTAINER_PATH,
            container_xml: container_xml
          )
        end
      rescue Zip::Error, REXML::ParseException => e
        raise EbookReader::EPUBParseError.new(e.message, epub_path)
      end

      private

      def read_container(zip)
        Infrastructure::PerfTracer.measure('epub.read_container') do
          zip.read(CONTAINER_PATH)
        end
      rescue Zip::Error
        raise EbookReader::EPUBParseError.new('Missing META-INF/container.xml', @epub_path)
      end

      def locate_opf_path(zip, container_xml)
        Infrastructure::PerfTracer.measure('epub.locate_opf') do
          doc = REXML::Document.new(container_xml)
          elems = doc.elements
          rootfile = elems['//rootfile'] || elems['//container:rootfile']
          candidate = rootfile&.attributes&.[]('full-path')
          return candidate if candidate && zip.find_entry(candidate)
        end

        if (match = container_xml.to_s.match(/full-path=["']([^"']+)["']/i))
          candidate = match[1]
          return candidate if zip.find_entry(candidate)
        end

        raise EbookReader::EPUBParseError.new('Unable to locate OPF file', @epub_path)
      rescue REXML::ParseException => e
        raise EbookReader::EPUBParseError.new("Invalid container.xml: #{e.message}", @epub_path)
      end

      def build_chapters(zip, opf_path, processor, manifest, chapter_titles)
        chapters = []
        hrefs    = []
        spine    = []

        processor.process_spine(manifest, chapter_titles) do |file_path, number, title, href|
          raw = read_text_entry(zip, file_path)
          resolved_href = resolve_href(opf_path, href)
          chapter = Domain::Models::Chapter.new(
            number: number.to_s,
            title: extract_chapter_title(raw, number, title),
            lines: nil,
            metadata: { source_path: file_path, href: resolved_href },
            blocks: nil,
            raw_content: raw
          )
          ensure_lines_present(chapter)

          chapters << chapter
          hrefs << resolved_href
          spine << file_path
        end

        { chapters:, hrefs:, spine: }
      end

      def build_toc_entries(chapters, toc_entries, chapter_hrefs, opf_path)
        href_to_index = {}
        chapter_hrefs.each_with_index do |href, idx|
          href_to_index[href] = idx if href
        end

        Array(toc_entries).map do |entry|
          title = entry[:title]
          href  = entry[:href]
          level = entry[:level].to_i

          target = resolve_toc_target(opf_path, entry)
          chapter_index = href_to_index[target]
          if chapter_index && (chapter = chapters[chapter_index]) && chapter.title.to_s.strip.empty?
            chapter.title = title
          end

          Domain::Models::TOCEntry.new(
            title: title,
            href: href,
            level: level,
            chapter_index: chapter_index,
            navigable: !chapter_index.nil?
          )
        end
      end

      def resolve_toc_target(opf_path, entry)
        return nil unless entry

        if entry.is_a?(Hash) && entry[:target]
          return entry[:target].to_s
        end

        href = entry.is_a?(Hash) ? entry[:href] : nil
        return nil unless href

        core = href.to_s.split('#', 2).first.to_s
        return nil if core.empty?

        source_path = entry.is_a?(Hash) ? entry[:source_path] : nil
        base_path = (source_path || opf_path).to_s
        base_dir = File.dirname(base_path)
        File.expand_path(File.join('/', base_dir, core), '/').sub(%r{^/}, '')
      end

      def extract_resources(zip, opf_path, manifest)
        resources = {}

        manifest.each_value do |href|
          rel = href.to_s
          next if rel.empty?

          path = resolve_href(opf_path, rel)
          next unless zip.find_entry(path)

          resources[path] = read_binary_entry(zip, path)
        end
        resources
      end

      def read_text_entry(zip, path)
        Infrastructure::PerfTracer.measure('epub.read_text_entry') do
          content = zip.read(path)
          normalize_text(content)
        end
      end

      def read_binary_entry(zip, path)
        Infrastructure::PerfTracer.measure('epub.read_binary_entry') do
          data = zip.read(path)
          data.force_encoding(Encoding::BINARY)
        end
      end

      def normalize_text(content)
        content.force_encoding(Encoding::UTF_8)
        content.delete_prefix('﻿')
      end

      def resolve_href(opf_path, href)
        return nil unless href

        base = File.dirname(opf_path)
        root = File.expand_path(File.join('/', base, href), '/')
        root.sub(%r{^/}, '')
      end

      def extract_chapter_title(raw_content, number, hinted_title)
        hinted = hinted_title.to_s.strip
        return hinted unless hinted.empty?

        Helpers::HTMLProcessor.extract_title(raw_content) || "Chapter #{number}"
      end

      def ensure_lines_present(chapter)
        return unless chapter
        return if chapter.lines && !chapter.lines.empty?

        plain = Helpers::HTMLProcessor.html_to_text(chapter.raw_content.to_s)
        chapter.lines = plain.split("\n").map(&:rstrip)
      end

      def fallback_title(path)
        File.basename(path, File.extname(path)).tr('_', ' ')
      end
    end
  end
end

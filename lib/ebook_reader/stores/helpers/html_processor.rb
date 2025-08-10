# frozen_string_literal: true

require 'cgi'

module EbookReader
  module Helpers
    # Processes HTML content
    class HTMLProcessor
      def self.extract_title(html)
        match = html.match(%r{<title[^>]*>([^<]+)</title>}i) ||
                html.match(%r{<h[1-3][^>]*>([^<]+)</h[1-3]>}i)
        clean_html(match[1]) if match
      end

      def self.html_to_text(html)
        text = html.dup
        # Handle CDATA sections BEFORE removing other tags
        text = handle_cdata_sections(text)
        text = remove_scripts_and_styles(text)
        text = replace_block_elements(text)
        text = strip_tags(text)
        text = CGI.unescapeHTML(text)
        clean_whitespace(text)
      end

      BLOCK_REPLACEMENTS = {
        %r{</p>}i => "\n\n",
        /<p[^>]*>/i => "\n\n",
        /<br[^>]*>/i => "\n",
        %r{</h[1-6]>}i => "\n\n",
        /<h[1-6][^>]*>/i => "\n\n",
        %r{</div>}i => "\n",
        /<div[^>]*>/i => "\n",
      }.freeze

      private_constant :BLOCK_REPLACEMENTS

      private_class_method def self.handle_cdata_sections(text)
        # Extract CDATA content before other processing
        text.gsub(/<!\[CDATA\[(.*?)\]\]>/m, '\1')
      end

      private_class_method def self.remove_scripts_and_styles(text)
        text.gsub!(%r{<script[^>]*>.*?</script>}mi, '')
        text.gsub!(%r{<style[^>]*>.*?</style>}mi, '')
        text
      end

      private_class_method def self.replace_block_elements(text)
        BLOCK_REPLACEMENTS.each { |pattern, rep| text.gsub!(pattern, rep) }
        text
      end

      private_class_method def self.strip_tags(text)
        text.gsub!(/<[^>]+>/, '')
        text
      end

      private_class_method def self.clean_whitespace(text)
        text.delete!("\r")
        text.gsub!(/\n{3,}/, "\n\n")
        text.gsub!(/[ \t]+/, ' ')
        text.strip
      end

      def self.clean_html(text)
        CGI.unescapeHTML(text.strip)
      end
    end
  end
end

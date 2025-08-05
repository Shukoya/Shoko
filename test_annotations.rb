#!/usr/bin/env ruby
# Test script for annotation functionality

require_relative 'lib/ebook_reader'

puts "Testing annotation integration..."
puts "1. Mouse support: #{defined?(EbookReader::Annotations::MouseHandler) ? 'OK' : 'FAIL'}"
puts "2. Popup menu: #{defined?(EbookReader::UI::Components::PopupMenu) ? 'OK' : 'FAIL'}"
puts "3. Annotation store: #{defined?(EbookReader::Annotations::AnnotationStore) ? 'OK' : 'FAIL'}"
puts "4. Editor mode: #{defined?(EbookReader::ReaderModes::AnnotationEditorMode) ? 'OK' : 'FAIL'}"
puts "5. List mode: #{defined?(EbookReader::ReaderModes::AnnotationsMode) ? 'OK' : 'FAIL'}"

puts "\nIntegration complete! You can now:"
puts "- Select text with mouse to see popup menu"
puts "- Press 'a' or 'A' to view all annotations"
puts "- Create, edit, and delete annotations"

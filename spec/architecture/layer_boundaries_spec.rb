# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Layer boundaries' do
  def offenses_for(patterns, regex)
    Array(patterns).each_with_object({}) do |pattern, acc|
      Dir.glob(pattern).each do |path|
        next unless File.file?(path)

        matches = []
        File.readlines(path).each_with_index do |line, index|
          matches << (index + 1) if regex.match?(line)
        end
        acc[path] = matches unless matches.empty?
      end
    end
  end

  def format_offenses(offenses, rationale)
    details = offenses.map { |path, lines| "#{path}:#{lines.join(',')}" }
    ([rationale] + details).join("\n")
  end

  it 'prevents presentation controllers/components from touching infrastructure directly' do
    regex = /(EbookReader::Infrastructure|Infrastructure::|require_relative ['"].*infrastructure)/
    offenders = offenses_for(
      %w[lib/ebook_reader/controllers/**/*.rb lib/ebook_reader/components/**/*.rb],
      regex
    )
    expect(offenders).to be_empty,
                         format_offenses(offenders, 'Presentation layers must not depend on infrastructure')
  end
end

# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Observable state stores' do
  describe EbookReader::Core::ReaderState do
    it 'notifies field-specific observers on change' do
      state = described_class.new
      calls = []
      observer = Class.new do
        define_method(:initialize) { |arr| @arr = arr }
        define_method(:state_changed) { |field, old, new| @arr << [field, old, new] }
      end.new(calls)

      state.add_observer(observer, :current_chapter)
      state.current_chapter = 1

      expect(calls).to include([:current_chapter, 0, 1])
    end

    it 'does not notify when value is unchanged' do
      state = described_class.new
      calls = []
      observer = Class.new do
        define_method(:initialize) { |arr| @arr = arr }
        define_method(:state_changed) { |field, old, new| @arr << [field, old, new] }
      end.new(calls)
      state.add_observer(observer, :left_page)

      state.left_page = 0
      expect(calls).to be_empty
    end

    it 'supports all-fields observers' do
      state = described_class.new
      calls = []
      observer = Class.new do
        define_method(:initialize) { |arr| @arr = arr }
        define_method(:state_changed) { |field, old, new| @arr << field }
      end.new(calls)

      state.add_observer(observer)
      state.single_page = 2
      expect(calls).to include(:single_page)
    end
  end
end


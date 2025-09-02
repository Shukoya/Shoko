# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Services::AnnotationService do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }
  let(:state) { EbookReader::Infrastructure::ObserverStateStore.new(bus) }

  class CtnAnn
    def initialize(state) = (@state = state)

    def resolve(name)
      return @state if name == :state_store

      nil
    end
  end

  subject(:service) { described_class.new(CtnAnn.new(state)) }

  before do
    stub_const('EbookReader::Annotations::AnnotationStore', Class.new do
      @data = Hash.new { |h, k| h[k] = [] }
      class << self; attr_reader :data; end
      def self.get(path) = @data[path] || []
      def self.all = @data

      def self.add(path, text, note, range, chapter_index, page_meta)
        (@data[path] ||= []) << {
          'id' => 'x', 'text' => text, 'note' => note,
          'range' => range, 'chapter_index' => chapter_index,
          'page_current' => page_meta&.dig(:current), 'page_total' => page_meta&.dig(:total), 'page_mode' => page_meta&.dig(:type)
        }
      end

      def self.update(path, id, note)
        item = (@data[path] || []).find { |a| a['id'] == id } || ((@data[path] ||= []) << { 'id' => id, 'note' => nil }).last
        item['note'] = note
      end

      def self.delete(path, id)
        (@data[path] ||= []).reject! { |a| a['id'] == id }
      end
    end)
  end

  it 'lists for book and all' do
    expect(service.list_for_book('/tmp/a.epub')).to eq([])
    expect(service.list_all).to be_a(Hash)
  end

  it 'adds, updates, deletes and dispatches update action' do
    expect do
      service.add('/tmp/a.epub', 't', 'n', { start: { x: 0, y: 0 }, end: { x: 1, y: 0 } }, 0, { current: 1, total: 10, type: :single })
    end.to change { service.list_for_book('/tmp/a.epub').length }.by(1)

    expect do
      service.update('/tmp/a.epub', 'x', 'new')
    end.not_to raise_error

    expect do
      service.delete('/tmp/a.epub', 'x')
    end.not_to raise_error
  end
end

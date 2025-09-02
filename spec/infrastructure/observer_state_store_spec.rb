# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Infrastructure::ObserverStateStore do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }
  let(:store) { described_class.new(bus) }

  it 'notifies observers on set and update' do
    called = []
    observer = Class.new do
      attr_reader :called

      def initialize(called) = @called = called
      def state_changed(path, _old, _new) = @called << path
    end.new(called)
    store.add_observer(observer, %i[reader current_chapter])

    store.set(%i[reader current_chapter], 2)
    store.update({ %i[reader current_chapter] => 3 })
    expect(called).to include(%i[reader current_chapter])
  end
end

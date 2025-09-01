# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ObserverStateStore notifications (expanded)' do
  let(:bus) { EbookReader::Infrastructure::EventBus.new }
  let(:store) { EbookReader::Infrastructure::ObserverStateStore.new(bus) }

  it 'notifies parent path observers' do
    calls = []
    parent = Object.new
    def parent.state_changed(path, *_); @calls << path; end
    parent.instance_variable_set(:@calls, calls)

    store.add_observer(parent, [:reader])
    store.set(%i[reader mode], :help)
    expect(calls).to include(%i[reader mode])
  end
end


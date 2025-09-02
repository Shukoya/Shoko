# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Input::Dispatcher do
  let(:context) { double('Context') }
  let(:dispatcher) { described_class.new(context) }

  it 'dispatches to active mode bindings and respects stack order' do
    dispatcher.register_mode(:a, { 'x' => ->(_ctx, _k) { :pass } })
    dispatcher.register_mode(:b, { 'x' => ->(_ctx, _k) { :handled } })
    dispatcher.activate_stack(%i[a b])

    expect(dispatcher.handle_key('x')).to eq(:handled)
  end

  it 'returns :pass when no binding and no default' do
    dispatcher.register_mode(:a, {})
    dispatcher.activate(:a)
    expect(dispatcher.handle_key('y')).to eq(:pass)
  end
end

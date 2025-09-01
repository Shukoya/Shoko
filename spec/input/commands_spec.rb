# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Input::Commands do
  before do
    allow(EbookReader::Input::DomainCommandBridge).to receive(:has_domain_command?).and_return(false)
  end

  it 'executes symbol methods with or without args' do
    ctx = Class.new do
      def ping(key=nil); key ? :with_key : :no_key; end
    end.new

    expect(described_class.execute(:ping, ctx, 'x')).to eq(:with_key)
    expect(described_class.execute(:ping, ctx)).to eq(:no_key)
  end

  it 'executes procs with varying arity' do
    ctx = Object.new
    two = ->(c, k) { [:two, k] }
    one = ->(k) { [:one, k] }
    zero = -> { :zero }
    expect(described_class.execute(two, ctx, 'k')).to eq([:two, 'k'])
    expect(described_class.execute(one, ctx, 'k')).to eq([:one, 'k'])
    expect(described_class.execute(zero, ctx, 'k')).to eq(:zero)
  end

  it 'executes array command [symbol, *args]' do
    ctx = Class.new do
      def sum(a,b); a+b; end
    end.new
    expect(described_class.execute([:sum, 2, 3], ctx)).to eq(5)
  end

  it 'routes BaseCommand to execute with params' do
    cmd = Class.new(EbookReader::Domain::Commands::BaseCommand) do
      def perform(context, params={}); :handled if params[:triggered_by] == :input; end
    end.new(name: 'x')
    ctx = double('Ctx')
    expect(described_class.execute(cmd, ctx, 'k')).to eq(:handled)
  end
end

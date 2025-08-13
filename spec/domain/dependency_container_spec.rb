# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::DependencyContainer do
  let(:container) { described_class.new }

  describe '#register' do
    it 'registers a singleton service' do
      service = double('Service')
      
      container.register(:test_service, service)
      
      expect(container.resolve(:test_service)).to eq(service)
    end
  end

  describe '#register_factory' do
    it 'registers a factory for lazy instantiation' do
      service = double('Service')
      factory = proc { service }
      
      container.register_factory(:test_service, &factory)
      
      expect(container.resolve(:test_service)).to eq(service)
    end
    
    it 'creates new instance each time for factories' do
      container.register_factory(:test_service) { double('Service') }
      
      service1 = container.resolve(:test_service)
      service2 = container.resolve(:test_service)
      
      expect(service1).not_to be(service2)
    end
  end

  describe '#register_singleton' do
    it 'registers a singleton factory' do
      service = double('Service')
      factory = proc { service }
      
      container.register_singleton(:test_service, &factory)
      
      expect(container.resolve(:test_service)).to eq(service)
    end
    
    it 'returns same instance for singletons' do
      container.register_singleton(:test_service) { double('Service') }
      
      service1 = container.resolve(:test_service)
      service2 = container.resolve(:test_service)
      
      expect(service1).to be(service2)
    end
  end

  describe '#resolve' do
    context 'when service is registered' do
      it 'returns the service' do
        service = double('Service')
        container.register(:test_service, service)
        
        expect(container.resolve(:test_service)).to eq(service)
      end
    end

    context 'when service is not registered' do
      it 'raises DependencyError' do
        expect {
          container.resolve(:unknown_service)
        }.to raise_error(EbookReader::Domain::DependencyContainer::DependencyError, "Service 'unknown_service' not registered")
      end
    end
    
    context 'when circular dependency exists' do
      it 'raises CircularDependencyError' do
        container.register_factory(:service_a) { |c| c.resolve(:service_b) }
        container.register_factory(:service_b) { |c| c.resolve(:service_a) }
        
        expect {
          container.resolve(:service_a)
        }.to raise_error(EbookReader::Domain::DependencyContainer::CircularDependencyError)
      end
    end
  end

  describe '#resolve_many' do
    it 'resolves multiple services' do
      service1 = double('Service1')
      service2 = double('Service2')
      container.register(:service1, service1)
      container.register(:service2, service2)
      
      result = container.resolve_many(:service1, :service2)
      
      expect(result).to eq({ service1: service1, service2: service2 })
    end
  end

  describe '#registered?' do
    it 'returns true for registered services' do
      container.register(:test_service, double('Service'))
      
      expect(container.registered?(:test_service)).to be true
    end
    
    it 'returns true for registered factories' do
      container.register_factory(:test_service) { double('Service') }
      
      expect(container.registered?(:test_service)).to be true
    end
    
    it 'returns false for unregistered services' do
      expect(container.registered?(:unknown_service)).to be false
    end
  end

  describe '#service_names' do
    it 'returns all registered service names' do
      container.register(:service1, double('Service'))
      container.register_factory(:service2) { double('Service') }
      container.register_singleton(:service3) { double('Service') }
      
      expect(container.service_names).to contain_exactly(:service1, :service2, :service3)
    end
  end

  describe '#create_child' do
    it 'creates child container with inherited services' do
      container.register(:parent_service, double('Service'))
      
      child = container.create_child
      child.register(:child_service, double('Child Service'))
      
      expect(child.registered?(:parent_service)).to be true
      expect(child.registered?(:child_service)).to be true
      expect(container.registered?(:child_service)).to be false
    end
  end

  describe '#clear!' do
    it 'removes all registrations' do
      container.register(:service1, double('Service'))
      container.register_factory(:service2) { double('Service') }
      
      container.clear!
      
      expect(container.service_names).to be_empty
    end
  end
end

RSpec.describe EbookReader::Domain::ContainerFactory do
  describe '.create_default_container' do
    let(:container) { described_class.create_default_container }

    it 'registers infrastructure services' do
      expect(container.registered?(:event_bus)).to be true
      expect(container.registered?(:state_store)).to be true
      expect(container.registered?(:logger)).to be true
    end

    it 'registers domain services' do
      expect(container.registered?(:navigation_service)).to be true
      expect(container.registered?(:bookmark_service)).to be true
      expect(container.registered?(:page_calculator)).to be true
    end
  end

  describe '.create_test_container' do
    let(:container) { described_class.create_test_container }

    it 'registers mock services' do
      expect(container.registered?(:event_bus)).to be true
      expect(container.registered?(:state_store)).to be true
      expect(container.registered?(:logger)).to be true
    end

    it 'provides mock implementations' do
      event_bus = container.resolve(:event_bus)
      state_store = container.resolve(:state_store)
      logger = container.resolve(:logger)

      expect(event_bus).to respond_to(:subscribe)
      expect(state_store).to respond_to(:get)
      expect(logger).to respond_to(:info)
    end
  end
end
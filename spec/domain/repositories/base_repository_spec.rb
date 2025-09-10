# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EbookReader::Domain::Repositories::BaseRepository do
  let(:mock_dependencies) do
    instance_double(EbookReader::Domain::DependencyContainer).tap do |deps|
      allow(deps).to receive(:resolve).with(:logger).and_return(mock_logger)
    end
  end

  let(:mock_logger) do
    class_double(EbookReader::Infrastructure::Logger).tap do |logger|
      allow(logger).to receive(:error)
      allow(logger).to receive(:debug)
      allow(logger).to receive(:info)
      allow(logger).to receive(:warn)
      allow(logger).to receive(:fatal)
    end
  end

  let(:test_repository_class) do
    Class.new(described_class) do
      def test_method_with_error
        raise StandardError, 'Test error'
      rescue StandardError => e
        handle_storage_error(e, 'test context')
      end

      def test_validation
        validate_required_params({ key1: 'value' }, %i[key1 key2])
      end

      def test_entity_exists(entity)
        ensure_entity_exists(entity, 'TestEntity')
      end
    end
  end

  subject { test_repository_class.new(mock_dependencies) }

  describe '#initialize' do
    it 'sets up dependencies and logger' do
      expect(subject.send(:dependencies)).to eq(mock_dependencies)
    end

    it 'calls setup_repository_dependencies template method' do
      expect_any_instance_of(test_repository_class).to receive(:setup_repository_dependencies)
      test_repository_class.new(mock_dependencies)
    end
  end

  describe '#handle_storage_error' do
    context 'with context' do
      it 'logs error with context and raises PersistenceError' do
        expect(mock_logger).to receive(:error).with('Repository error - test context: Test error')
        expect { subject.test_method_with_error }.to raise_error(
          described_class::PersistenceError, 'test context: Test error'
        )
      end
    end

    context 'with validation errors' do
      let(:test_repository_with_no_method_error) do
        Class.new(described_class) do
          def test_no_method_error
            raise NoMethodError, 'Test method error'
          rescue StandardError => e
            handle_storage_error(e, 'test context')
          end
        end
      end

      it 'raises ValidationError for NoMethodError' do
        repo = test_repository_with_no_method_error.new(mock_dependencies)

        expect { repo.test_no_method_error }.to raise_error(described_class::ValidationError)
      end
    end
  end

  describe '#validate_required_params' do
    it 'raises ValidationError when required parameters are missing' do
      expect { subject.test_validation }.to raise_error(
        described_class::ValidationError, 'Missing required parameters: key2'
      )
    end

    it 'passes when all required parameters are present' do
      expect { subject.send(:validate_required_params, { key1: 'value', key2: 'value' }, %i[key1 key2]) }.not_to raise_error
    end
  end

  describe '#ensure_entity_exists' do
    it 'raises EntityNotFoundError when entity is nil' do
      expect { subject.test_entity_exists(nil) }.to raise_error(
        described_class::EntityNotFoundError, 'TestEntity not found'
      )
    end

    it 'passes when entity exists' do
      expect { subject.test_entity_exists('some entity') }.not_to raise_error
    end
  end

  describe 'error classes' do
    it 'defines RepositoryError as base' do
      expect(described_class::RepositoryError).to be < StandardError
    end

    it 'defines EntityNotFoundError inheriting from RepositoryError' do
      expect(described_class::EntityNotFoundError).to be < described_class::RepositoryError
    end

    it 'defines ValidationError inheriting from RepositoryError' do
      expect(described_class::ValidationError).to be < described_class::RepositoryError
    end

    it 'defines PersistenceError inheriting from RepositoryError' do
      expect(described_class::PersistenceError).to be < described_class::RepositoryError
    end
  end
end

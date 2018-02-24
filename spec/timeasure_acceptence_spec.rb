require 'timeasure'

RSpec.describe Timeasure do
  before(:each) { Timeasure::Profiling::Manager.prepare }

  context 'direct interface' do
    describe '.measure' do
      let(:klass_name) { double }
      let(:method_name) { double }
      let(:segment) { double }
      let(:metadata) { double }

      context 'proper calls' do
        let(:measure) do
          described_class.measure(klass_name: klass_name, method_name: method_name,
                                  segment: segment, metadata: metadata) { :some_return_value }
        end

        it 'returns the return value of the code block' do
          expect(measure).to eq :some_return_value
        end

        it 'calls post_measuring_proc' do
          expect(Timeasure.configuration.post_measuring_proc).to receive(:call)
          measure
        end
      end

      context 'error handling' do
        context 'in the code block itself' do
          it 'raises an error normally' do
            expect { described_class.measure { raise 'some error in the code block!' } }.to raise_error(RuntimeError)
          end
        end

        context 'in the post_measuring_proc' do
          before do
            Timeasure.configure do |configuration|
              configuration.post_measuring_proc = lambda do |measurement|
                raise RuntimeError
              end
            end
          end

          it 'calls the rescue proc' do
            expect(Timeasure.configuration.rescue_proc).to receive(:call)
            described_class.measure { :some_return_value }
          end

          it 'does not interfere with block return value' do
            expect(described_class.measure { :some_return_value }).to eq :some_return_value
          end

          after do
            Timeasure.configure do |configuration|
              configuration.post_measuring_proc = lambda do |measurement|
                Timeasure::Profiling::Manager.report(measurement)
              end
            end
          end
        end
      end
    end
  end


  context 'DSL interface' do
    before(:all) do
      # The next section emulates the creation of a new class that includes Timeasure.
      # Since using the `Class.new` syntax is obligatory in test environment,
      # it has to be assigned to a constant first in order to have a name.

      FirstClass ||= Class.new
      FirstClass.class_eval do
        include Timeasure
        tracked_class_methods :a_class_method
        tracked_instance_methods :a_method, :a_method_with_args, :a_method_with_a_block


        def self.a_class_method
          false
        end

        def self.an_untracked_class_method
          'untracked class method'
        end

        def a_method
          true
        end

        def a_method_with_args(arg)
          arg
        end

        def a_method_with_a_block(&block)
          yield
        end

        def an_untracked_method
          'untracked method'
        end

      end
    end

    let(:instance) { FirstClass.new }

    context 'methods return value' do
      context 'public methods' do
        it 'returns methods return values transparently' do
          expect(instance.a_method).to eq true
          expect(instance.a_method_with_args('arg')).to eq 'arg'
          expect(instance.a_method_with_a_block { true ? 8 : 0 }).to eq 8
          expect(FirstClass.a_class_method).to eq false
        end
      end

      context 'private methods' do
        before(:all) do
          FirstClass.class_eval do
            tracked_class_methods :a_class_method_that_calls_a_private_method,
                                  :a_private_class_method, :a_private_class_method_in_an_unsupported_way,
                                  :a_class_method_that_calls_a_private_class_method_in_an_unsupported_way
            tracked_instance_methods :a_method_that_calls_a_private_method, :a_private_method,
                                     :a_method_that_calls_a_private_method_in_an_unsupported_way,
                                     :a_private_method_in_an_unsupported_way

            class << self
              def a_class_method_that_calls_a_private_method
                a_private_class_method
              end

              private

              def a_private_class_method
                :class_private_stuff
              end
            end

            def self.a_class_method_that_calls_a_private_class_method_in_an_unsupported_way
              a_private_class_method_in_an_unsupported_way
            end

            private_class_method def self.a_private_class_method_in_an_unsupported_way
              :unsupported_class_private_stuff
            end

            def a_method_that_calls_a_private_method
              a_private_method
            end

            def a_method_that_calls_a_private_method_in_an_unsupported_way
              a_private_method_in_an_unsupported_way
            end

            private def a_private_method_in_an_unsupported_way
              :unsupported_private_stuff
            end

            private

            def a_private_method
              :instance_private_stuff
            end
          end
        end

        context 'scope private visibility declarations' do
          it 'returns calling method return value transparently' do
            expect(FirstClass.a_class_method_that_calls_a_private_method).to eq :class_private_stuff
            expect(instance.a_method_that_calls_a_private_method).to eq :instance_private_stuff
          end
        end

        context 'inline private visibility declaration' do
          it 'raises an error' do
            expect { FirstClass.a_class_method_that_calls_a_private_class_method_in_an_unsupported_way }
                .to raise_error NoMethodError
            expect { instance.a_method_that_calls_a_private_method_in_an_unsupported_way }
                .to raise_error NoMethodError
          end
        end
      end
    end

    context 'triggering Timeasure' do
      it 'calls Timeasure.measure for tracked methods' do
        expect(Timeasure).to receive(:measure).exactly(2).times
        instance.a_method
        FirstClass.a_class_method
      end

      it 'does not call Timeasure.measure for untracked methods' do
        expect(Timeasure).not_to receive(:measure)
        instance.an_untracked_method
        FirstClass.an_untracked_class_method
      end
    end
  end

  context 'profiler' do
    context 'reporting' do
      it 'reports each call trough Timeasure::Profiling::Manager.report' do
        expect(Timeasure::Profiling::Manager).to receive(:report).exactly(7).times

        2.times do
          Timeasure.measure(klass_name: 'Foo', method_name: 'bar') { :some_return_value }
        end

        5.times do
          Timeasure.measure(klass_name: 'Baz', method_name: 'qux') { :some_other_return_value }
        end
      end
    end

    context 'exporting' do
      before do
        3.times do
          Timeasure.measure(klass_name: 'Foo', method_name: 'bar') { :some_return_value }
        end

        4.times do
          Timeasure.measure(klass_name: 'Baz', method_name: 'qux') { :some_other_return_value }
        end
      end

      let(:export) { Timeasure::Profiling::Manager.export }

      it 'exports all calls in an aggregated manner' do
        expect(export.count).to eq 2
      end
    end
  end
end

require 'test_helper'

module Sinatra

  class ParamCheckerTest < Minitest::Test
    def test_that_it_has_a_version_number
      refute_nil ParamChecker::VERSION
    end
    def setup
      @param_scope = ParamChecker::ParamScope.new
    end


    def test_type_syntax
      e = assert_raises SyntaxError do
        @param_scope.required 'fake'
      end

      assert e.message =~ /missing option :type/

      [
        Integer, Float,
        TrueClass, FalseClass, ParamChecker::Boolean,
        String, ParamChecker::UUID,
        Array, Hash, File,
        Date, Time, DateTime
      ].each_with_index do |type, index|
        @param_scope.required "fake#{index}", type: type
        assert true
      end
    end

    def test_default_syntax
      [
        Integer, Float,
        TrueClass, FalseClass, ParamChecker::Boolean,
        String, ParamChecker::UUID,
        Array, Hash, File,
        Date, Time, DateTime
      ].each_with_index do |type, index|
        e = assert_raises SyntaxError do
          @param_scope.required "fake#{index}", type: type, default: ''
        end
        assert e.message =~ /:default can be used only with :optional params/
      end

      [Array, Hash, File].each_with_index do |type, index|
        e = assert_raises SyntaxError do
          @param_scope.optional "fake#{index}", type: type, default: ''
        end

        assert e.message =~ /:default cannot be used with :type File, Array or Hash/
      end
    end
  end
end

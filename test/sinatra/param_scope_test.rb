require 'date'

require 'test_helper'

module Sinatra
  class ParamScopeTest < Minitest::Test
    def params(&blk)
      param_scope = ParamChecker::ParamScope.new
      param_scope.instance_eval(&blk)
      param_scope
    end

    def setup
    end


    def test_type_syntax
      e = assert_raises SyntaxError do
        params { required 'fake' }
      end

      assert e.message =~ /missing option :type/

      [
        Integer, Float,
        TrueClass, FalseClass, ParamChecker::Boolean,
        String, ParamChecker::UUID,
        Array, Hash, File,
        Date, Time, DateTime
      ].each do |type|
        params { required '', type: type }
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
      ].each do |type|
        e = assert_raises SyntaxError do
          params { required 'fake', type: type, default: '' }
        end
        assert e.message =~ /:default can be used only with :optional params/
      end

      [Array, Hash, File].each do |type|
        e = assert_raises SyntaxError do
          params { optional 'fake', type: type, default: '' }
        end
        assert e.message =~ /:default cannot be used with :type File, Array or Hash/
      end

      [
        Integer, Float,
        TrueClass, FalseClass, ParamChecker::Boolean,
        String, ParamChecker::UUID,
        Date, Time, DateTime
      ].zip([
              0, 0.0,
              false, true, false,
              '', '',
              Date.today, Time.now, DateTime.now
            ]).each do |type, default|
        p = params { optional 'fake', type: type, default: default }.params
        assert_equal [[:optional, 'fake', type: type, default: default]], p
      end
    end

    def test_values_syntax
      [Array, Hash, File].each do |type|
        e = assert_raises SyntaxError do
          params { optional 'fake', type: type, values: [] }
        end
        assert e.message =~ /:values cannot be used with :type File, Array or Hash/
      end
      [
        Integer, Float,
        TrueClass, FalseClass, ParamChecker::Boolean,
        String, ParamChecker::UUID,
        Date, Time, DateTime
      ].zip([
              [0], [0.0],
              [false], [true], [false],
              [''], [''],
              [Date.today], [Time.now], [DateTime.now]
            ]).each do |type, values|
        p = params { optional 'fake', type: type, values: values }.params
        assert_equal [[:optional, 'fake', type: type, values: values]], p
      end
    end

    def test_min_max_syntax
      [Integer, Float].zip([0, 0.0], [100, 100.0]).each do |type, min, max|
        p = params {optional 'fake', type: type, min: min, max: max}.params
        assert_equal [[:optional, 'fake', type: type, min: min, max: max]], p
      end
    end

    def test_range_syntax
      [Integer].zip([0..100]).each do |type, range|
        p = params {optional 'fake', type: type, range: range}.params
        assert_equal [[:optional, 'fake', type: type, range: range]], p
      end
      [Float].zip([0..100]).each do |type, range|
        e = assert_raises SyntaxError do
          params {optional 'fake', type: type, range: range}.params
        end
        assert e.message =~ /:range can be used only with :type Integer/
      end
    end

    def test_delimiter_syntax
      [Array, Hash].zip([',', ',']).each do |type, delimiter|
        p = params {optional 'fake', type: type, delimiter: delimiter}.params
        assert_equal [[:optional, 'fake', type: type, delimiter: delimiter]], p
      end

      [
        Integer, Float,
        TrueClass, FalseClass, ParamChecker::Boolean,
        String, ParamChecker::UUID,
        Date, Time, DateTime
      ].each do |type|
        e = assert_raises SyntaxError do
          params {optional 'fake', type: type, delimiter: ','}.params
        end
        assert e.message =~ /:delimiter can be used only with :type Array and Hash/
      end
    end

    def test_separator_syntax
      [Hash].zip([':']).each do |type, separator|
        p = params {optional 'fake', type: type, separator: separator}.params
        assert_equal [[:optional, 'fake', type: type, separator: separator]], p
      end
      [Array].zip([':']).each do |type, separator|
        e = assert_raises SyntaxError do
          params {optional 'fake', type: type, separator: separator}.params
        end
        assert e.message =~ /:separator can be used only with :type Hash/
      end
    end


    def test_validate_default
      p = params {
        optional 'fake', type: String, default: 'fake'
      }
      assert_equal({'fake' => 'fake'}, p.validate!({}))

      p = params {
        optional 'fake', type: String
      }

      assert_equal({}, p.validate!({}))
    end

    def test_validate_min_max
      p = params {
        required 'number', type: Float, min: 10.0, max: 100.0
      }

      assert_equal({'number' => 12}, p.validate!({'number' => 12}))
      assert_raises Sinatra::ParamChecker::InvalidParameterError do
        p.validate!({'number' => 9})
      end
      assert_raises Sinatra::ParamChecker::InvalidParameterError do
        p.validate!({'number' => 101})
      end
    end

    def test_validate_range
      p = params {
        required 'number', type: Integer, range: 10..100
      }

      assert_equal({'number' => 12}, p.validate!({'number' => 12}))
      assert_raises Sinatra::ParamChecker::InvalidParameterError do
        p.validate!({'number' => 9})
      end
      assert_raises Sinatra::ParamChecker::InvalidParameterError do
        p.validate!({'number' => 101})
      end
    end

    def test_validate_values
      p = params {
        required 'number', type: Integer, values: [2, 4, 8, 16]
      }

      assert_equal({'number' => 2}, p.validate!({'number' => 2}))
      assert_raises Sinatra::ParamChecker::InvalidParameterError do
        p.validate!({'number' => 3})
      end
      assert_raises Sinatra::ParamChecker::InvalidParameterError do
        p.validate!({'number' => 11})
      end
    end

    def test_validate_regexp
      p = params {
        required 'id', type: String, regexp: /^\d{5,10}$/
      }

      assert_equal({'id' => '123456'}, p.validate!({'id' => '123456'}))

      assert_raises Sinatra::ParamChecker::InvalidParameterError do
        p.validate!({'id' => '12345678901'})
      end
      assert_raises Sinatra::ParamChecker::InvalidParameterError do
        p.validate!({'id' => '1234'})
      end
    end

    def test_validate_file
      p = params {
        required 'file', type: File
      }

      h = {
        'file' => {tempfile: Tempfile.new('fake')}
      }
      assert_equal h, p.validate!(h)
    end
  end
end

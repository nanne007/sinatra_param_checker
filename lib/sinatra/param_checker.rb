require 'sinatra/base'

module Sinatra
  module ParamChecker
    Boolean = :boolean.freeze
    UUID = :uuid.freeze
    class InvalidParameterError < StandardError
      attr_accessor :param, :options
    end
    class ParamScope
      def initialize
        @params = []
      end

      def requires(name, options = {})
        param = [:requires, name, options]
        validate_opts! param
        @params << param
      end

      def optional(name, options = {})
        param = [:optional, name, options]
        validate_opts! param
        @params << param
      end

      def coerce(param, type, options = {})
        return nil if param.nil?
        return param if (param.is_a?(type) rescue false)
        return Integer(param) if type == Integer
        return Float(param) if type == Float
        return String(param) if type == String
        return String(param) if type == UUID
        return param if (type == File && param[:tempfile] rescue false)
        return Date.parse(param) if type == Date
        return Time.parse(param) if type == Time
        return DateTime.parse(param) if type == DateTime
        if type == Array
          return param if param.is_a? Array
          return Array(param.split(options[:delimiter] || ','))
        end
        if type == Hash
          return param if param.is_a? Hash
          return Hash[param.split(options[:delimiter] || ',').map { |c| c.split(options[:separator] || ':') }]
        end
        return (/(false|f|no|n|0)$/i === param.to_s ? false : (/(true|t|yes|y|1)$/i === param.to_s ? true : nil)) if [TrueClass, FalseClass, Boolean].include?(type)
        return nil
      rescue
        raise InvalidParameterError, "#{type} expected"
      end

      def validate!(thiz)
        @params.each do |e|
          type, name, opts = e

          begin
            thiz.params[name] = coerce(thiz.params[name], opts[:type], opts)
            # check exist
            case type
            when :optional
              thiz.params[name] ||=
                (opts[:default].call if opts[:default].respond_to?(:call)) || opts[:default]
            when :requires
              raise InvalidParameterError, "param #{name} not found" unless thiz.params[name]
            end
            next if thiz.params[name].nil?
            validate(thiz.params[name], opts)
          rescue InvalidParameterError => e
            e.param, e.options = name, opts
            raise e
          end
        end
      end

      private

      def validate(v, opts)
        # check value
        case opts[:type].to_s.to_sym
        when :String
          raise InvalidParameterError, 'blank string' if v.strip.size == 0
          raise InvalidParameterError, 'wrong format' if opts[:regexp] && !(v =~ opts[:regexp])
        when UUID
          raise InvalidParameterError, 'uuid expected', 'INVALID_UUID' unless v =~ /\A[a-f0-9]{32}\z/
        when :Integer, :Float
          raise InvalidParameterError, "not in range(#{opts[:range]})" if opts[:type] == Integer && opts[:range] && !opts[:range].include?(v)
          raise InvalidParameterError, "greater than #{opts[:max]}" if opts[:max] && v > opts[:max]
          raise InvalidParameterError, "smaller than #{opts[:min]}" if opts[:min] && v < opts[:min]
        when :File
          tf = v[:tempfile] rescue nil
          raise InvalidParameterError, 'File expected' unless Tempfile === tf
        end
        raise InvalidParameterError, 'invalid enumeration member' if opts[:values] && !opts[:values].include?(v)
      end

      def syntax_err(msg)
        fail SyntaxError, "ParamChecker: #{msg}"
      end

      def check_type(type, value)
        return String == value if type == UUID
        return [true, false].include?(value) if [TrueClass, FalseClass, Boolean].include?(type)
        return true if (value.is_a?(type) rescue false)
        false
      end

      OPTIONS = [:type, :default, :values, :min, :max, :range, :regexp, :raise]
      def validate_opts!(param)
        type, name, opts = param
        syntax_err "#{name}: missing option :type" unless opts[:type]
        prefix = "#{name}(#{opts[:type]})"
        opts.each do |k, v|
          syntax_err "#{prefix}: unsupported option :#{k}" unless OPTIONS.include?(k)
          case k
          when :default
            syntax_err "#{prefix}: :default can be used only with :optional params" if type == :requires
            syntax_err "#{prefix}: :default cannot be used with :type File, Array or Hash" if [File, Array, Hash].include?(opts[:type])
            syntax_err "#{prefix}: :default must be #{opts[:type]}" unless check_type(opts[:type], v)
          when :values
            syntax_err "#{prefix}: :values cannot be used with :type File, Array or Hash" if [File, Array, Hash].include?(opts[:type])
            syntax_err "#{prefix}: :values must be Array(size > 0)" unless Array === v && v.size > 0
            v.each do |val|
              syntax_err "#{prefix}: values in :values must be #{opts[:type]}" unless check_type(opts[:type], val)
            end
          when :min, :max
            syntax_err "#{prefix}: :#{k} can be used only with :type Integer and Float" unless [Integer, Float].include?(opts[:type])
            syntax_err "#{prefix}: :#{k} must be #{opts[:type]}" unless check_type(opts[:type], v)
          when :range
            syntax_err "#{prefix}: :range can be used only with :type Integer" unless opts[:type] == Integer
            syntax_err "#{prefix}: :range must be Range of Integer" unless Range === v && Integer === v.begin
          when :regexp
            syntax_err "#{prefix}: :regexp can be used only with :type String" unless opts[:type] == String
            syntax_err "#{prefix}: :regexp must be Regexp" unless Regexp === v
          end
        end
      end
    end

    def params(path = nil, options = {}, &block)
      ps = ParamScope.new
      ps.instance_eval(&block)
      methods = options.delete(:methods)
      before path, options do
        if methods.include?(self.request.request_method.downcase.to_sym)
          ps.validate!(self)
        end
      end
    end
  end

  register ParamChecker
end

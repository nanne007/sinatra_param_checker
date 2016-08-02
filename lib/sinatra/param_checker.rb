require 'sinatra/base'

module Sinatra
  module ParamChecker
    Boolean = Class.new
    UUID = Class.new
    class InvalidParameterError < StandardError
      attr_accessor :param, :options
    end
    class ParamScope
      attr_reader :params
      def initialize
        @params = []
      end

      def required(name, options = {})
        param = [:required, name.to_s, options]
        validate_opts! param
        @params << param
      end

      def optional(name, options = {})
        param = [:optional, name.to_s, options]
        validate_opts! param
        @params << param
      end

      def validate!(thiz)
        @params.each do |e|
          type, name, opts = e
          begin
            # handle default
            v = if this.params[name].nil?
              case type
              when :optional
                (opts[:default].call if opts[:default].respond_to?(:call)) || opts[:default]
              when :required
                raise InvalidParameterError, "param #{name} not found"
              end
            else
              this.params[name]
            end

            next if v.nil?

            coerced_value = coerce(v, opts[:type], opts)
            validate(coerced_value, opts)
            thiz.params[name] = coerced_value
          rescue InvalidParameterError => e
            e.param, e.options = name, opts
            raise e
          end
        end
      end

      private

      def coerce(value, type, options = {})
        return value if value.is_a?(type)
        case type
        when Integer
          Integer(value)
        when Float
          Float(value)
        when String
          String(value)
        when UUID
          String(value)
        when File
          if value.is_a?(Rack::Multipart::UploadedFile)
            value
          else
            raise "cannot coerce value to #{type}"
          end
        when Date
          Date.parse(value)
        when Time
          Time.parse(value)
        when DateTime
          Time.parse(value)
        when Array
          delimiter = options[:delimiter] || ','
          Array(value.split(delimiter))
        when Hash
          delimiter = options[:delimiter] || ','
          separator = options[:separator] || ':'
          value.split(delimiter).map do |c|
            c.split(separator, 2)
          end.to_h
        when TrueClass, FalseClass, Boolean
          if /(false|f|no|n|0)$/i === value.to_s
            false
          elsif /(true|t|yes|y|1)$/i === value.to_s
            true
          else
            raise "cannot coerce value to Boolean"
          end
        else
          raise "cannot coerce value to #{type}"
        end
      rescue => _e
        raise InvalidParameterError, "#{type} expected"
      end


      def validate(v, opts)
        case opts[:type]
        when ::String
          if opts[:regexp] && !(v =~ opts[:regexp])
            raise InvalidParameterError, 'wrong format'
          end
        when UUID
          unless v =~ /\A[a-f0-9]{32}\z/
            raise InvalidParameterError, 'uuid expected'
          end
        when ::Integer, ::Float
          if opts[:type] == Integer && opts[:range] && !opts[:range].include?(v)
            raise InvalidParameterError, "not in range(#{opts[:range]})"
          end
          if opts[:max] && v > opts[:max]
            raise InvalidParameterError, "greater than #{opts[:max]}"
          end
          if opts[:min] && v < opts[:min]
            raise InvalidParameterError, "smaller than #{opts[:min]}"
          end
        when ::File
          tf = v[:tempfile] rescue nil
          raise InvalidParameterError, 'File expected' unless Tempfile === tf
        end

        unless [Hash, Array, File].include?(opts[:type])
          if opts[:values] && !opts[:values].include?(v)
            raise InvalidParameterError, 'invalid enumeration member'
          end
        end
      end

      def syntax_err(msg)
        fail SyntaxError, "ParamChecker: #{msg}"
      end

      def check_type(type, value)
        return value.is_a?(String) if type == UUID
        return [true, false].include?(value) if [TrueClass, FalseClass, Boolean].include?(type)
        return true if (value.is_a?(type) rescue false)
        false
      end

      OPTIONS = [:type, :default, :values, :min, :max, :range, :regexp, :delimiter, :separator]
      def validate_opts!(param)
        type, name, opts = param

        syntax_err "#{name}: missing option :type" unless opts[:type]
        unless opts[:type].is_a?(Class)
          syntax_err "#{name}: :type value should be class"
        end

        prefix = "#{name}(#{opts[:type]})"
        opts.each do |k, v|
          syntax_err "#{prefix}: unsupported option :#{k}" unless OPTIONS.include?(k)
          case k
          when :default
            if type == :required
              syntax_err "#{prefix}: :default can be used only with :optional params"
            end
            if [File, Array, Hash].include?(opts[:type])
              syntax_err "#{prefix}: :default cannot be used with :type File, Array or Hash"
            end

            unless check_type(opts[:type], v)
              syntax_err "#{prefix}: :default must be #{opts[:type]}"
            end
          when :values
            if [File, Array, Hash].include?(opts[:type])
              syntax_err "#{prefix}: :values cannot be used with :type File, Array or Hash"
            end
            unless Array === v && v.size > 0
              syntax_err "#{prefix}: :values must be Array(size > 0)"
            end
            v.each do |val|
               unless check_type(opts[:type], val)
                 syntax_err "#{prefix}: values in :values must be #{opts[:type]}"
               end
            end
          when :min, :max
             unless [Integer, Float].include?(opts[:type])
               syntax_err "#{prefix}: :#{k} can be used only with :type Integer and Float"
             end
             unless check_type(opts[:type], v)
               syntax_err "#{prefix}: :#{k} must be #{opts[:type]}"
             end
          when :range
            unless opts[:type] == Integer
              syntax_err "#{prefix}: :range can be used only with :type Integer"
            end
            unless Range === v && Integer === v.begin
              syntax_err "#{prefix}: :range must be Range of Integer"
            end
          when :regexp
            unless opts[:type] == String
              syntax_err "#{prefix}: :regexp can be used only with :type String"
            end
            unless Regexp === v
              syntax_err "#{prefix}: :regexp must be Regexp"
            end
          when :delimiter
            unless [Array, Hash].include?(opts[:type])
              syntax_err "#{prefix}: :delimiter can be used only with :type Array and Hash"
            end
          when :separator
            unless opts[:type] == Hash
              syntax_err "#{prefix}: :separator can be used only with :type Hash"
            end
          end
        end
      end
    end

    def params(path = nil, options = {}, &block)
      ps = ParamScope.new
      ps.instance_eval(&block)
      methods = options.delete(:methods)
      if methods.nil?
        methods = [:post]
      end
      before path, options do
        if methods.include?(self.request.request_method.downcase.to_sym)
          ps.validate!(self)
        end
      end
    end
  end

  register ParamChecker
end

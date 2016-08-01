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

      def coerce(value, type, options = {})
        return nil if value.nil?
        return value if value.is_a?(type)
        return Integer(value) if type == Integer
        return Float(value) if type == Float
        return String(value) if type == String
        return String(value) if type == UUID
        return value if (type == File && value.is_a?(Rack::Multipart::UploadedFile))
        return Date.parse(value) if type == Date
        return Time.parse(value) if type == Time
        return DateTime.parse(value) if type == DateTime
        if type == Array
          return Array(value.split(options[:delimiter] || ','))
        end
        if type == Hash
          return Hash[value.split(options[:delimiter] || ',').map { |c| c.split(options[:separator] || ':', 2) }]
        end

        if [TrueClass, FalseClass, Boolean].include?(type)
          if /(false|f|no|n|0)$/i === value.to_s
            false
          elsif /(true|t|yes|y|1)$/i === value.to_s
            true
          else
            raise "cannot coerce #{value.to_s} to Boolean"
          end
        end
        nil
      rescue
        raise InvalidParameterError, "#{type} expected"
      end

      def validate!(thiz)
        @params.each do |e|
          type, name, opts = e
          begin
            thiz.params[name] = coerce(thiz.params[name], opts[:type], opts)
            # check exist
            if this.params[name].nil?
              case type
              when :optional
                this.params[name] =
                  (opts[:default].call if opts[:default].respond_to?(:call)) || opts[:default]
              when :required
                raise InvalidParameterError, "param #{name} not found"
              end
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
          # allow empty string
          # raise InvalidParameterError, 'blank string' if v.strip.size == 0
          raise InvalidParameterError, 'wrong format' if opts[:regexp] && !(v =~ opts[:regexp])
        when UUID
          raise InvalidParameterError, 'uuid expected' unless v =~ /\A[a-f0-9]{32}\z/
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

      OPTIONS = [:type, :default, :values, :min, :max, :range, :regexp, :delimiter, :separator]
      def validate_opts!(param)
        type, name, opts = param
        syntax_err "#{name}: missing option :type" unless opts[:type]
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

require "active_model/serializer"
require "datasource"

module ActiveLoaders
  module Adapters
    module ActiveModelSerializers
      module ArraySerializer
        def initialize_with_loaders(objects, options = {})
          datasource_class = options.delete(:datasource)
          adapter = Datasource.orm_adapters.find { |a| a.is_scope?(objects) }
          if adapter && !adapter.scope_loaded?(objects)
            scope = begin
              objects
              .for_serializer(options[:serializer])
              .datasource_params(*[options[:loader_params]].compact)
            rescue NameError
              if options[:serializer].nil?
                return initialize_without_loaders(objects, options)
              else
                raise
              end
            end

            if datasource_class
              scope = scope.with_datasource(datasource_class)
            end

            records = adapter.scope_to_records(scope)

            initialize_without_loaders(records, options)
          else
            initialize_without_loaders(objects, options)
          end
        end
      end

    module_function
      def get_serializer_for(klass, serializer_assoc = nil)
        serializer = if serializer_assoc
          if serializer_assoc.kind_of?(Hash)
            serializer_assoc[:options].try(:[], :serializer)
          else
            serializer_assoc.options[:serializer]
          end
        end
        serializer || "#{klass.name}Serializer".constantize
      end

      def to_datasource_select(result, klass, serializer = nil, serializer_assoc = nil, adapter = nil, datasource = nil)
        adapter ||= Datasource::Base.default_adapter
        serializer ||= get_serializer_for(klass, serializer_assoc)
        if serializer._attributes.respond_to?(:keys)  # AMS 0.8
          result.concat(serializer._attributes.keys)
        else                                          # AMS 0.9
          result.concat(serializer._attributes)
        end
        result.concat(serializer.loaders_context.select)
        if serializer.loaders_context.skip_select.empty?
          result.unshift("*")
        else
          datasource_class = if datasource
            datasource.class
          else
            serializer.use_datasource || klass.default_datasource
          end
          result.concat(datasource_class._column_attribute_names -
            serializer.loaders_context.skip_select.map(&:to_s))
        end
        result_assocs = serializer.loaders_context.includes.dup
        result.push(result_assocs)

        serializer._associations.each_pair do |name, serializer_assoc|
          # TODO: what if assoc is renamed in serializer?
          reflection = adapter.association_reflection(klass, name.to_sym)
          assoc_class = reflection[:klass]

          name = name.to_s
          result_assocs[name] = []
          to_datasource_select(result_assocs[name], assoc_class, nil, serializer_assoc, adapter)
        end
      rescue Exception => ex
        if ex.is_a?(SystemStackError) || ex.is_a?(Datasource::RecursionError)
          fail Datasource::RecursionError, "recursive association (involving #{klass.name})"
        else
          raise
        end
      end
    end
  end
end

module SerializerClassMethods
  class SerializerDatasourceContext
    def initialize(serializer)
      @serializer = serializer
    end

    def select(*args)
      @datasource_select ||= []
      @datasource_select.concat(args)

      @datasource_select
    end

    def skip_select(*args)
      @datasource_skip_select ||= []
      @datasource_skip_select.concat(args)

      @datasource_skip_select
    end

    def includes(*args)
      @datasource_includes ||= {}

      args.each do |arg|
        @datasource_includes.deep_merge!(datasource_includes_to_select(arg))
      end

      @datasource_includes
    end

    def use_datasource(*args)
      @serializer.use_datasource(*args)
    end

  private
    def datasource_includes_to_select(arg)
      if arg.kind_of?(Hash)
        arg.keys.inject({}) do |memo, key|
          memo[key.to_sym] = ["*", datasource_includes_to_select(arg[key])]
          memo
        end
      elsif arg.kind_of?(Array)
        arg.inject({}) do |memo, element|
          memo.deep_merge!(datasource_includes_to_select(element))
        end
      elsif arg.respond_to?(:to_sym)
        { arg.to_sym => ["*"] }
      else
        fail Datasource::Error, "unknown includes value type #{arg.class}"
      end
    end
  end

  def inherited(base)
    select_values = loaders_context.select.deep_dup
    skip_select_values = loaders_context.skip_select.deep_dup
    includes_values = loaders_context.includes.deep_dup
    base.loaders do
      select(*select_values)
      skip_select(*skip_select_values)
      includes(*includes_values)
    end
    base.use_datasource(use_datasource)

    super
  end

  def loaders_context
    @loaders_context ||= SerializerDatasourceContext.new(self)
  end

  def loaders(&block)
    loaders_context.instance_eval(&block)
  end

  # required by datasource gem
  def datasource_adapter
    ActiveLoaders::Adapters::ActiveModelSerializers
  end

  # required by datasource gem
  def use_datasource(*args)
    @use_datasource = args.first unless args.empty?
    @use_datasource
  end
end

array_serializer_class = if defined?(ActiveModel::Serializer::ArraySerializer)
  ActiveModel::Serializer::ArraySerializer
else
  ActiveModel::ArraySerializer
end

array_serializer_class.class_exec do
  alias_method :initialize_without_loaders, :initialize
  include ActiveLoaders::Adapters::ActiveModelSerializers::ArraySerializer
  def initialize(*args)
    initialize_with_loaders(*args)
  end
end

ActiveModel::Serializer.singleton_class.send :prepend, SerializerClassMethods
Datasource::Base.default_consumer_adapter ||= ActiveLoaders::Adapters::ActiveModelSerializers

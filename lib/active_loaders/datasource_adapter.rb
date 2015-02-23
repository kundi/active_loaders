require "active_model/serializer"
require "datasource"

module ActiveLoaders
  module Adapters
    module ActiveModelSerializers
      module ArraySerializer
        def initialize_with_datasource(objects, options = {})
          datasource_class = options.delete(:datasource)
          adapter = Datasource.orm_adapters.find { |a| a.is_scope?(objects) }
          if adapter && !adapter.scope_loaded?(objects)
            datasource_class ||= adapter.scope_to_class(objects).default_datasource

            scope = begin
              objects
              .with_datasource(datasource_class)
              .for_serializer(options[:serializer])
              .datasource_params(*[options[:datasource_params]].compact)
            rescue NameError
              if options[:serializer].nil?
                return initialize_without_datasource(objects, options)
              else
                raise
              end
            end

            records = adapter.scope_to_records(scope)

            initialize_without_datasource(records, options)
          else
            initialize_without_datasource(objects, options)
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

      def to_datasource_select(result, klass, serializer = nil, serializer_assoc = nil, adapter = nil)
        adapter ||= Datasource::Base.default_adapter
        serializer ||= get_serializer_for(klass, serializer_assoc)
        result.unshift("*") if Datasource.config.simple_mode
        if serializer._attributes.respond_to?(:keys)  # AMS 0.8
          result.concat(serializer._attributes.keys)
        else                                          # AMS 0.9
          result.concat(serializer._attributes)
        end
        result.concat(serializer.datasource_select)
        result_assocs = serializer.datasource_includes.dup
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
  def inherited(base)
    base.datasource_select(*datasource_select.deep_dup)
    base.datasource_includes(*datasource_includes.deep_dup)

    super
  end

  def datasource_adapter
    ActiveLoaders::Adapters::ActiveModelSerializers
  end

  def datasource_select(*args)
    @datasource_select ||= []
    @datasource_select.concat(args)

    @datasource_select
  end

  def datasource_includes(*args)
    @datasource_includes ||= {}

    args.each do |arg|
      @datasource_includes.deep_merge!(datasource_includes_to_select(arg))
    end

    @datasource_includes
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

array_serializer_class = if defined?(ActiveModel::Serializer::ArraySerializer)
  ActiveModel::Serializer::ArraySerializer
else
  ActiveModel::ArraySerializer
end

array_serializer_class.class_exec do
  alias_method :initialize_without_datasource, :initialize
  include ActiveLoaders::Adapters::ActiveModelSerializers::ArraySerializer
  def initialize(*args)
    initialize_with_datasource(*args)
  end
end

ActiveModel::Serializer.singleton_class.send :prepend, SerializerClassMethods
Datasource::Base.default_consumer_adapter ||= ActiveLoaders::Adapters::ActiveModelSerializers

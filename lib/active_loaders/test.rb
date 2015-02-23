require 'set'

module ActiveLoaders
  module Test
    Error = Class.new(StandardError)
    def test_serializer_queries(serializer_klass, model_klass, ignore_columns: [], skip_columns_check: false, allow_queries_per_record: 0)
      records = get_all_records(model_klass, serializer_klass)
      fail "Not enough records to test #{serializer_klass}. Create at least 1 #{model_klass}." unless records.size > 0

      records.each do |record|
        queries = get_executed_queries do
          serializer_klass.new(record).as_json
        end

        unless queries.size == allow_queries_per_record
          fail Error, "unexpected queries\n\nRecord:\n#{record.inspect}\n\nQueries:\n#{queries.join("\n")}"
        end
      end

      # just for good measure
      queries = get_executed_queries do
        ActiveModel::ArraySerializer.new(records, each_serializer: serializer_klass).as_json
      end
      unless queries.size == (records.size * allow_queries_per_record)
        fail Error, "unexpected queries when using ArraySerializer\n\nModel:\n#{model_klass}\n\nQueries:\n#{queries.join("\n")}"
      end

      # select values (if supported)
      # TODO: Sequel?
      unless skip_columns_check
        if defined?(ActiveRecord::Base) && model_klass.ancestors.include?(ActiveRecord::Base)
          if records.first.respond_to?(:accessed_fields)
            accessed_fields = Set.new
            records.each { |record| accessed_fields.merge(record.accessed_fields) }

            unaccessed_columns = model_klass.column_names - accessed_fields.to_a - ignore_columns.map(&:to_s)

            unless unaccessed_columns.empty?
              unaccessed_columns_str = unaccessed_columns.join(", ")
              unaccessed_columns_syms = unaccessed_columns.map { |c| ":#{c}" }.join(", ")
              all_unaccessed_columns_syms = (ignore_columns.map(&:to_s) + unaccessed_columns).map { |c| ":#{c}" }.join(", ")
              fail Error, "unnecessary select for #{model_klass} columns: #{unaccessed_columns_str}\n\nAdd to #{serializer_klass} loaders block:\n  skip_select #{unaccessed_columns_syms}\n\nOr ignore this error with:\ntest_serializer_queries(#{serializer_klass}, #{model_klass}, ignore_columns: [#{all_unaccessed_columns_syms}])\n\nOr skip this columns check:\n  test_serializer_queries(#{serializer_klass}, #{model_klass}, skip_columns_check: true)"
            end
          end
        end
      end

      (@active_loaders_tested_serializers ||= Set.new).add(serializer_klass)
    end

    def assert_all_serializers_tested(namespace = nil)
      descendants =
        ObjectSpace.each_object(Class)
        .select { |klass| klass < ActiveModel::Serializer }
        .select { |klass| (namespace.nil? && !klass.name.include?("::")) || klass.name.starts_with?("#{namespace}::") }
        .reject { |klass| Array(@active_loaders_tested_serializers).include?(klass) }

      unless descendants.empty?
        fail Error, "serializers not tested: #{descendants.map(&:name).join(", ")}"
      end
    end

  private
    def get_all_records(model_klass, serializer_klass)
      if defined?(ActiveRecord::Base) && model_klass.ancestors.include?(ActiveRecord::Base)
        model_klass.for_serializer(serializer_klass).to_a
      elsif defined?(Sequel::Model) && model_klass.ancestors.include?(Sequel::Model)
        model_klass.for_serializer(serializer_klass).all
      else
        fail "Unknown model #{model_klass} of type #{model_klass.superclass}."
      end
    end

    def get_executed_queries
      logger_io = StringIO.new
      logger = Logger.new(logger_io)
      logger.formatter = ->(severity, datetime, progname, msg) {
        msg
      }
      if defined?(ActiveRecord::Base)
        ar_old_logger = ActiveRecord::Base.logger
        ActiveRecord::Base.logger = logger
      end
      if defined?(Sequel::Model)
        Sequel::Model.db.loggers << logger
      end

      begin
        yield
      ensure
        if defined?(ActiveRecord::Base)
          ActiveRecord::Base.logger = ar_old_logger
        end
        if defined?(Sequel::Model)
          Sequel::Model.db.loggers.delete(logger)
        end
      end

      logger_io.string.lines.reject { |line| line.strip == "" }
    end
  end
end

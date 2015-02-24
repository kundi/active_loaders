db_path = File.expand_path("../../db.sqlite3")
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: db_path)
Sequel::Model.db = Sequel.sqlite(db_path)
Sequel::Model.plugin :active_model
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define(:version => 0) do
  create_table :blogs, :force => true do |t|
    t.string :title
  end

  create_table :posts, :force => true do |t|
    t.integer :blog_id
    t.string :title
    t.string :author_first_name
    t.string :author_last_name
  end

  create_table :comments, :force => true do |t|
    t.integer :post_id
    t.text :comment
  end
end

Sequel::Model.send :include, ActiveModel::SerializerSupport

def expect_query_count(count)
  logger_io = StringIO.new
  logger = Logger.new(logger_io)
  logger.formatter = ->(severity, datetime, progname, msg) { "#{msg}\n" }
  if defined?(ActiveRecord::Base)
    ar_old_logger = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = logger
  end
  if defined?(Sequel::Model)
    Sequel::Model.db.loggers << logger
  end

  begin
    yield(logger_io)
  ensure
    if defined?(ActiveRecord::Base)
      ActiveRecord::Base.logger = ar_old_logger
    end
    if defined?(Sequel::Model)
      Sequel::Model.db.loggers.delete(logger)
    end
  end

  output = logger_io.string
  puts output if output.lines.count != count
  expect(logger_io.string.lines.count).to eq(count)
end

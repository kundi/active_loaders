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

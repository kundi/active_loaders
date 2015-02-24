# ActiveLoaders

- Automatically preload associations for your serializers
- Specify custom SQL snippets for virtual attributes (Query attributes)
- Write custom preloading logic in a reusable way

*Note: the API of this gem is still unstable and may change between versions. This project uses semantic versioning, however until version 1.0.0, minor version (MAJOR.MINOR.PATCH) changes may include API changes, but patch version will not)*

<a href="http://www.youtube.com/watch?feature=player_embedded&v=ajSNCbZYqKk
" target="_blank"><img src="http://img.youtube.com/vi/ajSNCbZYqKk/0.jpg"
alt="Datasource talk" width="240" height="180" border="10" /><br>A 30-min talk about Datasource</a>

#### Install

Ruby version requirement:

- MRI 2.0 or higher
- JRuby 9000

Supported ORM:

- ActiveRecord
- Sequel

Add to Gemfile (recommended to use github version until API is stable)

```
gem 'active_loaders', github: 'kundi/active_loaders'
```

```
bundle install
rails g datasource:install
```

#### Upgrade

```
rails g datasource:install
```

### Introduction

The most important role of ActiveLoaders is to help prevent and fix the
[N+1 queries problem](http://guides.rubyonrails.org/active_record_querying.html#eager-loading-associations)
when using Active Model Serializers.

This gem depends on the datasource gem that handles actual data loading. What this gem
adds on top of it is integration with Active Model Serializers. It will automatically
read your serializers to make datasource preload the necessary associations. Additionally
it provides a simple DSL to configure additional dependencies and test helpers to ensure
your queries are optimized.

ActiveLoaders will automatically recognize associations in your **serializer** when you use
the `has_many` or `belongs_to` keywords:

```ruby
class PostSerializer < ActiveModel::Serializer
  belongs_to :blog
  has_many :comments
end
```

In this case, it will then look in your BlogSerializer and CommentSerializer to properly
load them as well (so it is recursive).

When you are using loaded values (explained below), ActiveLoaders will automatically
use them if you specify the name in `attributes`. For example if you have a
`loaded :comment_count` it will automatically be used if you have
`attributes :comment_count` in your serializer.

In case ActiveLoaders doesn't automatically detect something, you can always manually
specify it in your serializer using a simple DSL.

A test helper is also provided which you can ensure that your serializers don't produce
N+1 queries.

### Associations

The most noticable magic effect of using ActiveLoaders is that associations will
automatically be preloaded using a single query.

```ruby
class PostSerializer < ActiveModel::Serializer
  attributes :id, :title
end

class UserSerializer < ActiveModel::Serializer
  attributes :id
  has_many :posts
end
```
```sql
SELECT users.* FROM users
SELECT posts.* FROM posts WHERE id IN (?)
```

This means you **do not** need to call `includes` yourself. It will be done
automatically.

#### Manually include

In case you are not using `has_many` or `belongs_to` in your serializer but you are
still using the association (usually when you do not embed the association), then you
need to manually specify this in your serializer. There are two options depending on
what data you need.

**includes**: use this when you just need a simple `includes`, which behaves the same
as in ActiveRecord.

```ruby
class UserSerializer < ActiveModel::Serializer
  attributes :id, :post_titles
  loaders do
    includes :posts
    # includes posts: { :comments }
  end

  def post_titles
    object.posts.map(&:title)
  end
end
```

**select**: use this to use the serializer loading logic - the same recursive logic that
happens when you use `has_many` or `belongs_to`. This will also load associations and
loaded values (unless otherwise specified).


```ruby
class UserSerializer < ActiveModel::Serializer
  attributes :id, :comment_loaded_values
  loaders do
    select :posts
    # select posts: [:id, comments: [:id, :some_loaded_value]]
  end

  def comment_loaded_values
    object.posts.flat_map(&:comments).map(&:some_loaded_value)
  end
end

class PostSerializer < ActiveModel::Serializer
  attributes :id
  has_many :comments
end

class CommentSerializer < ActiveModel::Serializer
  attributes :id, :some_loaded_value
end
```

### Query attribute

You can specify a SQL fragment for `SELECT` and use that as an attribute on your
model. This is done through the datasource gem DSL. As a simple example you can
concatenate 2 strings together in SQL:

```ruby
class User < ActiveRecord::Base
  datasource_module do
    query :full_name do
      "users.first_name || ' ' || users.last_name"
    end
  end
end

class UserSerializer < ActiveModel::Serializer
  attributes :id, :full_name
end
```

```sql
SELECT users.*, (users.first_name || ' ' || users.last_name) AS full_name FROM users
```

Note: If you need data from another table, use a loaded value.

### Refactor with standalone Datasource class

If you are going to have more complex preloading logic (like using Loaded below),
then it might be better to put Datasource code into its own class. This is pretty
easy, just create a directory `app/datasources` (or whatever you like), and create
a file depending on your model name, for example for a `Post` model, create
`post_datasource.rb`. The name is important for auto-magic reasons. Example file:

```ruby
class PostDatasource < Datasource::From(Post)
  query(:full_name) { "users.first_name || ' ' || users.last_name" }
end
```

This is completely equivalent to using `datasource_module` in your model:

```ruby
class Post < ActiveRecord::Base
  datasource_module do
    query(:full_name) { "users.first_name || ' ' || users.last_name" }
  end
end
```

### Loaded

You might want to have some more complex preloading logic. In that case you can
use a method to load values for all the records at once (e.g. with a custom query
or even from a cache). The loading methods are only executed if you use the values,
otherwise they will be skipped.

First just declare that you want to have a loaded attribute (the parameters will be explained shortly):

```ruby
class UserDatasource < Datasource::From(User)
  loaded :post_count, from: :array, default: 0
end
```

By default, datasource will look for a method named `load_<name>` for loading
the values, in this case `load_newest_comment`. It needs to be defined in the
collection block, which has methods to access information about the collection (posts)
that are being loaded. These methods are `scope`, `models`, `model_ids`,
`datasource`, `datasource_class` and `params`.

```ruby
class UserDatasource < Datasource::From(User)
  loaded :post_count, from: :array, default: 0

  collection do
    def load_post_count
      Post.where(user_id: model_ids)
      .group(:user_id)
      .pluck("user_id, COUNT(id)")
    end
  end
end
```

In this case `load_post_count` returns an array of pairs.
For example: `[[1, 10], [2, 5]]`. Datasource can understand this because of
`from: :array`. This would result in the following:

```ruby
post_id_1.post_count # => 10
post_id_2.post_count # => 5
# other posts will have the default value or nil if no default value was given
other_post.post_count # => 0
```

Besides `default` and `from: :array`, you can also specify `group_by`, `one`
and `source`. Source is just the name of the load method.

The other two are explained in the following example.

```ruby
class PostDatasource < Datasource::From(Post)
  loaded :newest_comment, group_by: :post_id, one: true, source: :load_newest_comment

  collection do
    def load_newest_comment
      Comment.for_serializer.where(post_id: model_ids)
        .group("post_id")
        .having("id = MAX(id)")
    end
  end
end
```

In this case the load method returns an ActiveRecord relation, which for our purposes
acts the same as an Array (so we could also return an Array if we wanted).
Using `group_by: :post_id` in the `loaded` call tells datasource to group the
results in this array by that attribute (or key if it's an array of hashes instead
of model objects). `one: true` means that we only want a single value instead of
an array of values (we might want multiple, e.g. `newest_10_comments`).
So in this case, if we had a Post with id 1, `post.newest_comment` would be a
Comment from the array that has `post_id` equal to 1.

In this case, in the load method, we also used `for_serializer`, which will load
the `Comment`s according to the `CommentSerializer`.

Note that it's perfectly fine (even recommended) to already have a method with the same
name in your model.
If you use that method outside of serializers/datasource, it will work just as
it should. But when using datasource, it will be overwritten by the datasource
version. Counts is a good example:

```ruby
class User < ActiveRecord::Base
  has_many :posts

  def post_count
    posts.count
  end
end

class UserDatasource < Datasource::From(User)
  loaded :post_count, from: :array, default: 0

  collection do
    def load_post_count
      Post.where(user_id: model_ids)
        .group(:user_id)
        .pluck("user_id, COUNT(id)")
    end
  end
end

class UserSerializer < ActiveModel::Serializer
  attributes :id, :post_count # <- post_count will be read from load_post_count
end

User.first.post_count # <- your model method will be called
```

### Params

You can also specify params that can be read from collection methods. The params
can be specified when you call `render`:

```ruby
# controller
  render json: posts,
    loader_params: { include_newest_comments: true }

# datasource
  loaded :newest_comments, default: []

  collection do
    def load_newest_comments
      if params[:include_newest_comments]
        # ...
      end
    end
  end
```

### Debugging and logging

Datasource outputs some useful logs that you can use debugging. By default the log level is
set to warnings only, but you can change it. You can add the following line at the end of your
`config/initializers/datasource.rb`:

```ruby
Datasource.logger.level = Logger::INFO unless Rails.env.production?
```

You can also set it to `DEBUG` for more output. The logger outputs to `stdout` by default. It
is not recommended to have this enabled in production (simply for performance reasons).

### Using manually

When using a serializer, ActiveLoaders should work automatically. If for some reason
you want to manually trigger loaders on a scope, you can call `for_serializer`.

```ruby
Post.for_serializer.find(params[:id])
Post.for_serializer(PostSerializer).find(params[:id])
Post.for_serializer.where("created_at > ?", 1.day.ago).to_a
```

You can also use it on an existing record, but you must use the returned value (the record
may be reloaded e.g. if you are using query attributes).

```ruby
user = current_user.for_serializer
```

For even more advanced usage, see Datasource gem documentation.

### Testing your serializer queries

ActiveLoaders provides test helpers to make sure your queries stay optimized. By default
it expects there to be no N+1 queries, so after the initial loading of the records and
associations, there should be no queries from code in the serializers. The helpers raise
and error otherwise, so you can use them with any testing framework (rspec, minitest).
You need to put some records into the database before calling the helper, since it is
required to be able to test the serializer.

```ruby
test_serializer_queries(serializer_class, model_class, options = {})
```

Here is a simple example in rspec with factory_girl:

```ruby
require 'spec_helper'
require 'active_loaders/test'

context "serializer queries" do
  include ActiveLoaders::Test
  let(:blog) { create :blog }
  before do
    2.times {
      create :post, blog_id: blog.id
    }
  end

  it "should not contain N+1 queries" do
    expect { test_serializer_queries(BlogSerializer, Blog) }.to_not raise_error
  end

  # example if you have N+1 queries and you can't avoid them
  it "should contain exactly two N+1 queries (two queries for every Blog)" do
    expect { test_serializer_queries(BlogSerializer, Blog, allow_queries_per_record: 2) }.to_not raise_error
  end
end
```

#### Columns check

Recently (not yet released as of Rails 4.2), an `accessed_fields` instance method
was added to ActiveRecord models. ActiveLoaders can use this information in your
tests to determine which attributes you are not using in your serializer. This check
is skipped if your Rails version doesn't support `accessed_fields`.

Let's say your are not using User#payment_data in your serializer. You have this test:

```ruby
  it "should not contain N+1 queries" do
    expect { test_serializer_queries(UserSerializer, User) }.to_not raise_error
  end
```

Then this test will fail with instructions on how to fix it:

```ruby
ActiveLoaders::Test::Error:
  unnecessary select for User columns: payment_data

  Add to UserSerializer loaders block:
    skip_select :payment_data

  Or ignore this error with:
    test_serializer_queries(UserSerializer, User, ignore_columns: [:payment_data])

  Or skip this columns check entirely:
    test_serializer_queries(UserSerializer, User, skip_columns_check: true)
```

The instructions should be self-explanatory. Choosing the first option:

```ruby
class UserSerializer < ActiveModel::Serializer
  attributes :id, :title

  loaders do
    skip_select :payment_data
  end
end
```

Would then produce an optimized query:
```sql
SELECT users.id, users.title FROM users
```

## Getting Help

If you find a bug, please report an [Issue](https://github.com/kundi/active_loaders/issues/new).

If you have a question, you can also open an Issue.

## Contributing

1. Fork it ( https://github.com/kundi/active_loaders/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

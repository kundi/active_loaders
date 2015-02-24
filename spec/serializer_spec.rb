require 'spec_helper'

module SerializerSpec
  describe "Serializer", :activerecord do
    class Comment < ActiveRecord::Base
      belongs_to :post
    end

    class Post < ActiveRecord::Base
      belongs_to :blog
      has_many :comments

      datasource_module do
        query :author_name do
          "posts.author_first_name || ' ' || posts.author_last_name"
        end
      end
    end

    class Blog < ActiveRecord::Base
      has_many :posts
    end

    class BlogSerializer < ActiveModel::Serializer
      attributes :id, :title

      has_many :posts
    end

    class PostSerializer < ActiveModel::Serializer
      attributes :id, :title, :author_name

      has_many :comments
    end

    class CommentSerializer < ActiveModel::Serializer
      attributes :id, :comment
    end

    it "returns serialized hash" do
      blog = Blog.create! title: "Blog 1"
      post = blog.posts.create! title: "Post 1", author_first_name: "John", author_last_name: "Doe"
      post.comments.create! comment: "Comment 1"
      post = blog.posts.create! title: "Post 2", author_first_name: "Maria", author_last_name: "Doe"
      post.comments.create! comment: "Comment 2"
      blog = Blog.create! title: "Blog 2"

      expected_result = [
        {:id =>1, :title =>"Blog 1", :posts =>[
          {:id =>1, :title =>"Post 1", :author_name =>"John Doe", comments: [{:id =>1, :comment =>"Comment 1"}]},
          {:id =>2, :title =>"Post 2", :author_name =>"Maria Doe", comments: [{:id =>2, :comment =>"Comment 2"}]}
        ]},
        {:id =>2, :title =>"Blog 2", :posts =>[]}
      ]

      expect_query_count(3) do
        serializer = ActiveModel::ArraySerializer.new(Blog.all)
        expect(expected_result).to eq(serializer.as_json)
      end
    end
  end
end

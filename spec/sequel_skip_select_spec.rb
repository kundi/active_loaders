require 'spec_helper'

module SequelSkipSelectSpec
  describe "skip_select (Sequel)", :sequel do
    class Comment < Sequel::Model
      many_to_one :post
    end

    class Post < Sequel::Model
      many_to_one :blog
      one_to_many :comments

      datasource_module do
        query :author_name do
          "posts.author_first_name || ' ' || posts.author_last_name"
        end
      end
    end

    class Blog < Sequel::Model
      one_to_many :posts
    end

    class CommentSerializer < ActiveModel::Serializer
      attributes :id, :comment
    end

    class PostSerializer < ActiveModel::Serializer
      attributes :id, :title, :author_name
      has_many :comments, each_serializer: CommentSerializer

      loaders do
        skip_select :author_first_name, :author_last_name
      end

      def author_name
        object.values[:author_name]
      end
    end

    class BlogSerializer < ActiveModel::Serializer
      attributes :id, :title

      has_many :posts, each_serializer: PostSerializer
    end

    it "returns serialized hash" do
      blog = Blog.create title: "Blog 1"
      post = Post.create blog_id: blog.id, title: "Post 1", author_first_name: "John", author_last_name: "Doe"
      Comment.create(post_id: post.id, comment: "Comment 1")
      post = Post.create blog_id: blog.id, title: "Post 2", author_first_name: "Maria", author_last_name: "Doe"
      Comment.create(post_id: post.id, comment: "Comment 2")
      blog = Blog.create title: "Blog 2"

      expected_result = [
        {:id =>1, :title =>"Blog 1", :posts =>[
          {:id =>1, :title =>"Post 1", :author_name =>"John Doe", comments: [{:id =>1, :comment =>"Comment 1"}]},
          {:id =>2, :title =>"Post 2", :author_name =>"Maria Doe", comments: [{:id =>2, :comment =>"Comment 2"}]}
        ]},
        {:id =>2, :title =>"Blog 2", :posts =>[]}
      ]

      expect_query_count(3) do |logger|
        serializer = ActiveModel::ArraySerializer.new(Blog.where, each_serializer: BlogSerializer)
        expect(expected_result).to eq(serializer.as_json)
        expect(logger.string.lines[0]).to include("blogs.*")
        expect(logger.string.lines[1]).to_not include("posts.*")
        expect(logger.string.lines[1]).to_not include("posts.author_first_name,")
        expect(logger.string.lines[1]).to_not include("posts.author_last_name,")
        expect(logger.string.lines[1]).to include("posts.id")
        expect(logger.string.lines[1]).to include("posts.title")
        expect(logger.string.lines[1]).to include("posts.blog_id")
        expect(logger.string.lines[2]).to include("comments.*")
      end
    end
  end
end

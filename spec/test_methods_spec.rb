require 'spec_helper'

module TestMethodsSpec
  describe "Test Methods" do
    include ActiveLoaders::Test

    class Post < ActiveRecord::Base
      belongs_to :blog
    end
    class Blog < ActiveRecord::Base
      has_many :posts
    end

    class PostSerializer < ActiveModel::Serializer
      attributes :id, :title
    end

    class BlogSerializer < ActiveModel::Serializer
      attributes :id, :title
      has_many :posts
    end

    class BadBlogSerializer < ActiveModel::Serializer
      attributes :id, :title, :stuff

      def stuff
        object.posts.to_a
        "^^^ I was naughty ^^^"
      end
    end

    it "should fail when data is not preloaded" do
      blog = Blog.create! title: "The Blog"
      2.times do
        blog.posts.create! title: "The Post", author_first_name: "John", author_last_name: "Doe", blog_id: 10
      end

      expect { test_serializer_queries(BadBlogSerializer, Blog) }.to raise_error(ActiveLoaders::Test::Error)
    end

    it "should not fail when data is preloaded" do
      blog = Blog.create! title: "The Blog"
      2.times do
        blog.posts.create! title: "The Post", author_first_name: "John", author_last_name: "Doe", blog_id: 10
      end

      expect { test_serializer_queries(BlogSerializer, Blog) }.to_not raise_error
    end

    it "should fail when not all serializers were tested" do
      blog = Blog.create! title: "The Blog"

      test_serializer_queries(BlogSerializer, Blog)
      expect { assert_all_serializers_tested(TestMethodsSpec) }.to raise_error(ActiveLoaders::Test::Error)
    end
  end
end

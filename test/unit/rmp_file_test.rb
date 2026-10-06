# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RmpFileTest < ActiveSupport::TestCase
  RmpFile = RedmineMorePreviews::Lib::RmpFile

  def test_directory_creates_a_missing_directory
    Dir.mktmpdir do |dir|
      sub = File.join(dir, 'a', 'b')
      assert_equal sub, RmpFile.directory(sub)
      assert File.directory?(sub)
      # and accepts an existing one (File.exists? was removed in Ruby 3.2)
      assert_equal sub, RmpFile.directory(sub)
    end
  end

  def test_directory_refuses_a_subdir_above_dir
    Dir.mktmpdir do |dir|
      assert_nil RmpFile.directory('../escape', dir)
    end
  end
end

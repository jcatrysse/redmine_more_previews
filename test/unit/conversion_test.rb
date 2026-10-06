# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class ConversionTest < ActiveSupport::TestCase
  def worker(options = {})
    RedmineMorePreviews::Converter.find(:teddie).worker({ :target => Rails.root.join('tmp', 'more_previews', 'x', 'index.txt').to_s }.merge(options))
  end

  def test_an_asset_inside_the_preview_directory_is_accepted
    assert_equal 'inner/hello.txt', worker(:asset => 'inner/hello.txt').asset
  end

  def test_an_asset_outside_the_preview_directory_is_refused
    assert_raise(RedmineMorePreviews::Exceptions::ConverterBadArgument) { worker(:asset => '../../../config/database.yml') }
    assert_raise(RedmineMorePreviews::Exceptions::ConverterBadArgument) { worker(:asset => '/etc/passwd') }
  end
end

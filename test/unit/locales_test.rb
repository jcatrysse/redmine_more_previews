# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class LocalesTest < ActiveSupport::TestCase
  ROOT = File.expand_path('../..', __dir__)

  def keys(file)
    YAML.load_file(file).values.first.keys.sort
  end

  def test_shipped_locales_have_the_same_keys_as_english
    files = Dir[File.join(ROOT, 'config/locales/*.yml')] + Dir[File.join(ROOT, 'converters/*/config/locales/*.yml')]
    files.each do |file|
      english = File.join(File.dirname(file), 'en.yml')
      assert_equal keys(english), keys(file), "#{file.delete_prefix(ROOT)} is out of sync with en.yml"
    end
  end

  # the converters keep their texts under redmine_more_previews.<converter> (vince's
  # vcard field names, from upstream, are incomplete in some locales and fall back)
  def test_shipped_locales_have_the_same_converter_texts_as_english
    files = Dir[File.join(ROOT, 'config/locales/*.yml')] + Dir[File.join(ROOT, 'converters/*/config/locales/*.yml')]
    files.each do |file|
      english = File.join(File.dirname(file), 'en.yml')
      assert_equal deep_keys(YAML.load_file(english).values.first.slice('redmine_more_previews')),
                   deep_keys(YAML.load_file(file).values.first.slice('redmine_more_previews')),
                   "#{file.delete_prefix(ROOT)} is out of sync with en.yml"
    end
  end

  def deep_keys(hash, prefix = nil)
    hash.flat_map { |key, value| value.is_a?(Hash) ? deep_keys(value, "#{prefix}#{key}.") : ["#{prefix}#{key}"] }.sort
  end

  def test_brazilian_portuguese_is_found_under_redmine_locale_name
    # Redmine's locale is "pt-BR"; config/locales/pt-BR.yml carries that key (GEOxyz b564c08)
    assert_equal 'pt-BR', YAML.load_file(File.join(ROOT, 'config/locales/pt-BR.yml')).keys.first
    assert I18n.exists?(:label_redmine_more_previews, :'pt-BR')
  end
end

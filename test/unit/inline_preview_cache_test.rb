# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

# port of curecodejp 0b3e950 (#71): sanitized inline previews are kept in a
# bounded store of the process (32 MiB, an hour), keyed on the content, so a
# page view does not sanitize the same html again. Upstream's tests on our
# more_previews_inline (upstream's sanitize_inline_preview), plus ours: the
# bounds, and many Puma threads at once.
class InlinePreviewCacheTest < Redmine::HelperTest
  include ApplicationHelper

  CACHE = RedmineMorePreviews::Patches::ApplicationHelperPatch::INLINE_PREVIEW_CACHE

  def setup
    super
    CACHE.clear
    RedmineMorePreviews::Converter.stubs(:cache_previews?).returns(true)
    @sanitized = Concurrent::AtomicFixnum.new(0)
    counter = @sanitized
    # counts the real sanitizer calls, and still sanitizes
    singleton_class.prepend(Module.new do
      define_method(:sanitize) do |*args, **options|
        counter.increment
        super(*args, **options)
      end
    end)
  end

  def teardown
    CACHE.clear
    super
  end

  # [the block's result, how many times the html was really sanitized]
  def counted
    before = @sanitized.value
    result = yield
    [result, @sanitized.value - before]
  end

  def test_the_store_is_a_bounded_memory_store
    assert_kind_of ActiveSupport::Cache::MemoryStore, CACHE
    assert_equal 32 * 1024 * 1024, CACHE.instance_variable_get(:@max_size)
    assert_equal 1.hour, CACHE.options[:expires_in]
  end

  def test_identical_html_is_sanitized_only_once
    html = '<p>cached</p><script>alert(1)</script>'
    first  = counted { more_previews_inline(html) }
    second = counted { more_previews_inline(html) }

    assert_equal [1, 0], [first.last, second.last]
    assert_equal '<p>cached</p>alert(1)', second.first
    assert second.first.html_safe?
  end

  def test_different_html_is_not_mixed_up
    assert_equal '<p>one</p>alert(1)', more_previews_inline('<p>one</p><script>alert(1)</script>')
    assert_equal '<p>two</p>alert(2)', more_previews_inline('<p>two</p><script>alert(2)</script>')
  end

  def test_kept_apart_per_sub_uri
    html = '<p>sub</p>'
    Redmine::Utils.stubs(:relative_url_root).returns('/redmine')
    assert_equal 1, counted { more_previews_inline(html) }.last
    Redmine::Utils.stubs(:relative_url_root).returns('')
    assert_equal 1, counted { more_previews_inline(html) }.last
  end

  def test_nothing_is_kept_or_read_when_the_preview_cache_is_disabled
    html = '<p>never kept</p>'
    RedmineMorePreviews::Converter.stubs(:cache_previews?).returns(true)
    more_previews_inline(html)
    RedmineMorePreviews::Converter.stubs(:cache_previews?).returns(false)
    2.times { assert_equal [html, 1], counted { more_previews_inline(html) } }
    CACHE.clear
    more_previews_inline('<p>other</p>')
    assert_not CACHE.exist?("#{Redmine::Utils.relative_url_root}:#{Digest::SHA256.hexdigest('<p>other</p>')}")
  end

  def test_parser_limit_failures_are_not_kept
    # the HTML5 vendor raises on this (Redmine 7 keeps HTML4, see inline_preview_limit_test)
    self.class.stubs(:safe_list_sanitizer).returns(Rails::HTML5::SafeListSanitizer.new)
    html = '<div>' * 500 + 'x' + '</div>' * 500
    notice = '<p class="nodata">The inline preview is too complex to display. Download the file to view it.</p>'
    2.times { assert_equal [notice, 1], counted { more_previews_inline(html) } }
  end

  def test_oversized_html_is_not_sanitized_nor_kept
    assert_equal 0, counted { more_previews_inline('x' * 262_145) }.last
    assert_equal 0, CACHE.instance_variable_get(:@data).size
  end

  def test_the_store_stays_within_its_size
    # 200 different previews of about 250 KiB: 50 MiB sanitized, at most 32 kept
    200.times { |i| more_previews_inline("<p>#{i}</p>" + ('a' * 250_000)) }
    assert_operator CACHE.instance_variable_get(:@cache_size), :<=, 32 * 1024 * 1024
    assert_operator CACHE.instance_variable_get(:@data).size, :<, 200
  end

  def test_kept_results_expire_after_an_hour
    html = '<p>expires</p>'
    more_previews_inline(html)
    travel(61.minutes) do
      assert_equal 1, counted { more_previews_inline(html) }.last
    end
  end

  # Puma threads share the store: every thread gets the result of its own html
  def test_threads_sharing_the_store_get_their_own_results
    results = Concurrent::Array.new
    threads = 16.times.map do |t|
      Thread.new do
        50.times do |i|
          n = (t * 50 + i) % 40
          results << [n, more_previews_inline("<p>#{n}</p><script>x</script>").to_s]
        end
      end
    end
    threads.each(&:join)
    assert_equal 800, results.size
    results.each { |n, html| assert_equal "<p>#{n}</p>x", html }
    assert_operator @sanitized.value, :<=, 800
  end
end

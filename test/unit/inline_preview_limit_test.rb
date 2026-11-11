# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

# port of curecodejp 5fb219a (#61): an inline preview is sanitized in the
# Rails worker, outside the converter's process limits. Converted html over
# 256 KiB is not parsed there: the page gets a notice instead. Upstream's
# tests of sanitize_inline_preview, on our more_previews_inline (upstream
# expects the sanitizer class never to be built; ours calls ActionView's
# sanitize, so that is what must not be called).
class InlinePreviewLimitTest < Redmine::HelperTest
  include ApplicationHelper

  def test_limit_is_256_kib
    assert_equal 262_144, RedmineMorePreviews::Patches::ApplicationHelperPatch::MAX_INLINE_PREVIEW_HTML_BYTES
  end

  def test_inline_preview_accepts_input_at_byte_limit
    html = '<p>' + ('a' * (262_144 - 7)) + '</p>'
    assert_equal 262_144, html.bytesize

    assert_equal html, more_previews_inline(html)
  end

  def test_inline_preview_rejects_oversized_html_without_parsing_it
    html = '<script>alert(1)</script>' + ('x' * 262_144)
    expects(:sanitize).never

    output = more_previews_inline(html)

    assert_equal '<p class="nodata">The inline preview exceeds the size limit. Download the file to view it.</p>', output
    assert output.html_safe?
  end

  def test_inline_preview_counts_bytes_not_characters
    # 87,382 characters, 262,146 bytes
    output = more_previews_inline('あ' * 87_382)

    assert_includes output, 'The inline preview exceeds the size limit.'
  end

  def test_inline_preview_still_strips_scripts_below_limit
    output = more_previews_inline('<p>safe</p><script>alert(1)</script>')

    # Rails' sanitizer keeps the text of the removed element (upstream's own
    # scrubber drops it): inert text, no element
    assert_equal '<p>safe</p>alert(1)', output
  end

  def test_notice_is_translated
    ::I18n.locale = 'de'
    assert_includes more_previews_inline('x' * 262_145), 'Das eingebettete Preview ist zu groß.'
  end

  # port of curecodejp 77ce987 (#70): the HTML5 parser refuses markup over its
  # tree depth and attribute limits by raising, far below the size limit; the
  # page must not fail, and the input is never returned unsanitized. Redmine 7
  # keeps ActionView's HTML4 sanitizer (no load_defaults), which does not
  # raise; an installation (or a later Redmine) choosing the HTML5 vendor
  # does: these tests use it
  def with_html5_sanitizer
    self.class.stubs(:safe_list_sanitizer).returns(Rails::HTML5::SafeListSanitizer.new)
    yield
  end

  def test_inline_preview_shows_a_notice_for_nesting_over_the_parser_limit
    with_html5_sanitizer do
      output = more_previews_inline('<script>alert(1)</script>' + '<div>' * 500 + 'x' + '</div>' * 500)

      assert_equal '<p class="nodata">The inline preview is too complex to display. Download the file to view it.</p>', output
      assert output.html_safe?
    end
  end

  def test_inline_preview_shows_a_notice_for_attributes_over_the_parser_limit
    with_html5_sanitizer do
      attributes = (0...500).map { |i| %(a#{i}="1") }.join(' ')
      output = more_previews_inline("<script>alert(1)</script><span #{attributes}>x</span>")

      assert_equal '<p class="nodata">The inline preview is too complex to display. Download the file to view it.</p>', output
      assert output.html_safe?
    end
  end

  def test_inline_preview_still_sanitizes_nesting_below_the_parser_limit
    with_html5_sanitizer do
      output = more_previews_inline('<script>alert(1)</script>' + '<div>' * 300 + 'x' + '</div>' * 300)

      assert_includes output, '<div>'
      assert_not_includes output, '<script>'
      assert_not_includes output, 'too complex'
    end
  end

  # ours: Redmine 7's own sanitizer keeps deep markup and still removes scripts
  def test_redmine_sanitizer_sanitizes_deep_nesting
    output = more_previews_inline('<script>alert(1)</script>' + '<div>' * 500 + 'x' + '</div>' * 500)

    assert_includes output, '<div>'
    assert_not_includes output, '<script>'
  end

  def test_parser_limit_notice_is_translated
    with_html5_sanitizer do
      ::I18n.locale = 'de'
      assert_includes more_previews_inline('<div>' * 500), 'Das eingebettete Preview ist zu komplex'
    end
  end
end

# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

# port of curecodejp ee6c728 (#79): Zippy's listing is an html fragment
# without <meta charset>, sent as text/html: a browser guessed its encoding
# and garbled non-ASCII headings (Japanese, say). Upstream's tests of
# html_preview_downloads_test (a file that exists only upstream).
class ZippyListingCharsetTest < Redmine::ControllerTest
  include RedmineMorePreviews::TestHelper
  tests AttachmentsController

  fixtures :users, :email_addresses, :projects, :roles, :members, :member_roles,
           :enabled_modules, :issues, :trackers, :issue_statuses, :enumerations,
           :projects_trackers, :attachments

  SETTINGS = ZIPPY_SETTINGS.deep_merge(
    'converter' => {'pass' => {'active' => '1', 'mime_types' => {'html' => {'active' => '1', 'format' => 'html'}}}}
  ).freeze

  def setup
    set_tmp_attachments_directory
    @old_settings = Setting.plugin_redmine_more_previews
    Setting.plugin_redmine_more_previews = SETTINGS
    Setting.clear_cache
    EnabledModule.create!(project_id: 1, name: 'redmine_more_previews')
    @storage = Dir.mktmpdir('rmp-storage')
    @old_storage = RedmineMorePreviews::Constants::Defaults::MORE_PREVIEWS_STORAGE_PATH
    RedmineMorePreviews::Constants::Defaults.send(:remove_const, :MORE_PREVIEWS_STORAGE_PATH)
    RedmineMorePreviews::Constants::Defaults.const_set(:MORE_PREVIEWS_STORAGE_PATH, @storage)
    @request.session[:user_id] = 2
  end

  def teardown
    Setting.plugin_redmine_more_previews = @old_settings
    Setting.clear_cache # the writer caches the symbol key; the plugin reads the string key
    RedmineMorePreviews::Constants::Defaults.send(:remove_const, :MORE_PREVIEWS_STORAGE_PATH)
    RedmineMorePreviews::Constants::Defaults.const_set(:MORE_PREVIEWS_STORAGE_PATH, @old_storage)
    FileUtils.rm_rf(@storage)
  end

  def attach(path, content_type)
    a = Attachment.new(container: Issue.find(1), file: Rack::Test::UploadedFile.new(path, content_type, true), author: User.find(2))
    assert a.save
    a
  end

  def test_zippy_listing_is_shown_in_utf8
    User.find(2).update_column(:language, 'ja')
    Dir.mktmpdir do |dir|
      a = attach(build_zip(File.join(dir, 'a.zip'), 'file.txt' => 'x'), 'application/zip')
      get :more_preview, params: {id: a.id, format: 'html'}
      assert_response :success
      assert_displayed_as 'ファイル名', response

      # also when the listing comes from the cache
      get :more_preview, params: {id: a.id, format: 'html'}
      assert_response :success
      assert_displayed_as '圧縮されたサイズ', response

      Setting.plugin_redmine_more_previews = SETTINGS.merge('cache_previews' => '0')
      Setting.clear_cache
      get :more_preview, params: {id: a.id, format: 'html'}
      assert_response :success
      assert_displayed_as 'ファイル名', response
    end
  end

  # a browser that kept a listing served before sends its old ETag: it gets
  # the listing again with the charset, not a 304 that keeps the old headers;
  # the current ETag still gets a 304
  def test_zippy_listing_cached_by_the_browser_before_the_fix_is_sent_again
    Dir.mktmpdir do |dir|
      a = attach(build_zip(File.join(dir, 'a.zip'), 'file.txt' => 'x'), 'application/zip')
      AttachmentsController.any_instance.stubs(:preview_content_type).returns('text/html')
      get :more_preview, params: {id: a.id, format: 'html'} # converts: the ETag follows the cache
      get :more_preview, params: {id: a.id, format: 'html'}
      assert_response :success
      old_etag = response.headers['ETag']
      @request.headers['If-None-Match'] = old_etag
      get :more_preview, params: {id: a.id, format: 'html'}
      assert_response :not_modified

      AttachmentsController.any_instance.unstub(:preview_content_type)
      @request.headers['If-None-Match'] = old_etag
      get :more_preview, params: {id: a.id, format: 'html'}
      assert_response :success
      assert_equal 'text/html; charset=utf-8', response.headers['Content-Type']
      new_etag = response.headers['ETag']
      assert_not_equal old_etag, new_etag

      @request.headers['If-None-Match'] = new_etag
      get :more_preview, params: {id: a.id, format: 'html'}
      assert_response :not_modified
    end
  end

  # an uploaded page may be in any encoding: Pass serves it as it is, and the
  # browser reads the page's own declaration
  def test_uploaded_html_gets_no_charset_from_the_plugin
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'page.html')
      File.binwrite(path, '<!DOCTYPE html><html><head><meta http-equiv="Content-Type" content="text/html; charset=Shift_JIS"></head>'.b +
                          "<body>#{'表'.encode('Shift_JIS').b}</body></html>".b)
      a = attach(path, 'text/html')
      assert_equal 'pass', RedmineMorePreviews::Converter.responsible(a.diskfile).id.to_s
      get :more_preview, params: {id: a.id, format: 'html'}
      assert_response :success
      assert_equal 'text/html', response.media_type
      assert_no_match(/charset/i, response.headers['Content-Type'].to_s)
      assert_equal 'shift_jis', declared_charset(response)
      assert_displayed_as '表', response
    end
  end

  # ours: the converter is chosen by the content, as the conversion does
  def test_converter_is_chosen_by_content_as_the_conversion_does
    Dir.mktmpdir do |dir|
      zip = build_zip(File.join(dir, 'a.zip'), 'file.txt' => 'x')
      a = attach(zip, 'application/zip')
      assert_equal 'zippy', RedmineMorePreviews::Converter.responsible(a.diskfile).id.to_s
      get :more_preview, params: {id: a.id, format: 'html'}
      assert_equal 'text/html; charset=utf-8', response.headers['Content-Type']
    end
  end

  # port of curecodejp 966c49d (#78): the frame is an opaque origin, from which
  # a browser may send no SameSite=Lax session cookie: the links open in the top
  # window, which the sandbox allows Zippy's listing after a click only
  def test_zippy_listing_links_open_in_the_top_window
    Dir.mktmpdir do |dir|
      a = attach(build_zip(File.join(dir, 'a.zip'), 'dir/' => '', 'dir/file.txt' => 'x'), 'application/zip')
      get :more_preview, params: {id: a.id, format: 'html'}
      assert_response :success
      csp = response.headers['Content-Security-Policy']
      assert_equal 'sandbox allow-downloads allow-popups allow-popups-to-escape-sandbox allow-top-navigation-by-user-activation', csp
      link = Nokogiri::HTML.fragment(response.body).css('a').find { |l| l.text == 'file.txt' }
      assert link, 'the entry is linked'
      assert_equal '_top', link['target']

      # the entry itself is served as before, without top navigation
      get :more_preview, params: {id: a.id, format: 'html', asset: 'dir/file.txt'}
      assert_response :success
      assert_includes response.headers['Content-Disposition'], 'attachment'
    end
  end

  # ours: other html (an uploaded page, Pass) gets no top navigation
  def test_other_html_previews_get_no_top_navigation
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'page.html')
      File.write(path, '<p>page</p>')
      a = attach(path, 'text/html')
      get :more_preview, params: {id: a.id, format: 'html'}
      assert_response :success
      assert_equal 'sandbox allow-downloads allow-popups allow-popups-to-escape-sandbox', response.headers['Content-Security-Policy']
    end
  end

  # ours (after curecodejp 3b8a5ea): Cliff writes every body in UTF-8, an html
  # body without <meta> as well: without the charset in the header a browser
  # read "café" as "cafÃ©" (seen in the round 10 e2e, a Windows-1252 email);
  # Cliff gets no top navigation, its html is the email's
  def test_cliff_html_is_sent_as_utf8_without_top_navigation
    Setting.plugin_redmine_more_previews = SETTINGS.deep_merge(
      'converter' => {'cliff' => {'active' => '1', 'mime_types' => {'eml' => {'active' => '1', 'format' => 'html'}}}}
    )
    Setting.clear_cache
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'w1252.eml')
      File.binwrite(path, "From: a@example.test\r\nTo: b@example.test\r\nSubject: s\r\nMIME-Version: 1.0\r\n" \
                          "Content-Type: text/html; charset=Windows-1252\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n" \
                          "<p>caf=E9 na=EFve =80</p>\r\n")
      a = attach(path, 'message/rfc822')
      get :more_preview, params: {id: a.id, format: 'html'}
      assert_response :success
      assert_equal 'text/html; charset=utf-8', response.headers['Content-Type']
      assert_displayed_as 'café naïve €', response
      assert_equal 'sandbox allow-downloads allow-popups allow-popups-to-escape-sandbox', response.headers['Content-Security-Policy']
    end
  end
end

# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

# port of curecodejp d6a2029 (#57): the headers above an email on its attachment
# page were converted again, in a child process, for every view of the page;
# they are read from the stored conversion now, as the preview frame reads it.
# Ours expect no conversion (upstream: a conversion that raises, which the
# headers already stored would hide), and a test of the order of the boxes.
class CliffCachedFragmentsTest < Redmine::ControllerTest
  include RedmineMorePreviews::TestHelper
  tests AttachmentsController

  fixtures :users, :email_addresses, :projects, :roles, :members, :member_roles,
           :enabled_modules, :issues, :trackers, :issue_statuses, :enumerations,
           :projects_trackers, :attachments

  SOURCE = "From: writer@example.test\r\nTo: reader@example.test\r\nSubject: cached-mail-subject\r\n" \
           "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\ncached mail body\r\n"

  def setup
    set_tmp_attachments_directory
    @old_settings = Setting.plugin_redmine_more_previews
    settings = ZIPPY_SETTINGS.deep_dup
    settings['converter']['cliff'] = {
      'active' => '1', 'mime_types' => {'eml' => {'active' => '1', 'format' => 'html'}}
    }
    Setting.plugin_redmine_more_previews = settings
    Setting.clear_cache
    EnabledModule.find_or_create_by!(project_id: 1, name: 'redmine_more_previews')
    @request.session[:user_id] = 2
    @tmp = Dir.mktmpdir('rmp-cliff-cache')
    @storage = Dir.mktmpdir('rmp-cliff-cache-storage')
    @old_storage = RedmineMorePreviews::Constants::Defaults::MORE_PREVIEWS_STORAGE_PATH
    RedmineMorePreviews::Constants::Defaults.send(:remove_const, :MORE_PREVIEWS_STORAGE_PATH)
    RedmineMorePreviews::Constants::Defaults.const_set(:MORE_PREVIEWS_STORAGE_PATH, @storage)
    path = File.join(@tmp, 'cached.eml')
    File.binwrite(path, SOURCE)
    upload = Rack::Test::UploadedFile.new(path, 'message/rfc822', true)
    @attachment = Attachment.new(container: Issue.find(1), file: upload, author: User.find(2))
    assert @attachment.save
  end

  def teardown
    Setting.plugin_redmine_more_previews = @old_settings
    Setting.clear_cache
    RedmineMorePreviews::Constants::Defaults.send(:remove_const, :MORE_PREVIEWS_STORAGE_PATH)
    RedmineMorePreviews::Constants::Defaults.const_set(:MORE_PREVIEWS_STORAGE_PATH, @old_storage)
    FileUtils.rm_rf(@storage)
    FileUtils.rm_rf(@tmp)
  end

  # port of curecodejp ebe0641 (#63): a stored fragment over 256 KiB is a notice
  # in its place; the email, the other fragments and the page stay, and the
  # fragment requested directly answers 413
  def test_oversized_cached_fragment_stays_local_to_attachment_preview
    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    fields_path = @attachment.preview_assetpath(asset: 'fields.html')
    File.binwrite(fields_path, 'x' * 262_145)

    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    assert_equal 1, response.body.scan('The inline preview exceeds the size limit. Download the file to view it.').length
    assert_select '#preview_repository_entry_top p.nodata', 1
    assert_includes response.body, 'cached-mail-subject'
    assert_not_includes response.body, 'x' * 1000
    assert_select '#preview_pane'
    assert_select 'a[href*="download"]'

    get :more_asset, params: {id: @attachment.id, asset: 'fields', assetformat: 'html'}
    assert_response 413
    assert_equal 'The file is too large to be previewed.', response.body
  end

  def test_transient_fragment_marker_stays_local_to_attachment_preview
    settings = Setting.plugin_redmine_more_previews.deep_dup
    settings['cache_previews'] = '0'
    Setting.plugin_redmine_more_previews = settings
    Setting.clear_cache
    marker = '<!-- redmine_more_previews:cliff_fragment_too_large -->'
    assert_equal marker, RedmineMorePreviews::Conversion::CLIFF_FRAGMENT_TOO_LARGE
    Attachment.any_instance.stubs(:more_asset).with(has_entries(assets: %w[headers.html fields.html attachments.html])).returns(
      ['<p>header visible</p>', marker, '<p>attachments visible</p>']
    )

    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    assert_equal 1, response.body.scan('The inline preview exceeds the size limit. Download the file to view it.').length
    assert_includes response.body, 'header visible'
    assert_includes response.body, 'attachments visible'
    assert_select '#preview_pane'
  end

  # a fragment converted without the cache over the limit: the marker, in the
  # page a notice, directly 413
  def test_transient_oversized_fragment_answers_413_and_notice
    settings = Setting.plugin_redmine_more_previews.deep_dup
    settings['cache_previews'] = '0'
    Setting.plugin_redmine_more_previews = settings
    Setting.clear_cache
    RedmineMorePreviews::Patches::ApplicationHelperPatch.send(:remove_const, :MAX_INLINE_PREVIEW_HTML_BYTES)
    RedmineMorePreviews::Patches::ApplicationHelperPatch.const_set(:MAX_INLINE_PREVIEW_HTML_BYTES, 100)

    get :more_asset, params: {id: @attachment.id, asset: 'headers', assetformat: 'html'}
    assert_response 413

    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    assert_select '#preview_repository_entry_top p.nodata', :minimum => 1
    assert_not_includes response.body, 'cached-mail-subject'
  ensure
    RedmineMorePreviews::Patches::ApplicationHelperPatch.send(:remove_const, :MAX_INLINE_PREVIEW_HTML_BYTES)
    RedmineMorePreviews::Patches::ApplicationHelperPatch.const_set(:MAX_INLINE_PREVIEW_HTML_BYTES, 256 * 1024)
  end

  # port of curecodejp bed742c (#65): a fragment stored (and fetched) before the
  # limit existed keeps its file and mtime, hence its ETag: a browser
  # revalidating it must still get 413, not 304
  def test_conditional_get_of_an_oversized_cached_fragment_answers_413
    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    fields_path = @attachment.preview_assetpath(asset: 'fields.html')
    mtime = File.mtime(fields_path)

    get :more_asset, params: {id: @attachment.id, asset: 'fields', assetformat: 'html'}
    assert_response :success
    etag = response.headers['ETag']
    assert etag.present?

    File.binwrite(fields_path, 'x' * 262_145)
    File.utime(mtime, mtime, fields_path)
    @request.if_none_match = etag
    get :more_asset, params: {id: @attachment.id, asset: 'fields', assetformat: 'html'}
    assert_response 413
  end

  def test_conditional_get_of_a_regular_fragment_stays_not_modified
    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    get :more_asset, params: {id: @attachment.id, asset: 'fields', assetformat: 'html'}
    assert_response :success

    @request.if_none_match = response.headers['ETag']
    get :more_asset, params: {id: @attachment.id, asset: 'fields', assetformat: 'html'}
    assert_response :not_modified
  end

  def test_repeat_attachment_page_reuses_cached_header_and_fields
    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    assert_includes response.body, 'cached-mail-subject'
    assert File.file?(@attachment.preview_filepath)
    assert File.file?(@attachment.preview_assetpath(asset: 'headers.html'))

    # the email has no attachment: attachments.html missing converts nothing either
    Cliff.any_instance.expects(:convert).never
    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    assert_includes response.body, 'cached-mail-subject'
  end

  def test_disabling_cache_keeps_transient_header_rendering
    settings = Setting.plugin_redmine_more_previews.deep_dup
    settings['cache_previews'] = '0'
    Setting.plugin_redmine_more_previews = settings
    Setting.clear_cache

    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    assert_includes response.body, 'cached-mail-subject'
    assert_not File.file?(@attachment.preview_filepath)
    assert_boxes_in_order
  end

  def test_full_cache_still_renders_headers_without_repeated_conversions
    RedmineMorePreviews::Lib::RmpCacheSize.stubs(:full?).returns(true)
    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    assert_includes response.body, 'cached-mail-subject'
    assert_not File.file?(@attachment.preview_filepath)
    assert_boxes_in_order
  end

  def test_full_cache_reuses_an_existing_preview_without_reconversion
    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    assert File.file?(@attachment.preview_assetpath(asset: 'headers.html'))

    RedmineMorePreviews::Lib::RmpCacheSize.stubs(:full?).returns(true)
    Cliff.any_instance.expects(:convert).never
    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    assert_includes response.body, 'cached-mail-subject'
  end

  def test_admin_reload_does_not_display_stale_cached_headers
    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    File.write(@attachment.preview_assetpath(asset: 'headers.html'), 'stale cache header')

    @request.session[:user_id] = 1 # administrator
    User.current = nil
    get :show, params: {id: @attachment.id, filename: @attachment.filename,
                        format: 'html', reload: '1'}
    assert_response :success
    assert_includes response.body, 'cached-mail-subject'
    assert_not_includes response.body, 'stale cache header'
    assert_boxes_in_order
  end

  def test_full_cache_does_not_accept_an_older_marker
    cache_dir = @attachment.preview_dirname
    FileUtils.mkdir_p(cache_dir)
    File.write(@attachment.preview_filepath, 'old cached mail body')
    File.write(@attachment.preview_assetpath(asset: 'headers.html'), 'old header')
    File.write("#{cache_dir}.converter", 'cliff:converter-fixes-v1:normal')
    assert_not RedmineMorePreviews::Conversion.current_cached_preview?(@attachment.preview_filepath, :cliff)

    RedmineMorePreviews::Lib::RmpCacheSize.stubs(:full?).returns(true)
    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    assert_includes response.body, 'cached-mail-subject'
    assert_not_includes response.body, 'old header'
    assert_boxes_in_order
    # Cache is full: the transient conversion must not overwrite the old marker.
    assert_equal 'cliff:converter-fixes-v1:normal', File.read("#{cache_dir}.converter")
  end

  def test_locale_mismatch_does_not_reuse_cached_headers
    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    locale_file = "#{@attachment.preview_dirname}#{Cliff::LOCALE_MARKER}"
    assert_equal I18n.locale.to_s, File.read(locale_file)
    assert_not File.exist?(File.join(@attachment.preview_dirname, Cliff::LOCALE_MARKER)),
               'locale metadata must not appear in extracted mail assets'

    # The cached representation came from a different language. Even when the
    # index and version marker are valid, show the current viewer's headers.
    File.write(locale_file, 'other-locale')
    File.write(@attachment.preview_assetpath(asset: 'headers.html'), 'wrong-language-header')
    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    assert_includes response.body, 'cached-mail-subject'
    assert_not_includes response.body, 'wrong-language-header'
    assert_equal 'other-locale', File.read(locale_file), 'the fallback must not overwrite shared cache'
  end

  def test_older_cliff_cache_marker_is_invalidated
    cache_dir = @attachment.preview_dirname
    FileUtils.mkdir_p(cache_dir)
    File.write(@attachment.preview_filepath, 'old cached mail body')
    File.write(@attachment.preview_assetpath(asset: 'headers.html'), 'old header')
    File.write("#{cache_dir}.converter", 'cliff:converter-fixes-v1:normal')

    get :show, params: {id: @attachment.id, filename: @attachment.filename, format: 'html'}
    assert_response :success
    assert_includes response.body, 'cached-mail-subject'
    assert_not_includes response.body, 'old header'
    assert_equal 'cliff:converter-fixes-v3:normal', File.read("#{cache_dir}.converter")
  end

  # port of curecodejp 6ce4793 (#64), as guards: ours had both since round 8
  # (the |_html, _asset, *data| block, ebe6d6c) and round 6 (the hook rescues
  # ConverterTooLarge with a warning)
  WITH_ATTACHMENT = "From: writer@example.test\r\nTo: reader@example.test\r\nSubject: slot-mail-subject\r\n" \
                    "MIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=b\r\n\r\n" \
                    "--b\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nslot mail body\r\n" \
                    "--b\r\nContent-Type: text/plain; name=slot-attached.txt\r\n" \
                    "Content-Disposition: attachment; filename=slot-attached.txt\r\n\r\nattached\r\n--b--\r\n"

  # the transient conversion yields the body, the (absent) asset and then the
  # three fragments; each must land in its own box, as with a stored preview
  def test_transient_fragments_keep_their_boxes
    settings = Setting.plugin_redmine_more_previews.deep_dup
    settings['cache_previews'] = '0'
    Setting.plugin_redmine_more_previews = settings
    Setting.clear_cache
    attachment = upload_mail('slot.eml', WITH_ATTACHMENT)

    get :show, params: {id: attachment.id, filename: attachment.filename, format: 'html'}
    assert_response :success
    assert_fragment_boxes 'slot-attached.txt'
  end

  def test_cached_fragments_keep_their_boxes
    attachment = upload_mail('slot.eml', WITH_ATTACHMENT)

    get :show, params: {id: attachment.id, filename: attachment.filename, format: 'html'}
    assert_response :success
    assert_fragment_boxes 'slot-attached.txt'
  end

  # an email beyond Cliff's limits answers 413 in the preview frame only; the
  # attachment page stays, with its download link and the reason (upstream: its
  # inline size notice; ours the refusal's own reason, since round 6).
  # More MIME parts than Cliff's default max_parts (1,000)
  MANY_PARTS = "From: writer@example.test\r\nSubject: many parts\r\nMIME-Version: 1.0\r\n" \
               "Content-Type: multipart/mixed; boundary=b\r\n\r\n" +
               (1..1100).map { |i| "--b\r\nContent-Type: text/plain\r\n\r\npart #{i}\r\n" }.join +
               "--b--\r\n"

  def test_email_beyond_limits_keeps_the_attachment_page
    attachment = upload_mail('many-parts.eml', MANY_PARTS)

    2.times do # converted the first time, a remembered failure the second
      get :show, params: {id: attachment.id, filename: attachment.filename, format: 'html'}
      assert_response :success
      assert_select '#preview_repository_entry_top p.warning', :text => 'the email has more than 1000 parts', :count => 1
      assert_select 'a[href*="download"]'
      assert_select '#preview_pane'
    end
  end

  # the transient branch (cache off, admin reload, other locale) gets the limit
  # from the conversion child rather than from a stored failure
  def test_email_beyond_limits_keeps_the_attachment_page_without_cache
    settings = Setting.plugin_redmine_more_previews.deep_dup
    settings['cache_previews'] = '0'
    Setting.plugin_redmine_more_previews = settings
    Setting.clear_cache
    attachment = upload_mail('many-parts.eml', MANY_PARTS)

    get :show, params: {id: attachment.id, filename: attachment.filename, format: 'html'}
    assert_response :success
    assert_select '#preview_repository_entry_top p.warning', :text => 'the email has more than 1000 parts', :count => 1
    assert_select 'a[href*="download"]'
    assert_select '#preview_pane'
    assert_not File.file?(attachment.preview_filepath)
  end

  private

  # the conversion that is not stored yields the preview and the asset slot
  # before the three names: the headers come first and are shown, the fields
  # are folded (upstream's |_html, *data| shifts each one box down)
  def assert_boxes_in_order
    assert_select '#preview_repository_entry_top div.box:not([style]) table.white'
    assert_select '#preview_repository_entry_top div.box[style*="display:none"] table.email.header_fields'
    assert_select '#preview_repository_entry_top div.box[style*="display:none"] table.white', 0
  end

  def upload_mail(name, source)
    path = File.join(@tmp, name)
    File.binwrite(path, source)
    upload = Rack::Test::UploadedFile.new(path, 'message/rfc822', true)
    attachment = Attachment.new(container: Issue.find(1), file: upload, author: User.find(2))
    assert attachment.save
    attachment
  end

  def assert_fragment_boxes(attached_name)
    boxes = css_select('#preview_repository_entry_top div.box')
    assert_equal 3, boxes.size, response.body
    headers, fields, attachments = boxes
    assert headers.at_css('table.white'), 'headers.html belongs in the first box'
    assert_nil headers['id']
    assert fields.at_css('table.email.header_fields'), 'fields.html belongs in the collapsed box'
    assert_match(/display:\s*none/, fields['style'].to_s)
    assert_nil attachments.at_css('table.white')
    assert_nil attachments.at_css('table.email.header_fields')
    assert_includes attachments.text, attached_name
  end
end

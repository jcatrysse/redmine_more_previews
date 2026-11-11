# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

# port of curecodejp 31d1001 (#73): a converted PDF is stored as index.pdf,
# which a browser's PDF viewer offered as the name to save under; it is now
# named after the original. Upstream's tests of html_preview_downloads_test
# (a file that exists only upstream). The conversion is stubbed: these check
# the response headers, without LibreOffice.
class PdfDownloadFilenameTest < Redmine::ControllerTest
  include RedmineMorePreviews::TestHelper
  tests AttachmentsController

  fixtures :users, :email_addresses, :projects, :roles, :members, :member_roles,
           :enabled_modules, :issues, :trackers, :issue_statuses, :enumerations,
           :projects_trackers, :attachments

  def setup
    set_tmp_attachments_directory
    @old_settings = Setting.plugin_redmine_more_previews
    Setting.plugin_redmine_more_previews = ZIPPY_SETTINGS
    Setting.clear_cache
    EnabledModule.create!(project_id: 1, name: 'redmine_more_previews')
    @request.session[:user_id] = 2
  end

  def teardown
    Setting.plugin_redmine_more_previews = @old_settings
    Setting.clear_cache # the writer caches the symbol key; the plugin reads the string key
  end

  def attach(name)
    Dir.mktmpdir do |dir|
      path = File.join(dir, name)
      File.binwrite(path, 'synthetic spreadsheet')
      a = Attachment.new(container: Issue.find(1), author: User.find(2),
                         file: Rack::Test::UploadedFile.new(path, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', true))
      assert a.save
      Attachment.any_instance.stubs(:preview_convertible?).returns(true)
      a
    end
  end

  def test_converted_pdf_uses_original_filename_with_cache
    a = attach('monthly.report.2026.xlsx')
    Attachment.any_instance.stubs(:more_preview).returns('%PDF-1.4 synthetic')

    get :more_preview, params: {id: a.id, format: 'pdf'}
    assert_response :success
    assert_equal 'application/pdf', response.media_type
    assert_includes response.headers['Content-Disposition'], 'monthly.report.2026.pdf'
    assert_not_includes response.headers['Content-Disposition'], 'index.pdf'
  end

  def test_pdf_preview_rename_invalidates_old_etag_and_updates_download_name
    a = attach('previous.xlsx')
    Attachment.any_instance.stubs(:preview_mtime).returns(Time.utc(2026, 11, 5))
    Attachment.any_instance.stubs(:more_preview).returns('%PDF-1.4 synthetic')

    get :more_preview, params: {id: a.id, format: 'pdf'}
    assert_response :success
    old_etag = response.headers['ETag']
    assert old_etag.present?, 'cached preview needs an ETag'
    assert_includes response.headers['Content-Disposition'], 'previous.pdf'

    # a conditional request without changes takes the 304 path
    @request.headers['If-None-Match'] = old_etag
    get :more_preview, params: {id: a.id, format: 'pdf'}
    assert_response :not_modified

    # same bytes and mtime, another name: the old ETag no longer gives a 304
    a.update_columns(filename: 'renamed.xlsx')
    get :more_preview, params: {id: a.id, format: 'pdf'}
    assert_response :success
    assert_not_equal old_etag, response.headers['ETag']
    assert_includes response.headers['Content-Disposition'], 'renamed.pdf'
    assert_not_includes response.headers['Content-Disposition'], 'previous.pdf'
  end

  def test_converted_pdf_uses_original_filename_without_cache
    a = attach('monthly.report.2026.xlsx')
    Setting.plugin_redmine_more_previews = ZIPPY_SETTINGS.merge('cache_previews' => '0')
    Setting.clear_cache
    Attachment.any_instance.stubs(:more_preview).yields('%PDF-1.4 synthetic')

    get :more_preview, params: {id: a.id, format: 'pdf'}
    assert_response :success
    assert_equal 'application/pdf', response.media_type
    assert_includes response.headers['Content-Disposition'], 'monthly.report.2026.pdf'
  end

  # ours: other formats keep the stored name, and their ETag
  def test_other_formats_keep_the_stored_name
    a = attach('monthly.xlsx')
    Attachment.any_instance.stubs(:preview_mtime).returns(Time.utc(2026, 11, 5))
    Attachment.any_instance.stubs(:more_preview).returns('<p>x</p>')

    get :more_preview, params: {id: a.id, format: 'html'}
    assert_response :success
    assert_includes response.headers['Content-Disposition'], 'index.html'
    etag = response.headers['ETag']
    a.update_columns(filename: 'renamed.xlsx')
    @request.headers['If-None-Match'] = etag
    get :more_preview, params: {id: a.id, format: 'html'}
    assert_response :not_modified
  end
end

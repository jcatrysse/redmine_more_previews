# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

# port of curecodejp d6a2029 (#57): the headers above an email on its repository
# page are read from the stored conversion, as on the attachment page.
class CliffRepositoryCachedFragmentsTest < Redmine::ControllerTest
  include RedmineMorePreviews::TestHelper
  tests RepositoriesController

  fixtures :users, :email_addresses, :projects, :roles, :members, :member_roles,
           :enabled_modules, :repositories

  PROJECT_ID = 3

  def setup
    super
    User.current = nil
    @old_enabled_scm = Setting.enabled_scm.dup
    Setting.enabled_scm = @old_enabled_scm + ['Filesystem'] unless @old_enabled_scm.include?('Filesystem')
    @old_settings = Setting.plugin_redmine_more_previews
    settings = ZIPPY_SETTINGS.deep_dup
    settings['converter']['cliff'] = {
      'active' => '1', 'mime_types' => {'eml' => {'active' => '1', 'format' => 'html'}}
    }
    Setting.plugin_redmine_more_previews = settings
    Setting.clear_cache
    EnabledModule.find_or_create_by!(project_id: PROJECT_ID, name: 'redmine_more_previews')
    @repo_dir = Dir.mktmpdir('rmp-cliff-repo')
    File.binwrite(File.join(@repo_dir, 'cached.eml'),
      "From: writer@example.test\r\nTo: reader@example.test\r\nSubject: repo-cache-subject\r\n" \
      "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nrepository body\r\n")
    @repository = Repository::Filesystem.create!(project: Project.find(PROJECT_ID), url: @repo_dir, path_encoding: '')
    @storage = Dir.mktmpdir('rmp-cliff-repo-cache')
    @old_storage = RedmineMorePreviews::Constants::Defaults::MORE_PREVIEWS_STORAGE_PATH
    RedmineMorePreviews::Constants::Defaults.send(:remove_const, :MORE_PREVIEWS_STORAGE_PATH)
    RedmineMorePreviews::Constants::Defaults.const_set(:MORE_PREVIEWS_STORAGE_PATH, @storage)
    @request.session[:user_id] = 1
  end

  def teardown
    super
    Setting.enabled_scm = @old_enabled_scm
    Setting.plugin_redmine_more_previews = @old_settings
    Setting.clear_cache
    RedmineMorePreviews::Constants::Defaults.send(:remove_const, :MORE_PREVIEWS_STORAGE_PATH)
    RedmineMorePreviews::Constants::Defaults.const_set(:MORE_PREVIEWS_STORAGE_PATH, @old_storage)
    FileUtils.rm_rf(@storage)
    FileUtils.rm_rf(@repo_dir)
  end

  def test_repeat_repository_entry_page_uses_cached_header
    entry = {id: PROJECT_ID, repository_id: @repository.id, format: 'html',
             path: repository_path_hash(['cached.eml'])[:param]}
    get :entry, params: entry
    assert_response :success
    assert_includes response.body, 'repo-cache-subject'
    assert File.file?(@repository.preview_filepath('cached.eml', nil))
    assert File.file?(@repository.preview_assetpath('cached.eml', nil, asset: 'headers.html'))

    Cliff.any_instance.expects(:convert).never
    get :entry, params: entry
    assert_response :success
    assert_includes response.body, 'repo-cache-subject'
  end

  def test_admin_reload_does_not_display_stale_repository_headers
    entry = {id: PROJECT_ID, repository_id: @repository.id, format: 'html',
             path: repository_path_hash(['cached.eml'])[:param]}
    get :entry, params: entry
    assert_response :success
    File.write(@repository.preview_assetpath('cached.eml', nil, asset: 'headers.html'), 'stale repository header')

    get :entry, params: entry.merge(reload: '1')
    assert_response :success
    assert_includes response.body, 'repo-cache-subject'
    assert_not_includes response.body, 'stale repository header'
    assert_boxes_in_order
  end

  def test_locale_mismatch_does_not_reuse_repository_headers
    entry = {id: PROJECT_ID, repository_id: @repository.id, format: 'html',
             path: repository_path_hash(['cached.eml'])[:param]}
    get :entry, params: entry
    assert_response :success

    locale_file = "#{@repository.preview_dirname('cached.eml', nil)}#{Cliff::LOCALE_MARKER}"
    assert_equal I18n.locale.to_s, File.read(locale_file)
    assert_not File.exist?(File.join(@repository.preview_dirname('cached.eml', nil), Cliff::LOCALE_MARKER))
    File.write(locale_file, 'other-locale')
    File.write(@repository.preview_assetpath('cached.eml', nil, asset: 'headers.html'), 'wrong-repo-language-header')

    get :entry, params: entry
    assert_response :success
    assert_includes response.body, 'repo-cache-subject'
    assert_not_includes response.body, 'wrong-repo-language-header'
  end

  def test_full_cache_reuses_stored_repository_fragments
    entry = {id: PROJECT_ID, repository_id: @repository.id, format: 'html',
             path: repository_path_hash(['cached.eml'])[:param]}
    get :entry, params: entry
    assert_response :success
    assert File.file?(@repository.preview_assetpath('cached.eml', nil, asset: 'headers.html'))

    RedmineMorePreviews::Lib::RmpCacheSize.stubs(:full?).returns(true)
    Cliff.any_instance.expects(:convert).never
    get :entry, params: entry
    assert_response :success
    assert_includes response.body, 'repo-cache-subject'
  end

  # port of curecodejp ebe0641 (#63), upstream's repositories_more_asset_test on
  # this test's repository: the page and the email stay, the fragment is a notice
  # there and 413 directly
  def test_oversized_cliff_fragment_keeps_repository_page_and_body
    File.binwrite(File.join(@repo_dir, 'fragment.eml'),
      "From: writer@example.test\r\nSubject: preserved\r\nContent-Type: text/plain\r\n\r\nemail body")
    params = {id: PROJECT_ID, repository_id: @repository.id, format: 'html',
              path: repository_path_hash(['fragment.eml'])[:param]}
    get :entry, params: params
    assert_response :success
    fields = @repository.preview_assetpath('fragment.eml', nil, asset: 'fields.html')
    File.binwrite(fields, 'x' * 262_145)

    get :entry, params: params
    assert_response :success
    assert_equal 1, response.body.scan('The inline preview exceeds the size limit. Download the file to view it.').length
    assert_includes response.body, 'preserved'
    assert_not_includes response.body, 'x' * 1000
    assert_select 'h2'

    # more_asset receives the file extension separately from the path
    get :more_asset, params: {id: PROJECT_ID, repository_id: @repository.id,
                              path: repository_path_hash(['fragment'])[:param],
                              baseformat: 'eml', asset: 'fields', assetformat: 'html'}
    assert_response 413
  end

  private

  # the headers come first and are shown, the fields are folded (see
  # CliffCachedFragmentsTest#assert_boxes_in_order)
  def assert_boxes_in_order
    assert_select '#preview_repository_entry_top div.box:not([style]) table.white'
    assert_select '#preview_repository_entry_top div.box[style*="display:none"] table.email.header_fields'
    assert_select '#preview_repository_entry_top div.box[style*="display:none"] table.white', 0
  end
end

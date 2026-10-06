# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class RepositoryPreviewsTest < Redmine::IntegrationTest
  include RedmineMorePreviews::TestHelper

  fixtures :projects, :users, :email_addresses, :user_preferences, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses, :issues, :enumerations

  CONVERTERS = { :teddie => { :txt => :txt }, :mark => { :md => :inline }, :zippy => { :zip => :html }, :cliff => { :eml => :html } }

  def setup
    assert Redmine::Scm::Adapters::GitAdapter.client_available, 'git is needed for the repository previews'
    @dir = Dir.mktmpdir('rmp-repo')
    FileUtils.mkdir_p(File.join(@dir, 'docs'))
    FileUtils.cp(File.join(FILES, 'sample.txt'), File.join(@dir, 'docs'))
    FileUtils.cp(File.join(FILES, 'sample.md'), @dir)
    FileUtils.cp(File.join(FILES, 'sample.zip'), @dir)
    FileUtils.cp(File.join(FILES, 'sample.eml'), @dir)
    git = ->(*args) { system('git', '-C', @dir, *args, exception: true, out: File::NULL, err: File::NULL) }
    git.call('init', '-q', '-b', 'main')
    git.call('add', '.')
    git.call('-c', 'user.name=Test', '-c', 'user.email=test@example.net', 'commit', '-q', '-m', 'samples')
    @project = Project.find(1)
    enable_previews(@project)
    @project.repositories.destroy_all
    @repository = Repository::Git.create!(:project => @project, :url => File.join(@dir, '.git'), :identifier => 'samples', :is_default => true)
    @repository.fetch_changesets
  end

  def teardown
    FileUtils.rm_rf(@dir) if @dir
    FileUtils.rm_rf(File.join(RedmineMorePreviews::Constants::Defaults::MORE_PREVIEWS_STORAGE_PATH, 'repositories'))
  end

  def test_entry_renders_the_preview_page
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/entry/docs/sample.txt'
      assert_response :success
      assert_select '#preview_pane'
    end
  end

  def test_inline_entry_is_rendered_in_the_page
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/entry/sample.md'
      assert_response :success
      assert_select '#preview_repository_entry_top + div em', :text => 'emphasis'
    end
  end

  def test_more_preview_returns_the_conversion
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/preview/docs/sample.txt@/index.txt'
      assert_response :success
      assert_include 'Plain text sample', response.body
    end
  end

  def test_zip_entry_lists_its_files_and_serves_them
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/preview/sample.zip@/index.html'
      assert_response :success
      href = css_select('a[download="hello.txt"]').first&.[]('href')
      assert_equal '/projects/ecookbook/repository/samples/preview/sample.zip@/index.html?asset=inner%2Fhello.txt', href
      get href
      assert_response :success
      assert_equal "hello inner\n", response.body
    end
  end

  def test_mail_entry_shows_the_headers_and_the_body
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/entry/sample.eml'
      assert_response :success
      assert_select '#preview_repository_entry_top .box td', :text => 'Sample mail for the preview'
      get '/projects/ecookbook/repository/samples/preview/sample.eml@/index.html'
      assert_response :success
      assert_include 'this is the body of the sample mail', response.body
    end
  end

  def test_previews_of_two_repositories_with_the_same_identifier_are_kept_apart
    other_dir = Dir.mktmpdir('rmp-repo')
    FileUtils.mkdir_p(File.join(other_dir, 'docs'))
    File.write(File.join(other_dir, 'docs', 'sample.txt'), "Secret of the other project\n")
    git = ->(*args) { system('git', '-C', other_dir, *args, exception: true, out: File::NULL, err: File::NULL) }
    git.call('init', '-q', '-b', 'main')
    git.call('add', '.')
    git.call('-c', 'user.name=Test', '-c', 'user.email=test@example.net', 'commit', '-q', '-m', 'other')
    other = Project.find(2) # jsmith is a manager there too
    enable_previews(other)
    other.repositories.destroy_all
    Repository::Git.create!(:project => other, :url => File.join(other_dir, '.git'), :identifier => 'samples', :is_default => true).fetch_changesets
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/onlinestore/repository/samples/preview/docs/sample.txt@/index.txt'
      assert_include 'Secret of the other project', response.body
      get '/projects/ecookbook/repository/samples/preview/docs/sample.txt@/index.txt'
      assert_response :success
      assert_include 'Plain text sample', response.body
      assert_not_include 'Secret', response.body
    end
  ensure
    FileUtils.rm_rf(other_dir) if other_dir
  end

  def test_a_new_commit_gets_a_new_preview
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/preview/docs/sample.txt@/index.txt'
      assert_include 'Plain text sample', response.body
      File.write(File.join(@dir, 'docs', 'sample.txt'), "Changed text\n")
      system('git', '-C', @dir, '-c', 'user.name=Test', '-c', 'user.email=test@example.net', 'commit', '-q', '-am', 'change', exception: true)
      @repository.fetch_changesets
      get '/projects/ecookbook/repository/samples/preview/docs/sample.txt@/index.txt'
      assert_include 'Changed text', response.body
    end
  end

  def test_entry_falls_back_to_core_when_the_module_is_disabled
    @project.enabled_module_names = @project.enabled_module_names - ['redmine_more_previews']
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/entry/docs/sample.txt'
      assert_response :success
      assert_select '#preview_pane', 0
    end
  end

  def test_more_preview_is_allowed_with_browse_repository_alone
    # entry needs browse_repository; its preview frame must not need more
    Role.find(1).remove_permission!(:view_changesets)
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/preview/docs/sample.txt@/index.txt'
      assert_response :success
    end
  end

  def test_more_preview_needs_a_repository_permission
    Role.find(1).remove_permission!(:view_changesets)
    Role.find(1).remove_permission!(:browse_repository)
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/preview/docs/sample.txt@/index.txt'
      assert_response :forbidden
    end
  end

  def test_asset_outside_the_preview_directory_is_refused
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/entry/sample.zip', :params => { :asset => '../../../../../../../../../../etc/passwd' }
      assert_response :not_found
      assert_not_include 'root:', response.body
      get '/projects/ecookbook/repository/samples/preview/sample.zip@/index.html', :params => { :asset => '/etc/passwd' }
      assert_response :not_found
      assert_not_include 'root:', response.body
    end
  end
end

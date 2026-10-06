# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class AttachmentPreviewsTest < Redmine::IntegrationTest
  include RedmineMorePreviews::TestHelper

  fixtures :projects, :users, :email_addresses, :user_preferences, :members, :member_roles, :roles,
           :enabled_modules, :trackers, :projects_trackers, :issue_statuses, :issues, :enumerations

  CONVERTERS = {
    :teddie => { :txt => :txt },
    :mark   => { :md => :html, :textile => :inline },
    :zippy  => { :zip => :html, :tar => :inline, :tgz => :html },
    :vince  => { :vcf => :html },
    :cliff  => { :eml => :html },
    :pass   => { :html => :html }
  }

  def setup
    set_tmp_attachments_directory
    @project = Project.find(1)
    enable_previews(@project)
    @issue = Issue.find(1)
  end

  def teardown
    remove_preview_attachments
  end

  def test_show_renders_the_preview_page_when_the_module_is_enabled
    attachment = preview_attachment(@issue, 'sample.txt')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/#{attachment.id}"
      assert_response :success
      assert_select "#preview_pane [data='/attachments/more_preview/#{attachment.id}/index.txt']"
    end
  end

  def test_show_falls_back_to_core_when_the_module_is_disabled
    @project.enabled_module_names = @project.enabled_module_names - ['redmine_more_previews']
    attachment = preview_attachment(@issue, 'sample.txt')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/#{attachment.id}"
      assert_response :success
      assert_select '#preview_pane', 0
      assert_select '.filecontent', 1
    end
  end

  def test_show_falls_back_to_core_when_no_converter_is_active
    attachment = preview_attachment(@issue, 'sample.txt')
    with_converters({}) do
      log_user('jsmith', 'jsmith')
      get "/attachments/#{attachment.id}"
      assert_response :success
      assert_select '#preview_pane', 0
    end
  end

  def test_more_preview_returns_the_conversion
    attachment = preview_attachment(@issue, 'sample.txt')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.txt"
      assert_response :success
      assert_equal 'text/plain', response.media_type
      assert_include 'Plain text sample', response.body
    end
  end

  def test_more_preview_of_a_file_without_converter_is_404
    attachment = preview_attachment(@issue, 'sample.csv')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response :not_found
    end
  end

  def test_more_preview_of_a_private_project_is_refused_to_non_members
    attachment = preview_attachment(Issue.find(4), 'sample.txt') # issue 4 is in the private project 2
    with_converters(CONVERTERS) do
      log_user('dlopper', 'foo')
      get "/attachments/more_preview/#{attachment.id}/index.txt"
      assert_response :forbidden
      get "/attachments/#{attachment.id}"
      assert_response :forbidden
      reset!
      get "/attachments/more_preview/#{attachment.id}/index.txt"
      assert_response :unauthorized # anonymous, non-HTML format
    end
  end

  def test_markdown_preview
    attachment = preview_attachment(@issue, 'sample.md')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response :success
      assert_include '<em>emphasis</em>', response.body
    end
  end

  def test_vcard_preview
    attachment = preview_attachment(@issue, 'sample.vcf')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response :success
      assert_include 'John Doe', response.body
    end
  end

  def test_mail_preview
    attachment = preview_attachment(@issue, 'sample.eml')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response :success
      assert_include 'this is the body of the sample mail', response.body
    end
  end

  def test_zip_table_and_top_level_asset
    attachment = preview_attachment(@issue, 'sample.zip')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response :success
      assert_include 'top.txt', response.body
      get "/attachments/more_preview/#{attachment.id}/index.html", :params => { :asset => 'top.txt' }
      assert_response :success
      assert_equal "top level\n", response.body
    end
  end

  def test_tgz_asset
    attachment = preview_attachment(@issue, 'sample.tgz')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.html", :params => { :asset => 'inner/hello.txt' }
      assert_response :success
      assert_equal "hello inner\n", response.body
    end
  end

  def test_admin_info_lists_the_converter_checks
    with_converters(CONVERTERS) do
      log_user('admin', 'admin')
      get '/admin/info'
      assert_response :success
      assert_include I18n.t(:text_pandoc_available), response.body
    end
  end

  def test_plugin_settings_page
    with_converters(CONVERTERS) do
      log_user('admin', 'admin')
      get '/settings/plugin/redmine_more_previews'
      assert_response :success
      assert_select 'input[name=?][checked=checked]', 'settings[converter][zippy][active]'
      assert_select 'select[name=?]', 'settings[converter][libre][mime_types][docx][format]'
    end
  end
end

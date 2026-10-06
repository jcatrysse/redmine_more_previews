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

  def test_more_preview_without_format_is_404
    attachment = preview_attachment(@issue, 'sample.txt')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      # the plugin always links a format; without one the file came back as application/octet-stream
      get "/attachments/more_preview/#{attachment.id}/index"
      assert_response :not_found
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

  def test_asset_outside_the_preview_directory_is_refused
    attachment = preview_attachment(@issue, 'sample.txt')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      secret = Rails.root.join('config', 'database.yml').relative_path_from(Pathname.new(attachment.preview_dirname))
      get "/attachments/more_preview/#{attachment.id}/index.txt", :params => { :asset => secret.to_s }
      assert_response :not_found
      assert_not_include 'adapter', response.body
      get "/attachments/more_preview/#{attachment.id}/index.txt", :params => { :asset => '/etc/passwd' }
      assert_response :not_found
      get "/attachments/more_preview/#{attachment.id}/#{secret.to_s.delete_suffix('.yml')}.yml"
      assert_response :not_found
      assert_not_include 'adapter', response.body
    end
  end

  def test_html_previews_and_assets_are_sandboxed
    attachment = preview_attachment(@issue, 'sample.html')
    zip = preview_attachment(@issue, 'sample.zip')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response :success
      assert_match /(\A|;\s*)sandbox\b/, response.headers['Content-Security-Policy']
      assert_not_include 'allow-scripts', response.headers['Content-Security-Policy']
      assert_not_include 'allow-same-origin', response.headers['Content-Security-Policy']
      assert_equal 'nosniff', response.headers['X-Content-Type-Options']
      get "/attachments/more_preview/#{zip.id}/top.txt"
      assert_response :success
      assert_match /(\A|;\s*)sandbox\b/, response.headers['Content-Security-Policy']
    end
  end

  def test_pdf_previews_are_not_sandboxed
    # Chrome does not render a PDF in a sandboxed document
    attachment = preview_attachment(@issue, 'sample.pdf')
    with_converters(:peek => { :pdf => :pdf }) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.pdf"
      assert_response :success
      assert_equal 'application/pdf', response.media_type
      assert_nil response.headers['Content-Security-Policy']
    end
  end

  def test_inline_previews_are_sanitized
    attachment = preview_attachment(@issue, 'evil.md', "# Title\n\n<script>alert(1)</script>\n\n<img src=\"x\" onerror=\"alert(2)\">\n\n| a | b |\n|---|---|\n| 1 | 2 |\n")
    with_converters(:mark => { :md => :inline }) do
      log_user('jsmith', 'jsmith')
      get "/attachments/#{attachment.id}"
      assert_response :success
      assert_select '#preview_repository_entry_top + div h1', :text => 'Title'
      assert_select '#preview_repository_entry_top + div table td', :text => '2'
      assert_select '#preview_repository_entry_top + div script', 0
      assert_select '#preview_repository_entry_top + div img[onerror]', 0
      assert_not_include '<script>alert(1)', response.body
    end
  end

  def test_textile_inline_preview
    attachment = preview_attachment(@issue, 'sample.textile')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/#{attachment.id}"
      assert_response :success
      assert_select '#preview_repository_entry_top + div h1', :text => 'Textile sample'
    end
  end

  def test_mail_with_one_cc_shows_the_cc
    mail = File.read(File.join(FILES, 'sample.eml')).sub("To: Bob Example <bob@example.net>\n", "To: Bob Example <bob@example.net>\nCc: carol@example.net\n")
    attachment = preview_attachment(@issue, 'cc.eml', mail)
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/#{attachment.id}"
      assert_response :success
      assert_select '#preview_repository_entry_top .box td', :text => 'carol@example.net'
    end
  end

  def test_plain_text_mail_body_is_escaped
    mail = File.read(File.join(FILES, 'sample.eml')).sub('this is the body', '<b>bold</b> <script>alert(1)</script> this is the body')
    attachment = preview_attachment(@issue, 'tags.eml', mail)
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response :success
      assert_include '&lt;b&gt;bold&lt;/b&gt;', response.body
      assert_not_include '<script>', response.body
    end
  end

  def test_mail_headers_are_escaped_on_the_preview_page
    mail = File.read(File.join(FILES, 'sample.eml')).sub('Subject: Sample mail for the preview', 'Subject: <img src="x" onerror="alert(1)"> hello')
    attachment = preview_attachment(@issue, 'subject.eml', mail)
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/#{attachment.id}"
      assert_response :success
      assert_select 'img[onerror]', 0
      assert_include '&lt;img src="x" onerror="alert(1)"&gt; hello', response.body
    end
  end

  def test_zip_folder_names_are_escaped
    zip = Zip::OutputStream.write_buffer do |out|
      out.put_next_entry('<img src=x onerror=alert(1)>/')
      out.put_next_entry('<img src=x onerror=alert(1)>/a.txt')
      out.write 'a'
    end.string
    attachment = preview_attachment(@issue, 'names.zip', zip)
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response :success
      assert_not_include '<img', response.body
    end
  end

  def test_preview_page_does_not_use_the_removed_jquery_load_handler
    attachment = preview_attachment(@issue, 'sample.txt')
    with_converters(CONVERTERS, 'embedding' => '1') do # iframe
      log_user('jsmith', 'jsmith')
      get "/attachments/#{attachment.id}"
      assert_response :success
      assert_select 'iframe#preview_frame'
      # jQuery 3 removed .load(handler): "e.indexOf is not a function" on every preview page
      assert_not_include ".load(function", response.body
      assert_include "$('#preview_frame').on('load', function", response.body
    end
  end

  def test_preview_page_icons
    attachment = preview_attachment(@issue, 'sample.eml')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/#{attachment.id}"
      assert_response :success
      if Redmine::VERSION::MAJOR >= 6 # SVG sprite icons replaced the icon-* CSS
        assert_select 'a.icon-reload svg use[href*=?]', 'icon--reload'
        assert_select 'a.icon-warning svg use[href*=?]', 'icon--warning'
      else
        assert_select 'a.icon-reload', :text => I18n.t(:button_update)
      end
    end
  end

  def test_zip_links_to_files_in_folders_are_encoded_once
    attachment = preview_attachment(@issue, 'sample.zip')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response :success
      href = css_select('a[download="hello.txt"]').first['href']
      assert_equal "/attachments/more_preview/#{attachment.id}/index.html?asset=inner%2Fhello.txt", href
      get href
      assert_response :success
      assert_equal "hello inner\n", response.body
    end
  end

  def test_vcard_preview_links_only_existing_stylesheets
    attachment = preview_attachment(@issue, 'sample.vcf')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response :success
      assert_not_include 'jquery-ui-1.11.0', response.body
      assert_not_include 'tribute-3.7.3', response.body
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

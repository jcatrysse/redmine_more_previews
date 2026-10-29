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

  # another plugin's prepend on a core filter is honoured by the plugin's actions
  module SpyOnFindAttachment
    mattr_accessor :calls, default: 0
    def find_attachment
      SpyOnFindAttachment.calls += 1
      super
    end
  end
  AttachmentsController.prepend(SpyOnFindAttachment)

  def test_more_preview_runs_core_filters_through_other_plugins_prepends
    attachment = preview_attachment(@issue, 'sample.txt')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      SpyOnFindAttachment.calls = 0
      get "/attachments/more_preview/#{attachment.id}/index.txt"
      assert_response :success
      assert_equal 1, SpyOnFindAttachment.calls
    end
  end

  def test_after_the_hand_over_core_previews_pdf_and_the_plugin_keeps_office
    pdf = preview_attachment(@issue, 'sample.pdf')
    md = preview_attachment(@issue, 'sample.md')
    eml = preview_attachment(@issue, 'sample.eml')
    with_converters(CONVERTERS.merge(:peek => { :pdf => :pdf })) do
      RedmineMorePreviews::CoreHandover.apply!
      log_user('jsmith', 'jsmith')
      get "/attachments/#{pdf.id}"
      assert_response :success
      assert_select '#preview_pane', 0
      get "/attachments/#{md.id}"
      assert_select '#preview_pane', 0
      assert_select '.filecontent.wiki h1', :text => 'Markdown sample' # core's markdown preview
      get "/attachments/#{eml.id}"
      assert_select '#preview_pane'
    end
  end

  def test_maggie_still_converts_a_png_and_a_pdf
    png = preview_attachment(@issue, 'sample.png')
    pdf = preview_attachment(@issue, 'sample.pdf')
    with_converters(:maggie => { :png => :jpg, :pdf => :png }) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{png.id}/index.jpg"
      assert_response :success
      assert response.body.b.start_with?("\xFF\xD8".b), 'a JPEG'
      skip 'Ghostscript is not available' unless Redmine::Thumbnail.gs_available?
      get "/attachments/more_preview/#{pdf.id}/index.png"
      assert_response :success
      assert response.body.b.start_with?("\x89PNG".b), 'a PNG of the first page'
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

  TWO_PARTS = "Subject: big\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=\"b\"\r\n\r\n" \
              "--b\r\nContent-Type: text/plain\r\n\r\nfirst\r\n--b\r\nContent-Type: text/plain\r\n\r\nsecond\r\n--b--\r\n"

  # upstream 6b27fe7 (#38): an email beyond Cliff's limits is answered with 413,
  # not stored as a preview; the body and the page say why, in the user's language
  def test_mail_beyond_the_limits_is_answered_with_413_and_its_reason
    attachment = preview_attachment(@issue, 'too-many.eml', TWO_PARTS)
    cliff = CONVERTERS.slice(:cliff)
    with_converters(cliff) do
      settings = Setting.plugin_redmine_more_previews
      settings['converter']['cliff']['max_parts'] = '1'
      Setting.plugin_redmine_more_previews = settings
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response 413
      assert_equal I18n.t(:'redmine_more_previews.cliff.text_refused_parts', :count => 1, :locale => :en), response.body
      assert_not File.exist?(attachment.preview_filepath(:format => 'html'))
      # remembered: refused again at once, without converting, with its reason
      # (own review: it was the generic text until the failure was forgotten)
      Cliff.any_instance.expects(:eml).never
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response 413
      assert_equal I18n.t(:'redmine_more_previews.cliff.text_refused_parts', :count => 1, :locale => :en), response.body

      Cliff.any_instance.unstub(:eml)

      # and in the language of the next viewer; the page's header boxes convert
      # on their own (as before) and say why
      User.find(2).update!(:language => 'de')
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response 413
      assert_equal I18n.t(:'redmine_more_previews.cliff.text_refused_parts', :count => 1, :locale => :de), response.body
      get "/attachments/#{attachment.id}"
      assert_response :success
      assert_select '#content p.warning', :text => I18n.t(:'redmine_more_previews.cliff.text_refused_parts', :count => 1, :locale => :de)
      assert_select '#preview_pane'
    end
  end

  # a remembered refusal that is not one of the plugin's translations with
  # numbers (the failure files are on disk) is the generic refusal
  def test_remembered_refusal_is_only_a_translation_with_numbers
    failures = RedmineMorePreviews::Lib::RmpFailures
    assert_kind_of RedmineMorePreviews::Exceptions::ConverterRefused,
                   failures.refusal('refused:{"key":"redmine_more_previews.cliff.text_refused_parts","values":{"count":3}}')
    ['refused:{"key":"label_user_plural","values":{}}',
     'refused:{"key":"redmine_more_previews.cliff.text_refused_parts","values":{"count":"<b>x</b>"}}',
     'refused:not json', 'too_large'].each do |reason|
      assert_nil failures.refusal(reason), reason
    end
  end

  def test_mail_within_the_limits_is_still_previewed
    attachment = preview_attachment(@issue, 'sample.eml')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/#{attachment.id}"
      assert_response :success
      assert_select '#content p.warning', 0
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response :success
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

  # upstream 9e8df9d, 048837b: the module switches the direct URLs off as well
  def test_disabled_project_module_blocks_previews_and_assets
    attachment = preview_attachment(@issue, 'sample.zip')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      @project.enabled_module_names = @project.enabled_module_names - ['redmine_more_previews']
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response :not_found
      get "/attachments/more_preview/#{attachment.id}/index.html", :params => { :asset => 'top.txt' }
      assert_response :not_found
      get "/attachments/more_preview/#{attachment.id}/top.txt"
      assert_response :not_found
      assert_not_include 'top level', response.body

      enable_previews(@project)
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response :success
      assert_include 'top.txt', response.body
      get "/attachments/more_preview/#{attachment.id}/top.txt"
      assert_response :success
      assert_equal "top level\n", response.body
    end
  end

  # the module check comes after the visibility check: no 404 tells a
  # non-member that the attachment exists
  def test_attachment_one_cannot_see_stays_forbidden_with_the_module_off
    private_project = Project.find(2)
    private_project.enabled_module_names = private_project.enabled_module_names - ['redmine_more_previews']
    attachment = preview_attachment(Issue.find(4), 'sample.zip') # issue 4 is in the private project 2
    with_converters(CONVERTERS) do
      log_user('dlopper', 'foo')
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response :forbidden
    end
  end

  # upstream 35fdcb6, 554a683: a browser that kept the ETag of the preview in the
  # other debug mode (or of one stored before the cache format changed) gets the
  # preview again, not a 304 for what it holds
  def test_etag_of_the_other_debug_mode_is_not_answered_with_304
    attachment = preview_attachment(@issue, 'sample.txt')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      # the first request converts: its ETag carries the time before the conversion
      2.times { get "/attachments/more_preview/#{attachment.id}/index.txt" }
      assert_response :success
      etag = response.headers['ETag']
      get "/attachments/more_preview/#{attachment.id}/index.txt", :headers => { 'If-None-Match' => etag }
      assert_response :not_modified
      Setting.plugin_redmine_more_previews = Setting.plugin_redmine_more_previews.merge('debug' => '1')
      # the setter clears the cache under the symbol, Converter.debug? reads the
      # string key; a request clears the whole cache only if the setting's
      # updated_on (whole seconds) is not before the last clear
      Setting.clear_cache
      get "/attachments/more_preview/#{attachment.id}/index.txt", :headers => { 'If-None-Match' => etag }
      assert_response :success
      assert_include 'Converter debug information', response.body
      assert_not_include @project.identifier, response.body
    end
  end

  # upstream 128e9db (#35): as core's show and download, a file missing on disk
  # is not found for every preview endpoint, and nothing is converted
  def test_missing_disk_file_is_not_found_by_all_preview_endpoints
    attachment = preview_attachment(@issue, 'sample.zip')
    File.delete(attachment.diskfile)
    assert_not attachment.readable?
    Zippy.any_instance.expects(:convert).never
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.html"
      assert_response :not_found
      get "/attachments/more_preview/#{attachment.id}/index.html", :params => { :asset => 'top.txt' }
      assert_response :not_found
      get "/attachments/more_preview/#{attachment.id}/top.txt"
      assert_response :not_found
      reset!
      # reload and unsafe skip the cache, for administrators
      log_user('admin', 'admin')
      get "/attachments/more_preview/#{attachment.id}/index.html", :params => { :unsafe => '1' }
      assert_response :not_found
      get "/attachments/more_preview/#{attachment.id}/top.txt", :params => { :reload => '1' }
      assert_response :not_found
      get "/attachments/#{attachment.id}"
      assert_response :not_found
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

  # an inline preview is converted with the page's query: a key named as a converter
  # attribute must not set it (timeout=x raised ConverterWrongArgument, a 500)
  def test_inline_preview_ignores_converter_attributes_in_the_query
    attachment = preview_attachment(@issue, 'sample.textile')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/#{attachment.id}", :params => { :timeout => 'x', :threadsafe => 'x', :shell_api => 'x' }
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

  # upstream 2bec017, 9e2c960: the labels of the header box stay on one line
  # (a German "Betreff" broke over two lines in a 5% wide cell)
  def test_mail_header_labels_stay_on_one_line
    attachment = preview_attachment(@issue, 'sample.eml')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/#{attachment.id}"
      assert_response :success
      labels = css_select('#preview_repository_entry_top .box td[style*="font-weight"]')
      assert_operator labels.size, :>=, 4
      labels.each { |td| assert_includes td['style'].to_s.delete(' '), 'white-space:nowrap', td.text }
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

  # reload and unsafe are for administrators only (Jan 2026-10-12, port of curecodejp 03f140f)
  def test_preview_page_icons
    attachment = preview_attachment(@issue, 'sample.eml')
    with_converters(CONVERTERS) do
      log_user('admin', 'admin')
      get "/attachments/#{attachment.id}"
      assert_response :success
      assert_select 'a.icon-reload svg use[href*=?]', 'icon--reload'
      assert_select 'a.icon-warning svg use[href*=?]', 'icon--warning'
    end
  end

  def test_reload_and_unsafe_links_are_not_shown_to_other_users
    attachment = preview_attachment(@issue, 'sample.eml')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/#{attachment.id}"
      assert_response :success
      assert_select '#preview_pane'
      assert_select 'a.icon-reload', 0
      assert_select 'a.icon-warning', 0
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

  # the listing is stored and shown to everyone: query keys of the first request that
  # are url options (script_name, anchor) or reload must not reach its links
  def test_zip_links_are_built_from_the_route_only
    attachment = preview_attachment(@issue, 'sample.zip')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.html",
          :params => { :script_name => '//evil.example', :anchor => 'x', :reload => '1' }
      assert_response :success
      href = css_select('a[download="hello.txt"]').first['href']
      assert_equal "/attachments/more_preview/#{attachment.id}/index.html?asset=inner%2Fhello.txt", href
      assert_not_include 'evil.example', response.body
    end
  end

  def test_empty_asset_parameter_is_no_asset
    attachment = preview_attachment(@issue, 'sample.zip')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.html", :params => { :asset => '' }
      assert_response :success
      assert_select 'a[download="hello.txt"]'
    end
  end

  # without the cache an asset is converted for each request: a missing entry is a 404
  def test_missing_asset_without_the_cache_is_not_found
    attachment = preview_attachment(@issue, 'sample.zip')
    with_converters(CONVERTERS, 'cache_previews' => '0') do
      log_user('jsmith', 'jsmith')
      get "/attachments/more_preview/#{attachment.id}/index.html", :params => { :asset => 'inner/hello.txt' }
      assert_response :success
      assert_equal "hello inner\n", response.body
      get "/attachments/more_preview/#{attachment.id}/index.html", :params => { :asset => 'no/such.txt' }
      assert_response :not_found
    end
  end

  # Cliff's headers above an email are converted while its page is rendered: no free
  # conversion slot leaves them out, the page itself is shown (it was a bare 503)
  def test_email_page_is_shown_when_the_conversions_are_busy
    attachment = preview_attachment(@issue, 'sample.eml')
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      RedmineMorePreviews::Conversion.any_instance.stubs(:with_slot).raises(RedmineMorePreviews::Exceptions::ConverterLockTimeOut, 'busy')
      get "/attachments/#{attachment.id}"
      assert_response :success
      assert_select '#preview_pane'
      assert_select '#preview_repository_entry_top .box', 0
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

  # upstream cef06a3: without a working bubblewrap sandbox Libre converts
  # nothing, there is no fallback to an unsandboxed LibreOffice
  def test_libre_without_a_working_sandbox_converts_nothing
    attachment = preview_attachment(@issue, 'sample.docx')
    real = File.method(:executable?)
    File.stubs(:executable?).with { |path| path != Libre::BWRAP_BIN && real.call(path) }.returns(true)
    File.stubs(:executable?).with(Libre::BWRAP_BIN).returns(false)
    Libre.any_instance.expects(:command).never
    with_converters(:libre => { :docx => :pdf }) do
      log_user('admin', 'admin')
      get "/attachments/more_preview/#{attachment.id}/index.pdf"
      assert_response :not_found
      get '/admin/info'
      assert_response :success
      assert_select 'tr', :text => /#{Regexp.escape(I18n.t(:text_libre_office_available))}/ do
        assert_select 'td.tick span.icon-error'
      end
    end
  end

  # upstream 0baa6a7: no raster icons behind .icon-file on Redmine 7. Core draws
  # its file icons as SVG and has no background rules for .icon any more, so the
  # plugin's icon tiled over the names (repository browser, Cliff's attachment links)
  def test_pages_carry_no_raster_file_icon_css
    # with redmine_view_issue_description an issue needs its permission (GEOxyz set)
    if Redmine::Plugin.installed?(:redmine_view_issue_description)
      Role.find(1).add_permission!(:view_issue_description)
    end
    with_converters(:libre => { :docx => :pdf, :xlsx => :html }) do
      log_user('jsmith', 'jsmith')
      get "/issues/#{@issue.id}"
      assert_response :success
      assert_no_match(/\.icon-file\.[^{]*\{\s*background-image/, response.body)
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

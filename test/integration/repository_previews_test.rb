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
    FileUtils.rm_rf(File.join(RedmineMorePreviews::Constants::Defaults::MORE_PREVIEWS_STORAGE_PATH, 'repository'))
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

  # port of curecodejp dc493bc (#62): converted html over 256 KiB is not stored,
  # sanitized or embedded; the entry page stays and says why (before: the html
  # was sanitized in the worker and embedded)
  def test_inline_entry_over_the_inline_limit_leaves_a_notice
    File.write(File.join(@dir, 'big.md'), "*big* " + ('word ' * 60_000))
    system('git', '-C', @dir, 'add', 'big.md', exception: true, out: File::NULL, err: File::NULL)
    system('git', '-C', @dir, '-c', 'user.name=Test', '-c', 'user.email=test@example.net', 'commit', '-q', '-m', 'big',
           exception: true, out: File::NULL, err: File::NULL)
    @repository.fetch_changesets
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/entry/big.md'
      assert_response :success
      assert_select '#preview_repository_entry_top + div p.nodata',
                    :text => 'The inline preview exceeds the size limit. Download the file to view it.'
      assert_select '#preview_repository_entry_top + div em', 0
      assert_empty Dir.glob(File.join(RedmineMorePreviews::Constants::Defaults::MORE_PREVIEWS_STORAGE_PATH, 'repository', '**', 'big.md', '**', 'index.inline'))
      # remembered: the next view is answered at once, with the same notice
      get '/projects/ecookbook/repository/samples/entry/big.md'
      assert_response :success
      assert_select '#preview_repository_entry_top + div p.nodata',
                    :text => 'The inline preview exceeds the size limit. Download the file to view it.'
    end
  end

  # port of curecodejp 77ce987 (#70): html over the parser's limits leaves the
  # entry page with a notice (upstream's stub on a Filesystem repository; ours
  # on the git repository of this test)
  def test_inline_entry_over_the_parser_limit_leaves_a_notice
    with_converters(CONVERTERS) do
      Repository::Git.any_instance.stubs(:more_preview).returns('<div>' * 500 + 'x' + '</div>' * 500)
      # the HTML5 vendor raises on this (Redmine 7 keeps HTML4, see inline_preview_limit_test)
      ActionView::Base.stubs(:safe_list_sanitizer).returns(Rails::HTML5::SafeListSanitizer.new)
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/entry/sample.md'
      assert_response :success
      assert_select '#preview_repository_entry_top + div p.nodata',
                    :text => 'The inline preview is too complex to display. Download the file to view it.'
      assert_select 'h2'
    end
  end

  # port of curecodejp 31d1001 (#73): a converted PDF of a repository file is
  # named after the file (upstream's test on a Filesystem repository; the
  # conversion stubbed, no LibreOffice)
  def test_converted_pdf_uses_the_name_of_the_repository_file
    name = 'monthly.report.2026.xlsx'
    File.binwrite(File.join(@dir, name), 'synthetic spreadsheet')
    system('git', '-C', @dir, 'add', name, exception: true, out: File::NULL, err: File::NULL)
    system('git', '-C', @dir, '-c', 'user.name=Test', '-c', 'user.email=test@example.net', 'commit', '-q', '-m', 'xlsx',
           exception: true, out: File::NULL, err: File::NULL)
    @repository.fetch_changesets
    with_converters(CONVERTERS) do
      Redmine::Scm::Adapters::Entry.any_instance.stubs(:convertible?).returns(true)
      Repository::Git.any_instance.stubs(:more_preview).returns('%PDF-1.4 synthetic')
      log_user('jsmith', 'jsmith')
      get "/projects/ecookbook/repository/samples/preview/#{name}@/index.pdf"
      assert_response :success
      assert_equal 'application/pdf', response.media_type
      assert_includes response.headers['Content-Disposition'], 'monthly.report.2026.pdf'
      assert_not_includes response.headers['Content-Disposition'], 'index.pdf'
    end
  end

  # port of curecodejp 64315f4 (#77), upstream's repository test on our git
  # repository: an entry of the listing's name is served, the listing stays
  def test_zip_entry_named_as_the_listing_is_served_and_the_listing_stays
    Dir.mktmpdir do |tmp|
      build_zip(File.join(tmp, 'b.zip'), 'index.html' => 'the entry')
      FileUtils.cp(File.join(tmp, 'b.zip'), @dir)
    end
    system('git', '-C', @dir, 'add', 'b.zip', exception: true, out: File::NULL, err: File::NULL)
    system('git', '-C', @dir, '-c', 'user.name=Test', '-c', 'user.email=test@example.net', 'commit', '-q', '-m', 'b',
           exception: true, out: File::NULL, err: File::NULL)
    @repository.fetch_changesets
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/preview/b.zip@/index.html'
      assert_response :success
      assert_select 'a', text: 'index.html'

      get '/projects/ecookbook/repository/samples/preview/b.zip@/index.html', params: { asset: 'index.html' }
      assert_response :success
      assert_equal 'the entry', response.body
      assert_includes response.headers['Content-Disposition'], 'attachment'


      get '/projects/ecookbook/repository/samples/preview/b.zip@/index.html'
      assert_select 'a', text: 'index.html'
    end
  end

  # port of curecodejp e1a2d25 (#76), on our git repository
  def test_image_preview_has_a_message_for_when_it_fails_to_load
    with_converters(CONVERTERS) do
      RedmineMorePreviews::Converter.stubs(:conversion_ext).returns('png')
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/entry/docs/sample.txt'
      assert_response :success
      assert_select 'img[onerror]', 1
      assert_select 'img[onerror] + p.nodata[style*="display:none"]', :text => I18n.t(:text_more_previews_image_failed), :count => 1
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

  def test_zip_links_keep_the_revision_and_no_other_query_key
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      rev = @repository.changesets.first.revision
      get '/projects/ecookbook/repository/samples/preview/sample.zip@/index.html', :params => { :rev => rev, :script_name => '//evil.example' }
      assert_response :success
      href = css_select('a[download="hello.txt"]').first&.[]('href')
      assert_equal "/projects/ecookbook/repository/samples/#{rev}/preview/sample.zip@/index.html?asset=inner%2Fhello.txt", href
      assert_not_include 'evil.example', response.body
    end
  end

  # Cliff lists an email's attachments with a link once they are stored
  def test_asset_link_of_a_stored_asset
    path = File.join(@repository.preview_dirname('sample.eml', nil, :format => @repository.preview_format('sample.eml', nil)), 'note.txt')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, 'stored')
    html = @repository.asset_link('sample.eml', nil, 'note.txt')
    assert_include 'note.txt', html
    assert_include 'text-plain', html
  end

  # upstream a213a44 (#36): the link of an asset in a folder kept only its name
  def test_asset_link_of_a_stored_asset_in_a_folder
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/preview/sample.zip@inner/hello.txt'
      assert_response :success
      html = @repository.asset_link('sample.zip', nil, 'inner/hello.txt')
      href = Nokogiri::HTML.fragment(html).at_css('a')['href']
      assert_equal 'inner/hello', Array(Rails.application.routes.recognize_path(href)[:asset]).join('/')
      get href
      assert_response :success, href
      assert_equal "hello inner\n", response.body
      assert_equal '', @repository.asset_link('sample.zip', nil, 'inner/missing.txt')
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

  # upstream 3b1b73a, d15b781: "Browse repository" does not override the module
  def test_disabled_project_module_blocks_preview_and_asset
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      @project.enabled_module_names = @project.enabled_module_names - ['redmine_more_previews']
      get '/projects/ecookbook/repository/samples/preview/docs/sample.txt@/index.txt'
      assert_response :not_found
      get '/projects/ecookbook/repository/samples/preview/sample.zip@inner/hello.txt'
      assert_response :not_found
      assert_not_include 'hello inner', response.body

      enable_previews(@project)
      get '/projects/ecookbook/repository/samples/preview/docs/sample.txt@/index.txt'
      assert_response :success
      assert_include 'Plain text sample', response.body
      get '/projects/ecookbook/repository/samples/preview/sample.zip@inner/hello.txt'
      assert_response :success
      assert_equal "hello inner\n", response.body
    end
  end

  # upstream 6b27fe7 (#38): an email beyond Cliff's limits is answered with 413,
  # and the entry page says why
  def test_mail_beyond_the_limits_is_answered_with_413_and_its_reason
    with_converters(CONVERTERS) do
      # the sample is smaller than the smallest size limit that can be set
      Cliff.any_instance.stubs(:limit).with('max_size').returns(0)
      Cliff.any_instance.stubs(:limit).with { |key| key != 'max_size' }.returns(1000)
      reason = I18n.t(:'redmine_more_previews.cliff.text_refused_size', :size => 0, :locale => :en)
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/entry/sample.eml'
      assert_response :success
      assert_select '#content p.warning', :text => reason
      RedmineMorePreviews::Lib::RmpFailures.stubs(:recorded).returns(nil)
      get '/projects/ecookbook/repository/samples/preview/sample.eml@/index.html'
      assert_response 413
      assert_equal reason, response.body
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

  def test_more_preview_and_asset_are_refused_with_view_changesets_alone
    # file content needs browse_repository in core (entry, raw); so do the previews
    Role.find(1).remove_permission!(:browse_repository)
    assert Role.find(1).has_permission?(:view_changesets)
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/preview/docs/sample.txt@/index.txt'
      assert_response :forbidden
      get '/projects/ecookbook/repository/samples/preview/sample.zip@inner/hello.txt'
      assert_response :forbidden
      assert_not_include 'hello inner', response.body
    end
  end

  def test_more_asset_is_allowed_with_browse_repository
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/preview/sample.zip@inner/hello.txt'
      assert_response :success
      assert_equal "hello inner\n", response.body
    end
  end

  # a relative link in a preview served at ...@/index.html (the images of a Libre
  # HTML preview) asks for ...@/<asset>: the slash after @ is part of the route,
  # not an absolute path (404 since 74f59fc, round 5)
  def test_more_asset_after_the_slash_of_the_preview_url
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/preview/sample.zip@/inner/hello.txt'
      assert_response :success
      assert_equal "hello inner\n", response.body
      get "/projects/ecookbook/repository/samples/#{@repository.changesets.first.revision}/preview/sample.zip@/top.txt"
      assert_response :success
      # only that slash: an absolute path or one leading out is still refused
      secret = File.join(Dir.mktmpdir('rmp-secret'), 'secret.txt')
      File.write(secret, 'RMP-ASSET-SECRET')
      ["%2F#{secret[1..].gsub('/', '%2F')}", "#{'..%2F' * 20}#{secret[1..].gsub('/', '%2F')}"].each do |asset|
        get "/projects/ecookbook/repository/samples/preview/sample.zip@/#{asset}"
        assert_response :not_found
        assert_not_include 'RMP-ASSET-SECRET', response.body
      end
    end
  end

  # port of curecodejp 5ac6319 (#56): an attachment without an extension is listed
  # by its name, the others are linked by the first conversion, also with an
  # extension of other characters than letters and digits
  def test_mail_with_an_attachment_without_extension
    mail = Mail.new do
      from 'author@example.test'
      to 'reader@example.test'
      subject 'repository attachments'
      text_part { body 'repository body survives' }
    end
    mail.add_file(filename: 'Makefile', content: 'all: test')
    mail.add_file(filename: 'notes.txt', content: 'repository note')
    mail.add_file(filename: 'source.c++', content: 'source code')
    mail.add_file(filename: 'notes.v_2', content: 'v2 data')
    mail.add_file(filename: 'backup.txt~', content: 'backup data')
    File.binwrite(File.join(@dir, 'mail.eml'), mail.to_s)
    system('git', '-C', @dir, 'add', '.', exception: true, out: File::NULL, err: File::NULL)
    system('git', '-C', @dir, '-c', 'user.name=Test', '-c', 'user.email=test@example.net', 'commit', '-q', '-m', 'mail', exception: true, out: File::NULL, err: File::NULL)
    @repository.fetch_changesets
    with_converters(CONVERTERS) do
      log_user('jsmith', 'jsmith')
      get '/projects/ecookbook/repository/samples/preview/mail.eml@/index.html'
      assert_response :success
      assert_include 'repository body survives', response.body
      get '/projects/ecookbook/repository/samples/preview/mail.eml@/attachments.html'
      assert_response :success
      document = Nokogiri::HTML.fragment(response.body)
      assert_include 'Makefile', document.text
      assert_not_include 'Makefile', document.css('a').map(&:text)
      %w(notes.txt source.c++ notes.v_2 backup.txt~).each do |name|
        link = document.css('a').find { |a| a.text == name }
        assert link, "no link for #{name}"
        recognized = Rails.application.routes.recognize_path(CGI.unescapeHTML(link['href']), method: :get)
        assert_equal 'more_asset', recognized[:action], name
        assert_equal name, "#{Array(recognized[:asset]).join('/')}.#{recognized[:assetformat]}", name
        get CGI.unescapeHTML(link['href'])
        assert_response :success, name
      end
      get '/projects/ecookbook/repository/samples/preview/mail.eml@/source.c++'
      assert_response :success
      assert_equal 'source code', response.body
      assert_equal 'README&lt;script&gt;', @repository.asset_link('mail.eml', nil, 'README<script>', true)
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

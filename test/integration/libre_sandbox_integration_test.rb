# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)
require 'shellwords'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'zlib'
require 'zip'
require 'timeout'
require 'base64'

# upstream cef06a3, 448caa9 (curecodejp 6.1.3), with the HTML output, the plugin's
# own conversion path and the time limit added.
# Runs on hosts with a working bwrap sandbox, system LibreOffice and pdfimages;
# RMP_LIBRE_REQUIRE_SANDBOX=1 makes their absence a failure instead of a skip.
# The intentionally unsandboxed positive control uses ONLY generated dummy data.
class LibreSandboxIntegrationTest < ActiveSupport::TestCase
  include RedmineMorePreviews::TestHelper

  fixtures :projects, :users, :issues, :trackers, :projects_trackers, :issue_statuses, :enumerations

  def setup
    worker = Libre.allocate
    unless worker.send(:sandbox_available?) && system('command -v pdfimages >/dev/null 2>&1')
      message = 'working bwrap/soffice namespace and pdfimages are required'
      flunk message if ENV['RMP_LIBRE_REQUIRE_SANDBOX'] == '1'
      skip message
    end
  end

  def test_external_file_image_is_inaccessible_but_document_converts
    worker = Libre.allocate
    Dir.mktmpdir('rmp-libre-integration') do |root|
      stage = File.join(root, 'staged')
      outside = File.join(root, 'outside')
      sandbox_output = File.join(root, 'sandbox-output')
      control_output = File.join(root, 'control-output')
      profile = File.join(root, 'profile')
      [stage, outside, sandbox_output, control_output, profile].each { |dir| FileUtils.mkdir_p(dir) }
      image = File.join(outside, 'DUMMY.png')
      File.binwrite(image, dummy_png)
      input = File.join(stage, 'external-image.odt')
      build_odt(input, "file://#{image}")

      worker.tmpdir = sandbox_output
      worker.preview_format = 'pdf'
      command = Shellwords.split(worker.soffice(input, File.join(profile, 'user_installation')))
      stdout, stderr, status = Timeout.timeout(120) { Open3.capture3(*command) }
      assert status.success?, "Sandboxed LibreOffice failed: #{stdout} #{stderr}"
      pdf = File.join(sandbox_output, 'external-image.pdf')
      assert File.file?(pdf), 'Sandboxed conversion must still produce a PDF'
      assert File.binread(pdf, 5).start_with?('%PDF-')
      worker.send(:validate_libre_output!)
      assert_equal 0, image_objects_4x4(pdf), 'External file image must not be embedded'

      control_profile = File.join(root, 'control-profile')
      stdout, stderr, status = Timeout.timeout(120) do
        Open3.capture3(Libre::LIBRE_OFFICE_BIN,
                       "-env:UserInstallation=file://#{control_profile}",
                       '--headless', '--convert-to', 'pdf', '--outdir', control_output, input)
      end
      assert status.success?, "Unsandboxed dummy-only control failed: #{stdout} #{stderr}"
      control_pdf = File.join(control_output, 'external-image.pdf')
      assert File.file?(control_pdf)
      assert_operator image_objects_4x4(control_pdf), :>=, 1,
                      'Positive control must embed the generated external PNG'
    end
  end

  # the HTML output neither embeds nor copies the server's file
  def test_external_file_image_is_not_copied_into_html_output
    Dir.mktmpdir('rmp-libre-integration') do |root|
      outside = File.join(root, 'outside')
      output = File.join(root, 'output')
      profile = File.join(root, 'profile')
      [outside, output, profile].each { |dir| FileUtils.mkdir_p(dir) }
      image = File.join(outside, 'DUMMY.png')
      File.binwrite(image, dummy_png)
      input = File.join(root, 'external-image.odt')
      build_odt(input, "file://#{image}")

      worker = Libre.allocate
      worker.tmpdir = output
      worker.preview_format = 'html'
      command = Shellwords.split(worker.soffice(input, File.join(profile, 'user_installation')))
      stdout, stderr, status = Timeout.timeout(120) { Open3.capture3(*command) }
      assert status.success?, "Sandboxed LibreOffice failed: #{stdout} #{stderr}"
      html = File.read(File.join(output, 'external-image.html'))
      assert_includes html, 'LIBRE-SANDBOX-TEST'
      worker.send(:validate_libre_output!)
      Dir.glob(File.join(output, '**', '*')).select { |f| File.file?(f) }.each do |file|
        assert_not_includes File.binread(file), dummy_png, "#{File.basename(file)} holds the server's file"
      end
      assert_not_includes html, Base64.strict_encode64(dummy_png)
    end
  end

  # the plugin's own path: an attachment previewed as PDF and as HTML by Libre
  def test_docx_attachment_is_previewed_as_pdf_and_html_in_the_sandbox
    set_tmp_attachments_directory
    attachment = preview_attachment(Issue.find(1), 'sample.docx')
    %w(pdf html).each do |format|
      with_converters(:libre => { :docx => format }) do
        # the settings and the attachment keep the format once read (upstream 399486c)
        Setting.clear_cache
        data = Attachment.find(attachment.id).more_preview(:format => format)
        assert data, format
        if format == 'pdf'
          assert data.start_with?('%PDF-')
        else
          assert_match(/<html/i, data)
        end
      end
    end
  ensure
    remove_preview_attachments
  end

  # LibreOffice prints the sheet name of a csv, which is the input's file name, as
  # page header: it showed Redmine's disk name (<timestamp>_sample)
  def test_csv_preview_has_no_disk_file_name
    set_tmp_attachments_directory
    attachment = preview_attachment(Issue.find(1), 'sample.csv')
    disk_stem = File.basename(attachment.disk_filename, '.csv')
    assert_match(/\A\d+_sample\z/, disk_stem)
    with_converters(:libre => { :csv => 'pdf' }) do
      Setting.clear_cache
      data = Attachment.find(attachment.id).more_preview(:format => 'pdf')
      assert data&.start_with?('%PDF-')
      text = Dir.mktmpdir('rmp-csv') do |dir|
        pdf = File.join(dir, 'preview.pdf')
        File.binwrite(pdf, data)
        Open3.capture2('pdftotext', '-layout', pdf, '-').first
      end
      assert_includes text, File.read(File.join(FILES, 'sample.csv')).lines.first.split(',').first.strip
      assert_not_includes text, disk_stem
      assert_match(/^\s*sample\s*$/, text)
    end
  ensure
    remove_preview_attachments
  end

  # the images of an HTML preview are found by their links, for a repository
  # file whose name has no ASCII letter or digit (it keeps its name in the
  # sandbox) and for an attachment (its name is made ASCII before, #25077)
  def test_html_image_links_resolve_for_non_ascii_names
    { '会議録.docx' => :repository, 'Offerte_Réunion 2026.docx' => :attachment }.each do |name, type|
      Dir.mktmpdir('rmp-libre-image-link') do |dir|
        src = File.join(dir, type == :repository ? name : '261029_Offerte_R_union_2026.docx')
        FileUtils.cp(File.join(FILES, 'sample_image.docx'), src)
        cache = File.join(RedmineMorePreviews::Constants::Defaults::MORE_PREVIEWS_STORAGE_PATH, 'libre-image-link', type.to_s)
        object = type == :repository ? { :type => :repository, :path => "docs/#{name}" } : { :type => :attachment, :object => Attachment.new(:filename => name) }
        with_converters(:libre => { :docx => 'html' }) do
          data = RedmineMorePreviews::Converter.convert(src, File.join(cache, 'index.html'), :object => object, :preview_format => 'html')
          assert_includes data.to_s, 'LIBRE-IMAGE-LINK-TEST', name
          links = data.scan(/<img[^>]* src="([^"]+)"/i).flatten
          assert_equal 1, links.size, "#{name}: #{links.inspect}"
          assert_match(/_html_\h+\.png\z/, links.first, name)
          assert File.file?(File.join(cache, URI.decode_uri_component(links.first))), "#{name}: #{links.first} names a stored image"
        end
      ensure
        FileUtils.rm_rf(File.join(RedmineMorePreviews::Constants::Defaults::MORE_PREVIEWS_STORAGE_PATH, 'libre-image-link'))
      end
    end
  end

  # without the C.UTF-8 locale LibreOffice writes the links of a non-ASCII name
  # encoded twice (Offerte_R%C3%83%C2%A9union%202026_html_...): fix_image_path
  # sets them right (port of curecodejp 43a7eec, 6b15276, fa1fbca). The sandbox
  # here sets LANG=C.UTF-8; a host without that locale falls back to C, as this
  # test does
  def test_html_image_links_are_fixed_when_the_sandbox_has_no_utf8_locale
    worker = Libre.allocate
    Dir.mktmpdir('rmp-libre-image-link') do |root|
      output = File.join(root, 'output')
      profile = File.join(root, 'profile')
      [output, profile].each { |dir| FileUtils.mkdir_p(dir) }
      input = File.join(root, '会議録.docx')
      FileUtils.cp(File.join(FILES, 'sample_image.docx'), input)
      worker.tmpdir = output
      worker.preview_format = 'html'
      command = Shellwords.split(worker.soffice(input, File.join(profile, 'user_installation')))
      command[command.index('C.UTF-8')] = 'C'
      stdout, stderr, status = Timeout.timeout(120) { Open3.capture3(*command) }
      assert status.success?, "Sandboxed LibreOffice failed: #{stdout} #{stderr}"
      html = File.join(output, '会議録.html')
      assert_match(/img src="%C3%A4%C2%BC%C2%9A[^"]*_html_/, File.read(html), 'precondition: encoded twice')
      worker.send(:validate_libre_output!)
      worker.send(:fix_image_path)
      links = File.read(html).scan(/<img[^>]* src="([^"]+)"/i).flatten
      assert_equal 1, links.size
      assert links.first.start_with?('%E4%BC%9A%E8%AD%B0%E9%8C%B2_html_'), links.first
      assert File.file?(File.join(output, URI.decode_uri_component(links.first))), "#{links.first} names the image"
    end
  end

  # a conversion that runs out of time is stopped with the sandbox and every
  # LibreOffice process in it (bwrap starts them in a new session)
  def test_sandboxed_conversion_is_stopped_at_the_time_limit
    set_tmp_attachments_directory
    attachment = preview_attachment(Issue.find(1), 'sample.docx')
    with_converters(:libre => { :docx => 'pdf' }) do
      Libre.any_instance.stubs(:conversion_timeout).returns(0.5)
      started = RedmineMorePreviews::Lib::RmpProcess.now
      assert_nil attachment.more_preview(:format => 'pdf')
      assert_operator RedmineMorePreviews::Lib::RmpProcess.now - started, :<, 15
      deadline = RedmineMorePreviews::Lib::RmpProcess.now + 5
      sleep 0.1 while sandboxed_soffice? && RedmineMorePreviews::Lib::RmpProcess.now < deadline
      assert_not sandboxed_soffice?, 'no LibreOffice of the sandbox is left running'
    end
  ensure
    remove_preview_attachments
  end

  private

  def sandboxed_soffice?
    Dir.glob('/proc/[0-9]*/cmdline').any? do |file|
      File.binread(file).include?('/profile/user_installation') rescue false
    end
  end

  def image_objects_4x4(pdf)
    stdout, stderr, status = Timeout.timeout(20) { Open3.capture3('pdfimages', '-list', pdf) }
    assert status.success?, "pdfimages failed: #{stderr}"
    stdout.lines.count do |line|
      columns = line.split
      columns.length >= 5 && columns[0].match?(/\A\d+\z/) &&
        columns[3] == '4' && columns[4] == '4'
    end
  end

  def png_chunk(kind, body)
    [body.bytesize].pack('N') + kind + body + [Zlib.crc32(kind + body)].pack('N')
  end

  def dummy_png
    rows = 4.times.map do |y|
      "\x00".b + 4.times.map do |x|
        [20 + x * 60, 25 + y * 55, 50 + (x + y * 4) * 12].pack('C3')
      end.join
    end.join
    "\x89PNG\r\n\x1a\n".b +
      png_chunk('IHDR', [4, 4, 8, 2, 0, 0, 0].pack('NNC5')) +
      png_chunk('IDAT', Zlib::Deflate.deflate(rows)) + png_chunk('IEND', ''.b)
  end

  def build_odt(path, file_url)
    namespaces = 'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" ' \
                 'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" ' \
                 'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" ' \
                 'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" ' \
                 'xmlns:xlink="http://www.w3.org/1999/xlink"'
    content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" \
              "<office:document-content #{namespaces} office:version=\"1.2\">" \
              '<office:body><office:text><text:p>LIBRE-SANDBOX-TEST</text:p>' \
              '<text:p><draw:frame draw:name="ExternalImage" text:anchor-type="as-char" ' \
              'svg:width="3cm" svg:height="3cm">' \
              "<draw:image xlink:href=\"#{file_url}\" xlink:type=\"simple\" " \
              'xlink:show="embed" xlink:actuate="onLoad"/>' \
              '</draw:frame></text:p></office:text></office:body></office:document-content>'
    manifest = '<?xml version="1.0" encoding="UTF-8"?>' \
               '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" ' \
               'manifest:version="1.2">' \
               '<manifest:file-entry manifest:full-path="/" ' \
               'manifest:media-type="application/vnd.oasis.opendocument.text"/>' \
               '<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>' \
               '</manifest:manifest>'
    Zip::File.open(path, create: true) do |zip|
      zip.get_output_stream('mimetype') { |io| io.write('application/vnd.oasis.opendocument.text') }
      zip.get_output_stream('content.xml') { |io| io.write(content) }
      zip.get_output_stream('META-INF/manifest.xml') { |io| io.write(manifest) }
    end
  end
end

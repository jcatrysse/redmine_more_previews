# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)
require 'shellwords'

# Peek makes its images of a PDF with the plugin's command and ImageMagick's limits
# (Jan, 2026-10-12, port of curecodejp 0893c53): Redmine::Thumbnail.generate kills
# only its shell on timeout, leaving convert and Ghostscript running.
class PeekTest < ActiveSupport::TestCase
  PDF = "%PDF-1.4\n%%EOF\n"
  BODY = "newpath 10 10 moveto 100 100 lineto stroke showpage\n"
  POSTSCRIPT = {
    'PostScript' => "%!PS\n#{BODY}",
    'PostScript with %PDF-1.4 on its second line' => "%!PS\n%PDF-1.4\n#{BODY}",
    'PostScript after a space' => " %!PS\n%PDF-1.4\n#{BODY}",
    'PostScript without a header' => "#{BODY}%PDF-1.4\n"
  }.freeze

  def setup
    @dir = Dir.mktmpdir('rmp-peek')
    Redmine::Thumbnail.stubs(:gs_available?).returns(true)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_peek_does_not_hand_postscript_to_imagemagick
    Redmine::Thumbnail.expects(:generate).never
    POSTSCRIPT.each do |name, bytes|
      %w(png jpg gif).each do |format|
        worker = peek(file('doc.pdf', bytes), format)
        worker.expects(:command).never
        worker.convert
      end
    end
  end

  def test_peek_converts_a_pdf_with_limits
    Redmine::Thumbnail.expects(:generate).never
    source = file('doc.pdf', PDF)
    %w(png jpg gif).each do |format|
      worker = peek(source, format)
      cmd = nil
      worker.expects(:command).with {|c| cmd = c}.returns(true)
      worker.convert
      convert = cmd.split('; ').map {|part| Shellwords.split(part)}.find {|p| p.first.end_with?('convert', 'magick')}
      input = convert.index("pdf:#{source}[0]")
      assert input, format
      %w(width height area memory map disk).each do |resource|
        limit = convert.each_cons(2).find_index {|a, b| a == '-limit' && b == resource}
        assert limit && limit < input, "#{format}: -limit #{resource} before the input"
      end
      assert_equal "#{format}:./out.#{format}", convert.last
    end
  end

  # the limits, the coder prefixes and -thumbnail must be accepted by the
  # installed ImageMagick and Ghostscript
  def test_peek_converts_a_real_pdf
    Redmine::Thumbnail.unstub(:gs_available?)
    assert Redmine::Thumbnail.convert_available? && Redmine::Thumbnail.gs_available?, 'ImageMagick and Ghostscript are needed'
    source = File.join(Dir.mktmpdir('src', @dir), 'real.pdf')
    FileUtils.cp(File.join(RedmineMorePreviews::TestHelper::FILES, 'sample.pdf'), source)
    worker = peek(source, 'png')
    worker.convert
    assert File.file?(worker.tmptarget)
    assert_equal "\x89PNG".b, File.binread(worker.tmptarget, 4)
  end

  def test_peek_needs_ghostscript
    Redmine::Thumbnail.stubs(:gs_available?).returns(false)
    worker = peek(file('doc.pdf', PDF), 'png')
    worker.expects(:command).never
    Redmine::Thumbnail.expects(:generate).never
    worker.convert
  end

  def test_peek_passes_a_pdf_through_without_conversion
    source = file('doc.pdf', "%!PS\n#{BODY}")
    worker = peek(source, 'pdf')
    Redmine::Thumbnail.expects(:generate).never
    worker.convert
    assert_equal File.binread(source), File.binread(worker.tmptarget)
  end

  private

  def file(name, bytes)
    path = File.join(Dir.mktmpdir('src', @dir), name)
    File.binwrite(path, bytes)
    path
  end

  def peek(source, format)
    worker = Peek.allocate
    worker.source = source
    worker.preview_format = format
    worker.tmpdir = Dir.mktmpdir('tmp', @dir)
    worker.tmptarget = File.join(worker.tmpdir, "index.#{format}")
    worker
  end
end

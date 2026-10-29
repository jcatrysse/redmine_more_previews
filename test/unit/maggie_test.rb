# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Maggie hands files to ImageMagick only as their own type (Jan, 2026-10-11,
# port of curecodejp e58d928): a PDF must start as one (Ghostscript runs anything
# else as PostScript), every input is read with the coder of its type, and the
# output has a fixed name instead of one made from the (committer chosen) file name.
class MaggieTest < ActiveSupport::TestCase
  include RedmineMorePreviews::TestHelper

  PDF = File.binread(File.join(RedmineMorePreviews::TestHelper::FILES, 'sample.pdf'))

  # runs Maggie on a file with the given name and content, records the shell commands
  def commands_for(name, content, format: 'png')
    commands = []
    Dir.mktmpdir do |dir|
      path = File.join(dir, name)
      File.binwrite(path, content)
      worker = RedmineMorePreviews::Converter.find(:maggie).worker(
        :target => File.join(dir, 'preview', "index.#{format}"), :preview_format => format)
      worker.define_singleton_method(:command) { |cmd, _options = {}| commands << cmd; true }
      worker.preview(File.new(path)) { |*_| }
    end
    commands
  end

  def test_postscript_disguised_as_pdf_is_not_handed_to_imagemagick
    # PostScript without a %! header, or anything before %PDF-: Marcel says PDF, Ghostscript runs PostScript
    ["/a 1 def\n%PDF-1.4\nshowpage\n", "\n%PDF-1.4\n/a 1 def\n", "garbage\n%PDF-1.4\n"].each do |content|
      assert_equal 'application/pdf', Marcel::MimeType.for(StringIO.new(content), :name => 'evil.pdf'),
                   "precondition: Marcel takes #{content.inspect} for a PDF"
      assert_equal [], commands_for('evil.pdf', content), "#{content.inspect}: no ImageMagick call"
    end
    # with a PostScript header (other than %!PS too) Marcel says PostScript, which Maggie never converts
    ["%!PS-Adobe-3.0\n%PDF-1.4\n", "\x04%!\n%PDF-1.4\n", "%!FontType1\n%PDF-1.4\n"].each do |content|
      assert_equal [], commands_for('evil.pdf', content), "#{content.inspect}: no ImageMagick call"
    end
  end

  def test_a_hostile_file_name_cannot_steer_imagemagick
    Redmine::Thumbnail.stubs(:gs_available?).returns(true)
    ['|touch pwned.pdf', '-write x.pdf'].each do |name|
      cmd = commands_for(name, PDF).join
      assert_include "'png:./out.png'", cmd
      assert_match %r{'pdf:/[^']*\[0\]'}, cmd, 'input read with the pdf coder'
      assert_no_match %r{'\./\|touch|'\./-write|'\|touch|'-write}, cmd, "#{name}: no output name from the file name"
    end
  end

  # port of curecodejp df0c1cf: without Ghostscript a PDF was copied under the
  # image name (index.png holding a PDF); now there is no preview
  def test_pdf_without_ghostscript_is_not_copied_as_an_image
    Redmine::Thumbnail.stubs(:gs_available?).returns(false)
    %w(png jpg gif).each do |format|
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'doc.pdf')
        File.binwrite(path, PDF)
        target = File.join(dir, 'preview', "index.#{format}")
        worker = RedmineMorePreviews::Converter.find(:maggie).worker(:target => target, :preview_format => format)
        assert_nil worker.preview(File.new(path)), "#{format}: no preview"
        assert_not File.exist?(target), "#{format}: no PDF stored as index.#{format}"
      end
    end
  end

  def test_images_do_not_need_ghostscript
    Redmine::Thumbnail.stubs(:gs_available?).returns(false)
    png = File.binread(File.join(RedmineMorePreviews::TestHelper::FILES, 'sample.png'))
    cmd = commands_for('picture.png', png).join
    assert_include "'png:", cmd
    assert_include "'png:./out.png'", cmd
  end

  def test_images_are_read_with_their_coder_and_imagemagick_is_bounded
    png = File.binread(File.join(RedmineMorePreviews::TestHelper::FILES, 'sample.png'))
    cmd = commands_for('picture.png', png, :format => 'jpg').join
    assert_include "'png:", cmd
    assert_include "'jpg:./out.jpg'", cmd
    assert_match(/-limit area \S+ .*'png:/, cmd, '-limit before the input')
  end
end

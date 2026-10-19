# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)
require 'shellwords'
require 'nokogiri'

# upstream a4d7616, 050405a (curecodejp 6.1.3)
class MarkCommandTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :attachments

  def setup
    @dir = Dir.mktmpdir('rmp-mark')
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # mv took "-draft.html" for an option: the preview was never moved in place
  def test_leading_dash_output_is_a_relative_path
    worker = worker_for('-draft.md', "# heading\n")
    RedmineMorePreviews::Converter.stubs(:mime).returns({'mime' => 'text/markdown'})
    _, move = commands(worker)
    assert_equal 'mv', move.first
    assert_equal './-draft.html', move[1]
  end

  def test_textile_uses_pandoc_textile_reader
    worker = worker_for('example.textile', "h1. Heading\n")
    RedmineMorePreviews::Converter.stubs(:mime).returns({'mime' => 'text/x-web-textile'})
    pandoc, = commands(worker)
    assert_equal 'textile', pandoc[pandoc.index('-f') + 1]
  end

  # the base URL ends with the file name, which may close the attribute it is
  # written into. Attachment#filename= replaces quotes, a repository path keeps
  # them: the name is set past the sanitizer here
  def test_base_url_is_escaped
    attachment = Attachment.find(1)
    attachment.write_attribute(:filename, "x'onmouseover='alert(1).md")
    worker = worker_for('x.md', "# heading\n", 'html')
    worker.object = {'type' => :attachment, 'object' => attachment}
    RedmineMorePreviews::Converter.stubs(:mime).returns({'mime' => 'text/markdown'})
    pandoc, = commands(worker)
    include = pandoc.find {|arg| arg.start_with?('header-includes=')}.delete_prefix('header-includes=')
    fragment = Nokogiri::HTML.fragment(include)
    assert_equal ['base'], fragment.children.map(&:name)
    assert_equal ['href'], fragment.at_css('base').attributes.keys
    assert fragment.at_css('base')['href'].end_with?("/x'onmouseover='alert(1).md"), fragment.to_html
  end

  private

  def worker_for(filename, body, format = 'inline')
    input = File.join(@dir, filename)
    File.write(input, body)
    worker = Mark.allocate
    worker.source = input
    worker.format = format
    worker.preview_format = 'html'
    worker.object = {}
    worker.tmpdir = Dir.mktmpdir('out', @dir)
    worker.tmptarget = File.join(worker.tmpdir, filename.sub(/\.[^.]+\z/, '.html'))
    worker.stubs(:converter_settings).returns({})
    worker
  end

  def commands(worker)
    command = nil
    worker.expects(:command).with {|value| command = value; true}.returns(true)
    worker.convert
    parts = command.split('; ').map {|part| Shellwords.split(part)}
    [parts.find {|args| args.first == Mark::PANDOC_BIN},
     parts.find {|args| args.first == 'mv'}]
  end
end

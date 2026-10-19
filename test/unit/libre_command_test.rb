# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)
require 'shellwords'

# upstream ddeeba2, 05bbe3f (curecodejp 6.1.3)
class LibreCommandTest < ActiveSupport::TestCase
  def setup
    @worker = Libre.allocate
    @worker.tmpdir = '/tmp/rmp libre'
  end

  def test_allowed_output_formats_remain_supported
    %w(html txt pdf png jpg).each do |format|
      @worker.preview_format = format
      command = Shellwords.split(@worker.soffice('/tmp/input.docx', '/tmp/lo profile'))
      assert_equal format, command[command.index('--convert-to') + 1]
    end
  end

  def test_shell_quote_is_called_for_the_validated_format
    @worker.preview_format = 'pdf'
    @worker.stubs(:shell_quote).returns('quoted')
    @worker.expects(:shell_quote).with('pdf').returns("'pdf'")
    assert_includes @worker.soffice('/tmp/input.docx', '/tmp/profile'), "--convert-to 'pdf'"
  end

  def test_unknown_and_shell_metacharacter_formats_are_rejected
    ['inline', 'xml', '', 'pdf;touch /tmp/unwanted', 'pdf$(id)', "pdf\nwhoami"].each do |format|
      @worker.preview_format = format
      assert_raises(RedmineMorePreviews::Exceptions::ConverterBadArgument, format) do
        @worker.soffice('/tmp/input.docx', '/tmp/profile')
      end
    end
  end
end

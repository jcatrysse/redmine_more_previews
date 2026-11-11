# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)
require 'open3'

# Ours (round 10, after curecodejp aa28b8b): ImageMagick lists HEIC whenever it
# was built with libheif, and decodes it only when libheif has an HEVC decoder
# plugin (libheif-plugin-libde265). Without it every conversion failed with
# "Unsupported codec". A probe file shipped with the plugin is really decoded
# once per program; Maggie, its settings and the real-conversion tests ask it.
class ImagemagickDecodeProbeTest < ActiveSupport::TestCase
  def setup
    RedmineMorePreviews.reset_imagemagick_decodes
  end

  def teardown
    RedmineMorePreviews.reset_imagemagick_decodes
  end

  def test_the_probe_file_is_shipped_and_is_a_heic
    probe = RedmineMorePreviews::IMAGEMAGICK_PROBES['HEIC']
    assert File.file?(probe)
    assert RedmineMorePreviews.valid_heif_magic?(probe)
    assert_not probe.include?('/test/'), 'the probe ships with the plugin, not with its tests'
  end

  def test_a_coder_without_a_probe_is_taken_as_listed
    RedmineMorePreviews.expects(:imagemagick_run).never
    assert RedmineMorePreviews.imagemagick_decodes?('TIFF')
  end

  def test_the_probe_decodes_the_file_with_the_coder_within_the_limits_without_a_shell
    probe = RedmineMorePreviews::IMAGEMAGICK_PROBES['HEIC']
    RedmineMorePreviews.expects(:imagemagick_run).with do |*args|
      args.include?("heic:#{probe}[0]") && args.last == 'info:' &&
        args.each_cons(3).any? {|a, b, c| a == '-limit' && b == 'area' && c == '128MP' }
    end.returns('64x64')
    assert RedmineMorePreviews.imagemagick_decodes?('HEIC')
  end

  def test_a_failed_or_odd_decode_is_no_decode
    [nil, '', "convert: Unsupported codec (4.3000)\n", '64x64 trailing'].each do |out|
      RedmineMorePreviews.reset_imagemagick_decodes
      RedmineMorePreviews.stubs(:imagemagick_run).returns(out)
      assert_not RedmineMorePreviews.imagemagick_decodes?('HEIC'), out.inspect
    end
  end

  def test_a_success_is_kept
    RedmineMorePreviews.expects(:imagemagick_run).once.returns('64x64')
    3.times { assert RedmineMorePreviews.imagemagick_decodes?('HEIC') }
  end

  # a decoder installed meanwhile is found without a restart
  def test_a_failure_is_asked_again_after_a_while
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(1000.0)
    RedmineMorePreviews.stubs(:imagemagick_run).returns(nil)
    assert_not RedmineMorePreviews.imagemagick_decodes?('HEIC')
    RedmineMorePreviews.stubs(:imagemagick_run).returns('64x64')
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(1000.0 + RedmineMorePreviews::IMAGEMAGICK_PROBE_RETRY - 1)
    assert_not RedmineMorePreviews.imagemagick_decodes?('HEIC'), 'kept for a while'
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(1000.0 + RedmineMorePreviews::IMAGEMAGICK_PROBE_RETRY + 1)
    assert RedmineMorePreviews.imagemagick_decodes?('HEIC')
  end

  def test_kept_per_program
    RedmineMorePreviews.stubs(:convert_bin).returns('convert')
    RedmineMorePreviews.stubs(:imagemagick_run).returns('64x64')
    assert RedmineMorePreviews.imagemagick_decodes?('HEIC')
    RedmineMorePreviews.stubs(:convert_bin).returns('magick')
    RedmineMorePreviews.stubs(:imagemagick_run).returns(nil)
    assert_not RedmineMorePreviews.imagemagick_decodes?('HEIC')
  end

  # Maggie converts a HEIC only when its coder is listed and decodes
  def test_maggie_needs_both
    RedmineMorePreviews.stubs(:imagemagick_reads?).returns(true)
    RedmineMorePreviews.stubs(:imagemagick_decodes?).with('HEIC').returns(false)
    RedmineMorePreviews.stubs(:imagemagick_decodes?).with('TIFF').returns(true)
    assert_not Maggie.coder_available?('HEIC')
    assert_equal ['HEIC/HEIF'], Maggie.unreadable_formats(%w(heic tif))
    RedmineMorePreviews.stubs(:imagemagick_decodes?).returns(true)
    assert Maggie.coder_available?('HEIC')
    assert_empty Maggie.unreadable_formats(%w(heic tif))
  end

  # the real probe agrees with a real conversion of the file on this host
  def test_the_real_probe_agrees_with_imagemagick
    skip 'ImageMagick is not available' unless Redmine::Thumbnail.convert_available?
    probe = RedmineMorePreviews::IMAGEMAGICK_PROBES['HEIC']
    _out, status = Open3.capture2e(RedmineMorePreviews::CONVERT_BIN, "heic:#{probe}[0]", 'png:/dev/null')
    assert_equal status.success?, RedmineMorePreviews.imagemagick_decodes?('HEIC')
  end
end

# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)
require 'open3'

# Ours (round 10, beyond curecodejp 3f866f0): the header Maggie reads is the
# attacker's. A box libheif takes the first of, or an item it would find twice,
# is not guessed at (the file is not read); and what a HEIC file declares is not
# what it codes, so the ImageMagick command of a HEIC or TIFF image runs with an
# address-space limit that follows max_megapixels.
class MaggieHeifHardeningTest < ActiveSupport::TestCase
  include RedmineMorePreviews::TestHelper

  FIXTURES = File.expand_path('../../fixtures/maggie', __FILE__)

  def setup
    @dir = Dir.mktmpdir('rmp-maggie-hardening')
    Redmine::Thumbnail.stubs(:gs_available?).returns(true)
    @settings = {'mime_types' => %w(png pdf heic heif tif tiff).to_h {|ext| [ext, {'active' => '1', 'format' => 'png'}]}}
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def heif(bytes)
    path = File.join(@dir, 'x.heic')
    File.binwrite(path, bytes)
    RedmineMorePreviews.heif_dimensions(path)
  end

  def meta_file(children)
    iso_box('ftyp', 'heic' + "\0\0\0\0" + 'mif1heic') + iso_box('meta', [0].pack('N') + children)
  end

  def pitm(item)
    iso_box('pitm', [0, item].pack('Nn'))
  end

  def ipco(*sizes)
    iso_box('ipco', sizes.map {|w, h| iso_box('ispe', [0, w, h].pack('NNN')) }.join)
  end

  # entries: [[item, [property indices]], ...]
  def ipma(entries)
    iso_box('ipma', [0, entries.size].pack('NN') + entries.map {|id, idx| [id, idx.size].pack('nC') + idx.map {|i| 0x80 | i }.pack('C*') }.join)
  end

  def test_the_header_builder_is_read
    assert_equal [64, 48], heif(meta_file(pitm(1) + iso_box('iprp', ipco([64, 48]) + ipma([[1, [1]]]))))
  end

  # libheif takes the first pitm: a small primary item first, a large one after
  def test_two_pitm_boxes_are_not_read
    iprp = iso_box('iprp', ipco([16, 16], [20_000, 20_000]) + ipma([[1, [1]], [2, [2]]]))
    assert_nil heif(meta_file(pitm(1) + pitm(2) + iprp))
  end

  def test_two_iprp_or_ipco_boxes_are_not_read
    small = iso_box('iprp', ipco([16, 16]) + ipma([[1, [1]]]))
    large = iso_box('iprp', ipco([20_000, 20_000]) + ipma([[1, [1]]]))
    assert_nil heif(meta_file(pitm(1) + small + large))
    assert_nil heif(meta_file(pitm(1) + iso_box('iprp', ipco([16, 16]) + ipco([20_000, 20_000]) + ipma([[1, [1]]]))))
  end

  # the primary item listed twice, in one ipma box or in two
  def test_an_item_associated_twice_is_not_read
    assert_nil heif(meta_file(pitm(1) + iso_box('iprp', ipco([16, 16], [20_000, 20_000]) + ipma([[1, [1]], [1, [2]]]))))
    assert_nil heif(meta_file(pitm(1) + iso_box('iprp', ipco([16, 16], [20_000, 20_000]) + ipma([[1, [1]]]) + ipma([[1, [2]]]))))
    # another item twice is no matter
    assert_equal [16, 16], heif(meta_file(pitm(1) + iso_box('iprp', ipco([16, 16], [8, 8]) + ipma([[1, [1]], [2, [2]], [2, [2]]]))))
  end

  def test_two_ispe_properties_of_the_primary_item_are_not_read
    assert_nil heif(meta_file(pitm(1) + iso_box('iprp', ipco([16, 16], [20_000, 20_000]) + ipma([[1, [1, 2]]]))))
  end

  # an oversized ispe: 413 before ImageMagick, with the size in the reason
  def test_an_oversized_ispe_is_refused_before_imagemagick
    RedmineMorePreviews.stubs(:imagemagick_reads?).returns(true)
    RedmineMorePreviews.stubs(:imagemagick_decodes?).returns(true)
    worker = worker_for('big.heic', heic_header({1 => [100_000, 100_000]}))
    worker.expects(:command).never
    error = assert_raises(RedmineMorePreviews::Exceptions::ConverterTooLarge) { worker.convert }
    assert_includes error.message, '100000x100000'
  end

  # --- the address-space limit ------------------------------------------------------

  def test_heic_and_tiff_commands_run_with_an_address_space_limit
    RedmineMorePreviews.stubs(:imagemagick_reads?).returns(true)
    RedmineMorePreviews.stubs(:imagemagick_decodes?).returns(true)
    {'a.heic' => heic_header({1 => [64, 64]}), 'a.tif' => tiff_header(64, 64)}.each do |name, bytes|
      assert_match(/\Acd '[^']+'; ulimit -v 2621440 \|\| exit 1; '?convert/, command_of(worker_for(name, bytes)), name)
      @settings = @settings.merge('max_megapixels' => '16')
      assert_match(/; ulimit -v 1441792 \|\| exit 1; /, command_of(worker_for(name, bytes)), name)
      @settings = @settings.except('max_megapixels')
    end
  end

  def test_other_images_have_no_address_space_limit
    {'a.png' => File.binread(File.join(FILES, 'sample.png')), 'a.pdf' => File.binread(File.join(FILES, 'sample.pdf'))}.each do |name, bytes|
      assert_not_includes command_of(worker_for(name, bytes)), 'ulimit', name
    end
  end

  # a shell that cannot set the limit does not run ImageMagick
  def test_a_failing_ulimit_stops_the_command
    out, status = Open3.capture2e('sh', '-c', "ulimit -v nonsense || exit 1; echo ran")
    assert_not status.success?
    assert_not_includes out, 'ran'
  end

  # real conversions (ImageMagick with libheif): the file declares 64x64 and
  # codes 9000x9000. Within a limit of 16 megapixels by its header, it is not
  # decoded whole: the conversion fails. Without the address-space limit
  # ImageMagick wrote a 9000x9000 preview (1.4 GB resident)
  def test_a_heic_coding_more_than_it_declares_is_not_decoded
    real_heic!
    assert_equal [64, 64], RedmineMorePreviews.heif_dimensions(File.join(FIXTURES, 'lying-ispe.heic'))
    @settings = @settings.merge('max_megapixels' => '16')
    worker = worker_for('lying-ispe.heic', File.binread(File.join(FIXTURES, 'lying-ispe.heic')))
    assert_raises(RedmineMorePreviews::Exceptions::ConverterShellError) { worker.convert }
    assert_not File.exist?(worker.tmptarget)
  end

  # the default limit leaves room for an image of 64 megapixels it declares
  def test_a_heic_of_64_megapixels_is_converted_within_the_default_limit
    real_heic!
    worker = worker_for('coded-64mp.heic', File.binread(File.join(FIXTURES, 'coded-64mp.heic')))
    worker.convert
    assert_equal "\x89PNG".b, File.binread(worker.tmptarget, 4)
  end

  private

  def real_heic!
    skip 'ImageMagick lists no HEIC, or decodes no file of it (no HEVC decoder, f.i. libheif-plugin-libde265)' unless Maggie.coder_available?('HEIC')
  end

  def worker_for(name, bytes)
    work = Dir.mktmpdir('work', @dir)
    source = File.join(work, name)
    File.binwrite(source, bytes)
    worker = Maggie.allocate
    worker.source = source
    worker.preview_format = 'png'
    worker.tmpdir = Dir.mktmpdir('tmp', @dir)
    worker.tmptarget = File.join(worker.tmpdir, 'index.png')
    worker.stubs(:converter_settings).returns(@settings)
    worker
  end

  def command_of(worker)
    cmd = nil
    worker.expects(:command).with {|c| cmd = c }.returns(true)
    worker.convert
    cmd.to_s
  end
end

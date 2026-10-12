# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

# An archive expands without bound: a tgz is inflated from the start up to the
# entry asked for, and rubyzip reads the whole central directory of a zip. The
# walk through a tar / tgz, the central directory of a zip, the size of an
# extracted asset and the assets stored per archive are bounded.
class ZippyLimitsTest < ActiveSupport::TestCase
  include RedmineMorePreviews::TestHelper

  ConverterTooLarge = RedmineMorePreviews::Exceptions::ConverterTooLarge

  def setup
    @tmp = Dir.mktmpdir('rmp-zippy-limits')
    @old_tmpdir = ENV['TMPDIR']
    ENV['TMPDIR'] = File.join(@tmp, 'tmp').tap { |d| FileUtils.mkdir_p(d) }
    @target = File.join(@tmp, 'cache', 'preview.html', 'index.html')
    @old_settings = Setting.plugin_redmine_more_previews
  end

  def teardown
    ENV['TMPDIR'] = @old_tmpdir
    Setting.plugin_redmine_more_previews = @old_settings
    Setting.clear_cache
    FileUtils.rm_rf(@tmp)
  end

  def test_tgz_list_stops_at_the_entry_limit
    tgz = build_tgz(path('a.tgz'), (1..5).to_h { |n| ["f#{n}.txt", "file #{n}"] })
    with_zippy_limits('max_entries' => '3') do
      html = listing(tgz)
      assert_includes html, 'f3.txt'
      assert_not_includes html, 'f4.txt'
      assert_includes html, CGI.escapeHTML(I18n.translate(:"redmine_more_previews.zippy.text_list_truncated"))
    end
  end

  def test_tgz_list_stops_at_the_inflated_limit
    tgz = build_tgz(path('a.tgz'), 'big.bin' => "\0" * (2 * 1024 * 1024), 'after.txt' => 'after')
    with_zippy_limits('max_inflated' => '1') do
      html = listing(tgz)
      assert_not_includes html, 'after.txt'
      assert_includes html, CGI.escapeHTML(I18n.translate(:"redmine_more_previews.zippy.text_list_truncated"))
      # the entry beyond the limit is not reached either
      assert_raises(ConverterTooLarge) { extract(tgz, 'after.txt') }
    end
  end

  def test_complete_tar_list_is_not_marked_truncated
    tar = build_tar(path('a.tar'), 'a.txt' => 'a')
    assert_not_includes listing(tar), CGI.escapeHTML(I18n.translate(:"redmine_more_previews.zippy.text_list_truncated"))
  end

  def test_tar_asset_larger_than_the_limit_is_refused
    tar = build_tar(path('a.tar'), 'big.bin' => 'x' * (1024 * 1024 + 1))
    with_zippy_limits('max_asset' => '1') do
      assert_raises(ConverterTooLarge) { extract(tar, 'big.bin') }
    end
  end

  def test_zip_asset_larger_than_the_limit_is_refused
    zip = build_zip(path('a.zip'), 'big.bin' => 'x' * (1024 * 1024 + 1))
    with_zippy_limits('max_asset' => '1') do
      assert_raises(ConverterTooLarge) { extract(zip, 'big.bin') }
    end
  end

  def test_zip_with_too_many_entries_is_not_opened
    zip = build_zip(path('a.zip'), (1..5).to_h { |n| ["f#{n}.txt", "file #{n}"] })
    with_zippy_limits('max_entries' => '3') do
      Zip::File.expects(:open).never
      assert_raises(ConverterTooLarge) { listing(zip) }
      assert_raises(ConverterTooLarge) { extract(zip, 'f1.txt') }
    end
  end

  def test_zip64_end_of_central_directory_is_read
    # a zip64 record, its locator and a record pointing to them
    zip64 = [0x06064b50, 44, 45, 45, 0, 0, 70_000, 70_000, 5_000_000, 0].pack('VQ<vvVVQ<Q<Q<Q<')
    locator = [0x07064b50, 0, 16, 1].pack('VVQ<V')
    eocd = [0x06054b50, 0, 0, 0xFFFF, 0xFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0].pack('VvvvvVVv')
    file = path('zip64.zip')
    File.binwrite(file, ('P' * 16) + zip64 + locator + eocd)
    worker = zippy_worker(target: @target)
    worker.source = file
    assert_equal [70_000, 5_000_000], worker.send(:central_directory)
  end

  # the check goes by the numbers rubyzip goes by (rubyzip 3 on Redmine 7: the last
  # end of central directory record, its zip64 record only where it marks a field)
  def test_entries_are_counted_as_rubyzip_counts_them
    five = (1..5).to_h { |n| ["f#{n}.txt", "file #{n}"] }
    in_comment = build_zip(path('comment.zip'), five)
    add_comment(in_comment, zip64_record(3, 1000) + zip64_locator)
    marked = zip64_file(path('marked.zip'), 3)
    pointed = path('pointed.zip')
    # the zip64 record lies before the bytes rubyzip reads from the end: the locator points to it
    File.binwrite(pointed, zip64_record(7, 1000) + ('P' * 70_000) + [0x07064b50, 0, 0, 1].pack('VVQ<V') +
                           [0x06054b50, 0, 0, 0xFFFF, 0xFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0].pack('VvvvvVVv'))
    { in_comment => 5, marked => 3, pointed => 7 }.each do |zip, count|
      worker = zippy_worker(target: @target)
      worker.source = zip
      rubyzip = File.open(zip, 'rb') { |io| Zip::CentralDirectory.new.count_entries(io) }
      assert_equal count, rubyzip, File.basename(zip)
      assert_equal rubyzip, worker.send(:central_directory).first, File.basename(zip)
    end
  end

  def test_zip64_record_beyond_the_limit_is_refused
    zip = zip64_file(path('zip64.zip'), 20_000)
    Zip::File.expects(:open).never
    assert_raises(ConverterTooLarge) { listing(zip) }
  end

  def test_zip64_record_rubyzip_does_not_read_is_not_counted
    zip = build_zip(path('comment.zip'), 'f.txt' => 'file')
    add_comment(zip, zip64_record(20_000, 1000) + zip64_locator)
    assert_include 'f.txt', listing(zip)
  end

  def test_file_without_end_of_central_directory_is_left_to_rubyzip
    file = path('broken.zip')
    File.binwrite(file, 'not a zip')
    worker = zippy_worker(target: @target)
    worker.source = file
    assert_nil worker.send(:central_directory)
  end

  def test_assets_stored_per_archive_are_bounded
    zip = build_zip(path('a.zip'), 'small.txt' => 'small')
    preview_dir = File.dirname(@target)
    FileUtils.mkdir_p(preview_dir)
    File.binwrite(File.join(preview_dir, 'stored.bin'), 'x' * (1024 * 1024))
    File.write("#{preview_dir}.converter", 'zippy')
    File.write(@target, '<p>listing</p>')
    with_zippy_limits('max_stored' => '1') do
      worker = zippy_worker(target: File.join(preview_dir, 'small.txt'), asset: 'small.txt')
      assert_raises(ConverterTooLarge) { worker.preview(File.new(zip)) }
      # not stored, so not bounded: a transient extraction still works
      assert_equal 'small', extract(zip, 'small.txt')
    end
  end

  # a nested asset is stored at its own path below the archive's directory:
  # the assets stored for the whole archive count
  def test_assets_stored_per_archive_count_nested_assets
    zip = build_zip(path('a.zip'), 'dir/small.txt' => 'small')
    preview_dir = File.dirname(@target)
    FileUtils.mkdir_p(File.join(preview_dir, 'other'))
    File.binwrite(File.join(preview_dir, 'other', 'stored.bin'), 'x' * (1024 * 1024))
    File.write("#{preview_dir}.converter", 'zippy')
    File.write(@target, '<p>listing</p>')
    with_zippy_limits('max_stored' => '1') do
      worker = zippy_worker(target: File.join(preview_dir, 'dir', 'small.txt'), asset: 'dir/small.txt')
      assert_raises(ConverterTooLarge) { worker.preview(File.new(zip)) }
    end
  end

  def test_full_cache_does_not_bound_what_is_stored_per_archive
    zip = build_zip(path('a.zip'), 'small.txt' => 'small')
    preview_dir = File.dirname(@target)
    FileUtils.mkdir_p(preview_dir)
    File.binwrite(File.join(preview_dir, 'stored.bin'), 'x' * (1024 * 1024))
    File.write("#{preview_dir}.converter", 'zippy')
    File.write(@target, '<p>listing</p>')
    RedmineMorePreviews::Lib::RmpCacheSize.stubs(:full?).returns(true)
    with_zippy_limits('max_stored' => '1') do
      worker = zippy_worker(target: File.join(preview_dir, 'small.txt'), asset: 'small.txt')
      assert_equal 'small', worker.preview(File.new(zip))
      assert_not File.exist?(File.join(preview_dir, 'small.txt'))
    end
  end

  def test_tar_asset_beyond_the_limits_is_refused
    tgz = build_tgz(path('a.tgz'), (1..5).to_h { |n| ["f#{n}.txt", "file #{n}"] })
    with_zippy_limits('max_entries' => '3') do
      assert_equal 'file 2', extract(tgz, 'f2.txt')
      assert_raises(ConverterTooLarge) { extract(tgz, 'f5.txt') }
      assert_nil extract(build_tgz(path('b.tgz'), 'a.txt' => 'a'), 'missing.txt')
    end
  end

  def test_deep_directories_are_listed_as_one_name
    name = (1..70).map { |n| "d#{n}" }.join('/') + '/file.txt'
    zip = build_zip(path('deep.zip'), name => 'deep')
    worker = zippy_worker(target: @target)
    depth = 0
    Zip::File.open(zip) do |zip_file|
      node = worker.send(:ziptree, zip_file)
      while node.size == 1 && node.values.first[:dir]
        depth += 1
        node = node.values.first[:children]
      end
      assert_equal (65..70).map { |n| "d#{n}" }.join('/') + '/file.txt', node.keys.first
    end
    assert_equal Zippy::MAX_DEPTH, depth
  end

  private

  def path(name)
    File.join(FileUtils.mkdir_p(File.join(@tmp, 'archives')).first, name)
  end

  # each archive has a preview directory of its own, as each attachment has
  def target_of(archive_path)
    File.join(@tmp, 'cache', File.basename(archive_path), 'preview.html', 'index.html')
  end

  def listing(archive_path)
    worker = zippy_worker(target: target_of(archive_path), request: fake_request)
    html = nil
    worker.preview(File.new(archive_path)) { |preview| html = preview }
    html.to_s.dup.force_encoding(Encoding::UTF_8)
  end

  def extract(archive_path, asset)
    worker = zippy_worker(target: File.join(File.dirname(target_of(archive_path)), asset), asset: asset)
    result = nil
    worker.preview(File.new(archive_path)) { |_preview, asset_data| result = asset_data }
    result
  end

  def zip64_locator
    [0x07064b50, 0, 0, 1].pack('VVQ<V')
  end

  # the end of central directory record ends with the comment's length
  def add_comment(zip, comment)
    data = File.binread(zip)
    data[-2, 2] = [comment.bytesize].pack('v')
    File.binwrite(zip, data + comment)
  end

  # a zip64 record, its locator and an end of central directory record marked zip64
  def zip64_file(path, entries)
    File.binwrite(path, ('P' * 16) + zip64_record(entries, entries * 46) + zip64_locator +
                        [0x06054b50, 0, 0, 0xFFFF, 0xFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0].pack('VvvvvVVv'))
    path
  end

  def zip64_record(entries, size)
    [0x06064b50, 44, 45, 45, 0, 0, entries, entries, size, 0].pack('VQ<vvVVQ<Q<Q<Q<')
  end

  def fake_request
    ActionDispatch::TestRequest.create(
      'PATH_INFO' => '/attachments/more_preview/1.html',
      'action_dispatch.request.path_parameters' => {controller: 'attachments', action: 'more_preview', id: '1', format: 'html'}
    )
  end

  def with_zippy_limits(values)
    settings = @old_settings.to_h.deep_dup
    settings['converter'] = settings['converter'].to_h
    settings['converter']['zippy'] = settings['converter']['zippy'].to_h.merge(values)
    Setting.plugin_redmine_more_previews = settings
    Setting.clear_cache
    yield
  end
end

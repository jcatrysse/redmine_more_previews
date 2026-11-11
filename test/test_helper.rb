# frozen_string_literal: true

# Load the Redmine helper
require File.expand_path('../../../test/test_helper', __dir__)

# the conversions keep lock files, the cache size and the failures they remember
# in the storage path: keep them out of the Redmine instance the tests run in
RedmineMorePreviews::Constants::Defaults.send(:remove_const, :MORE_PREVIEWS_STORAGE_PATH)
RedmineMorePreviews::Constants::Defaults.const_set(:MORE_PREVIEWS_STORAGE_PATH, Dir.mktmpdir('rmp-test-storage'))
Minitest.after_run { FileUtils.rm_rf(RedmineMorePreviews::Constants::Defaults::MORE_PREVIEWS_STORAGE_PATH) }

# sanitized inline previews are kept in the process (curecodejp 0b3e950, #71):
# no test may read what another one sanitized
ActiveSupport::TestCase.setup do
  RedmineMorePreviews::Patches::ApplicationHelperPatch::INLINE_PREVIEW_CACHE.clear
end

module RedmineMorePreviews
  module TestHelper
    FILES = File.expand_path('fixtures/files', __dir__)

    # Activates the given converters, each with {extension => format}.
    def with_converters(converters, settings = {}, &block)
      config = converters.to_h do |id, mime_types|
        [id.to_s, { 'active' => '1',
                    'mime_types' => mime_types.to_h { |ext, fmt| [ext.to_s, { 'active' => '1', 'format' => fmt.to_s }] } }]
      end
      with_settings(:plugin_redmine_more_previews => {
        'embedding' => '0', 'cache_previews' => '1', 'debug' => '0', 'absolute' => '0', 'converter' => config
      }.merge(settings), &block)
    end

    # Attaches a file from test/fixtures/files (or the given content) to the container.
    def preview_attachment(container, filename, content = nil)
      content ||= File.binread(File.join(FILES, filename))
      attachment = Attachment.new(file: StringIO.new(content), author: User.find(1))
      attachment.filename = filename
      attachment.content_type = Marcel::MimeType.for(StringIO.new(content), name: filename)
      attachment.container = container
      attachment.save!
      @preview_attachments ||= []
      @preview_attachments << attachment
      attachment
    end

    def remove_preview_attachments
      Array(@preview_attachments).each { |a| FileUtils.rm_rf(a.preview_storagepath) }
    end

    def enable_previews(project)
      project.enabled_module_names = project.enabled_module_names | ['redmine_more_previews']
    end

    # helpers of curecodejp's test suite (ported with its tests, round 5)
    # plugin settings with the Zippy converter enabled for zip / tar / tgz
    ZIPPY_SETTINGS = {
      'embedding' => '0', 'cache_previews' => '1', 'debug' => '0', 'absolute' => '0',
      'converter' => {
        'zippy' => {
          'active' => '1',
          'mime_types' => {
            'zip' => {'active' => '1', 'format' => 'html'},
            'tar' => {'active' => '1', 'format' => 'html'},
            'tgz' => {'active' => '1', 'format' => 'html'}
          }
        }
      }
    }.freeze

    # Marks an archive entry that should be written as a symlink to +target+.
    Symlink = Struct.new(:target)

    def symlink_to(target = '/etc/hostname')
      Symlink.new(target)
    end

    # Builds a zip archive at +path+ from a hash of entry name => content
    # (a String, or symlink_to(target) for a symlink entry).
    def build_zip(path, entries)
      Zip::File.open(path, create: true) do |zip|
        entries.each do |name, content|
          if content.is_a?(Symlink)
            zip.add(name, symlink_source(content.target))
          elsif name.end_with?('/')
            zip.mkdir(name.chomp('/'))
          else
            zip.get_output_stream(name) { |io| io.write(content) }
          end
        end
      end
      path
    end

    # Builds a (non-compressed) tar archive at +path+.
    def build_tar(path, entries)
      File.open(path, 'wb') do |file|
        Gem::Package::TarWriter.new(file) do |tar|
          entries.each do |name, content|
            if content.is_a?(Symlink)
              tar.add_symlink(name, content.target, 0o644)
            else
              tar.add_file_simple(name, 0o644, content.bytesize) { |io| io.write(content) }
            end
          end
        end
      end
      path
    end

    # Builds a gzip compressed tar archive at +path+.
    def build_tgz(path, entries)
      tar = build_tar("#{path}.tar", entries)
      Zlib::GzipWriter.open(path) { |gz| gz.write(File.binread(tar)) }
      File.delete(tar)
      path
    end

    # the encoding a browser reads an html response in: the charset of the
    # Content-Type, else a <meta charset> (or http-equiv) in the first 1024
    # bytes; nil: the browser guesses (curecodejp ee6c728, #79)
    def declared_charset(response)
      header = response.headers['Content-Type'].to_s[/;\s*charset=["']?([^;"'\s]+)/i, 1]
      return header.downcase if header
      head = response.body.to_s.b[0, 1024]
      head[/<meta[^>]+charset\s*=\s*["']?([A-Za-z0-9_\-]+)/i, 1]&.downcase
    end

    # +text+ shows as it is: the body read in the declared encoding holds it
    def assert_displayed_as(text, response)
      charset = declared_charset(response)
      assert charset, "no charset declared, the browser has to guess (Content-Type: #{response.headers['Content-Type'].inspect})"
      shown = response.body.to_s.dup.force_encoding(charset)
      assert shown.valid_encoding?, "body is not valid #{charset}"
      assert_includes shown.encode('UTF-8'), text
    end

    # An ISO BMFF box
    def iso_box(type, payload = ''.b, size: nil)
      ([size || (8 + payload.bytesize)].pack('N') + type.b + payload.b).b
    end

    # The start of a HEIC file: an "ftyp" box, then a "meta" box whose primary
    # item (+primary+) and other items each have an "ispe" property of the size
    # +images+ gives (item id => [width, height]); +before+ comes between them
    # (f.i. an "mdat" box). No image data: only the header is read.
    def heic_header(images = {1 => [64, 64]}, primary: images.keys.first, major: 'heic', before: ''.b)
      ftyp  = iso_box('ftyp', major + "\0\0\0\0" + 'mif1heic')
      ipco  = images.values.map {|w, h| iso_box('ispe', [0, w, h].pack('NNN')) }.join
      ipma  = [0, images.size].pack('NN') + images.keys.each_with_index.map {|id, i| [id, 1, 0x81 + i].pack('nCC') }.join
      meta  = iso_box('meta', [0].pack('N') + iso_box('hdlr', [0, 0].pack('NN') + 'pict' + ("\0" * 13)) +
                              iso_box('pitm', [0, primary].pack('Nn')) +
                              iso_box('iprp', iso_box('ipco', ipco) + iso_box('ipma', ipma)))
      ftyp + before + meta
    end

    # The start of a TIFF file: a first IFD with ImageWidth and ImageLength of
    # the given types (3 SHORT, 4 LONG, 16 LONG8), little (II) or big (MM)
    # endian, classic or BigTIFF, the IFD after +pad+ bytes of image data
    def tiff_header(width, height, order: 'II', big: false, type: 4, pad: 16, count: 1)
      u16, u32, u64 = order == 'II' ? %w(v V Q<) : %w(n N Q>)
      value = lambda do |v, size|
        bytes = case type when 3 then [v].pack(u16) when 4 then [v].pack(u32) else [v].pack(u64) end
        bytes.ljust(size, "\0")
      end
      entries = {256 => width, 257 => height, 259 => 1}.map do |tag, v|
        t = tag == 259 ? 3 : type
        if big
          [tag, t].pack(u16 * 2) + [tag == 259 ? 1 : count].pack(u64) + (tag == 259 ? [v].pack(u16).ljust(8, "\0") : value.call(v, 8))
        else
          [tag, t].pack(u16 * 2) + [tag == 259 ? 1 : count].pack(u32) + (tag == 259 ? [v].pack(u16).ljust(4, "\0") : value.call(v, 4))
        end
      end.join
      if big
        offset = 16 + pad
        (order + [43, 8, 0].pack(u16 * 3) + [offset].pack(u64) + ("\0" * pad) + [3].pack(u64) + entries + [0].pack(u64)).b
      else
        offset = 8 + pad
        (order + [42].pack(u16) + [offset].pack(u32) + ("\0" * pad) + [3].pack(u16) + entries + [0].pack(u32)).b
      end
    end

    def zippy_worker(options = {})
      RedmineMorePreviews::Converter.find(:zippy).worker(
        { preview_format: 'html', object: {} }.merge(options)
      )
    end

    private

    # the symlink is added to the archive by path, so it must outlive the builder;
    # the directory is removed in teardown (see symlink_sources)
    def symlink_source(target)
      dir = Dir.mktmpdir('rmp-symlink')
      symlink_sources << dir
      link = File.join(dir, 'link')
      File.symlink(target, link)
      link
    end

    def symlink_sources
      @symlink_sources ||= []
    end

    def teardown
      super
      symlink_sources.each { |dir| FileUtils.rm_rf(dir) }
    end
  end
end

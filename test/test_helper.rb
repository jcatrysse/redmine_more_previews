# frozen_string_literal: true

# Load the Redmine helper
require File.expand_path('../../../test/test_helper', __dir__)

# the conversions keep lock files, the cache size and the failures they remember
# in the storage path: keep them out of the Redmine instance the tests run in
RedmineMorePreviews::Constants::Defaults.send(:remove_const, :MORE_PREVIEWS_STORAGE_PATH)
RedmineMorePreviews::Constants::Defaults.const_set(:MORE_PREVIEWS_STORAGE_PATH, Dir.mktmpdir('rmp-test-storage'))
Minitest.after_run { FileUtils.rm_rf(RedmineMorePreviews::Constants::Defaults::MORE_PREVIEWS_STORAGE_PATH) }

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

# frozen_string_literal: true

# Load the Redmine helper
require File.expand_path('../../../test/test_helper', __dir__)

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
  end
end

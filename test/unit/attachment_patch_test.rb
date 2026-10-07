# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

class AttachmentPatchTest < ActiveSupport::TestCase
  include RedmineMorePreviews::TestHelper

  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :enabled_modules,
           :trackers, :projects_trackers, :issue_statuses, :issues, :enumerations

  def setup
    set_tmp_attachments_directory
    User.current = nil
  end

  def teardown
    remove_preview_attachments
  end

  def test_destroy_removes_the_cached_previews
    attachment = preview_attachment(Issue.find(1), 'sample.txt')
    with_converters(:teddie => { :txt => :txt }) do
      assert attachment.more_preview(:format => 'txt')
      assert File.directory?(attachment.preview_storagepath)
      attachment.destroy
      assert_not File.exist?(attachment.preview_storagepath)
      assert_not File.exist?(attachment.diskfile)
    end
  end

  def test_destroy_removes_the_markdownized_preview_cache_of_redmine_7
    attachment = preview_attachment(Issue.find(1), 'sample.docx')
    # Redmine 7 caches the markdown it previews docx in; destroy must remove it
    path = attachment.send(:markdownized_preview_cache_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, 'cached markdown')
    attachment.destroy
    assert_not File.exist?(path)
  end
end

# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# Core methods other plugins also patch are extended with prepend, never copied
# or redefined (Jan, 2026-10-07): mixing alias_method and prepend on one method
# recurses, and a copy or a redefinition silently drops another plugin's prepend.
class PatchesTest < ActiveSupport::TestCase
  def test_controller_filters_are_not_copied_with_alias_method
    assert_not AttachmentsController.private_method_defined?(:find_attachment_for_more_preview)
    assert_not AttachmentsController.private_method_defined?(:read_authorize_for_more_preview)
    assert_not AttachmentsController.method_defined?(:find_attachment_for_more_preview)
    assert_not RepositoriesController.method_defined?(:find_project_repository_for_more_preview)
    assert_not RepositoriesController.private_method_defined?(:find_project_repository_for_more_preview)
  end

  def test_delete_from_disk_is_prepended_and_calls_core
    owner = Attachment.instance_method(:delete_from_disk!).owner
    assert_not_equal Attachment, owner
    assert Attachment.ancestors.index(owner) < Attachment.ancestors.index(Attachment), 'not prepended'
    assert_equal Attachment, Attachment.instance_method(:delete_from_disk!).super_method.owner
    assert Attachment.private_method_defined?(:delete_from_disk!), 'core keeps it private'
  end

  def test_css_class_of_is_prepended
    owner = Redmine::MimeType.method(:css_class_of).owner
    assert_not_equal Redmine::MimeType.singleton_class, owner
    assert_equal 'application-vnd-ms-excel', Redmine::MimeType.css_class_of('a.xls')
  end
end

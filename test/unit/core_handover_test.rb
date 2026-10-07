# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)
require 'rake'

# Jan, 2026-10-07 (q3, "Advies volgen"): after the upgrade Redmine shows pdf,
# images, text and md itself; the plugin keeps Office, mail and zip; the
# converters pass and mark-html go off.
class CoreHandoverTest < ActiveSupport::TestCase
  include RedmineMorePreviews::TestHelper

  ALL = {
    :libre => { :docx => :pdf, :odt => :html }, :cliff => { :eml => :html }, :zippy => { :zip => :html, :tar => :inline },
    :vince => { :vcf => :html }, :mark => { :md => :html, :textile => :inline, :html => :html }, :pass => { :html => :html },
    :teddie => { :txt => :txt }, :nil_text => { :txt => :html }, :peek => { :pdf => :pdf },
    :maggie => { :png => :jpg, :jpg => :png, :gif => :png, :bmp => :png, :pdf => :png }
  }

  def test_hands_pdf_images_text_markdown_and_html_to_core
    with_converters(ALL) do
      changes = RedmineMorePreviews::CoreHandover.apply!
      assert_include 'pass', changes
      assert_equal %w(docx eml odt tar vcf zip), RedmineMorePreviews::Converter.active_extensions.sort
      settings = Setting.plugin_redmine_more_previews
      assert_equal '0', settings['converter']['pass']['active']
      assert_equal '0', settings['converter']['mark']['mime_types']['html']['active']
      assert_equal '1', settings['converter']['mark']['active'], 'mark itself stays, it has nothing active'
      assert_equal 'pdf', settings['converter']['libre']['mime_types']['docx']['format'], 'formats are kept'
      assert_equal '1', settings['cache_previews'], 'global settings are kept'
    end
  end

  def test_is_idempotent_and_has_a_dry_run
    with_converters(ALL) do
      before = Setting.plugin_redmine_more_previews.to_h
      assert_not_empty RedmineMorePreviews::CoreHandover.apply!(:dry_run => true)
      assert_equal before, Setting.plugin_redmine_more_previews.to_h
      RedmineMorePreviews::CoreHandover.apply!
      assert_empty RedmineMorePreviews::CoreHandover.apply!
    end
  end

  def test_without_any_converter_settings
    with_settings(:plugin_redmine_more_previews => { 'embedding' => '0', 'cache_previews' => '1', 'debug' => '0', 'absolute' => '0' }) do
      assert_empty RedmineMorePreviews::CoreHandover.apply!
    end
  end

  def test_rake_task
    Rails.application.load_tasks unless Rake::Task.task_defined?('redmine_more_previews:use_core_previews')
    with_converters(ALL) do
      out, = capture_io { Rake::Task['redmine_more_previews:use_core_previews'].execute }
      assert_include 'pass', out
      assert_not_include 'pdf', RedmineMorePreviews::Converter.active_extensions
    end
  end
end

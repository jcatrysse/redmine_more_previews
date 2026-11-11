# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

# The frame of a preview (more_previews_tag), with <object> (embedding 0) and
# with <iframe> (embedding 1). Ports of curecodejp 5efeb83 (#72) and add99bb
# (#75), whose html_preview_sandbox_test exists only upstream (its frame code
# differs from ours: our sandbox is the preview's CSP header).
class PreviewFrameTest < Redmine::HelperTest
  include ApplicationHelper
  include RedmineMorePreviews::TestHelper

  def frame(type, embedding)
    html = with_settings(:plugin_redmine_more_previews => Setting.plugin_redmine_more_previews.to_h.merge('embedding' => embedding)) do
      more_previews_tag('/attachments/more_preview/1/index.x', 'report.pdf', :type => type)
    end
    doc = Nokogiri::HTML5.fragment(html)
    [doc.at_css('#preview_pane'), doc.at_css('#preview_frame, #preview_object')]
  end

  # an iframe without a height of its own stayed 16px until its load event,
  # which a PDF frame does not fire: the PDF was a strip with "Loading..."
  def test_iframe_fills_its_pane
    %w(application/pdf text/plain text/html).each do |type|
      _pane, iframe = frame(type, '1')
      assert_equal 'IFRAME', iframe.name.upcase, type
      assert_equal 'position:absolute;top:0;left:0;width:95%;height:100%;', iframe['style'], type
      assert_nil iframe['onload'], type
    end
  end

  def test_object_fills_its_pane
    _pane, object = frame('application/pdf', '0')
    assert_equal 'OBJECT', object.name.upcase
    assert_equal 'position:absolute;top:0;left:0;width:95%;height:100%;', object['style']
  end
end

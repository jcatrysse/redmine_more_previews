# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)
require 'erb'
require 'nokogiri'

# Vince renders its template with plain ERB and marks the result html_safe: the
# name of the card is escaped in the template (port of curecodejp 285601d).
# Upstream's tests of its self-contained template do not apply to ours.
class VinceHtmlTemplateTest < ActiveSupport::TestCase
  TEMPLATE = File.expand_path('../../converters/vince/app/views/vince/vince.html.erb', __dir__)

  def render(format, cards: [])
    @preview_format = format
    @vcfs = cards
    @iconize = false
    @converter = Struct.new(:public_web_directory, :settings).new(
      '/plugin_assets/redmine_more_previews/converters/vince',
      { logo: 'logo.png' }
    )
    ERB.new(File.read(TEMPLATE)).result(binding).squish
  end

  def test_fn_is_html_escaped_in_both_preview_formats
    vcf = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Name <b>not markup</b> & friends\r\nEND:VCARD\r\n"
    card = VinceLib::VObject::Reader.new(object: :vcard, string: vcf).stringall.first

    %w[html inline].each do |format|
      html = render(format, cards: [card])

      assert_includes html, 'Name &lt;b&gt;not markup&lt;/b&gt; &amp; friends'
      assert_not_includes html, '<b>not markup</b>'
    end
  end

  # the template never selected TITLE and ROLE, so a card's job title was not shown
  def test_job_title_and_role_are_shown
    vcf = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Test User\r\nN:User;Test;;;\r\nORG:Example Org\r\n" \
          "TITLE:Project Engineer\r\nROLE:Surveyor\r\nEND:VCARD\r\n"
    card = VinceLib::VObject::Reader.new(object: :vcard, string: vcf).stringall.first

    html = I18n.with_locale(:en) { render('html', cards: [card]) }
    fragment = Nokogiri::HTML.fragment(html)
    labels = fragment.css('label').map { |label| label.text.strip }
    assert_includes labels, 'Job title'
    assert_includes labels, 'Role'
    assert_includes fragment.text, 'Project Engineer'
    assert_includes fragment.text, 'Surveyor'
  end

end

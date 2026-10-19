# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)
require 'nokogiri'

class VinceUriLinkTest < ActiveSupport::TestCase
  def preview(field, value)
    vcf = "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Test User\r\n#{field.upcase}:#{value}\r\nEND:VCARD\r\n"
    card = VinceLib::VObject::Reader.new(object: :vcard, string: vcf).stringall.first
    Nokogiri::HTML.fragment(card.public_send(field.downcase).webalize)
  end

  def test_supported_uri_schemes_remain_clickable
    [
      ['url', 'http://example.invalid/page'],
      ['url', 'HTTPS://example.invalid/page'],
      ['url', 'ftp://example.invalid/file'],
      ['url', 'mailto:user@example.invalid'],
      ['tel', 'tel:+12025550123'],
      ['impp', 'xmpp:user@example.invalid'],
      ['impp', 'sip:user@example.invalid'],
      ['impp', 'sips:user@example.invalid'],
      ['impp', 'im:user@example.invalid'],
      ['impp', 'skype:echo123']
    ].each do |field, uri|
      link = preview(field, uri).at_css('a')
      assert_not_nil link, uri
      assert_equal uri.downcase.split(':', 2).first, link['href'].split(':', 2).first.downcase, uri
    end
  end

  def test_geo_has_a_dedicated_google_maps_renderer
    link = preview('geo', 'geo:35.0,139.0').at_css('a')

    assert_not_nil link
    assert link['href'].start_with?('https://www.google.com/maps/'), link['href']
    assert_includes link.text, '35.0,139.0'
  end

  def test_geo_uses_only_numeric_coordinates_in_map_url
    [
      ['geo:35.0,139.0;u=30', 'https://www.google.com/maps/@35.0,139.0,15z'],
      ['geo:-45.25,120.5,15;crs=wgs84', 'https://www.google.com/maps/@-45.25,120.5,15z'],
      ['geo:35.0,139.0;u=%2F..%2F', 'https://www.google.com/maps/@35.0,139.0,15z']
    ].each do |uri, expected_href|
      link = preview('geo', uri).at_css('a')
      assert_not_nil link, uri
      assert_equal expected_href, link['href'], uri
    end
  end

  def test_geo_rejects_malformed_parameters_without_creating_a_link
    [
      'geo:35.0,139.0;u=30/../../url?q=https://evil.example',
      'geo:35.0,139.0;u=30?next=https://evil.example'
    ].each do |uri|
      fragment = preview('geo', uri)

      assert_nil fragment.at_css('a'), uri
      assert_includes fragment.text, uri, uri
    end
  end

  def test_unsupported_uri_schemes_render_as_plain_text
    [
      ['url', 'javascript:noop'],
      ['url', 'data:text/plain,hello'],
      ['url', 'file:///tmp/sample.txt'],
      ['url', 'nothttps:example.invalid'],
      ['tel', 'javascript:noop'],
      ['impp', 'javascript:noop'],
      ['url', 'xmpp:user@example.invalid'],
      ['geo', 'custom:35.0,139.0'],
      ['geo', 'geo:1,2/../../url?q=https://evil.example'],
      ['geo', 'geo:95,139.0'],
      ['geo', 'geo:35.0,181']
    ].each do |field, uri|
      fragment = preview(field, uri)
      assert_nil fragment.at_css('a'), uri
      assert_includes fragment.text, uri, uri
    end
  end

  # parsing a card logged the raw values of its structured fields
  def test_parsing_does_not_log_the_card
    io = StringIO.new
    logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    VinceLib::VObject::Reader.new(object: :vcard,
      string: "BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Test\r\nN:Secretname;Given;;;\r\nADR:;;Secret street 1;Town;;;\r\nEND:VCARD\r\n").stringall.first.n.webalize
    assert_not_include 'Secret', io.string
  ensure
    Rails.logger = logger
  end

  # upstream a3bb8af, e0f27cd: the IMPP field had no label ("Translation missing")
  def test_impp_has_a_label_in_every_shipped_language
    %w(de en es fr ja pt pt-BR ru zh).each do |language|
      with_settings :default_language => language do
        label = preview('impp', 'xmpp:user@example.invalid').at_css('label')
        assert_not_nil label, language
        assert_equal I18n.t(:'vcard.IMPP', :locale => language), label.text.strip, language
        assert_not_includes label.text.downcase, 'translation missing', language
      end
    end
  end
end

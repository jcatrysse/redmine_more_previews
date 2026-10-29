# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

# port of curecodejp fc40099: the text rendering called a field's humanize proc
# with a second argument, iconize, which is not defined there (NameError)
class VinceHumanizeTest < ActiveSupport::TestCase
  def card
    @card ||= VinceLib::VObject::Reader.new(
      object: :vcard,
      string: [
        'BEGIN:VCARD',
        'VERSION:4.0',
        'FN:Test User',
        'N:Family;Given;;;',
        'NICKNAME:Alias,Friend',
        'KIND:individual',
        'PHOTO;VALUE=uri:https://example.invalid/photo.png',
        'LOGO;VALUE=uri:https://example.invalid/logo.png',
        'END:VCARD'
      ].join("\r\n") + "\r\n"
    ).stringall.first
  end

  # the five humanize methods that call a field's proc (fields, list, value,
  # symbol, uri); a lambda refuses a second argument
  {
    n: :fields,
    nickname: :fields,
    fn: :value,
    kind: :symbol,
    photo: :fields
  }.each do |field, value_kind|
    define_method("test_#{field}_custom_humanizer_receives_one_hash_argument") do
      entry = card.public_send(field)
      expected = entry.to_h.fetch(field).first
      assert expected.key?(value_kind), "Expected #{value_kind} in #{field} payload"

      received = []
      entry.humanize_proc = ->(hash) { received << hash; "custom #{field}" }

      assert_includes card.humanize(fields: [field]), "custom #{field}"
      assert_equal [expected], received
    end
  end

  def test_real_photo_and_logo_text_humanizers
    text = card.humanize(fields: [:photo, :logo])

    assert_includes text, ':-)'
    assert_includes text, '|/|'
  end
end

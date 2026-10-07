# encoding: utf-8
# frozen_string_literal: true

# Redmine plugin to preview various file types in redmine's preview pane
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#

module RedmineMorePreviews
  #
  # Redmine 7 previews pdf, images, text, markdown and textile itself. These
  # settings hand those file types back to core; Office, mail, zip and vcard
  # stay with the plugin (GEOxyz decision of 2026-10-07). Run once after the
  # upgrade: rake redmine_more_previews:use_core_previews
  #
  module CoreHandover
    # converter => file types core previews itself
    TYPES = {
      'peek'     => %w(pdf),
      'maggie'   => %w(png jpg gif bmp pdf),
      'mark'     => %w(md textile html),
      'teddie'   => %w(txt),
      'nil_text' => %w(txt),
      'pass'     => %w(html)
    }.freeze
    
    # converters switched off as a whole
    CONVERTERS = %w(pass).freeze
    
    # Switches the types and converters off in the plugin settings; returns
    # what was switched off ("peek .pdf", "pass"), nothing when already done.
    def self.apply!(dry_run: false)
      settings  = ::Setting.plugin_redmine_more_previews.to_h.deep_dup.deep_stringify_keys
      converter = settings['converter'].to_h
      changes   = []
      
      TYPES.each do |id, extensions|
        extensions.each do |ext|
          mime = converter.dig(id, 'mime_types', ext)
          next unless mime.is_a?(Hash) && mime['active'].to_s == '1'
          
          mime['active'] = '0'
          changes << "#{id} .#{ext}"
        end
      end
      CONVERTERS.each do |id|
        next unless converter[id].is_a?(Hash) && converter[id]['active'].to_s == '1'
        
        converter[id]['active'] = '0'
        changes << id
      end
      
      ::Setting.plugin_redmine_more_previews = settings.merge('converter' => converter) unless dry_run || changes.empty?
      changes
    end #def
  end #module
end #module

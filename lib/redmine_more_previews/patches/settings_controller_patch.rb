# encoding: utf-8
# frozen_string_literal: true

# Redmine plugin to preview various file types in redmine's preview pane
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#

# Redmine saves plugin settings as they are posted. A Libre format the
# converter does not offer for an extension is refused before it is saved:
# Libre refuses it at conversion time (Libre#soffice), so it would switch the
# previews of that extension off until corrected (upstream f06370c, 55da9ac,
# c7b709f, 4540b78)
module RedmineMorePreviews
  module Patches
    module SettingsControllerPatch
      def plugin
        if request.post? && params[:id] == 'redmine_more_previews'
          formats = libre_formats_param
          if formats.present? && !valid_libre_formats?(formats)
            flash[:error] = l(:error_more_previews_invalid_libre_format)
            return redirect_to(plugin_settings_path(params[:id]))
          end
          unreadable = unreadable_maggie_formats(params.dig(:settings, :converter, :maggie))
          if unreadable.any?
            flash[:error] = l(:error_more_previews_unreadable_image_format, :formats => unreadable.join(', '))
            return redirect_to(plugin_settings_path(params[:id]))
          end
        end
        super
      end #def

      private

      # settings[converter][libre][mime_types], nil if absent; a level that is
      # no hash (settings=x) gives itself, which is refused as invalid (dig
      # raised TypeError on a String: HTTP 500, own review)
      def libre_formats_param
        [:settings, :converter, :libre, :mime_types].reduce(params) do |level, key|
          return level unless level.respond_to?(:each_pair)
          level[key]
        end
      end #def

      # Maggie's HEIC/HEIF and TIFF previews need a coder ImageMagick may lack:
      # enabling them there is refused. The form sends the format checkboxes of
      # a converter that is off, so only an enabled Maggie is checked (port of
      # curecodejp aa28b8b, #81)
      def unreadable_maggie_formats(maggie)
        return [] unless settings_hash?(maggie) && setting_active?(maggie[:active]) && defined?(::Maggie)

        formats = maggie[:mime_types]
        return [] unless settings_hash?(formats)

        enabled = formats.each_pair.select {|_ext, config| settings_hash?(config) && setting_active?(config[:active])}.map(&:first)
        ::Maggie.unreadable_formats(enabled)
      end

      # what the converters take for enabled (Converter.select_active): also
      # true and 1, which a JSON request sends as they are
      def setting_active?(value)
        [true, 1, '1'].include?(value)
      end

      # a String answers [] too: malformed parameters are not checked here
      def settings_hash?(value)
        value.is_a?(ActionController::Parameters) || value.is_a?(Hash)
      end

      def valid_libre_formats?(formats)
        return false unless formats.respond_to?(:each_pair)

        supported = RedmineMorePreviews::Converter.find(:libre).mime_types
        formats.each_pair.all? do |extension, config|
          entry = supported[extension.to_s.to_sym]
          next false unless entry && config.respond_to?(:key?) && config.respond_to?(:[])

          !config.key?('format') || Array(entry[:formats]).map(&:to_s).include?(config['format'])
        end
      end #def
    end #module
  end #module
end #module

unless SettingsController.ancestors.include?(RedmineMorePreviews::Patches::SettingsControllerPatch)
  SettingsController.prepend(RedmineMorePreviews::Patches::SettingsControllerPatch)
end

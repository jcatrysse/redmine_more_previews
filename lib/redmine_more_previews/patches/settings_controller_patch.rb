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

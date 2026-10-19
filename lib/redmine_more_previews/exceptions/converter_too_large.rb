# encoding: utf-8
# frozen_string_literal: true

# Redmine plugin to preview various file types in redmine's preview pane
#
# Copyright © 2018 -2022 Stephan Wenzel <stephan.wenzel@drwpatent.de>
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

module RedmineMorePreviews
  module Exceptions
    # a file, an archive entry or a converted preview is larger than its limit:
    # the request is answered with 413, the conversion is not attempted or its
    # result not served
    class ConverterTooLarge < StandardError; end
    
    # a limit refused the file for a reason the user may read: translated, it
    # quotes nothing of the file and no path. It is the body of the 413 and is
    # shown on the page (see Cliff#refuse)
    class ConverterRefused < ConverterTooLarge
      # the translation key (below redmine_more_previews.) and its numbers: the
      # reason is remembered with the failure and translated for each viewer
      attr_reader :key, :values
      
      def initialize( message = nil, key: nil, values: {} )
        super( message )
        @key, @values = key, values.to_h
      end
      
      # translated in the current language; nil unless key and values are a
      # translation of the plugin with numbers only (they come from a file)
      def self.from( key, values )
        return nil unless key.is_a?( String ) && key.match?( /\Aredmine_more_previews(\.[a-z_]+)+\z/ )
        return nil unless values.is_a?( Hash ) && values.all? {|k, v| k.to_s.match?( /\A[a-z_]+\z/ ) && v.is_a?( Integer ) }
        values = values.transform_keys( &:to_sym )
        new( I18n.translate( key, **values ), :key => key, :values => values )
      end
    end
  end
end

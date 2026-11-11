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
  module Patches 
    module ApplicationHelperPatch
      WORKER_KEYS = %w(name preview_format threadsafe semaphore timeout shell_api mime_types settings version).freeze
      
      INLINE_TAGS = %w(table thead tbody tfoot tr th td caption colgroup col s u figure figcaption section article header footer)
      
      # sanitizing runs in the Rails worker, outside the converter's process
      # limits: a larger converted html is not parsed there (port of curecodejp
      # 5fb219a, #61)
      MAX_INLINE_PREVIEW_HTML_BYTES = 256 * 1024
      
      # sanitizing html near that limit can take seconds, on every page view:
      # the results are kept in the process (port of curecodejp 0b3e950, #71).
      # Not Rails.cache (a file store without size limit by default) nor the
      # preview storage (written by converters); a restart empties it, so a
      # changed sanitizer never serves results of the old one. MemoryStore
      # synchronizes every access with its own monitor: safe for Puma threads
      INLINE_PREVIEW_CACHE = ActiveSupport::Cache::MemoryStore.new(
        :size => 32 * 1024 * 1024, :expires_in => 1.hour
      )
      
      # text and PDF previews scroll inside their frame: a pane sized by its width
      # (padding-top:141%) is taller than the window on a wide screen and made the
      # page scroll as well. It leaves room for what the page shows around it
      # (port of curecodejp add99bb, #75); html previews keep their pane
      NON_HTML_PREVIEW_PANE_STYLE = "position:relative;height:calc(100vh - 320px);min-height:280px;"
      
      def self.included(base)
        base.class_eval do
        
          #unloadable 
          
          # inline previews are converted user files rendered into the page itself
          def more_previews_inline(html)
            html = RedmineMorePreviews::Lib::RmpText.to_utf8(html.to_s)
            # not truncated: cut markup could change what the sanitizer lets through
            if html.bytesize > RedmineMorePreviews::Patches::ApplicationHelperPatch::MAX_INLINE_PREVIEW_HTML_BYTES
              return content_tag(:p, l(:text_more_previews_inline_too_large), :class => "nodata")
            end
            begin
              # keyed on the content, so query parameters cannot bypass it; while
              # the preview cache is off nothing new is kept and nothing kept is
              # read (it expires on its own). A parser failure raises in the block
              # and is not kept
              if RedmineMorePreviews::Converter.cache_previews?
                key = "#{Redmine::Utils.relative_url_root}:#{Digest::SHA256.hexdigest(html)}"
                # a plain String is kept, not the SafeBuffer, marked safe again here
                RedmineMorePreviews::Patches::ApplicationHelperPatch::INLINE_PREVIEW_CACHE.fetch(key) do
                  sanitize_inline_preview_html(html).to_str
                end.html_safe
              else
                sanitize_inline_preview_html(html)
              end
            rescue ArgumentError => e
              # the HTML5 parser raises on markup over its tree depth or attribute
              # limits: keep the page, never fall back to the input (port of
              # curecodejp 77ce987, #70)
              Rails.logger.warn("Inline preview not sanitized: #{e.message}")
              content_tag(:p, l(:text_more_previews_inline_too_complex), :class => "nodata")
            end
          end #def
          
          def sanitize_inline_preview_html(html)
            sanitize(html,
              :tags       => ActionView::Base.sanitized_allowed_tags.to_a + RedmineMorePreviews::Patches::ApplicationHelperPatch::INLINE_TAGS,
              :attributes => ActionView::Base.sanitized_allowed_attributes.to_a + %w(colspan rowspan align download style)
            )
          end #def
          
          # query parameters the preview views may forward to the converters.
          # asset / assets select an archive entry and are only meaningful for
          # asset requests; forwarded from the preview page they made the inline
          # preview ask for the entry instead of the listing (nil once cached).
          def preview_query_parameters
            request.query_parameters.except('asset', 'assets')
          end
          
          # options of an inline preview, converted while the page is rendered.
          # reload takes effect for administrators only, as for a preview request
          # (see ControllerHelper#preview_reload?); unsafe never does: it converts
          # without the cache and so needs a block, which the cached view has not
          def inline_preview_options
            # nor may a query key set what the converter's own settings set (timeout,
            # shell_api, settings, ...: see Converter#worker_attributes)
            preview_query_parameters.except('reload', 'unsafe', *RedmineMorePreviews::Patches::ApplicationHelperPatch::WORKER_KEYS).symbolize_keys.merge(
              :format  => "inline",
              :request => request,
              :reload  => params[:reload].present? && User.current.admin?
            )
          end
          
          def more_previews_tag(path, filename, options={})
          
            html_preview = options[:type].to_s.split(';').first == 'text/html'
            pane_style   = html_preview ? "position:relative;padding-top:141%;" :
                           RedmineMorePreviews::Patches::ApplicationHelperPatch::NON_HTML_PREVIEW_PANE_STYLE
            if RedmineMorePreviews::Converter.embed?
              content_tag(:div, 
                content_tag(
                  :object,
                  tag(:embed, :href => path, :type => options[:type]),
                  { :style   => "position:absolute;top:0;left:0;width:95%;height:100%;",
                    :title   => filename,
                    :type    => options[:type],
                    :data    => path,
                    :id      => 'preview_object',
                   }.merge(options)
                ),
                :id     => "preview_pane",
                :style  => pane_style,
              )
            else
              content_tag(:div, 
                content_tag(:script, "$(document).ready(function() { $('#ajax-indicator').show()});".html_safe) +
                content_tag(
                  :iframe,
                  "",
                  # the frame fills its pane: it was 16px high until its load event
                  # set the window's height, which a PDF frame never fired, so a PDF
                  # stayed a strip (port of curecodejp 5efeb83, #72)
                  { :style                => "position:absolute;top:0;left:0;width:95%;height:100%;",
                    :seamless             => "seamless",
                    # text longer than the frame must scroll in it (#75)
                    :scrolling            => "auto",
                    :frameborder          => "0",
                    :allowtransparency    => "true",
                    :title                => filename,
                    :src                  => path,
                    :id                   => 'preview_frame'
                   }.merge(options)
                ),
                :id    => "preview_pane",
                :style => pane_style
              )
            end #if
          end #def
          
        end #base
      end #self
    end #module
  end #module
end #module

unless ApplicationHelper.included_modules.include?(RedmineMorePreviews::Patches::ApplicationHelperPatch)
  ApplicationHelper.send(:include, RedmineMorePreviews::Patches::ApplicationHelperPatch)
end



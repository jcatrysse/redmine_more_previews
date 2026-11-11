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
  module ControllerHelper
  
    # reload converts again and skips a remembered failure, unsafe converts
    # without the cache (and without Cliff's sweep): both take effect for
    # administrators only, for anyone else the request is served as without
    # them. Decided here once, for the cache branch, the ETag and the converter.
    def preview_reload?
      params[:reload].present? && User.current.admin?
    end
    private :preview_reload?

    def preview_unsafe?
      params[:unsafe].present? && User.current.admin?
    end
    private :preview_unsafe?

    # a valid asset name (see RmpFile.safe_relative_path) other than the name the
    # preview is stored under next to its assets (Attachment#preview_filename)
    def preview_asset?(asset, preview_format)
      asset.present? && asset != ["index", preview_format.presence].compact.join(".")
    end
    private :preview_asset?

    def preview_params
      params.permit(:format, :asset).
      merge({:request => request, 
             :asset   => @asset, 
             :format  => params[:format]&.downcase,
             :reload  => preview_reload?,
             :unsafe  => preview_unsafe?}.compact )
    end #def
    private :preview_params

    # the ETag of a stored preview: a browser that kept a preview stored before a
    # change of the cache format (Conversion::CACHE_FORMAT_VERSION), or in the
    # other debug mode, must not get a 304 for it (upstream 35fdcb6, 554a683)
    def preview_etag(mtime)
      [mtime, RedmineMorePreviews::Conversion::CACHE_FORMAT_VERSION,
       RedmineMorePreviews::Converter.debug?]
    end #def
    private :preview_etag

    # the preview is stored as index.<format>, but a browser's PDF viewer saves
    # under the name of the Content-Disposition: a converted PDF is named after
    # the original (its basename, further dots kept), other formats keep the
    # stored name (port of curecodejp 31d1001, #73)
    def preview_download_filename(original_filename, stored_filename)
      return stored_filename unless File.extname(stored_filename.to_s).casecmp?('.pdf')

      source = File.basename(original_filename.to_s.tr('\\', '/'))
      stem = source.delete_suffix(File.extname(source))
      stem.present? ? "#{stem}.pdf" : stored_filename
    end
    private :preview_download_filename

    # seconds after which a client may ask again for a preview that was busy
    BUSY_RETRY_AFTER = 10

    # no conversion slot or lock became free in time (see Conversion#wait_for):
    # the preview is being converted, or too many are. Nothing was converted, a
    # later request can succeed.
    def render_more_preview_busy(exception)
      response.headers['Retry-After'] = BUSY_RETRY_AFTER.to_s
      render :plain => l(:text_more_previews_busy), :status => 503, :content_type => 'text/plain'
    end
    private :render_more_preview_busy

    # a file, an archive entry or a preview is larger than its limit (see
    # Converter.max_repository_file, Converter.max_output, Zippy::LIMITS); an
    # email refused at one of Cliff's limits says which (ConverterRefused)
    def render_more_preview_too_large(exception)
      text = exception.is_a?(RedmineMorePreviews::Exceptions::ConverterRefused) ? exception.message : l(:text_more_previews_too_large)
      render :plain => text, :status => 413, :content_type => 'text/plain'
    end
    private :render_more_preview_too_large
    
    # headers.html, fields.html or attachments.html of a file Cliff previews: the
    # fragments Cliff's hook embeds in the page. An archive entry of the same
    # name is an ordinary asset (port of curecodejp ebe0641, bed742c)
    def cliff_embedded_fragment_asset?
      return false unless RedmineMorePreviews::Conversion::CLIFF_EMBEDDED_FRAGMENTS.include?(@asset.to_s)
      source_name = @attachment&.filename || @entry&.name
      source_name.present? && RedmineMorePreviews::Converter.responsible(source_name, :pathonly => true)&.id.to_s == 'cliff'
    end #def
    private :cliff_embedded_fragment_asset?
    
    # the marker of an oversized Cliff fragment is the hook's notice in the page;
    # requested directly, the fragment is answered with 413 (port of curecodejp
    # ebe0641, #63)
    def reject_oversized_cliff_fragment!(data)
      return unless cliff_embedded_fragment_asset?
      return unless data == RedmineMorePreviews::Conversion::CLIFF_FRAGMENT_TOO_LARGE
      raise RedmineMorePreviews::Exceptions::ConverterTooLarge, 'Embedded email fragment exceeds its preview limit'
    end #def
    private :reject_oversized_cliff_fragment!
    
    # Previews and assets are converted user files served from Redmine's origin.
    # Sandbox them, so that a script in a converted html, svg or mail cannot act
    # in the user's Redmine session. Chrome does not render a PDF in a sandbox.
    def sandbox_preview(type)
      response.headers['X-Content-Type-Options'] = 'nosniff'
      return if type.to_s == 'application/pdf'
      response.headers['Content-Security-Policy'] = 'sandbox allow-downloads allow-popups allow-popups-to-escape-sandbox'
    end #def
    private :sandbox_preview
    
  end #module
end #module

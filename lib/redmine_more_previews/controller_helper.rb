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
    # Converter.max_repository_file, Converter.max_output, Zippy::LIMITS)
    def render_more_preview_too_large(exception)
      render :plain => l(:text_more_previews_too_large), :status => 413, :content_type => 'text/plain'
    end
    private :render_more_preview_too_large
    
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

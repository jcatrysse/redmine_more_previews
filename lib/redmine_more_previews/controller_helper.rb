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
  
    def preview_params
      params.permit(:format, :asset, :reload, :convert, :unsafe).
      merge({:request => request, 
             :asset   => @asset, 
             :format  => params[:format]&.downcase}.compact )
    end #def
    private :preview_params
    
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

# encoding: utf-8
#
# RedmineMorePreviews vcf (electronic business cards) previewer
#
# Copyright © 2020 Stephan Wenzel <stephan.wenzel@drwpatent.de>
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

class Vince < RedmineMorePreviews::Conversion
  
  # the vCard is parsed and rendered in Ruby, which nothing else bounds: in a
  # child process with this much memory and the conversion timeout (see
  # Conversion#isolated), as Cliff parses an email (port of curecodejp 6b44d3a,
  # GHSA-hm82-jvvw-hmg4)
  MAX_MEMORY = 512 * 1024 * 1024
  
  # larger vCards are refused before the fork (413). 100,000 cards take some
  # 4 MB, which leaves room for photos embedded as data URIs
  MAX_SIZE   = 20 * 1024 * 1024
  
  def convert
  
    # what the child needs from the database is read here, before the fork, and
    # the translations loaded: the child must not use the inherited connection
    @iconize = converter_settings["iconize"].to_i > 0
    @vince_default_language = Setting.default_language
    I18n.with_locale(@vince_default_language){ I18n.translate(:"vcard.personal") }
    
    # without fork (Windows) Lib::RmpProcess.fork runs the block here, without
    # limits: an untrusted vCard is not parsed in the server's process
    raise ConverterShellError, "Vince requires process isolation" unless Process.respond_to?(:fork)
    
    if File.size(source) > MAX_SIZE
      raise ConverterTooLarge, "the vCard is larger than #{MAX_SIZE / 1024 / 1024} MiB"
    end
    
    isolated( :memory => MAX_MEMORY ) do
      VinceLib::VObject::Modules::Localization.language = @vince_default_language
      begin
        @vcfs = VinceLib::VObject::Reader.new(:object => :vcard, :filepath => source).fileall
        
        # create preview
        case preview_format
        
        when "html", "inline"
          erb  = ERB.new(File.read(File.join(views, 'vince', 'vince.html.erb')))
          obj  = I18n.with_locale(@vince_default_language){erb.result(binding).html_safe}.squish
          
        when "txt"
          erb  = ERB.new(File.read(File.join(views, 'vince', 'vince.txt.erb')))
          obj  = I18n.with_locale(@vince_default_language){erb.result(binding).html_safe}.gsub(/\n{3,}/, "\n")
        end
        
        File.open(tmptarget, "wb"){|f| f.write obj}
        
      rescue StandardError => e
        # the child leaves without a message (see Lib::RmpProcess.fork): why the
        # vCard was not previewed goes to the log. The message can quote the vCard
        Rails.logger.error "vCard #{File.basename(source)} not previewed: #{e.class}: #{e.message}\n#{Array(e.backtrace).join("\n")}"
        raise
      ensure
        VinceLib::VObject::Modules::Localization.language = nil
      end
    end
    
  end #def
  
end #class

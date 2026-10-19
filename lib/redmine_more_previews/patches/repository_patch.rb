# encoding: utf-8
# frozen_string_literal: true
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
    module RepositoryPatch
      def self.included(base)
        base.class_eval do
          #unloadable
          
          # the previews of a deleted repository are removed with it, once the
          # deletion is committed: a rolled back deletion keeps them (upstream
          # 504c42f)
          after_destroy_commit :remove_more_preview_cache_on_destroy
          
          ################################################################################
          #
          # preview data functions
          #
          ################################################################################
          # class specific
          def more_preview(path, rev, options={}, &block)
            with_repository_preview_lifecycle_lock do
              # checked under the lock: a request that started before the
              # deletion was committed does not store its preview again
              return nil unless Repository.uncached { Repository.unscoped.exists?(id) }
              if entry(path, rev)
                Dir.mktmpdir do |tmpdir|
                  filepath = File.join(tmpdir, entry(path, rev).name)
                  File.open( filepath, "wb") {|f| f.write(preview_content(path, rev))}
                  RedmineMorePreviews::Converter.convert(
                    filepath,
                    preview_filepath(path, rev, options),
                    options.merge(
                      :object => {:type => :repository, :object => self, :path => path, :rev => rev},
                      :preview_format => preview_format(path, rev)
                    ), 
                    &block
                  )
                end #Dir
              elsif block_given?
                yield nil
              end #if
            end
          end #def
          
          # class specific
          def more_asset(path, rev, options={}, &block)
            with_repository_preview_lifecycle_lock do
              # checked under the lock: a request that started before the
              # deletion was committed does not store its preview again
              return nil unless Repository.uncached { Repository.unscoped.exists?(id) }
              if entry(path, rev)
                Dir.mktmpdir do |tmpdir|
                  filepath = File.join(tmpdir, entry(path, rev).name)
                  File.open( filepath, "wb") {|f| f.write(preview_content(path, rev))}
                  RedmineMorePreviews::Converter.convert(
                    filepath,
                    preview_assetpath(path, rev, options),
                    options.merge(
                      :object => {:type => :repository, :object => self, :path => path, :rev => rev},
                      :preview_format => preview_format(path, rev)
                    ), 
                    &block
                  )
                end #Dir
              elsif block_given?
                yield nil
              end #if
            end
          end #def
          
          # repository files are not bound by the attachment size limit: the size the
          # SCM reports is checked before the file is read (cat reads it whole)
          def preview_content(path, rev)
            if preview_too_large?(path, rev)
              raise RedmineMorePreviews::Exceptions::ConverterTooLarge, "#{path} is larger than #{RedmineMorePreviews::Converter.max_repository_file} bytes, or of unknown size"
            end
            cat(path, rev)
          end #def
          
          # a file whose size the SCM does not report (Bazaar, CVS) counts as too
          # large: it could only be checked after it has been read whole
          def preview_too_large?(path, rev)
            size = entry(path, rev)&.size
            size.nil? || size.to_i > RedmineMorePreviews::Converter.max_repository_file
          end #def
          
          def preview_available?(path, rev, options={})
            File.exist?(preview_filepath(path, rev, options))
          end #def
          
          def asset_available?(path, rev, options={})
            File.exist?(preview_assetpath(path, rev, options))
          end #def
          
          # class specific
          def preview_format(path, rev)
            if e = entry(path, rev)
              extension = File.extname(e.name)[1..-1].downcase
              RedmineMorePreviews::Converter.conversion_extension(extension) if extension
            end
          end #def
          
          def preview_mtime(path, rev, options={})
            preview_available?(path, rev, options) ? File.mtime(preview_filepath(path, rev, options)) : Time.now
          end #def
          
          def asset_mtime(path, rev, options={})
            asset_available?(path, rev, options) ? File.mtime(preview_assetpath(path, rev, options)) : Time.now
          end #def
          
          ################################################################################
          #
          # path functions
          #
          ################################################################################
          def asset_link( path, rev, asset )
          
            extname     = File.extname( path)
            basename    = File.basename(path, extname)
            dirname     = File.dirname(path)
            
            assetformat = File.extname(asset)
            # the folders of the asset stay in its link: the controller finds the
            # stored asset by them (upstream a213a44)
            assetname   = asset.delete_suffix(assetformat)
            
            _link = Rails.application.routes.url_helpers.url_for(
              :controller    => "repositories",
              :action        => "more_asset",
              :id            => project.identifier,
              :repository_id => identifier_param,
              :rev           => rev,
              # a file at the top of the repository has no folder, not "."
              :path          => dirname == "." ? basename : [dirname, basename].join("/"),
              :baseformat    => extname[1..-1],
              :asset         => assetname,
              :assetformat   => assetformat[1..-1], 
              :only_path     => true
            )
            
            if asset_available?(path, rev, :asset => asset)
              ApplicationController.helpers.link_to( asset, _link,
                :class => "icon icon-file #{Marcel::MimeType.for(Pathname.new(preview_assetpath(path, rev, :asset => asset)), name: File.basename(asset))&.tr('/', '-')}",
                :style => "padding-top:2px;padding-bottom:2px;"
              )
            else
              "" # asset does not exist
            end
          end #def
          
          ################################################################################
          #
          # preview file functions
          #
          ################################################################################
          
          #
          # directories
          #
          
          # directory of all previews
          def previews_storagepath
            File.join(RedmineMorePreviews::Constants::Defaults::MORE_PREVIEWS_STORAGE_PATH, self.class.name.underscore.pluralize)
          end #def
          
          # Preview requests take a shared lock on <preview_storagepath>.lifecycle.lock,
          # the removal of a deleted repository's previews an exclusive one: the
          # removal waits for no conversion, a conversion waits no longer than the
          # wait limit (ConverterLockTimeOut)
          def with_repository_preview_lifecycle_lock(mode = File::LOCK_SH)
            FileUtils.mkdir_p(previews_storagepath)
            File.open("#{preview_storagepath}.lifecycle.lock", File::RDWR | File::CREAT, 0644) do |lock|
              deadline = RedmineMorePreviews::Lib::RmpProcess.now + RedmineMorePreviews::Converter.lock_timeout
              until lock.flock(mode | File::LOCK_NB)
                if RedmineMorePreviews::Lib::RmpProcess.now >= deadline
                  raise RedmineMorePreviews::Exceptions::ConverterLockTimeOut, "repository preview #{id} is busy"
                end
                sleep 0.05
              end
              begin
                yield
              ensure
                lock.flock(File::LOCK_UN)
              end
            end
          ensure
            # a removal that found a conversion running is done by the last one
            if mode == File::LOCK_SH && File.file?("#{preview_storagepath}.cleanup_pending")
              RedmineMorePreviews::Patches::RepositoryPatch.cleanup_removed_repository_cache(previews_storagepath, id)
            end
          end #def
          private :with_repository_preview_lifecycle_lock
          
          # the intent is written first: a conversion may outlive the request that
          # deleted the repository, it removes the previews when it ends, as does
          # the cache clean task (rake redmine_more_previews:cache:clean)
          def remove_more_preview_cache_on_destroy
            FileUtils.mkdir_p(previews_storagepath)
            File.write("#{preview_storagepath}.cleanup_pending", "pending\n")
            RedmineMorePreviews::Patches::RepositoryPatch.cleanup_removed_repository_cache(previews_storagepath, id)
          rescue StandardError => e
            Rails.logger.error "Repository preview cache cleanup failed: #{e.class}: #{e.message}"
          end #def
          private :remove_more_preview_cache_on_destroy
          
          # directory of this preview
          def preview_storagepath
            # the id: identifiers repeat across projects (and are empty for default repositories)
            File.join(previews_storagepath, id.to_s)
          end #def
          
          # the revision the entry was last changed in, so a new commit gets a new preview
          def preview_revision(path, rev)
            @preview_revisions ||= {}
            @preview_revisions[[path, rev]] ||= begin
              revision = entry(path, rev)&.lastrev&.identifier.presence ||
                         latest_changesets(path, rev, 1).first&.identifier.presence || rev.presence || "default"
              revision.to_s.gsub(/[^0-9A-Za-z._-]/, "_")
            end
          end #def
          
          # directory containing all preview files and assets
          def preview_dirname(path, rev, options={})
            format = options[:format].presence || preview_format(path, rev).presence
            File.join(preview_storagepath, preview_revision(path, rev), path, ["preview", format ].compact.join("."))
          end #def
          
          #
          # files
          #
          
          # preview file name
          def preview_filename(path, rev, options={})
            format = options[:format].presence || preview_format(path, rev).presence
            ["index", format].compact.join(".")
          end #def
          
          # full path to preview file on disk
          def preview_filepath(path, rev, options={})
            File.join(preview_dirname(path, rev, options), preview_filename(path, rev, options) )
          end #def
          
          # asset file name
          def preview_assetname(path, rev, options={})
            # like Attachment#preview_assetname: the asset name carries its extension
            [options[:asset], options[:assetformat].presence].compact.join(".")
          end #def
          
          # full path to asset file on disk
          def preview_assetpath(path, rev, options={})
#           File.join(preview_dirname(path, rev, options.merge(:format => preview_format(path, rev))), preview_filename(path, rev, options) )
            File.join(preview_dirname(path, rev, options.merge(:format => preview_format(path, rev))), preview_assetname(path, rev, options) )
          end #def
          
        end #base
      end #self
      
      # Removes the previews of the deleted repository id below root (a
      # repository class's previews_storagepath) when its removal is pending, and
      # no conversion holds the lifecycle lock (it is tried again then). An id
      # in use again (a restored database) keeps its previews: only the pending
      # removal goes. True once nothing is pending
      def self.cleanup_removed_repository_cache(root, repository_id)
        return false unless repository_id.to_s.match?(/\A[0-9]+\z/)
        storage = RedmineMorePreviews::Constants::Defaults::MORE_PREVIEWS_STORAGE_PATH
        return false unless RedmineMorePreviews::Lib::RmpFile.within_directory?(storage, root)
        dir = File.join(root, repository_id.to_s)
        pending = "#{dir}.cleanup_pending"
        return false unless File.file?(pending)
        
        File.open("#{dir}.lifecycle.lock", File::RDWR | File::CREAT, 0644) do |lock|
          return false unless lock.flock(File::LOCK_EX | File::LOCK_NB)
          begin
            unless Repository.uncached { Repository.unscoped.exists?(repository_id) }
              if File.symlink?(dir)
                File.unlink(dir) # the link, not what it points to
              elsif File.directory?(dir)
                raise ArgumentError, 'repository cache path is outside storage' unless RedmineMorePreviews::Lib::RmpFile.within_directory?(root, dir)
                FileUtils.remove_entry_secure(dir)
              end
            end
            File.delete(pending) if File.file?(pending)
            true
          ensure
            lock.flock(File::LOCK_UN)
          end
        end
      rescue StandardError => e
        Rails.logger.error "Repository preview cache cleanup failed: #{e.class}: #{e.message}"
        false
      end #def
      
    end #module
  end #module
end #module

unless Repository.included_modules.include?(RedmineMorePreviews::Patches::RepositoryPatch)
  Repository.send(:include, RedmineMorePreviews::Patches::RepositoryPatch)
end



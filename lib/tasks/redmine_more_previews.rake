# frozen_string_literal: true

namespace :redmine_more_previews do
  desc 'Let Redmine preview pdf, images, text, markdown and textile itself, switch the pass converter off ' \
       '(GEOxyz, after the upgrade to Redmine 7). DRY_RUN=1 only lists what would change.'
  task :use_core_previews => :environment do
    dry_run = ENV['DRY_RUN'].present?
    changes = RedmineMorePreviews::CoreHandover.apply!(:dry_run => dry_run)
    if changes.empty?
      puts 'Nothing to change: Redmine already previews these file types itself.'
    else
      puts "#{dry_run ? 'Would switch off' : 'Switched off'}: #{changes.join(', ')}"
    end
  end

  # Removes the cached previews created more than DAYS (default 30) days ago.
  # Run it from cron, f.i. daily:
  #   bundle exec rake redmine_more_previews:cache:clean RAILS_ENV=production DAYS=30
  # All of them, f.i. once after an upgrade, under the same per-preview locks
  # (upstream cef06a3):
  #   bundle exec rake redmine_more_previews:cache:clean RAILS_ENV=production DAYS=0 CONFIRM_PURGE_ALL=1
  namespace :cache do
    desc 'Remove the previews cached more than DAYS (default 30) days ago; DAYS=0 CONFIRM_PURGE_ALL=1 removes all'
    task :clean => :environment do
      raw_days = ENV['DAYS'].presence || RedmineMorePreviews::Constants::Defaults::CACHE_DAYS.to_s
      abort "DAYS must be a number of days, 0 or more" unless raw_days.to_s.match?(/\A\d+\z/)
      days = raw_days.to_i
      if days.zero? && ENV['CONFIRM_PURGE_ALL'] != '1'
        abort "DAYS=0 removes all cached previews; set CONFIRM_PURGE_ALL=1 as well"
      end
      removed = RedmineMorePreviews::Lib::RmpCacheClean.run( days )
      puts "#{removed} cached previews removed"
    end
  end
end

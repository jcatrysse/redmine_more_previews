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
  namespace :cache do
    desc 'Remove the previews cached more than DAYS (default 30) days ago'
    task :clean => :environment do
      days = (ENV['DAYS'].presence || RedmineMorePreviews::Constants::Defaults::CACHE_DAYS).to_i
      abort "DAYS must be a positive number of days" unless days > 0
      removed = RedmineMorePreviews::Lib::RmpCacheClean.run( days )
      puts "#{removed} cached previews removed"
    end
  end
end

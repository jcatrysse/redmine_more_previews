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
end

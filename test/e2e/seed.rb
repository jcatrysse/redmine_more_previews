# Plugin data for the end-to-end checks, run by .codex/start_server.sh after the
# generic seed. Idempotent.
#
# - activates the converters the way GEOxyz would use them, one format per
#   file type, without double registrations (pass owns .html, teddie owns .txt,
#   peek owns .pdf);
# - attaches one sample file per converter to the issue "E2E previews" in
#   e2e-project, and one to an issue in e2e-private;
# - creates a git repository with the same samples for the repository previews.

files = File.expand_path('../fixtures/files', __dir__)
admin = User.find_by!(login: 'admin')
User.current = admin
project = Project.find_by!(identifier: 'e2e-project')
private_project = Project.find_by!(identifier: 'e2e-private')

def mime(formats)
  formats.transform_values { |format| { 'active' => '1', 'format' => format } }
end

Setting.plugin_redmine_more_previews = {
  'embedding' => '0', 'cache_previews' => '1', 'debug' => '0', 'absolute' => '0',
  'converter' => {
    'libre' => { 'active' => '1', 'mime_types' => mime('docx' => 'pdf', 'odt' => 'html', 'xlsx' => 'html', 'csv' => 'png') },
    'cliff' => { 'active' => '1', 'mime_types' => mime('eml' => 'html') },
    'vince' => { 'active' => '1', 'mime_types' => mime('vcf' => 'html') },
    'mark' => { 'active' => '1', 'mime_types' => mime('md' => 'html', 'textile' => 'inline') },
    'pass' => { 'active' => '1', 'mime_types' => mime('html' => 'html') },
    'teddie' => { 'active' => '1', 'mime_types' => mime('txt' => 'txt') },
    'peek' => { 'active' => '1', 'mime_types' => mime('pdf' => 'pdf') },
    'maggie' => { 'active' => '1', 'mime_types' => mime('png' => 'jpg') },
    'zippy' => { 'active' => '1', 'mime_types' => mime('zip' => 'html', 'tar' => 'inline', 'tgz' => 'html') },
    'nil_text' => { 'active' => '0' }
  }
}

def e2e_preview_issue(project, subject, author)
  Issue.find_by(project_id: project.id, subject: subject) ||
    Issue.create!(project: project, tracker: project.trackers.first, subject: subject, author: author,
                  priority: IssuePriority.default || IssuePriority.first,
                  status: project.trackers.first.default_status,
                  description: 'Carries one sample file per converter of redmine_more_previews.')
end

def e2e_attach(container, path, author)
  name = File.basename(path)
  return if container.attachments.where(filename: name).exists?

  attachment = Attachment.new(file: File.open(path, 'rb'), author: author)
  attachment.filename = name
  attachment.content_type = Marcel::MimeType.for(Pathname.new(path), name: name)
  attachment.container = container
  attachment.save!
end

issue = e2e_preview_issue(project, 'E2E previews', admin)
Dir[File.join(files, 'sample.*')].sort.each { |f| e2e_attach(issue, f, admin) }
private_issue = e2e_preview_issue(private_project, 'E2E private previews', admin)
e2e_attach(private_issue, File.join(files, 'sample.md'), admin)

# git repository with the samples, for RepositoriesController#entry
Setting.enabled_scm = (Setting.enabled_scm.to_a | ['Git'])
repo_dir = Rails.root.join('tmp', 'e2e-repo').to_s
unless File.directory?(File.join(repo_dir, '.git'))
  FileUtils.mkdir_p(File.join(repo_dir, 'docs'))
  %w(sample.md sample.zip sample.vcf sample.txt).each { |f| FileUtils.cp(File.join(files, f), repo_dir) }
  FileUtils.cp(File.join(files, 'sample.docx'), File.join(repo_dir, 'docs'))
  system('git', '-C', repo_dir, 'init', '-q', '-b', 'main', exception: true)
  system('git', '-C', repo_dir, 'add', '.', exception: true)
  system('git', '-C', repo_dir, '-c', 'user.name=E2E', '-c', 'user.email=e2e@example.net',
         'commit', '-q', '-m', 'Samples for the previews', exception: true)
end
project.enabled_module_names = (project.enabled_module_names | ['repository'])
repository = project.repositories.find_by(identifier: 'samples') ||
             Repository::Git.new(project: project, identifier: 'samples', is_default: true)
repository.url = repository.root_url = File.join(repo_dir, '.git') # git wants the .git directory of a working copy
repository.save!
repository.fetch_changesets

puts "Plugin seed: #{issue.attachments.count} sample attachments on issue ##{issue.id}, " \
     "private issue ##{private_issue.id}, repository #{repository.identifier} (#{repository.changesets.count} changeset)"

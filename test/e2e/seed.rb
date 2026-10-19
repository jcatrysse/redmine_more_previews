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
  # 10 s instead of 60 so limits.mjs does not wait long for the hanging stand-in (test/e2e/bin/pandoc)
  'conversion_timeout' => '10',
  'converter' => {
    'libre' => { 'active' => '1', 'mime_types' => mime('docx' => 'pdf', 'odt' => 'html', 'xlsx' => 'html', 'csv' => 'png') },
    # max_size 1 MiB instead of 50 so an oversized email fits below Redmine's attachment limit
    'cliff' => { 'active' => '1', 'mime_types' => mime('eml' => 'html'), 'max_size' => '1' },
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

# files beyond the conversion limits (test/e2e/limits.mjs), generated here: an archive bomb,
# an archive of too many entries, emails too large, too deeply nested or of too many parts,
# a markdown file the pandoc stand-in hangs on, and a hostile vCard
require 'zip'
limits_dir = Rails.root.join('tmp', 'e2e-limits').to_s
FileUtils.mkdir_p(limits_dir)
limits = {
  'bomb.zip' => lambda do |path|
    Zip::OutputStream.open(path) do |zip|
      zip.put_next_entry('readme.txt')
      zip.write("200 MiB of zeros follow\n")
      zip.put_next_entry('zeros.bin')
      chunk = "\0" * (1024 * 1024)
      200.times { zip.write(chunk) }
    end
  end,
  'many.zip' => lambda do |path|
    Zip::OutputStream.open(path) do |zip|
      10_001.times { |n| zip.put_next_entry("f#{n}.txt"); zip.write('x') }
    end
  end,
  'large.eml' => ->(path) { File.write(path, "From: a@example.net\r\nSubject: large\r\n\r\n" + ("x" * 76 + "\r\n") * 30_000) },
  'nested.eml' => lambda do |path|
    mail = +"From: a@example.net\r\nSubject: nested\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=\"b1\"\r\n\r\n"
    (2..150).each { |n| mail << "--b#{n - 1}\r\nContent-Type: multipart/mixed; boundary=\"b#{n}\"\r\n\r\n" }
    mail << "--b150\r\nContent-Type: text/plain\r\n\r\nleaf\r\n"
    150.downto(1) { |n| mail << "--b#{n}--\r\n" }
    File.write(path, mail)
  end,
  'parts.eml' => lambda do |path|
    mail = +"From: a@example.net\r\nSubject: parts\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=\"p\"\r\n\r\n"
    1_001.times { |n| mail << "--p\r\nContent-Type: text/plain\r\n\r\npart #{n}\r\n" }
    File.write(path, mail << "--p--\r\n")
  end,
  'hang.md' => ->(path) { File.write(path, "# E2E-HANG\n\nThe pandoc stand-in of the e2e checks never returns for this file.\n") },
  'hostile.vcf' => lambda do |path|
    File.write(path, [
      'BEGIN:VCARD', 'VERSION:4.0', 'FN:Mallory <b>bold</b><img src=x onerror=alert(1)>', 'N:Mallory;Eve;;;',
      'URL:javascript:alert(document.domain)', 'IMPP:javascript:alert(1)', 'EMAIL:eve@example.net',
      'GEO:geo:37.386013,-122.082932/../../../evil', 'TEL;VALUE=uri:tel:+1-555-0100',
      'PHOTO;VALUE=uri:file:///etc/passwd', 'END:VCARD', ''
    ].join("\r\n"))
  end
}
limits_issue = e2e_preview_issue(project, 'E2E limits', admin)
limits.each do |name, make|
  path = File.join(limits_dir, name)
  make.call(path) unless File.exist?(path)
  e2e_attach(limits_issue, path, admin)
end

# with redmine_contacts_helpdesk (combined run): hostile customer emails arrive as tickets
# through HelpdeskMailer.receive, which stores each as message.eml on the ticket
# (test/e2e/helpdesk_mail.mjs); a Message-ID seen before is ignored the second time
if defined?(HelpdeskMailer)
  project.enabled_module_names = (project.enabled_module_names | %w(contacts contacts_helpdesk))
  ContactsSetting['helpdesk_answer_from', project.id] ||= 'support@e2e.example'
  nested = +"Content-Type: multipart/mixed; boundary=\"h1\"\r\n\r\n"
  (2..150).each { |n| nested << "--h#{n - 1}\r\nContent-Type: multipart/mixed; boundary=\"h#{n}\"\r\n\r\n" }
  nested << "--h150\r\nContent-Type: text/plain\r\n\r\nleaf\r\n"
  150.downto(1) { |n| nested << "--h#{n}--\r\n" }
  parts = +"Content-Type: multipart/mixed; boundary=\"p\"\r\n\r\n"
  1_001.times { |n| parts << "--p\r\nContent-Type: text/plain\r\n\r\npart #{n}\r\n" }
  parts << "--p--\r\n"
  { 'E2E hostile mail nested' => nested, 'E2E hostile mail parts' => parts }.each_with_index do |(subject, body), i|
    raw = ["Message-ID: <e2e-hostile-#{i}@customer.example>", "Date: #{Time.now.rfc2822}",
           'From: Mallory <mallory@customer.example>', 'To: support@e2e.example',
           "Subject: #{subject}", 'MIME-Version: 1.0'].join("\r\n") + "\r\n" + body
    HelpdeskMailer.receive(raw, issue: { project_id: project.identifier })
  end
end

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

# 'viewer': member of e2e-project with a role that may view changesets but not browse the
# repository (repository previews need browse_repository, Jan 2026-10-11)
changesets_role = Role.find_by(name: 'E2E changesets only') || Role.new(name: 'E2E changesets only')
changesets_role.permissions = %i(view_issues view_changesets)
changesets_role.save!
viewer = User.find_by(login: 'viewer') ||
         User.new(login: 'viewer', firstname: 'Viewer', lastname: 'E2E', mail: 'viewer@example.net')
viewer.password = viewer.password_confirmation = ENV.fetch('RMP_USER_PASSWORD', ENV.fetch('RMP_ADMIN_PASSWORD', 'Redmine7Test!'))
viewer.must_change_passwd = false
viewer.status = User::STATUS_ACTIVE
viewer.save!(validate: false)
Member.create!(principal: viewer, project: project, roles: [changesets_role]) unless Member.where(user_id: viewer.id, project_id: project.id).exists?

# round 6 (curecodejp 6.1.3): an ODT that links a file of the server as its image (Libre's
# sandbox must not embed it), a vCard with IMPP and a photo, a file whose copy on disk the
# scenario removes, a markdown file named with a leading dash; and a second repository with
# an email (with an attachment) at its top, deleted by test/e2e/repository_delete.mjs
require 'base64'
round6_dir = Rails.root.join('tmp', 'e2e-round6').to_s
FileUtils.mkdir_p(round6_dir)
secret_png = File.join(round6_dir, 'server-secret.png')
unless File.exist?(secret_png)
  require 'zlib'
  chunk = ->(kind, body) { [body.bytesize].pack('N') + kind + body + [Zlib.crc32(kind + body)].pack('N') }
  rows = 4.times.map { |y| "\x00".b + 4.times.map { |x| [20 + x * 60, 25 + y * 55, 50 + (x + y * 4) * 12].pack('C3') }.join }.join
  File.binwrite(secret_png, "\x89PNG\r\n\x1a\n".b + chunk.call('IHDR', [4, 4, 8, 2, 0, 0, 0].pack('NNC5')) +
                            chunk.call('IDAT', Zlib::Deflate.deflate(rows)) + chunk.call('IEND', ''.b))
end
round6 = {
  'external-image.odt' => lambda do |path|
    ns = 'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" ' \
         'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" ' \
         'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" ' \
         'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" xmlns:xlink="http://www.w3.org/1999/xlink"'
    content = %(<?xml version="1.0" encoding="UTF-8"?><office:document-content #{ns} office:version="1.2">) +
              '<office:body><office:text><text:p>E2E-SANDBOX: the image below is a file of the server</text:p>' \
              '<text:p><draw:frame draw:name="ServerFile" text:anchor-type="as-char" svg:width="3cm" svg:height="3cm">' +
              %(<draw:image xlink:href="file://#{secret_png}" xlink:type="simple" xlink:show="embed" xlink:actuate="onLoad"/>) +
              '</draw:frame></text:p></office:text></office:body></office:document-content>'
    manifest = '<?xml version="1.0" encoding="UTF-8"?><manifest:manifest ' \
               'xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">' \
               '<manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/>' \
               '<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/></manifest:manifest>'
    Zip::File.open(path, create: true) do |zip|
      zip.get_output_stream('mimetype') { |io| io.write('application/vnd.oasis.opendocument.text') }
      zip.get_output_stream('content.xml') { |io| io.write(content) }
      zip.get_output_stream('META-INF/manifest.xml') { |io| io.write(manifest) }
    end
  end,
  'impp.vcf' => lambda do |path|
    png = Base64.strict_encode64(File.binread(secret_png))
    File.write(path, ['BEGIN:VCARD', 'VERSION:4.0', 'FN:Ivy Impp', 'N:Impp;Ivy;;;', 'IMPP:xmpp:ivy@example.net',
                      "PHOTO:data:image/png;base64,#{png}", 'END:VCARD', ''].join("\r\n"))
  end,
  'gone.txt' => ->(path) { File.write(path, "removed from disk by test/e2e/missing_file.mjs\n") },
  '-draft.md' => ->(path) { File.write(path, "# Draft\n\nA file name that starts with a dash.\n") }
}
round6_issue = e2e_preview_issue(project, 'E2E round 6', admin)
round6.each do |name, make|
  path = File.join(round6_dir, name)
  make.call(path) unless File.exist?(path)
  e2e_attach(round6_issue, path, admin)
end
repo6_dir = Rails.root.join('tmp', 'e2e-repo6').to_s
unless File.directory?(File.join(repo6_dir, '.git'))
  FileUtils.mkdir_p(repo6_dir)
  File.write(File.join(repo6_dir, 'with-attachment.eml'), [
    'From: Alice <alice@example.net>', 'To: Bob <bob@example.net>', 'Subject: E2E email with an attachment',
    'MIME-Version: 1.0', 'Content-Type: multipart/mixed; boundary="att"', '',
    '--att', 'Content-Type: text/plain; charset=UTF-8', '', 'The note is attached.', '',
    '--att', 'Content-Type: text/plain; name="note.txt"', 'Content-Disposition: attachment; filename="note.txt"', '',
    'E2E-NOTE: the attachment of the email', '--att--', ''
  ].join("\r\n"))
  FileUtils.cp(File.join(files, 'sample.md'), repo6_dir)
  system('git', '-C', repo6_dir, 'init', '-q', '-b', 'main', exception: true)
  system('git', '-C', repo6_dir, 'add', '.', exception: true)
  system('git', '-C', repo6_dir, '-c', 'user.name=E2E', '-c', 'user.email=e2e@example.net',
         'commit', '-q', '-m', 'An email for the previews', exception: true)
end
repository6 = project.repositories.find_by(identifier: 'round6') ||
              Repository::Git.new(project: project, identifier: 'round6', is_default: false)
repository6.url = repository6.root_url = File.join(repo6_dir, '.git')
repository6.save!
repository6.fetch_changesets

# for scenarios that upload through the REST API
File.write(Rails.root.join('tmp', 'e2e-manager-api-key'), User.find_by!(login: 'manager').api_key)

puts "Plugin seed: #{issue.attachments.count} sample attachments on issue ##{issue.id}, " \
     "#{limits_issue.attachments.count} beyond the limits on ##{limits_issue.id}, " \
     "private issue ##{private_issue.id}, repository #{repository.identifier} (#{repository.changesets.count} changeset)"

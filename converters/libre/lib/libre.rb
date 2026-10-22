# encoding: utf-8
#
# RedmineMorePreviews converter to preview office files with LibreOffice
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

# LibreOffice runs in a bubblewrap sandbox (upstream 4fc7d00, cef06a3): no
# network, its own user, PID, IPC and UTS namespaces, an empty environment, and
# of the host only the input file (read-only), a writable output directory and
# profile, and the read-only system paths LibreOffice needs. A document cannot
# embed a file of the server (an image or a link to file:///...), nor reach the
# network. Linux only: without a working sandbox Libre converts nothing, there
# is no fallback to an unsandboxed LibreOffice.
class Libre < RedmineMorePreviews::Conversion

  #---------------------------------------------------------------------------------
  # constants
  #---------------------------------------------------------------------------------
  # a distribution's LibreOffice, by its absolute path: PATH is not used
  LIBRE_OFFICE_BIN = '/usr/bin/soffice'.freeze
  BWRAP_BIN = '/usr/bin/bwrap'.freeze
  ENV_BIN = '/usr/bin/env'.freeze
  ALLOWED_OUTPUT_FORMATS = %w(html txt pdf png jpg).freeze
  
  #---------------------------------------------------------------------------------
  # check: can LibreOffice run in its sandbox?
  #---------------------------------------------------------------------------------
  def status
    [:text_libre_office_available, sandbox_available?]
  end
  
  def convert
    raise ConverterShellError, 'LibreOffice sandbox unavailable' unless sandbox_available?
    
    Dir.mktmpdir do |tdir| 
      user_installation = File.join(tdir, "user_installation")
      command(cd + join + soffice( source, user_installation ))
      # what LibreOffice wrote is untrusted: no symlink or hard link is followed,
      # renamed or copied into the cache
      validate_libre_output!
      # LibreOffice names its output after the input inside the sandbox
      generated = File.join(tmpdir, File.basename(sandbox_input_name(source), '.*') + ".#{preview_format}")
      raise ConverterShellError, 'LibreOffice output is missing' unless File.file?(generated)
      File.rename(generated, tmptarget) unless generated == tmptarget
    end
    
  end #def
  
  # whether bubblewrap starts a sandbox with the namespaces Libre uses: an
  # executable bwrap is not enough (user namespaces may be off, or forbidden by
  # AppArmor or a container's seccomp profile). soffice must resolve inside the
  # paths the sandbox mounts (/usr/bin, /usr/lib): a LibreOffice under /opt
  # linked from /usr/bin/soffice would pass the probe and fail every conversion.
  # Probed for each worker (each conversion and each status check), in at most
  # 5 seconds, with the plugin's process handling
  def sandbox_available?
    return false if Redmine::Platform.mswin?
    return false unless [LIBRE_OFFICE_BIN, BWRAP_BIN, ENV_BIN].all? { |path| File.executable?(path) }
    return false unless File.directory?('/etc/fonts') && File.file?('/etc/ld.so.cache')
    return false unless %w(/usr/bin/ /usr/lib/).any? { |dir| File.realpath(LIBRE_OFFICE_BIN).start_with?(dir) }
    
    return @sandbox_probe_ok unless @sandbox_probe_ok.nil?
    command = [ENV_BIN, '-i', BWRAP_BIN, '--die-with-parent', '--new-session',
               '--unshare-user', '--unshare-pid', '--unshare-net', '--unshare-ipc', '--unshare-uts',
               '--ro-bind', '/usr', '/usr']
    %w(/bin /sbin /lib /lib64).each do |path|
      if File.symlink?(path)
        command.concat(['--symlink', File.readlink(path), path])
      elsif File.directory?(path)
        command.concat(['--ro-bind', path, path])
      end
    end
    command.concat(['--', '/usr/bin/true'])
    status = RedmineMorePreviews::Lib::RmpProcess.run(command, :timeout => 5, :in => File::NULL, :out => File::NULL, :err => File::NULL)
    @sandbox_probe_ok = status.success?
  rescue SystemCallError, ConverterTimeout
    @sandbox_probe_ok = false
  end #def
  private :sandbox_available?
  
  # only directories and regular files of one link each, never followed
  def validate_libre_output!
    pending = [tmpdir]
    while (directory = pending.pop)
      Dir.children(directory).each do |name|
        path = File.join(directory, name)
        stat = File.lstat(path)
        if stat.directory?
          pending << path
        elsif !stat.file? || stat.nlink != 1
          raise ConverterShellError, 'LibreOffice produced an unsafe output entry'
        end
      end
    end
  rescue SystemCallError => e
    raise ConverterShellError, "Could not inspect LibreOffice output: #{e.class}"
  end #def
  private :validate_libre_output!
  
  # LibreOffice names a spreadsheet's sheet after the input file and prints the
  # sheet name as the page header (pdf, png, jpg of a csv). Inside the sandbox the
  # input gets the attachment's or repository file's own name (sample.csv), not
  # Redmine's disk name (261019054842_sample.csv); only the characters Redmine
  # keeps in a disk name, the extension of the file on disk
  def sandbox_input_name( src )
    original = if object.is_a?(Hash)
                 object['type'] == :attachment ? object['object'].try(:filename) : object['path']
               end
    stem = File.basename(original.to_s, File.extname(original.to_s)).gsub(/[^a-zA-Z0-9_\-]/, '_')[0, 100]
    stem = File.basename(src, File.extname(src)) if stem.delete('_').empty?
    stem + File.extname(src)
  end #def
  private :sandbox_input_name
  
  def soffice( src, user_installation )
    # the format comes from the plugin settings, which an administrator edits:
    # checked before it goes into the shell command, and quoted
    output_format = preview_format.to_s
    unless ALLOWED_OUTPUT_FORMATS.include?(output_format)
      raise ConverterBadArgument, 'Unsupported LibreOffice output format'
    end
    if Redmine::Platform.mswin?
      raise ConverterShellError, 'LibreOffice sandbox is not supported on Windows'
    end
    
    # only this one input file is mounted, never its directory or the host's root
    paths = [src, user_installation, tmpdir]
    unless paths.all? { |path| path.is_a?(String) && path.start_with?('/') && !path.include?("\0") }
      raise ConverterBadArgument, 'LibreOffice sandbox requires absolute paths'
    end
    
    input_name = sandbox_input_name(src)
    profile_host_dir = File.dirname(user_installation)
    if input_name == '.' || input_name == '..' || src == '/' ||
       tmpdir == '/' || profile_host_dir == '/'
      raise ConverterBadArgument, 'Refusing to mount a host root or directory as LibreOffice input'
    end
    input_in_sandbox = File.join('/input', input_name)
    # bwrap 0.4.0 has no --clearenv: env -i empties the environment before bwrap
    # starts, --setenv gives LibreOffice the little it needs
    args = [
      ENV_BIN, '-i', BWRAP_BIN,
      '--die-with-parent', '--new-session',
      '--unshare-user', '--unshare-pid', '--unshare-net', '--unshare-ipc', '--unshare-uts',
      '--dir', '/usr',
      '--ro-bind', '/usr/bin', '/usr/bin',
      '--ro-bind', '/usr/lib', '/usr/lib',
      '--dir', '/usr/share',
      '--dir', '/etc',
      '--ro-bind', '/etc/fonts', '/etc/fonts',
      '--ro-bind', '/etc/ld.so.cache', '/etc/ld.so.cache',
      '--dev', '/dev', '--proc', '/proc',
      '--tmpfs', '/tmp', '--tmpfs', '/run',
      '--dir', '/input',
      '--ro-bind', src, input_in_sandbox,
      '--bind', tmpdir, '/output',
      '--bind', profile_host_dir, '/profile',
      '--setenv', 'HOME', '/tmp',
      '--setenv', 'TMPDIR', '/tmp',
      '--setenv', 'XDG_CACHE_HOME', '/tmp/cache',
      '--setenv', 'XDG_CONFIG_HOME', '/tmp/config',
      '--setenv', 'PATH', '/usr/bin:/bin',
      '--setenv', 'LANG', 'C.UTF-8',
      '--chdir', '/tmp', '--',
      LIBRE_OFFICE_BIN,
      '--headless', '--invisible', '--nodefault', '--nofirststartwizard',
      '--nolockcheck', '--nologo', '--norestore',
      '--convert-to', output_format,
      '--outdir', '/output',
      '-env:UserInstallation=file:///profile/user_installation',
      input_in_sandbox
    ]
    # /usr/share may hold secrets of other applications: only what LibreOffice
    # needs, not /usr/share or /usr/local as a whole
    optional_dirs = %w(
      /usr/lib64 /usr/share/fonts /usr/share/fontconfig /usr/share/locale
      /usr/share/mime /usr/share/libreoffice /usr/share/icu /usr/share/zoneinfo
      /etc/alternatives /etc/libreoffice
    )
    extra_mounts = optional_dirs.select { |path| File.directory?(path) }.flat_map do |path|
      ['--ro-bind', path, path]
    end
    # /bin and /lib are links into /usr on a merged /usr (Ubuntu, Debian 12),
    # directories on older systems: as on the host, without binding /
    %w(/bin /sbin /lib /lib64).each do |path|
      if File.symlink?(path)
        extra_mounts.concat(['--symlink', File.readlink(path), path])
      elsif File.directory?(path)
        extra_mounts.concat(['--ro-bind', path, path])
      end
    end
    # the mounts before the environment and the command
    execution = args.index('--setenv')
    args.insert(execution, *extra_mounts)
    args.map { |arg| shell_quote(arg) }.join(' ')
  end #def
  
end #class

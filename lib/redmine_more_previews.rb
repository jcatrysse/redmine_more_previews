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

require 'open3'

module RedmineMorePreviews
  
  CONVERT_BIN = (Redmine::Configuration['imagemagick_convert_command'] || 'convert').freeze
  
  # bounds of ImageMagick's pixel cache. width, height and disk are hard limits (the
  # conversion fails): -resample enlarges an image by its own resolution, which the
  # file sets. They do not bound Ghostscript's rendering of a PDF page, which only
  # the time limit of the conversion stops (see Conversion#command).
  IMAGEMAGICK_LIMITS = [["width", "16KP"], ["height", "16KP"], ["area", "128MP"],
                        ["memory", "256MiB"], ["map", "512MiB"], ["disk", "1GiB"]].freeze
  
  # the ImageMagick program the previews run: Redmine's imagemagick_convert_command,
  # "convert" (ImageMagick 6) unless it is set, f.i. to "magick" (ImageMagick 7)
  def self.convert_bin
    CONVERT_BIN
  end #def

  # ImageMagick's convert with the limits above, for Maggie and Peek
  def self.convert_command
    ([Redmine::Utils::Shell.shell_quote(convert_bin)] + IMAGEMAGICK_LIMITS.map{|resource, value| "-limit #{resource} #{value}"}).join(" ")
  end #def

  # Whether a file starts as a HEIC image: an ISO BMFF "ftyp" box whose major brand
  # is a HEVC brand, or "mif1" / "msf1" with a HEVC brand among the compatible ones.
  # Marcel reports image/heic for a file named so whatever it holds, and libheif
  # decodes whatever codec an image item names, not only HEVC: a file that names
  # an AVIF brand anywhere is not handed to the HEIC coder. A file that hides an
  # AV1 (or other) item behind HEVC brands is decoded if libheif has a decoder for it.
  HEVC_BRANDS = %w(heic heix hevc hevx heim heis hevm hevs).freeze
  AVIF_BRANDS = %w(avif avis).freeze

  def self.valid_heif_magic?(path)
    head = File.binread(path, 256).to_s
    return false unless head.bytesize >= 16 && head[4, 4] == "ftyp".b
    size   = head[0, 4].unpack1("N")
    # the whole box is read, or its brands cannot all be checked
    return false unless size >= 16 && size % 4 == 0 && size <= head.bytesize
    major  = head[8, 4]
    brands = head[16...size].to_s.scan(/.{4}/m)
    return false if ([major] + brands).any?{|brand| AVIF_BRANDS.include?(brand) }
    HEVC_BRANDS.include?(major) || (%w(mif1 msf1).include?(major) && brands.any?{|brand| HEVC_BRANDS.include?(brand) })
  rescue SystemCallError
    false
  end #def

  # Whether a file starts as a TIFF image (little or big endian, classic or BigTIFF)
  TIFF_MAGICS = ["II*\0", "MM\0*", "II+\0", "MM\0+"].map(&:b).freeze

  def self.valid_tiff_magic?(path)
    TIFF_MAGICS.include?(File.binread(path, 4).to_s)
  rescue SystemCallError
    false
  end #def

  # The size [width, height] a HEIC file declares for its primary image (the
  # "ispe" property of the "pitm" item, the coded size before "clap" crops it),
  # nil when it cannot be read: libheif allocates memory for this size while
  # decoding, outside ImageMagick's limits. The top-level boxes are walked to the
  # end of the file, at most HEIF_TOP_BOXES of them: libheif takes the last "meta"
  # box, so a file with more than one is not read. The "meta" box is read whole
  # when it is at most HEIF_META_LIMIT bytes.
  # It is what the file declares: a crafted file may code a larger image than
  # it declares, which only the time limit of the conversion stops.
  HEIF_META_LIMIT = 1024 * 1024
  HEIF_TOP_BOXES  = 16

  def self.heif_dimensions(path)
    File.open(path, 'rb') do |io|
      meta = heif_meta(io)
      return nil unless meta && meta.bytesize >= 4
      boxes = iso_boxes(meta, 4) or return nil
      # ours: a box libheif takes the first of, or an item it finds twice, is not
      # guessed at: such a file is not read (fail closed)
      return nil unless heif_single?(boxes, 'pitm') && heif_single?(boxes, 'iprp')
      pitm  = boxes.assoc('pitm')&.last
      iprp  = boxes.assoc('iprp')&.last
      return nil unless pitm && iprp && pitm.bytesize >= 6
      item  = pitm.getbyte(0) == 0 ? pitm[4, 2].unpack1('n') : pitm[4, 4].to_s.unpack1('N')
      iprp  = iso_boxes(iprp) or return nil
      return nil unless heif_single?(iprp, 'ipco')
      ipco  = iso_boxes(iprp.assoc('ipco')&.last.to_s) or return nil
      entries = iprp.select{|type, _| type == 'ipma' }.flat_map{|_, ipma| heif_associations(ipma, item) || (return nil) }
      return nil if entries.size > 1
      ispes = entries.flatten.filter_map{|index| ipco[index - 1] if index > 0 }.select{|type, _| type == 'ispe' }
      return nil if ispes.size > 1
      ispe  = ispes.first&.last
      return nil unless ispe && ispe.bytesize >= 12
      size = ispe[4, 8].unpack('NN')
      size.all?(&:positive?) ? size : nil
    end
  rescue SystemCallError, IOError
    nil
  end #def

  # the payload of the only top-level "meta" box, nil when there is none or more
  # than one, it is larger than HEIF_META_LIMIT or cut short, or the file has more
  # than HEIF_TOP_BOXES boxes. As for libheif, the walk ends with the file, or with
  # a box that reaches its end (size 0) or beyond it (f.i. a file cut short)
  def self.heif_meta(io)
    meta = nil
    HEIF_TOP_BOXES.times do
      header = io.read(8).to_s
      return meta if header.bytesize < 8
      size, type = header.unpack('Na4')
      length = 8
      if size == 1
        large = io.read(8).to_s
        return meta if large.bytesize < 8
        size, length = large.unpack1('Q>'), 16
      end
      return (type == 'meta' ? nil : meta) if size == 0
      return nil if size < length
      beyond = size - length > io.size - io.pos
      if type == 'meta'
        return nil if meta || beyond || size - length > HEIF_META_LIMIT
        meta = io.read(size - length)
      else
        return meta if beyond
        io.seek(size - length, IO::SEEK_CUR)
      end
    end
    io.eof? ? meta : nil
  end #def
  private_class_method :heif_meta

  # the boxes [type, payload] within data from offset on, nil when one does not
  # fit (a 64-bit size within a "meta" box is not expected)
  def self.iso_boxes(data, offset = 0)
    boxes = []
    while offset < data.bytesize
      return nil if data.bytesize - offset < 8
      size, type = data[offset, 8].unpack('Na4')
      size = data.bytesize - offset if size == 0
      return nil if size < 8 || offset + size > data.bytesize
      boxes << [type, data[offset + 8, size - 8]]
      offset += size
    end
    boxes
  end #def
  private_class_method :iso_boxes

  # at most one box of the type among boxes
  def self.heif_single?(boxes, type)
    boxes.count{|box_type, _| box_type == type } <= 1
  end #def
  private_class_method :heif_single?

  # the (1-based) property indices an "ipma" box associates with the item, one
  # list for each entry of the item (ours: all of them, not the first only),
  # nil when the box is cut short
  def self.heif_associations(ipma, item)
    return nil if ipma.bytesize < 8
    version, flags = ipma.getbyte(0), ("\0".b + ipma[1, 3]).unpack1('N')
    id_size, index_size = (version < 1 ? 2 : 4), (flags & 1 == 1 ? 2 : 1)
    offset = 8
    found  = []
    ipma[4, 4].unpack1('N').times do
      return nil if offset + id_size + 1 > ipma.bytesize
      id = ipma[offset, id_size].unpack1(id_size == 2 ? 'n' : 'N')
      count = ipma.getbyte(offset + id_size)
      offset += id_size + 1
      return nil if offset + count * index_size > ipma.bytesize
      if id == item
        found << ipma[offset, count * index_size].unpack(index_size == 2 ? 'n*' : 'C*').map{|value| value & (index_size == 2 ? 0x7fff : 0x7f) }
      end
      offset += count * index_size
    end
    found
  end #def
  private_class_method :heif_associations

  # The size [width, height] the first page of a TIFF file declares (the
  # ImageWidth and ImageLength tags of its first IFD), nil when it cannot be
  # read: libtiff allocates memory by them. Classic TIFF and BigTIFF, either
  # byte order; at most TIFF_MAX_ENTRIES tags.
  TIFF_MAX_ENTRIES = 4096

  def self.tiff_dimensions(path)
    File.open(path, 'rb') do |io|
      head = io.read(16).to_s
      return nil unless head.bytesize >= 8
      order = {"II" => %w(v V Q<), "MM" => %w(n N Q>)}[head[0, 2]] or return nil
      u16, u32, u64 = order
      case head[2, 2].unpack1(u16)
      when 42
        offset, count_size, entry_size, value_at = head[4, 4].unpack1(u32), 2, 12, 8
      when 43
        return nil unless head.bytesize == 16 && head[4, 4].unpack(u16 * 2) == [8, 0]
        offset, count_size, entry_size, value_at = head[8, 8].unpack1(u64), 8, 20, 12
      else
        return nil
      end
      return nil unless offset >= 8 && offset < io.size
      io.seek(offset)
      count = io.read(count_size).to_s
      return nil unless count.bytesize == count_size
      count = count.unpack1(count_size == 2 ? u16 : u64)
      return nil unless count.between?(1, TIFF_MAX_ENTRIES)
      entries = io.read(count * entry_size).to_s
      return nil unless entries.bytesize == count * entry_size
      size = {}
      count.times do |i|
        entry = entries[i * entry_size, entry_size]
        tag, type = entry[0, 4].unpack(u16 * 2)
        next unless tag == 256 || tag == 257
        # libtiff takes the first of a tag that comes twice: such a file is not read
        return nil if size.key?(tag)
        # libtiff reads the size from an entry of one value only; with more
        # values the value field is an offset, not the size
        return nil unless entry[4, value_at - 4].unpack1(entry_size == 20 ? u64 : u32) == 1
        size[tag] = case type
                    when 3  then entry[value_at, 2].unpack1(u16)
                    when 4  then entry[value_at, 4].unpack1(u32)
                    when 16 then entry_size == 20 ? entry[value_at, 8].unpack1(u64) : (return nil)
                    else return nil
                    end
      end
      dims = size.values_at(256, 257)
      dims.all?{|value| value.to_i > 0 } ? dims : nil
    end
  rescue SystemCallError, IOError
    nil
  end #def

  # Whether the ImageMagick program has a coder that reads the format (f.i. "HEIC"):
  # the format column of "-list format" (ImageMagick 6 and 7 alike), mode "r".
  # The module column may be empty (f.i. HEIC of ImageMagick 6.9.12 on Ubuntu
  # 24.04: "HEIC            r--"). Asked once per program and process, as
  # Redmine::Thumbnail.convert_available?. It tells whether the coder is
  # installed: a policy.xml that denies the coder still fails the conversion.
  def self.imagemagick_reads?(coder)
    imagemagick_formats.match?(/^\s*#{Regexp.escape(coder)}\*?\s+(?:[A-Z0-9]\S*\s+)?r[w-][+-](?:\s|$)/)
  end #def

  # cached once it succeeds: a failure (a fork error, a program being upgraded)
  # is asked again, rather than keeping HEIC and TIFF off until Redmine restarts
  # once per program also when the first requests come together
  IMAGEMAGICK_FORMATS_LOCK = Mutex.new

  def self.imagemagick_formats
    bin = convert_bin
    IMAGEMAGICK_FORMATS_LOCK.synchronize do
      @imagemagick_formats ||= {}
      return @imagemagick_formats[bin] if @imagemagick_formats.key?(bin)
      out = imagemagick_list_formats
      out ? (@imagemagick_formats[bin] = out) : ""
    end
  end #def
  
  # Ours: a coder ImageMagick lists may still decode nothing: HEIC is listed
  # whenever ImageMagick was built with libheif, and decoded only when libheif
  # has an HEVC decoder plugin (libheif-plugin-libde265); without it every
  # conversion failed with "Unsupported codec". A coder of IMAGEMAGICK_PROBES
  # counts as decoding once a tiny file of it (shipped with the plugin) has
  # really been decoded; others are taken as listed. Asked once per program and
  # coder: a success is kept, a failure for IMAGEMAGICK_PROBE_RETRY seconds (a
  # decoder installed meanwhile is found without a restart)
  IMAGEMAGICK_PROBES = {"HEIC" => File.expand_path("redmine_more_previews/probes/probe.heic", __dir__)}.freeze
  IMAGEMAGICK_PROBE_RETRY = 300
  IMAGEMAGICK_PROBE_LOCK  = Mutex.new

  def self.imagemagick_decodes?(coder)
    probe = IMAGEMAGICK_PROBES[coder]
    return true unless probe
    key = [convert_bin, coder]
    IMAGEMAGICK_PROBE_LOCK.synchronize do
      @imagemagick_decodes ||= {}
      known, at = @imagemagick_decodes[key]
      return known if known || (at && Process.clock_gettime(Process::CLOCK_MONOTONIC) - at < IMAGEMAGICK_PROBE_RETRY)
      result = imagemagick_decode_probe(coder, probe)
      @imagemagick_decodes[key] = [result, Process.clock_gettime(Process::CLOCK_MONOTONIC)]
      result
    end
  end #def

  # whether ImageMagick decodes the probe file with the coder: it prints the
  # image's size, within the limits of the previews (see imagemagick_run)
  def self.imagemagick_decode_probe(coder, probe)
    out = imagemagick_run(*IMAGEMAGICK_LIMITS.flat_map{|resource, value| ["-limit", resource, value] },
                          "#{coder.downcase}:#{probe}[0]", "-format", "%wx%h", "info:")
    out.to_s.match?(/\A\d+x\d+\z/)
  end #def

  def self.reset_imagemagick_decodes
    IMAGEMAGICK_PROBE_LOCK.synchronize { @imagemagick_decodes = nil }
  end #def

  # "-list format" of the program, nil when it fails or runs longer than
  # imagemagick_list_timeout seconds: it is asked within a request
  def self.imagemagick_list_formats
    imagemagick_run("-list", "format")
  end #def

  # the output of the program with args (no shell), nil when it fails or runs
  # longer than imagemagick_list_timeout seconds
  def self.imagemagick_run(*args)
    # Windows has no process groups to signal (see Lib::RmpProcess)
    windows = Redmine::Platform.mswin?
    group = windows ? {:new_pgroup => true} : {:pgroup => true}
    Open3.popen2e(convert_bin, *args, **group) do |stdin, out, wait|
      stdin.close
      reader = Thread.new { out.read }
      unless wait.join(imagemagick_list_timeout)
        begin
          Process.kill("KILL", windows ? wait.pid : -wait.pid)
        rescue SystemCallError
          # already ended
        end
        wait.join
        return nil
      end
      wait.value.success? ? reader.value : nil
    end
  rescue SystemCallError, IOError
    nil
  end #def
  
  def self.imagemagick_list_timeout
    10
  end #def
  
  def self.reset_imagemagick_formats
    IMAGEMAGICK_FORMATS_LOCK.synchronize { @imagemagick_formats = nil }
  end #def

end

require_relative "redmine_more_previews/constants"
require_relative "redmine_more_previews/exceptions"
require_relative "redmine_more_previews/modules"
require_relative "redmine_more_previews/lib"

require_relative "redmine_more_previews/controller_helper"
require_relative "redmine_more_previews/converter"
require_relative "redmine_more_previews/conversion"
require_relative "redmine_more_previews/plugin_loader"
require_relative "redmine_more_previews/core_handover"

require_relative "redmine_more_previews/patches"


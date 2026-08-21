require "zip"

class NoteImporter
  MAX_UPLOAD = 15.megabytes
  MAX_ENTRY = 2.megabytes
  MAX_NOTES = 500

  def self.rows(uploads)
    new(uploads).rows
  end

  def initialize(uploads)
    @uploads = Array.wrap(uploads).select { |upload| upload.respond_to?(:read) }
  end

  def rows
    raise ArgumentError, "missing_file" if @uploads.empty?

    found = []
    @uploads.each do |upload|
      raise ArgumentError, "unreadable" unless upload.respond_to?(:read)
      raise ArgumentError, "too_large" if upload.size.to_i > MAX_UPLOAD

      raw = read_bytes(upload)
      name = upload.respond_to?(:original_filename) ? upload.original_filename.to_s : ""
      found.concat parse_blob(raw, name)
    end
    raise ArgumentError, "empty" if found.empty?

    found.first(MAX_NOTES)
  end

  private
    def parse_blob(raw, name)
      return [] if raw.blank?
      return parse_zip(raw.b) if zip?(raw, name)

      bytes = decode(raw)
      json = try_json(bytes)
      if json
        parse_json(json, name)
      else
        [ plaintext_row(bytes, folder: "") ].compact
      end
    end

    def parse_json(json, name)
      if json.is_a?(Array)
        json.filter_map { |row| kuranotes_row(row) }
      elsif json.is_a?(Hash) && json["items"].is_a?(Array)
        standard_notes_rows(json["items"])
      elsif json.is_a?(Hash) && json["notes"].is_a?(Array)
        json["notes"].filter_map { |row| kuranotes_row(row) }
      elsif json.is_a?(Hash) && json["root"].is_a?(Hash)
        body = [ title_from_filename(name), lexical_to_text(json["root"]) ].compact_blank.join("\n\n")
        body.present? ? [ { body: body, folder: "" } ] : []
      else
        []
      end
    end

    def parse_zip(bytes)
      tmp = Tempfile.new([ "kura-import", ".zip" ])
      tmp.binmode
      tmp.write(bytes.b)
      tmp.close
      Zip::File.open(tmp.path) { |zip| rows_from_zip(zip) }
    ensure
      tmp&.close!
    end

    def rows_from_zip(zip)
      backup = zip.entries.find { |entry| standard_notes_backup_name?(entry.name) && !entry.directory? }
      if backup
        json = try_json(read_entry(backup))
        return parse_json(json, backup.name) if json
      end

      rows = []
      zip.each do |entry|
        next if skip_zip_entry?(entry)
        data = read_entry(entry)
        next if data.blank?

        json = try_json(data)
        parsed = if json
          parse_json(json, entry.name)
        else
          [ plaintext_row(data, folder: folder_from_zip_path(entry.name)) ].compact
        end
        rows.concat(parsed)
      end
      rows
    end

    def kuranotes_row(row)
      return unless row.is_a?(Hash)

      body = (row["body"] || row[:body]).to_s
      return if body.blank?

      { body: body, folder: (row["folder"] || row[:folder]).to_s }
    end

    def standard_notes_rows(items)
      tags_by_note = {}
      items.each do |item|
        next unless item.is_a?(Hash) && item["content_type"] == "Tag"
        content = item["content"]
        next unless content.is_a?(Hash)

        title = content["title"].to_s.strip
        next if title.blank?

        Array(content["references"]).each do |ref|
          uuid = ref.is_a?(Hash) ? ref["uuid"].to_s : ""
          tags_by_note[uuid] ||= title if uuid.present?
        end
      end

      items.filter_map { |item|
        next unless item.is_a?(Hash) && item["content_type"] == "Note"
        next if item["deleted"]

        content = item["content"]
        next unless content.is_a?(Hash)

        title = content["title"].to_s.strip
        text = note_text(content)
        body = [ title, text ].compact_blank.join("\n\n")
        next if body.blank?

        { body: body, folder: tags_by_note[item["uuid"].to_s].to_s }
      }
    end

    def note_text(content)
      raw = content["text"].to_s
      json = try_json(raw)
      if json.is_a?(Hash) && json["root"].is_a?(Hash)
        lexical_to_text(json["root"])
      else
        raw
      end
    end

    def plaintext_row(bytes, folder:)
      body = bytes.to_s.gsub("\r\n", "\n").strip
      return if body.blank?

      { body: body, folder: folder.to_s }
    end

    def lexical_to_text(node, list_type: nil, index: 0)
      return "" unless node.is_a?(Hash)

      type = node["type"].to_s
      children = Array(node["children"])
      walk = ->(extra = {}) { children.map { |child| lexical_to_text(child, **{ list_type: list_type, index: index }.merge(extra)) }.join }

      case type
      when "text" then node["text"].to_s
      when "linebreak", "tab" then "\n"
      when "heading", "paragraph" then "#{walk.call.strip}\n\n"
      when "quote" then "#{walk.call.strip.lines.map { |line| "> #{line}" }.join}\n\n"
      when "horizontalrule" then "---\n\n"
      when "list"
        kind = node["listType"].presence || node["tag"]
        children.map.with_index(1) { |child, i| lexical_to_text(child, list_type: kind, index: i) }.join + "\n"
      when "listitem"
        inner = walk.call.strip
        prefix = if node.key?("checked")
          node["checked"] ? "[x] " : "[ ] "
        elsif list_type.to_s.in?(%w[number numbered ol])
          "#{index}. "
        else
          "- "
        end
        "#{prefix}#{inner}\n"
      when "root"
        walk.call.gsub(/\n{3,}/, "\n\n").strip
      else
        walk.call
      end
    end

    def title_from_filename(name)
      File.basename(name.to_s, ".*").sub(/-[0-9a-f]{8}\z/i, "").tr("-", " ").strip.presence
    end

    def folder_from_zip_path(name)
      parts = name.to_s.tr("\\", "/").split("/")
      parts.pop
      parts.reject! { |part| part.blank? || part == "." || part.in?(%w[Items Note]) || part.start_with?("__") }
      parts.last.to_s
    end

    def skip_zip_entry?(entry)
      return true if entry.directory?
      path = entry.name.to_s.tr("\\", "/")
      return true if path.include?("..") || path.start_with?("/")
      return true if path.include?("__MACOSX") || File.basename(path).start_with?(".")
      return true unless path.match?(/\.(txt|json|md)\z/i)
      return true if entry.size.to_i > MAX_ENTRY

      false
    end

    def standard_notes_backup_name?(name)
      File.basename(name.to_s).match?(/backup and import file/i)
    end

    def zip?(bytes, name)
      name.to_s.downcase.end_with?(".zip") || bytes.b.start_with?("PK")
    end

    def try_json(bytes)
      text = bytes.to_s.delete_prefix("\uFEFF").lstrip
      return unless text.start_with?("{", "[")

      JSON.parse(text)
    rescue JSON::ParserError
      nil
    end

    def read_bytes(upload)
      upload.rewind if upload.respond_to?(:rewind)
      upload.read.to_s
    end

    def read_entry(entry)
      decode(entry.get_input_stream.read.to_s)
    end

    def decode(bytes)
      text = bytes.force_encoding(Encoding::UTF_8)
      text = text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "") unless text.valid_encoding?
      text.delete("\u0000").gsub("\r\n", "\n")
    end
end

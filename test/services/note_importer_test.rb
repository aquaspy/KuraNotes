require "test_helper"
require "zip"

class NoteImporterTest < ActiveSupport::TestCase
  test "reads a KuraNotes json array" do
    rows = NoteImporter.rows(upload("notes.json", [ { "body" => "Hello", "folder" => "in" } ].to_json))
    assert_equal [ { body: "Hello", folder: "in" } ], rows
  end

  test "reads a KuraNotes object with notes key" do
    rows = NoteImporter.rows(upload("notes.json", { "notes" => [ { "body" => "Wrapped" } ] }.to_json))
    assert_equal "Wrapped", rows.first[:body]
    assert_equal "", rows.first[:folder]
  end

  test "reads a Notesnook text file" do
    rows = NoteImporter.rows(upload("Receita-de-Brownie.txt", "Receita de Brownie\n\nChocolate e ovos\n"))
    assert_equal 1, rows.size
    assert_match(/Receita de Brownie/, rows.first[:body])
    assert_match(/Chocolate e ovos/, rows.first[:body])
    assert_equal "", rows.first[:folder]
  end

  test "reads a zip of Notesnook text files using folders" do
    bytes = zip_bytes(
      "Receitas/Brownie.txt" => "Brownie\n\nForno 180",
      "Inbox.txt" => "Solta\n\nSem pasta"
    )
    rows = NoteImporter.rows(upload("notesnook.zip", bytes))
    by_title = rows.to_h { |row| [ row[:body].lines.first.strip, row[:folder] ] }
    assert_equal "Receitas", by_title["Brownie"]
    assert_equal "", by_title["Solta"]
  end

  test "converts a Standard Notes backup and maps tags to folders" do
    payload = {
      "version" => "004",
      "items" => [
        {
          "content_type" => "Tag",
          "uuid" => "tag-1",
          "content" => { "title" => "receitas", "references" => [ { "uuid" => "note-1", "content_type" => "Note" } ] }
        },
        {
          "content_type" => "Note",
          "uuid" => "note-1",
          "deleted" => false,
          "content" => {
            "title" => "Pizza",
            "text" => lexical("300g de farinha", list: true),
            "preview_plain" => "truncated"
          }
        },
        {
          "content_type" => "Note",
          "uuid" => "note-2",
          "content" => { "title" => "Plain", "text" => "Just markdown.\n\nTwo lines." }
        },
        {
          "content_type" => "SN|UserPreferences",
          "uuid" => "pref",
          "content" => { "references" => [] }
        }
      ]
    }
    rows = NoteImporter.rows(upload("Standard Notes Backup and Import File.txt", payload.to_json))
    assert_equal 2, rows.size
    pizza = rows.find { |row| row[:body].start_with?("Pizza") }
    assert_equal "receitas", pizza[:folder]
    assert_includes pizza[:body], "- 300g de farinha"
    refute_includes pizza[:body], "truncated"
    plain = rows.find { |row| row[:body].start_with?("Plain") }
    assert_equal "", plain[:folder]
    assert_includes plain[:body], "Just markdown."
  end

  test "prefers the Standard Notes backup file inside a zip" do
    payload = { "version" => "004", "items" => [ { "content_type" => "Note", "uuid" => "n1", "content" => { "title" => "From backup", "text" => "Hi" } } ] }
    bytes = zip_bytes(
      "Standard Notes Backup and Import File.txt" => payload.to_json,
      "Items/Note/ignored-aaaaaaaa.txt" => { "root" => { "type" => "root", "children" => [] } }.to_json
    )
    rows = NoteImporter.rows(upload("sn.zip", bytes))
    assert_equal 1, rows.size
    assert_includes rows.first[:body], "From backup"
  end

  test "skips the empty string Rails prepends on file fields" do
    rows = NoteImporter.rows([ "", upload("note.txt", "Titulo\n\nCorpo") ])
    assert_equal 1, rows.size
    assert_includes rows.first[:body], "Titulo"
  end

  test "rejects an unrecognized json object" do
    assert_raises(ArgumentError) { NoteImporter.rows(upload("x.json", { "hello" => 1 }.to_json)) }
  end

  private
    def upload(name, content)
      io = StringIO.new(content.b)
      io.define_singleton_method(:original_filename) { name }
      io.define_singleton_method(:size) { io.string.bytesize }
      io
    end

    def zip_bytes(entries)
      Zip::OutputStream.write_buffer { |zio|
        entries.each do |name, body|
          zio.put_next_entry(name)
          zio.write(body)
        end
      }.string
    end

    def lexical(text, list: false)
      leaf = { "type" => "text", "text" => text }
      item = { "type" => "listitem", "children" => [ leaf ] }
      node = if list
        { "type" => "list", "listType" => "bullet", "children" => [ item ] }
      else
        { "type" => "paragraph", "children" => [ leaf ] }
      end
      { "root" => { "type" => "root", "children" => [ node ] } }.to_json
    end
end

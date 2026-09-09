require "test_helper"

class NoteTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "ada@example.com", password: "secret-password")
  end

  test "derives title and preview from the body" do
    note = @user.notes.create!(body: "Grocery list\nMilk")
    assert_equal "Grocery list", note.title
    assert_equal "Milk", note.preview
  end

  test "preview falls back to the title line" do
    note = @user.notes.create!(body: "Just a title")
    assert_equal "Just a title", note.title
    assert_equal "Just a title", note.preview
  end

  test "blank body stays untitled" do
    note = @user.notes.create!(body: "  \n")
    assert_equal "", note.title
    assert_equal "", note.preview
  end

  test "strips and truncates folder names" do
    note = @user.notes.create!(body: "A", folder: "  home  ")
    assert_equal "home", note.folder

    note.update!(folder: "x" * 100)
    assert_equal 80, note.folder.length
  end

  test "reserved folder names become inbox" do
    note = @user.notes.create!(body: "A", folder: "Inbox")
    assert_equal "", note.folder

    note.update!(folder: "all")
    assert_equal "", note.folder
  end

  test "rename_folder moves every note in that folder" do
    keep = @user.notes.create!(body: "Inbox", folder: "")
    one = @user.notes.create!(body: "One", folder: "work")
    two = @user.notes.create!(body: "Two", folder: "work")
    other = @user.notes.create!(body: "Other", folder: "home")
    stamp = one.updated_at

    assert_equal "office", Note.rename_folder(user: @user, from: "work", to: " office ")
    assert_equal "", keep.reload.folder
    assert_equal "office", one.reload.folder
    assert_equal "office", two.reload.folder
    assert_equal "home", other.reload.folder
    assert_equal stamp.to_i, one.updated_at.to_i
  end

  test "rename_folder merges into an existing folder" do
    @user.notes.create!(body: "A", folder: "work")
    @user.notes.create!(body: "B", folder: "home")

    Note.rename_folder(user: @user, from: "work", to: "home")
    assert_equal [ "home" ], @user.notes.distinct.pluck(:folder)
  end

  test "rename_folder rejects inbox all and blank names" do
    @user.notes.create!(body: "A", folder: "work")

    assert_nil Note.rename_folder(user: @user, from: "inbox", to: "home")
    assert_nil Note.rename_folder(user: @user, from: "", to: "home")
    assert_nil Note.rename_folder(user: @user, from: "work", to: "")
    assert_nil Note.rename_folder(user: @user, from: "work", to: "Inbox")
    assert_nil Note.rename_folder(user: @user, from: "work", to: "all")
    assert_equal "work", @user.notes.first.folder
  end

  test "rename_folder does not touch another user's notes" do
    other = User.create!(email: "lin@example.com", password: "secret-password")
    mine = @user.notes.create!(body: "Mine", folder: "work")
    theirs = other.notes.create!(body: "Theirs", folder: "work")

    Note.rename_folder(user: @user, from: "work", to: "home")
    assert_equal "home", mine.reload.folder
    assert_equal "work", theirs.reload.folder
  end

  test "list rows omit the body" do
    @user.notes.create!(body: "Secret body\nPreview line")
    row = @user.notes.list_row.first
    assert_equal "Preview line", row.preview
    refute row.has_attribute?(:body)
  end
end

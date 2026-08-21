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

  test "list rows omit the body" do
    @user.notes.create!(body: "Secret body\nPreview line")
    row = @user.notes.list_row.first
    assert_equal "Preview line", row.preview
    refute row.has_attribute?(:body)
  end
end

require "test_helper"

class NotesFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "ada@example.com", password: "secret-password")
  end

  test "signup can be turned off" do
    ENV["SIGNUP_ENABLED"] = "false"
    get signup_path
    assert_redirected_to login_path
    follow_redirect!
    refute_includes response.body, I18n.t("auth.create_one")

    assert_no_difference -> { User.count } do
      post signup_path, params: { email: "intruder@example.com", password: "secret-password", password_confirmation: "secret-password" }
    end
    assert_redirected_to login_path
  ensure
    ENV.delete("SIGNUP_ENABLED")
  end

  test "signup creates a user with a real password" do
    post signup_path, params: { email: "lin@example.com", password: "secret-password", password_confirmation: "secret-password" }
    assert_redirected_to root_path
    user = User.find_by(email: "lin@example.com")
    assert user
    assert user.authenticate("secret-password")
    refute user.authenticate("wrong")
  end

  test "login opens the notes page" do
    post login_path, params: { email: @user.email, password: "secret-password" }
    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert_includes response.body, "KuraNotes"
  end

  test "notes stay readable as plaintext on the server" do
    login
    post notes_path
    note = @user.notes.last
    patch note_path(note), params: { note: { body: "Grocery list\nMilk", folder: "home" } }
    note.reload
    assert_equal "Grocery list", note.title
    assert_equal "Grocery list\nMilk", note.body
    assert_equal "home", note.folder

    get note_path(note)
    assert_response :success
    assert_includes response.body, "Grocery list"
    assert_includes response.body, "Milk"
  end

  test "strangers cannot read notes" do
    @user.notes.create!(body: "Secret")
    get notes_path
    assert_redirected_to login_path
  end

  test "lock hides note bodies until unlocked" do
    login
    @user.notes.create!(body: "Hidden after lock")
    post lock_path
    assert_redirected_to unlock_path
    follow_redirect!
    assert_response :success
    refute_includes response.body, "Hidden after lock"

    get root_path
    assert_redirected_to unlock_path

    post unlock_path, params: { password: "wrong-password" }
    assert_response :unprocessable_entity

    post unlock_path, params: { password: "secret-password" }
    assert_redirected_to root_path
    follow_redirect!
    assert_includes response.body, "Hidden after lock"
  end

  test "ui language follows Accept-Language" do
    get login_path, headers: { "Accept-Language" => "pt-BR,pt;q=0.9" }
    assert_includes response.body, "Entrar"
    assert_includes response.body, 'lang="pt-BR"'

    get login_path, headers: { "Accept-Language" => "en-US,en;q=0.8" }
    assert_includes response.body, "Sign in"
    assert_includes response.body, 'lang="en"'
  end

  test "export downloads plaintext json" do
    login
    @user.notes.create!(body: "Exported note", folder: "box")
    get export_notes_path
    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "Exported note", payload.first["body"]
    assert_equal "box", payload.first["folder"]
  end

  test "note text is filtered from request logs" do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      .filter({ "note" => { "body" => "Secret grocery list", "folder" => "home" }, "q" => "milk", "title" => "List" })

    assert_equal "[FILTERED]", filtered.dig("note", "body")
    assert_equal "[FILTERED]", filtered.dig("note", "folder")
    assert_equal "[FILTERED]", filtered["q"]
    assert_equal "[FILTERED]", filtered["title"]
  end

  test "session cookie lasts until sign out" do
    assert_equal 20.years, Rails.application.config.session_options[:expire_after]
  end

  test "deleting a note removes it" do
    login
    note = @user.notes.create!(body: "Throw away")
    delete note_path(note)
    assert_redirected_to notes_path
    assert_nil Note.find_by(id: note.id)
  end

  test "deleting a folder removes its notes but keeps inbox" do
    login
    keep = @user.notes.create!(body: "Stay", folder: "")
    @user.notes.create!(body: "Gone 1", folder: "work")
    @user.notes.create!(body: "Gone 2", folder: "work")

    delete folder_notes_path, params: { folder: "work" }
    assert_redirected_to notes_path
    assert_equal [ keep.id ], @user.notes.reload.map(&:id)

    @user.notes.create!(body: "Inbox junk", folder: "")
    delete folder_notes_path, params: { folder: "inbox" }
    follow_redirect!
    assert_equal 0, @user.notes.count
    assert_includes response.body, I18n.t("js.inbox")
  end

  test "share link lets a stranger read one note" do
    login
    note = @user.notes.create!(body: "Shared recipe\nEggs and milk")
    post note_share_path(note)
    note.reload
    assert note.shared?
    token = note.share_token
    assert_match(/\A[A-Za-z0-9_-]{20,}\z/, token)

    delete logout_path
    get shared_note_path(token)
    assert_response :success
    assert_includes response.body, "Shared recipe"
    assert_includes response.body, "Eggs and milk"
    assert_includes response.body, "noindex"
    refute_includes response.body, 'property="og:'
    assert_equal "noindex, nofollow, noarchive", response.headers["X-Robots-Tag"]
  end

  test "revoking a share hides the note" do
    login
    note = @user.notes.create!(body: "Private again")
    post note_share_path(note)
    token = note.reload.share_token

    delete note_share_path(note)
    assert_nil note.reload.share_token

    delete logout_path
    get shared_note_path(token)
    assert_response :not_found
  end

  test "rotating a share invalidates the old url" do
    login
    note = @user.notes.create!(body: "Rotate me")
    post note_share_path(note)
    old_token = note.reload.share_token

    patch note_share_path(note)
    new_token = note.reload.share_token
    refute_equal old_token, new_token

    delete logout_path
    get shared_note_path(old_token)
    assert_response :not_found
    get shared_note_path(new_token)
    assert_response :success
    assert_includes response.body, "Rotate me"
  end

  test "note id is not a share url" do
    note = @user.notes.create!(body: "No peeking")
    get shared_note_path(note.id)
    assert_response :not_found
  end

  test "deleting a note kills its share" do
    login
    note = @user.notes.create!(body: "Gone")
    post note_share_path(note)
    token = note.reload.share_token
    delete note_path(note)

    delete logout_path
    get shared_note_path(token)
    assert_response :not_found
  end

  test "import creates notes from an export file" do
    login
    file = Tempfile.new([ "notes", ".json" ])
    file.write([ { "body" => "Imported note", "folder" => "in" } ].to_json)
    file.rewind

    assert_difference -> { @user.notes.count }, 1 do
      post import_notes_path, params: { file: Rack::Test::UploadedFile.new(file.path, "application/json") }
    end
    assert_redirected_to notes_path
    assert_equal "Imported note", @user.notes.last.body
    assert_equal "in", @user.notes.last.folder
  ensure
    file&.close!
  end

  private
    def login
      post login_path, params: { email: @user.email, password: "secret-password" }
      assert_redirected_to root_path
    end
end

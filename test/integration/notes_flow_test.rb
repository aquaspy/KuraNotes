require "test_helper"
require "zip"

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
    assert_select "#folders_nav.folder-strip"
  end

  test "notes stay readable as plaintext on the server" do
    login
    post notes_path
    note = @user.notes.last
    patch note_path(note), params: { note: { body: "Grocery list\nMilk", folder: "home" } }
    note.reload
    assert_equal "Grocery list", note.title
    assert_equal "Milk", note.preview
    assert_equal "Grocery list\nMilk", note.body
    assert_equal "home", note.folder

    get note_path(note)
    assert_response :success
    assert_includes response.body, "Grocery list"
    assert_includes response.body, "Milk"

    get notes_path
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

  test "new note reuses an empty untitled draft in the same folder" do
    login
    post notes_path
    first = @user.notes.last
    post notes_path
    assert_redirected_to note_path(first)
    assert_equal 1, @user.notes.count
  end

  test "new note in another folder does not reuse an inbox draft" do
    login
    post notes_path
    inbox = @user.notes.last
    post notes_path, params: { folder: "work" }
    assert_equal 2, @user.notes.count
    assert_not_equal inbox.id, @user.notes.order(:id).last.id
    assert_equal "work", @user.notes.order(:id).last.folder
  end

  test "new note opens a fresh one after writing" do
    login
    post notes_path
    first = @user.notes.last
    patch note_path(first), params: { note: { body: "Hello" } }
    post notes_path
    assert_equal 2, @user.notes.count
  end

  test "search filters titles and bodies" do
    login
    @user.notes.create!(body: "Garden\nRoses")
    @user.notes.create!(body: "Taxes\nDue in April")
    get notes_path, params: { q: "Tax" }
    assert_includes response.body, "Taxes"
    assert_not_includes response.body, "Garden"
    assert_includes response.body, %(target="_top")
  end

  test "search frame filters without discarding a draft" do
    login
    post notes_path
    draft = @user.notes.last
    @user.notes.create!(body: "Garden\nRoses")
    @user.notes.create!(body: "Taxes\nDue in April")

    get notes_path, params: { q: "Tax" }, headers: { "Turbo-Frame" => "note-search" }
    assert_response :success
    assert_includes response.body, "Taxes"
    assert_not_includes response.body, "Garden"
    assert_includes response.body, %(id="note-search")
    assert_includes response.body, %(target="_top")
    assert_not_includes response.body, "col-editor"
    assert Note.exists?(draft.id)
  end

  test "leaving an empty note discards the untitled draft" do
    login
    post notes_path
    draft = @user.notes.last
    get notes_path
    assert_nil Note.find_by(id: draft.id)
  end

  test "opening another note discards an abandoned untitled draft" do
    login
    keep = @user.notes.create!(body: "Keep")
    post notes_path
    draft = @user.notes.where.not(id: keep.id).last
    get note_path(keep)
    assert_nil Note.find_by(id: draft.id)
    assert Note.exists?(keep.id)
  end

  test "portuguese locale labels a blank title as Sem título" do
    login
    post notes_path
    note = @user.notes.last
    get note_path(note), headers: { "HTTP_ACCEPT_LANGUAGE" => "pt-BR,pt;q=0.9" }
    assert_response :success
    assert_includes response.body, "Sem título"
    assert_not_includes response.body, "Untitled"
  end

  test "auto lock is off by default and can be toggled" do
    login
    assert_not @user.reload.auto_lock?

    get root_path
    assert_includes response.body, "Turn on auto lock"
    assert_not_includes response.body, "Turn off auto lock"

    travel 20.minutes do
      get root_path
      assert_response :success
    end

    post auto_lock_path
    follow_redirect!
    assert @user.reload.auto_lock?
    assert_includes response.body, "Turn off auto lock"

    travel 20.minutes do
      get root_path
      assert_redirected_to unlock_path
    end
  end

  test "auto lock cannot be toggled while locked" do
    login
    post lock_path
    post auto_lock_path
    assert_redirected_to unlock_path
    assert_not @user.reload.auto_lock?
  end

  test "logged in user can change password" do
    login
    get root_path
    assert_includes response.body, "Change password"

    get edit_password_path
    assert_response :success
    assert_includes response.body, "Current password"

    patch password_path, params: { current_password: "wrong-password", password: "new-secret", password_confirmation: "new-secret" }
    assert_response :unprocessable_entity
    assert @user.reload.authenticate("secret-password")

    patch password_path, params: { current_password: "secret-password", password: "new-secret", password_confirmation: "mismatch!" }
    assert_response :unprocessable_entity
    assert @user.reload.authenticate("secret-password")

    patch password_path, params: { current_password: "secret-password", password: "new-secret", password_confirmation: "new-secret" }
    assert_redirected_to root_path
    follow_redirect!
    assert_includes response.body, "Password changed."
    assert @user.reload.authenticate("new-secret")
    assert_not @user.authenticate("secret-password")

    delete logout_path
    post login_path, params: { email: @user.email, password: "secret-password" }
    assert_response :unprocessable_entity
    post login_path, params: { email: @user.email, password: "new-secret" }
    assert_redirected_to root_path
  end

  test "change password requires a session" do
    get edit_password_path
    assert_redirected_to login_path
  end

  test "portuguese change password labels" do
    login
    get edit_password_path, headers: { "Accept-Language" => "pt-BR,pt;q=0.9" }
    assert_includes response.body, "Mudar senha"
    assert_includes response.body, "Senha atual"
    assert_not_includes response.body, "Change password"
  end

  test "import form uploads files as multipart" do
    login
    get notes_path
    assert_select "form.import-form[enctype='multipart/form-data']"
    assert_select "form.import-form input[type=file][multiple]"
    assert_select "form.import-form input[type=hidden][name='file[]']", count: 0
  end

  test "import creates notes from several Notesnook text files" do
    login
    one = Tempfile.new([ "Brownie", ".txt" ])
    two = Tempfile.new([ "Pizza", ".txt" ])
    one.write("Brownie\n\nChocolate")
    two.write("Pizza\n\nFarinha")
    one.rewind
    two.rewind

    assert_difference -> { @user.notes.count }, 2 do
      post import_notes_path, params: {
        file: [
          Rack::Test::UploadedFile.new(one.path, "text/plain"),
          Rack::Test::UploadedFile.new(two.path, "text/plain")
        ]
      }
    end
    bodies = @user.notes.pluck(:body)
    assert bodies.any? { |body| body.include?("Brownie") }
    assert bodies.any? { |body| body.include?("Pizza") }
  ensure
    one&.close!
    two&.close!
  end

  test "import creates notes from an export file" do
    login
    file = Tempfile.new([ "notes", ".json" ])
    file.write([ { "body" => "Imported note", "folder" => "in" } ].to_json)
    file.rewind

    assert_difference -> { @user.notes.count }, 1 do
      post import_notes_path, params: { file: [ "", Rack::Test::UploadedFile.new(file.path, "application/json") ] }
    end
    assert_redirected_to notes_path
    assert_equal "Imported note", @user.notes.last.body
    assert_equal "in", @user.notes.last.folder
  ensure
    file&.close!
  end

  test "import creates notes from a Notesnook text file" do
    login
    file = Tempfile.new([ "Brownie", ".txt" ])
    file.write("Receita de Brownie\n\nChocolate e ovos")
    file.rewind

    assert_difference -> { @user.notes.count }, 1 do
      post import_notes_path, params: { file: Rack::Test::UploadedFile.new(file.path, "text/plain") }
    end
    assert_includes @user.notes.last.body, "Receita de Brownie"
    assert_includes @user.notes.last.body, "Chocolate e ovos"
  ensure
    file&.close!
  end

  test "import creates notes from a zip of Notesnook text files" do
    login
    zip = Tempfile.new([ "notesnook", ".zip" ])
    Zip::OutputStream.open(zip.path) do |zio|
      zio.put_next_entry("Receitas/Brownie.txt")
      zio.write("Brownie\n\nChocolate")
      zio.put_next_entry("Inbox.txt")
      zio.write("Solta\n\nSem pasta")
    end

    assert_difference -> { @user.notes.count }, 2 do
      post import_notes_path, params: { file: Rack::Test::UploadedFile.new(zip.path, "application/zip") }
    end
    assert_redirected_to notes_path
    brownie = @user.notes.find { |note| note.body.include?("Brownie") }
    inbox = @user.notes.find { |note| note.body.include?("Solta") }
    assert_equal "Receitas", brownie.folder
    assert_equal "", inbox.folder
  ensure
    zip&.close!
  end

  test "import creates notes from a Standard Notes backup" do
    login
    payload = {
      "version" => "004",
      "items" => [
        { "content_type" => "Note", "uuid" => "n1", "content" => { "title" => "Viagem", "text" => "Passaporte" } }
      ]
    }
    file = Tempfile.new([ "Standard Notes Backup and Import File", ".txt" ])
    file.write(payload.to_json)
    file.rewind

    assert_difference -> { @user.notes.count }, 1 do
      post import_notes_path, params: { file: Rack::Test::UploadedFile.new(file.path, "text/plain") }
    end
    assert_includes @user.notes.last.body, "Viagem"
    assert_includes @user.notes.last.body, "Passaporte"
  ensure
    file&.close!
  end

  private
    def login
      post login_path, params: { email: @user.email, password: "secret-password" }
      assert_redirected_to root_path
    end
end

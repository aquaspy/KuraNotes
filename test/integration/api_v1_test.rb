require "test_helper"

class ApiV1Test < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "ada@example.com", password: "secret-password")
    @token = ApiToken.generate_for(@user, name: "hermes")
    @token.save!
    @auth = { "Authorization" => "Bearer #{@token.raw_token}" }
  end

  test "requests without a token are rejected" do
    get api_v1_notes_path
    assert_response :unauthorized
    assert_equal "unauthorized", JSON.parse(response.body)["error"]
  end

  test "requests with a bogus token are rejected" do
    get api_v1_notes_path, headers: { "Authorization" => "Bearer kura_bogus" }
    assert_response :unauthorized
  end

  test "lists notes filtered by folder and query" do
    @user.notes.create!(body: "Groceries\nmilk and eggs", folder: "home")
    @user.notes.create!(body: "Deploy checklist", folder: "work")

    get api_v1_notes_path(folder: "home"), headers: @auth
    assert_response :success
    notes = JSON.parse(response.body)["notes"]
    assert_equal [ "home" ], notes.map { |note| note["folder"] }.uniq
    assert_includes notes.first["body"], "milk"

    get api_v1_notes_path(q: "checklist"), headers: @auth
    assert_response :success
    assert_equal [ "Deploy checklist" ], JSON.parse(response.body)["notes"].map { |note| note["title"] }
  end

  test "an agent can create, read, update and delete a note" do
    post api_v1_notes_path, headers: @auth, as: :json, params: {
      note: { body: "Trip ideas\nKyoto in April", folder: "travel" }
    }
    assert_response :created
    created = JSON.parse(response.body)["note"]
    assert_equal "Trip ideas", created["title"]
    assert_equal "travel", created["folder"]
    id = created["id"]

    get api_v1_note_path(id), headers: @auth
    assert_response :success
    assert_includes JSON.parse(response.body)["note"]["body"], "Kyoto"

    patch api_v1_note_path(id), headers: @auth, as: :json, params: {
      note: { folder: "done" }
    }
    assert_response :success
    assert_equal "done", JSON.parse(response.body)["note"]["folder"]

    delete api_v1_note_path(id), headers: @auth
    assert_response :no_content
    assert_nil @user.notes.find_by(id: id)
  end

  test "note endpoints accept flat params for simpler agents" do
    post api_v1_notes_path, headers: @auth, as: :json, params: {
      body: "Flat note", folder: "inbox"
    }
    assert_response :created
    assert_equal "", JSON.parse(response.body)["note"]["folder"]
  end

  test "an agent can list, rename and clear folders" do
    @user.notes.create!(body: "One", folder: "work")
    @user.notes.create!(body: "Two", folder: "work")
    @user.notes.create!(body: "Three", folder: "home")

    get api_v1_folders_path, headers: @auth
    assert_response :success
    counts = JSON.parse(response.body)["folders"].to_h { |row| [ row["name"], row["count"] ] }
    assert_equal 2, counts["work"]
    assert_equal 1, counts["home"]

    patch api_v1_folders_path, headers: @auth, as: :json, params: { from: "work", to: "job" }
    assert_response :success
    assert_equal "job", JSON.parse(response.body)["folder"]
    assert_equal 2, @user.notes.where(folder: "job").count

    delete api_v1_folders_path(folder: "home"), headers: @auth
    assert_response :success
    assert_equal 1, JSON.parse(response.body)["deleted"]
    assert_empty @user.notes.where(folder: "home")
  end

  test "folder rename and clear reject reserved names" do
    @user.notes.create!(body: "One", folder: "work")

    patch api_v1_folders_path, headers: @auth, as: :json, params: { from: "work", to: "inbox" }
    assert_response :unprocessable_entity

    delete api_v1_folders_path(folder: "all"), headers: @auth
    assert_response :unprocessable_entity
    assert_equal 1, @user.notes.count
  end

  test "one user cannot touch another user's notes" do
    note = @user.notes.create!(body: "Secret")
    other = User.create!(email: "other@example.com", password: "secret-password")
    other_token = ApiToken.generate_for(other, name: "other")
    other_token.save!

    get api_v1_note_path(note), headers: { "Authorization" => "Bearer #{other_token.raw_token}" }
    assert_response :not_found
  end

  test "revoked tokens stop working" do
    @token.destroy
    get api_v1_notes_path, headers: @auth
    assert_response :unauthorized
  end

  test "tokens keep working while the app is locked" do
    post login_path, params: { email: @user.email, password: "secret-password" }
    post lock_path
    assert_redirected_to unlock_path

    get api_v1_notes_path, headers: @auth
    assert_response :success
  end

  test "using a token records its last use" do
    assert_nil @token.last_used_at
    get api_v1_notes_path, headers: @auth
    assert_response :success
    assert_not_nil @token.reload.last_used_at
  end
end

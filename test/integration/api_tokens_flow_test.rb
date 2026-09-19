require "test_helper"

class ApiTokensFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "ada@example.com", password: "secret-password")
    post login_path, params: { email: @user.email, password: "secret-password" }
  end

  test "strangers cannot open the tokens page" do
    delete logout_path
    get api_tokens_path
    assert_redirected_to login_path
  end

  test "creating a token requires the current password" do
    assert_no_difference -> { ApiToken.count } do
      post api_tokens_path, params: { name: "hermes", current_password: "wrong-password" }
    end
    assert_response :unprocessable_entity
  end

  test "a new token is shown once and works for the api" do
    post api_tokens_path, params: { name: "hermes", current_password: "secret-password" }
    assert_response :created
    raw = response.body[/kura_[A-Za-z0-9_\-]{20,}/]
    assert raw, "expected the raw token in the response"

    get api_tokens_path
    assert_response :success
    refute_includes response.body, raw
    assert_includes response.body, "hermes"

    get api_v1_notes_path, headers: { "Authorization" => "Bearer #{raw}" }
    assert_response :success
  end

  test "revoking a token kills api access" do
    token = ApiToken.generate_for(@user, name: "old agent")
    token.save!
    raw = token.raw_token

    delete api_token_path(token)
    assert_redirected_to api_tokens_path

    get api_v1_notes_path, headers: { "Authorization" => "Bearer #{raw}" }
    assert_response :unauthorized
  end

  test "one user cannot revoke another user's token" do
    other = User.create!(email: "other@example.com", password: "secret-password")
    token = ApiToken.generate_for(other, name: "other")
    token.save!

    delete api_token_path(token)
    assert_response :not_found
    assert ApiToken.exists?(token.id)
  end
end

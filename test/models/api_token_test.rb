require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "ada@example.com", password: "secret-password")
  end

  test "generate_for builds a token shown once and stored only as a digest" do
    token = ApiToken.generate_for(@user, name: "hermes")
    assert token.raw_token.start_with?("kura_")
    assert token.save
    assert_equal 64, token.token_digest.length
    refute_includes token.reload.token_digest, token.raw_token
    assert token.prefix.start_with?("kura_")
  end

  test "authenticate finds the token by its raw value" do
    token = ApiToken.generate_for(@user, name: "hermes")
    token.save!
    assert_equal token, ApiToken.authenticate(token.raw_token)
  end

  test "authenticate rejects blank and bogus values" do
    assert_nil ApiToken.authenticate(nil)
    assert_nil ApiToken.authenticate("")
    assert_nil ApiToken.authenticate("kura_bogus")
  end

  test "name is required" do
    token = ApiToken.generate_for(@user, name: "  ")
    refute token.valid?
    assert_includes token.errors[:name], I18n.t("activerecord.errors.models.api_token.attributes.name.blank")
  end

  test "tokens are capped per user" do
    ApiToken::PER_USER_CAP.times do |i|
      generated = ApiToken.generate_for(@user, name: "token-#{i}")
      generated.save!
    end
    extra = ApiToken.generate_for(@user, name: "one more")
    refute extra.valid?
  end
end

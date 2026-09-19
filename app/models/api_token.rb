class ApiToken < ApplicationRecord
  NAME_MAX = 80
  PER_USER_CAP = 10
  PREFIX = "kura_"

  belongs_to :user

  before_validation :normalize

  validates :name, presence: true, length: { maximum: NAME_MAX }
  validates :token_digest, presence: true, uniqueness: true
  validate :within_cap, on: :create

  attr_reader :raw_token

  def self.generate_for(user, name:)
    raw = "#{PREFIX}#{SecureRandom.urlsafe_base64(24)}"
    token = new(user: user, name: name, token_digest: digest(raw), prefix: raw.first(12))
    token.instance_variable_set(:@raw_token, raw)
    token
  end

  def self.authenticate(raw)
    return if raw.blank?

    find_by(token_digest: digest(raw.to_s.strip))
  end

  def self.digest(raw)
    Digest::SHA256.hexdigest(raw.to_s)
  end

  def touch_last_used!
    update_column(:last_used_at, Time.current)
  end

  private
    def normalize
      self.name = name.to_s.strip
    end

    def within_cap
      return unless user
      errors.add(:base, :too_many) if user.api_tokens.count >= PER_USER_CAP
    end
end

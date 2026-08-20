class Note < ApplicationRecord
  belongs_to :user

  before_validation :assign_title

  scope :blank_drafts, -> { where(title: "", share_token: nil).where("TRIM(body) = ''") }

  def self.open_draft_for(user, folder: "")
    folder = folder.to_s
    drafts = user.notes.blank_drafts.where(folder: folder)
    draft = drafts.order(updated_at: :desc).first || user.notes.create!(folder: folder)
    drafts.where.not(id: draft.id).delete_all
    draft
  end

  def inbox?
    folder.blank?
  end

  def preview
    lines = body.to_s.lines.map(&:strip).reject(&:blank?)
    (lines[1] || lines[0] || "").truncate(72, omission: "")
  end

  def self.reclaim_space
    connection.execute("VACUUM")
  rescue ActiveRecord::StatementInvalid
    nil
  end

  def shared?
    share_token.present?
  end

  def generate_share_token!
    5.times do
      token = SecureRandom.urlsafe_base64(18)
      update!(share_token: token)
      return share_token
    rescue ActiveRecord::RecordNotUnique
      next
    end
    raise "Could not generate a share token"
  end

  def revoke_share_token!
    update!(share_token: nil)
  end

  def body_after_title
    body.to_s.sub(/\A(?:[ \t]*\R)*[^\n]*\R?/, "")
  end

  private
    def assign_title
      line = body.to_s.lines.map(&:strip).find(&:present?)
      self.title = line.to_s.truncate(80, omission: "")
    end
end

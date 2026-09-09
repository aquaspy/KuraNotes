class Note < ApplicationRecord
  LIST_COLUMNS = [ :id, :title, :preview, :folder, :updated_at ].freeze
  FOLDER_MAX_LENGTH = 80
  RESERVED_FOLDERS = %w[all inbox].freeze

  belongs_to :user

  before_validation :normalize_folder_name
  before_validation :assign_title_and_preview

  scope :blank_drafts, -> { where(title: "", share_token: nil).where("TRIM(body) = ''") }
  scope :list_row, -> { select(*LIST_COLUMNS) }

  def self.open_draft_for(user, folder: "")
    folder = normalize_folder(folder)
    drafts = user.notes.blank_drafts.where(folder: folder)
    draft = drafts.order(updated_at: :desc).first || user.notes.create!(folder: folder)
    drafts.where.not(id: draft.id).delete_all
    draft
  end

  def inbox?
    folder.blank?
  end

  def self.reserved_folder?(name)
    key = name.to_s.strip
    key.blank? || RESERVED_FOLDERS.any? { |reserved| key.casecmp?(reserved) }
  end

  def self.normalize_folder(name)
    value = name.to_s.strip.truncate(FOLDER_MAX_LENGTH, omission: "")
    reserved_folder?(value) ? "" : value
  end

  # Returns the new folder name, or nil if the rename is not allowed.
  def self.rename_folder(user:, from:, to:)
    from = from.to_s.strip
    to = normalize_folder(to)
    return if reserved_folder?(from) || reserved_folder?(to)

    user.notes.where(folder: from).update_all(folder: to) unless from == to
    to
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
    def normalize_folder_name
      self.folder = self.class.normalize_folder(folder)
    end

    def assign_title_and_preview
      lines = body.to_s.lines.map(&:strip).reject(&:blank?)
      self.title = (lines[0] || "").truncate(80, omission: "")
      self.preview = (lines[1] || lines[0] || "").truncate(72, omission: "")
    end
end

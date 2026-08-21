class NotesController < ApplicationController
  before_action :set_note, only: %i[index show update]
  before_action :load_notes, only: %i[index show update]

  def index
  end

  def show
    render :index
  end

  def create
    note = Note.open_draft_for(current_user, folder: folder_param)
    redirect_to note_path(note, folder: params[:folder], q: params[:q])
  end

  def update
    @note.update(note_params)
    load_notes

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to note_path(@note, folder: params[:folder], q: params[:q]) }
    end
  end

  def destroy
    note = current_user.notes.find(params[:id])
    note.destroy
    Note.reclaim_space
    redirect_to notes_path(folder: params[:folder], q: params[:q])
  end

  def destroy_folder
    key = params[:folder].to_s
    if key.blank? || key == "all"
      redirect_to notes_path and return
    end

    scope = key == "inbox" ? current_user.notes.where(folder: "") : current_user.notes.where(folder: key)
    count = scope.delete_all
    Note.reclaim_space
    redirect_to notes_path(folder: key == "inbox" ? "inbox" : nil),
      notice: t("app.folder_cleared", count: count)
  end

  def export
    payload = current_user.notes.order(:updated_at).map { |note|
      note.slice(:title, :body, :folder, :updated_at)
    }
    send_data JSON.pretty_generate(payload),
      filename: "kuranotes-#{Date.current}.json",
      type: "application/json"
  end

  def import
    count = 0
    NoteImporter.rows(params[:file]).each do |row|
      current_user.notes.create!(body: row[:body], folder: row[:folder].to_s)
      count += 1
    end
    redirect_to notes_path, notice: t("app.import_done", count: count)
  rescue ArgumentError, JSON::ParserError, Zip::Error => e
    Rails.logger.warn("[import] #{e.class}: #{e.message}")
    redirect_to notes_path, alert: t("app.import_invalid")
  end

  private
    def set_note
      return if params[:id].blank?

      @note = if action_name == "index"
        current_user.notes.find_by(id: params[:id])
      else
        current_user.notes.find(params[:id])
      end
    end

    def load_notes
      abandoned = current_user.notes.blank_drafts
      abandoned = abandoned.where.not(id: @note.id) if @note
      abandoned.delete_all

      @query = params[:q].to_s.strip
      @folder = params[:folder]
      scope = current_user.notes.order(updated_at: :desc)
      scope = apply_folder(scope)
      if @query.present?
        like = "%#{Note.sanitize_sql_like(@query)}%"
        scope = scope.where("title LIKE ? OR body LIKE ?", like, like)
      end
      @notes = scope.list_row
      @folder_counts = current_user.notes.group(:folder).count
    end

    def apply_folder(scope)
      case @folder
      when nil, "all" then scope
      when "inbox" then scope.where(folder: "")
      else scope.where(folder: @folder)
      end
    end

    def folder_param
      case params[:folder]
      when nil, "all", "inbox" then ""
      else params[:folder].to_s
      end
    end

    def note_params
      params.require(:note).permit(:body, :folder)
    end
end

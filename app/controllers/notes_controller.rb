class NotesController < ApplicationController
  before_action :load_notes, only: %i[index show update]

  def index
    @note = current_user.notes.find_by(id: params[:id]) if params[:id]
  end

  def show
    @note = current_user.notes.find(params[:id])
    render :index
  end

  def create
    note = current_user.notes.create!(folder: folder_param)
    redirect_to note_path(note, folder: params[:folder], q: params[:q])
  end

  def update
    @note = current_user.notes.find(params[:id])
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
    file = params[:file]
    notes = parse_import(file)
    count = 0
    notes.first(500).each do |row|
      next unless row.is_a?(Hash)
      body = row["body"].presence || row[:body].to_s
      folder = (row["folder"] || row[:folder]).to_s
      next if body.blank?
      current_user.notes.create!(body: body, folder: folder)
      count += 1
    end
    redirect_to notes_path, notice: t("app.import_done", count: count)
  rescue JSON::ParserError, ArgumentError
    redirect_to notes_path, alert: t("app.import_invalid")
  end

  private
    def load_notes
      @query = params[:q].to_s.strip
      @folder = params[:folder]
      scope = current_user.notes.order(updated_at: :desc)
      scope = apply_folder(scope)
      if @query.present?
        like = "%#{Note.sanitize_sql_like(@query)}%"
        scope = scope.where("title LIKE ? OR body LIKE ?", like, like)
      end
      @notes = scope
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

    def parse_import(file)
      raise ArgumentError unless file.respond_to?(:read)
      raise ArgumentError if file.size > 2.megabytes

      payload = JSON.parse(file.read)
      notes = payload.is_a?(Array) ? payload : payload["notes"]
      raise ArgumentError unless notes.is_a?(Array)

      notes
    end
end

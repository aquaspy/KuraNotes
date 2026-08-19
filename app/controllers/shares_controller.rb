class SharesController < ApplicationController
  before_action :set_note

  def create
    @note.generate_share_token! unless @note.shared?
    render_change
  end

  def update
    @note.generate_share_token!
    render_change
  end

  def destroy
    @note.revoke_share_token!
    render_change
  end

  private
    def set_note
      @note = current_user.notes.find(params[:note_id])
    end

    def render_change
      respond_to do |format|
        format.turbo_stream { render :update }
        format.html { redirect_to note_path(@note, folder: params[:folder], q: params[:q]) }
      end
    end
end

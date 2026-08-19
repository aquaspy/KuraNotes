class SharedNotesController < ApplicationController
  allow_unauthenticated_access
  skip_unlock

  def show
    @note = Note.find_by!(share_token: params[:token])
    response.set_header("X-Robots-Tag", "noindex, nofollow, noarchive")
    response.set_header("Referrer-Policy", "no-referrer")
  end
end

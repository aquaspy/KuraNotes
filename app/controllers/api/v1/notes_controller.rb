module Api
  module V1
    class NotesController < Api::BaseController
      rate_limit to: 60, within: 1.minute, only: %i[create update],
        by: -> { current_api_token.id },
        with: -> { render json: { error: "rate_limited" }, status: :too_many_requests }

      def index
        scope = current_user.notes.order(updated_at: :desc)
        scope = apply_folder(scope)
        scope = apply_query(scope)
        render json: { notes: scope.limit(page_limit).map(&:as_api) }
      end

      def show
        note = current_user.notes.find_by(id: params[:id])
        return render_not_found unless note

        render json: { note: note.as_api }
      end

      def create
        note = current_user.notes.new(note_params)
        if note.save
          render json: { note: note.as_api }, status: :created
        else
          render_unprocessable(note)
        end
      end

      def update
        note = current_user.notes.find_by(id: params[:id])
        return render_not_found unless note

        if note.update(note_params)
          render json: { note: note.as_api }
        else
          render_unprocessable(note)
        end
      end

      def destroy
        note = current_user.notes.find_by(id: params[:id])
        return render_not_found unless note

        note.destroy
        Note.reclaim_space
        head :no_content
      end

      private
        def note_params
          nested = params[:note]
          source = nested.is_a?(ActionController::Parameters) ? nested : params
          source.permit(:body, :folder)
        end

        def apply_folder(scope)
          case params[:folder]
          when nil, "all" then scope
          when "inbox" then scope.where(folder: "")
          else scope.where(folder: params[:folder].to_s)
          end
        end

        def apply_query(scope)
          query = params[:q].to_s.strip
          return scope if query.blank?

          like = "%#{Note.sanitize_sql_like(query)}%"
          scope.where("title LIKE ? OR body LIKE ?", like, like)
        end

        def page_limit
          return 50 if params[:limit].blank?

          [ [ params[:limit].to_i, 1 ].max, 200 ].min
        end
    end
  end
end

module Api
  module V1
    class FoldersController < Api::BaseController
      def index
        counts = current_user.notes.group(:folder).count
        folders = counts.sort_by { |name, _| name.to_s }.map do |name, count|
          { "name" => name, "count" => count }
        end
        render json: { folders: folders }
      end

      def update
        to = Note.rename_folder(user: current_user, from: params[:from], to: params[:to])
        if to
          render json: { folder: to }
        else
          render json: { errors: [ I18n.t("app.folder_rename_invalid") ] }, status: :unprocessable_entity
        end
      end

      def destroy
        key = params[:folder].to_s
        if key.blank? || key == "all"
          render json: { errors: [ I18n.t("api.invalid_folder") ] }, status: :unprocessable_entity
          return
        end

        scope = key == "inbox" ? current_user.notes.where(folder: "") : current_user.notes.where(folder: key)
        count = scope.delete_all
        Note.reclaim_space
        render json: { folder: key, deleted: count }
      end
    end
  end
end

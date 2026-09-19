module Api
  class BaseController < ActionController::API
    before_action :authenticate_api_token!

    private
      attr_reader :current_user, :current_api_token

      def authenticate_api_token!
        raw = request.headers["Authorization"].to_s.sub(/\ABearer\s+/i, "").presence
        token = ApiToken.authenticate(raw)
        if token
          @current_api_token = token
          @current_user = token.user
          token.touch_last_used!
        else
          render json: { error: "unauthorized" }, status: :unauthorized
        end
      end

      def render_not_found
        render json: { error: "not_found" }, status: :not_found
      end

      def render_unprocessable(record)
        render json: { errors: record.errors.full_messages }, status: :unprocessable_entity
      end
  end
end

class ApiTokensController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :create,
    by: -> { current_user.id },
    with: -> { redirect_to api_tokens_path, alert: I18n.t("auth.too_many") }

  def index
    @api_tokens = current_user.api_tokens.order(created_at: :desc)
  end

  def create
    @api_tokens = current_user.api_tokens.order(created_at: :desc)
    unless current_user.authenticate(params[:current_password].to_s)
      flash.now[:alert] = t("js.wrong_password")
      render :index, status: :unprocessable_entity
      return
    end

    @api_token = ApiToken.generate_for(current_user, name: params[:name])
    if @api_token.save
      @raw_token = @api_token.raw_token
      @api_tokens = current_user.api_tokens.order(created_at: :desc)
      render :index, status: :created
    else
      flash.now[:alert] = @api_token.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    token = current_user.api_tokens.find(params[:id])
    token.destroy
    redirect_to api_tokens_path, notice: t("tokens.revoked")
  end
end

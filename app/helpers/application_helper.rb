module ApplicationHelper
  def signup_enabled?
    Kura.signup_enabled?
  end

  def note_filters(extra = {})
    { folder: params[:folder], q: params[:q] }.compact_blank.merge(extra)
  end

  def folder_label(name)
    name.blank? ? t("js.inbox") : name
  end
end

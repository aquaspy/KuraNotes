class AddPreviewToNotes < ActiveRecord::Migration[8.1]
  def up
    add_column :notes, :preview, :string, null: false, default: ""

    say_with_time "backfill previews" do
      Note.find_each do |note|
        lines = note.body.to_s.lines.map(&:strip).reject(&:blank?)
        note.update_columns(preview: (lines[1] || lines[0] || "").truncate(72, omission: ""))
      end
    end
  end

  def down
    remove_column :notes, :preview
  end
end

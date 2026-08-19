class AddShareTokenToNotes < ActiveRecord::Migration[8.1]
  def change
    add_column :notes, :share_token, :string
    add_index :notes, :share_token, unique: true
  end
end

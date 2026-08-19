class CreateNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :notes, id: :string do |t|
      t.references :user, null: false, foreign_key: true
      t.text :ciphertext, null: false, default: ""
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :notes, [ :user_id, :updated_at ]
  end
end

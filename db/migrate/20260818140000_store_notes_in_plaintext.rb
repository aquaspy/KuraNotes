class StoreNotesInPlaintext < ActiveRecord::Migration[8.1]
  def change
    drop_table :notes, if_exists: true

    create_table :notes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false, default: ""
      t.text :body, null: false, default: ""
      t.string :folder, null: false, default: ""
      t.timestamps
    end
    add_index :notes, [ :user_id, :updated_at ]
    add_index :notes, [ :user_id, :folder ]

    remove_column :users, :kdf_salt, :string, if_exists: true
    reversible { |dir| dir.up { execute "DELETE FROM users" } }
  end
end

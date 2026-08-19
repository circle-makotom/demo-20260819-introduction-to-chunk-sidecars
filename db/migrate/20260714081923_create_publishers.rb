class CreatePublishers < ActiveRecord::Migration[8.1]
  def change
    create_table :publishers do |t|
      t.string :name
      t.string :country

      t.timestamps
    end
  end
end

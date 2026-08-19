class AddPublisherToBooks < ActiveRecord::Migration[8.1]
  def change
    add_reference :books, :publisher, null: true, foreign_key: true
  end
end

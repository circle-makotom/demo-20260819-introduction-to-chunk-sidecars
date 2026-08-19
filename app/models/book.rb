class Book < ApplicationRecord
  belongs_to :author
  belongs_to :publisher, optional: true

  validates :title, presence: true
  validates :isbn, presence: true, uniqueness: true
  validates :year, numericality: { only_integer: true }, allow_nil: true
end

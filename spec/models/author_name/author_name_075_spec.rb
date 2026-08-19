require 'rails_helper'

# Auto-generated random-input case 075 of 100.
# Target: Author#name presence validation - deliberately minimal coverage
# (touches only app/models/author.rb + the factory), so CircleCI Test
# Impact Analysis skips these cases unless the Author model itself changes.
# Independent of Publisher: editing author.rb never selects Publisher's cases.
RSpec.describe Author, type: :model do
  it "is valid with a random name (case 075)" do
    expect(build(:author, name: "Chadwick Prohaska 0b3560")).to be_valid
  end
end

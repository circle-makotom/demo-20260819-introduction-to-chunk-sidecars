require 'rails_helper'

# Auto-generated random-input case 047 of 100.
# Target: Author#name presence validation - deliberately minimal coverage
# (touches only app/models/author.rb + the factory), so CircleCI Test
# Impact Analysis skips these cases unless the Author model itself changes.
# Independent of Publisher: editing author.rb never selects Publisher's cases.
RSpec.describe Author, type: :model do
  it "is valid with a random name (case 047)" do
    expect(build(:author, name: "Dayton Marvin e2cb96")).to be_valid
  end
end

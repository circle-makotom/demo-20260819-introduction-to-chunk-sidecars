require 'rails_helper'

# Auto-generated random-input case 079 of 100.
# Target: Author#name presence validation - deliberately minimal coverage
# (touches only app/models/author.rb + the factory), so CircleCI Test
# Impact Analysis skips these cases unless the Author model itself changes.
# Independent of Publisher: editing author.rb never selects Publisher's cases.
RSpec.describe Author, type: :model do
  it "is valid with a random name (case 079)" do
    expect(build(:author, name: "Elyse Spencer Jr. 36c9e4")).to be_valid
  end
end

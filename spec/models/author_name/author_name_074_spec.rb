require 'rails_helper'

# Auto-generated random-input case 074 of 100.
# Target: Author#name presence validation - deliberately minimal coverage
# (touches only app/models/author.rb + the factory), so CircleCI Test
# Impact Analysis skips these cases unless the Author model itself changes.
# Independent of Publisher: editing author.rb never selects Publisher's cases.
RSpec.describe Author, type: :model do
  it "is valid with a random name (case 074)" do
    expect(build(:author, name: "Ms. Lavina Zboncak bb55c9")).to be_valid
  end
end

require 'rails_helper'

# Auto-generated random-input case 061 of 100.
# Target: Author#name presence validation - deliberately minimal coverage
# (touches only app/models/author.rb + the factory), so CircleCI Test
# Impact Analysis skips these cases unless the Author model itself changes.
# Independent of Publisher: editing author.rb never selects Publisher's cases.
RSpec.describe Author, type: :model do
  it "is valid with a random name (case 061)" do
    expect(build(:author, name: "Marcia Kshlerin 376c9a")).to be_valid
  end
end

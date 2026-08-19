require 'rails_helper'

# Auto-generated random-input case 043 of 100.
# Target: Publisher#name presence validation — deliberately minimal coverage
# (touches only app/models/publisher.rb + the factory), so CircleCI Test
# Impact Analysis skips these cases unless the Publisher model itself changes.
# Independent of Author: editing publisher.rb never selects Author's cases.
RSpec.describe Publisher, type: :model do
  it "is valid with a random name (case 043)" do
    expect(build(:publisher, name: "Gutkowski, Blick and Bogan ad6938")).to be_valid
  end
end

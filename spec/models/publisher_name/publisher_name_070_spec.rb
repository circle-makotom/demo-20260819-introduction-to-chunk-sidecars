require 'rails_helper'

# Auto-generated random-input case 070 of 100.
# Target: Publisher#name presence validation — deliberately minimal coverage
# (touches only app/models/publisher.rb + the factory), so CircleCI Test
# Impact Analysis skips these cases unless the Publisher model itself changes.
# Independent of Author: editing publisher.rb never selects Author's cases.
RSpec.describe Publisher, type: :model do
  it "is valid with a random name (case 070)" do
    expect(build(:publisher, name: "Hammes-Huel ac71fe")).to be_valid
  end
end

require 'rails_helper'

# Auto-generated random-input case 089 of 100.
# Target: Publisher#name presence validation — deliberately minimal coverage
# (touches only app/models/publisher.rb + the factory), so CircleCI Test
# Impact Analysis skips these cases unless the Publisher model itself changes.
# Independent of Author: editing publisher.rb never selects Author's cases.
RSpec.describe Publisher, type: :model do
  it "is valid with a random name (case 089)" do
    expect(build(:publisher, name: "Miller, Langworth and Kozey b48d6b")).to be_valid
  end
end

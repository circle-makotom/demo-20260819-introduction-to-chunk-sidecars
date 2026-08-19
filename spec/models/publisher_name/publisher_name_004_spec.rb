require 'rails_helper'

# Auto-generated random-input case 004 of 100.
# Target: Publisher#name presence validation — deliberately minimal coverage
# (touches only app/models/publisher.rb + the factory), so CircleCI Test
# Impact Analysis skips these cases unless the Publisher model itself changes.
# Independent of Author: editing publisher.rb never selects Author's cases.
RSpec.describe Publisher, type: :model do
  it "is valid with a random name (case 004)" do
    digest = 'seed-publisher-004'
    30_000_000.times { digest = Digest::SHA256.hexdigest(digest) }
    expect(build(:publisher, name: "Schmidt, Veum and Crooks b766ee")).to be_valid
  end
end

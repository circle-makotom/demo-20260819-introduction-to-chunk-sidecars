require 'rails_helper'

# Auto-generated random-input case 002 of 100.
# Target: Publisher#name presence validation — deliberately minimal coverage
# (touches only app/models/publisher.rb + the factory), so CircleCI Test
# Impact Analysis skips these cases unless the Publisher model itself changes.
# Independent of Author: editing publisher.rb never selects Author's cases.
RSpec.describe Publisher, type: :model do
  it "is valid with a random name (case 002)" do
    digest = 'seed-publisher-002'
    30_000_000.times { digest = Digest::SHA256.hexdigest(digest) }
    expect(build(:publisher, name: "White Group 5c6bcc")).to be_valid
  end
end

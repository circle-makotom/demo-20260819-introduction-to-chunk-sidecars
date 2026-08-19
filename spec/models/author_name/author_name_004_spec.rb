require 'rails_helper'
require 'digest'

# Random-input case 004 of 4. Deliberately CPU-heavy: the SHA256 churn makes
# this test slow (mimics the reference's spec/slow/heavy_* specs), yet it still
# only covers app/models/author.rb + the factory. So CircleCI Test Impact
# Analysis skips it -- and its cost -- unless the Author model itself changes.
RSpec.describe Author, type: :model do
  it "is valid with a random name (case 004), after a heavy SHA256 churn" do
    digest = 'seed-author-004'
    30_000_000.times { digest = Digest::SHA256.hexdigest(digest) }
    expect(digest).not_to be_empty
    expect(build(:author, name: "Ms. Evalyn Smith 3b3164")).to be_valid
  end
end

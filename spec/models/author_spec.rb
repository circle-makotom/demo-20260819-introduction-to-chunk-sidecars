require 'rails_helper'

RSpec.describe Author, type: :model do
  describe "validations" do
    it "is valid with a name" do
      expect(build(:author)).to be_valid
    end

    it "is invalid without a name" do
      author = build(:author, name: nil)
      expect(author).not_to be_valid
      expect(author.errors[:name]).to include("can't be blank")
    end
  end

  describe "associations" do
    it "has many books" do
      author = create(:author)
      create_list(:book, 2, author: author)
      expect(author.books.count).to eq(2)
    end

    it "destroys its books when destroyed" do
      author = create(:author)
      create(:book, author: author)
      expect { author.destroy }.to change(Book, :count).by(-1)
    end
  end
end

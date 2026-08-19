require 'rails_helper'

RSpec.describe Book, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      expect(build(:book)).to be_valid
    end

    it "is invalid without a title" do
      book = build(:book, title: nil)
      expect(book).not_to be_valid
      expect(book.errors[:title]).to include("can't be blank")
    end

    it "requires a unique isbn" do
      existing = create(:book)
      duplicate = build(:book, isbn: existing.isbn)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:isbn]).to include("has already been taken")
    end

    it "rejects a non-integer year" do
      book = build(:book, year: "nineteen")
      expect(book).not_to be_valid
      expect(book.errors[:year]).to be_present
    end

    it "is invalid without an author" do
      book = build(:book, author: nil)
      expect(book).not_to be_valid
    end
  end

  describe "associations" do
    it "belongs to an author" do
      author = create(:author)
      book = create(:book, author: author)
      expect(book.author).to eq(author)
    end
  end
end

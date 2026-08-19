require 'rails_helper'

RSpec.describe Publisher, type: :model do
  describe "validations" do
    it "is valid with a name" do
      expect(build(:publisher)).to be_valid
    end

    it "is invalid without a name" do
      publisher = build(:publisher, name: nil)
      expect(publisher).not_to be_valid
      expect(publisher.errors[:name]).to include("can't be blank")
    end
  end

  describe "associations" do
    it "has many books" do
      publisher = create(:publisher)
      create_list(:book, 2, publisher: publisher)
      expect(publisher.books.count).to eq(2)
    end

    it "nullifies its books' publisher when destroyed (does not delete shared books)" do
      publisher = create(:publisher)
      book = create(:book, publisher: publisher)
      expect { publisher.destroy }.to change { book.reload.publisher_id }.from(publisher.id).to(nil)
      expect(Book.exists?(book.id)).to be(true)
    end
  end
end

FactoryBot.define do
  factory :author do
    name { Faker::Book.author }
    bio { Faker::Lorem.paragraph }
  end
end

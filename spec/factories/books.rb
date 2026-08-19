FactoryBot.define do
  factory :book do
    title { Faker::Book.title }
    sequence(:isbn) { |n| format("978%010d", n) }
    year { rand(1900..2025) }
    association :author
  end
end

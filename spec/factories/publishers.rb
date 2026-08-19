FactoryBot.define do
  factory :publisher do
    name { Faker::Company.name }
    country { Faker::Address.country }
  end
end

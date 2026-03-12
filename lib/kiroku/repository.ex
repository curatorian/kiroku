defmodule Kiroku.Repository do
  use Ash.Domain, otp_app: :kiroku, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Kiroku.Repository.Community
    resource Kiroku.Repository.Collection
    resource Kiroku.Repository.Item
    resource Kiroku.Repository.ItemKeyword
    resource Kiroku.Repository.ItemAuthor
    resource Kiroku.Repository.ItemAdvisor
    resource Kiroku.Repository.ItemExaminer
    resource Kiroku.Repository.ItemTeamMember
    resource Kiroku.Repository.ItemMetadata
  end
end

defmodule Kiroku.Accounts do
  use Ash.Domain, otp_app: :kiroku, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Kiroku.Accounts.Token
    resource Kiroku.Accounts.User
  end
end

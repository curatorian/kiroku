defmodule Kiroku.Access do
  use Ash.Domain, otp_app: :kiroku, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Kiroku.Access.RbacPolicy
  end
end

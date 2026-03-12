defmodule Kiroku.Analytics do
  use Ash.Domain, otp_app: :kiroku, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Kiroku.Analytics.ViewEvent
  end
end

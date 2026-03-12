defmodule Kiroku.Content do
  use Ash.Domain, otp_app: :kiroku, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Kiroku.Content.Bitstream
  end
end

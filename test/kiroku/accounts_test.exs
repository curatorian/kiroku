defmodule Kiroku.AccountsTest do
  use Kiroku.DataCase, async: true

  alias Kiroku.Accounts
  alias Kiroku.Accounts.User

  describe "create_user_from_oauth/1" do
    test "creates a user and stores a generated hashed password" do
      attrs = %{
        "email" => "oauth@example.com",
        "display_name" => "OAuth User",
        "identifier" => "199901022022023001",
        "faculty" => "Informatika",
        "department" => "Direktorat Pendidikan Non Gelar",
        "avatar_url" => "https://paus.unpad.ac.id/media/users/c/h/r/oauth/picture.jpg"
      }

      assert {:ok, %User{} = user} = Accounts.create_user_from_oauth(attrs)
      assert user.email == "oauth@example.com"
      assert user.display_name == "OAuth User"
      assert user.identifier == "199901022022023001"
      assert user.avatar_url == "https://paus.unpad.ac.id/media/users/c/h/r/oauth/picture.jpg"
      assert is_binary(user.hashed_password)
      assert byte_size(user.hashed_password) > 0
    end
  end
end

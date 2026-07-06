defmodule Kiroku.OnboardingTest do
  use Kiroku.DataCase, async: true

  alias Kiroku.Accounts.User
  alias Kiroku.{Onboarding, Settings}

  # onboarding state is cached in :persistent_term; reset between tests so a
  # prior test's cache doesn't leak into this one.
  setup do
    Onboarding.force_setup_state(false)
    :ok
  end

  describe "create_first_superadmin/1" do
    test "creates a confirmed superadmin when none exists" do
      attrs = %{
        "email" => "founder@university.ac.id",
        "password" => "super_secret_123",
        "display_name" => "Founding Admin"
      }

      assert {:ok, %User{} = user} = Onboarding.create_first_superadmin(attrs)
      assert user.email == "founder@university.ac.id"
      assert user.user_type == :superadmin
      assert user.confirmed_at != nil
      assert user.hashed_password != nil
    end

    test "refuses to create a second superadmin" do
      insert_superadmin(email: "first@university.ac.id")

      attrs = %{
        "email" => "second@university.ac.id",
        "password" => "super_secret_123",
        "display_name" => "Second"
      }

      assert {:error, :superadmin_exists} = Onboarding.create_first_superadmin(attrs)
    end

    test "validates required fields and password length" do
      assert {:error, changeset} =
               Onboarding.create_first_superadmin(%{
                 "email" => "bad",
                 "password" => "short",
                 "display_name" => ""
               })

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :email)
      assert Keyword.has_key?(changeset.errors, :password)
    end
  end

  describe "setup state" do
    test "mark_setup_complete/0 sets the setting and the cache" do
      assert Onboarding.needs_setup?()
      assert :ok = Onboarding.mark_setup_complete()
      assert Settings.setup_complete?()
      refute Onboarding.needs_setup?()
    end

    test "refresh_setup_state/0 returns true when a superadmin already exists" do
      # Simulates an existing seeded deployment.
      assert Onboarding.refresh_setup_state() == false

      insert_superadmin(email: "existing@university.ac.id")
      assert Onboarding.refresh_setup_state() == true
      refute Onboarding.needs_setup?()
    end
  end

  # Helpers ────────────────────────────────────────────────────────────────────

  defp insert_superadmin(email: email) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    %User{}
    |> User.registration_changeset(%{
      email: email,
      password: "super_secret_123",
      display_name: "Admin"
    })
    |> Ecto.Changeset.put_change(:user_type, :superadmin)
    |> Ecto.Changeset.put_change(:confirmed_at, now)
    |> Kiroku.Repo.insert!()
  end
end

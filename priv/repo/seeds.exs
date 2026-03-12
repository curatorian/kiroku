# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Kiroku.Repo.insert!(%Kiroku.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Kiroku.Accounts.{Group, GroupMembership}
alias Kiroku.Repository.{Community, Collection}

# ── System groups ─────────────────────────────────────────────────────────────
for name <- ["ANONYMOUS", "AUTHENTICATED", "ADMIN"] do
  case Group |> Ash.Query.filter(name == ^name) |> Ash.read_one(authorize?: false) do
    {:ok, nil} ->
      Ash.create!(Group, %{name: name, is_system: true}, authorize?: false)

    {:ok, _existing} ->
      :skip
  end
end

# ── Admin user (magic link auth — created or found by email) ──────────────────
admin_email = System.get_env("ADMIN_EMAIL") || "admin@yourinstitution.ac.id"

admin =
  case Kiroku.Accounts.User
       |> Ash.Query.filter(email == ^admin_email)
       |> Ash.read_one(authorize?: false) do
    {:ok, nil} ->
      Kiroku.Accounts.User
      |> Ash.Changeset.for_create(
        :sign_in_with_magic_link,
        %{token: "seed-bypass"},
        authorize?: false,
        upsert?: true,
        upsert_identity: :unique_email,
        upsert_fields: [:email]
      )
      # Seed users directly via Repo since magic link requires a real token flow
      |> then(fn _changeset ->
        {:ok, user} =
          %Kiroku.Accounts.User{}
          |> Ecto.Changeset.change(%{
            email: admin_email,
            full_name: "System Administrator",
            user_type: :superadmin,
            active: true
          })
          |> Kiroku.Repo.insert(on_conflict: :nothing)

        user
      end)

    {:ok, existing} ->
      existing
  end

admin_group =
  Group
  |> Ash.Query.filter(name == "ADMIN")
  |> Ash.read_one!(authorize?: false)

case GroupMembership
     |> Ash.Query.filter(user_id == ^admin.id and group_id == ^admin_group.id)
     |> Ash.read_one(authorize?: false) do
  {:ok, nil} ->
    Ash.create!(
      GroupMembership,
      %{user_id: admin.id, group_id: admin_group.id},
      authorize?: false
    )

  {:ok, _existing} ->
    :skip
end

# ── Default community + collection ────────────────────────────────────────────
community =
  case Community
       |> Ash.Query.filter(handle == "123456789/0")
       |> Ash.read_one(authorize?: false) do
    {:ok, nil} ->
      Ash.create!(
        Community,
        %{
          name: "Universitas Padjadjaran",
          handle: "123456789/0"
        },
        authorize?: false
      )

    {:ok, existing} ->
      existing
  end

case Collection
     |> Ash.Query.filter(handle == "123456789/1")
     |> Ash.read_one(authorize?: false) do
  {:ok, nil} ->
    Ash.create!(
      Collection,
      %{
        name: "Thesis & Dissertations",
        handle: "123456789/1",
        community_id: community.id,
        description: "Undergraduate and postgraduate thesis collection"
      },
      authorize?: false
    )

  {:ok, _existing} ->
    :skip
end

IO.puts("Seeds complete.")

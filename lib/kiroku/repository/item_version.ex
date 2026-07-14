defmodule Kiroku.Repository.ItemVersion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @moduledoc """
  Append-only version + audit-log entry for an item.

  Every lifecycle event (create, update, submit, review, publish, withdraw,
  import) writes a row with a numbered snapshot. The table serves double duty:

    1. **Version history** — DSpace-style numbered snapshots that can be
       diffed to show what changed between versions.
    2. **Audit trail** — who changed what when. The previous schema only
       captured the latest reviewer (`reviewed_by_id` / `reviewed_at`).
  """

  schema "item_versions" do
    field :version_number, :integer
    field :action, :string
    field :actor_name, :string
    field :summary, :string
    field :snapshot, :map

    belongs_to :item, Kiroku.Repository.Item
    belongs_to :actor, Kiroku.Accounts.User

    timestamps(updated_at: false)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :item_id,
      :version_number,
      :action,
      :actor_id,
      :actor_name,
      :summary,
      :snapshot
    ])
    |> validate_required([:item_id, :version_number, :action])
    |> unique_constraint([:item_id, :version_number])
    |> foreign_key_constraint(:actor_id)
  end
end

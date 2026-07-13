defmodule Kiroku.Analytics.DownloadEvent do
  @moduledoc """
  Records a bitstream download. Mirrors `ViewEvent` but scoped to a bitstream
  (with the parent `item_id` denormalised for cheap per-item rollups).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "download_events" do
    field :item_id, :binary_id
    field :user_id, :binary_id
    field :ip_hash, :string
    field :user_agent, :string
    field :referer, :string

    belongs_to :bitstream, Kiroku.Content.Bitstream

    timestamps(updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:item_id, :bitstream_id, :user_id, :ip_hash, :user_agent, :referer])
    |> validate_required([:item_id, :bitstream_id])
    |> foreign_key_constraint(:bitstream_id)
  end
end

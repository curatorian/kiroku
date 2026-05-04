defmodule Kiroku.Content do
  @moduledoc """
  Context module for Bitstream (file attachments for repository items).
  Accessibility rules are enforced here so controllers and live views stay thin.
  """

  import Ecto.Query
  alias Kiroku.Repo
  alias Kiroku.Content.Bitstream
  alias Kiroku.Repository.Item

  def list_bitstreams_for_item(item_id) do
    Repo.all(
      from b in Bitstream,
        where: b.item_id == ^item_id,
        order_by: [b.bundle_name, b.sequence]
    )
  end

  def get_bitstream!(id), do: Repo.get!(Bitstream, id)

  def get_bitstream(id), do: Repo.get(Bitstream, id)

  def create_bitstream(attrs) do
    %Bitstream{}
    |> Bitstream.changeset(attrs)
    |> Repo.insert()
  end

  def update_bitstream(%Bitstream{} = bitstream, attrs) do
    bitstream
    |> Bitstream.changeset(attrs)
    |> Repo.update()
  end

  def delete_bitstream(%Bitstream{} = bitstream), do: Repo.delete(bitstream)

  @doc """
  Determines whether `user` may access `bitstream`.

  Rules (evaluated in order):
  1. THUMBNAIL bundles → always accessible.
  2. ADMINISTRATIVE / LICENSE bundles → reviewer, admin, superadmin only.
  3. ORIGINAL sequence == 1 (abstract PDF) → never embargoed; always accessible.
  4. Everything else → accessible unless the parent item's files are embargoed.
     While under embargo: reviewer/admin/superadmin may still access.
  """
  def accessible?(%Bitstream{bundle_name: :THUMBNAIL}, _user, _item), do: true

  def accessible?(%Bitstream{bundle_name: bundle}, user, _item)
      when bundle in [:ADMINISTRATIVE, :LICENSE] do
    user_is_staff?(user)
  end

  def accessible?(%Bitstream{bundle_name: :ORIGINAL, sequence: 1}, _user, _item), do: true

  def accessible?(%Bitstream{}, user, %Item{} = item) do
    cond do
      user_is_staff?(user) -> true
      Item.files_embargoed?(item) -> false
      true -> true
    end
  end

  defp user_is_staff?(%{user_type: type}), do: type in [:reviewer, :admin, :superadmin]
  defp user_is_staff?(_), do: false
end

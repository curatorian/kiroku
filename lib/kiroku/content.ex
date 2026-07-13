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
  Determines whether `user` may access `bitstream` belonging to `item`.

  Rules (evaluated in order):
  1. THUMBNAIL bundles → always accessible.
  2. ADMINISTRATIVE / LICENSE bundles → reviewer, admin, superadmin only.
  3. ORIGINAL sequence == 1 (abstract PDF) → never embargoed, but still
     subject to the bitstream's own access_level.
  4. Staff (reviewer/admin/superadmin) → always accessible (bypass embargo).
  5. If the item's files are embargoed → not accessible.
  6. Otherwise → evaluate the bitstream's own access_level:
       :open       → accessible to everyone
       :internal   → accessible to any logged-in user
       :inherit    → use the parent item's access_level
       :restricted → staff only
       :closed     → no one (except staff, already handled above)
  """
  def accessible?(%Bitstream{bundle_name: :THUMBNAIL}, _user, _item), do: true

  def accessible?(%Bitstream{bundle_name: bundle}, user, _item)
      when bundle in [:ADMINISTRATIVE, :LICENSE] do
    user_is_staff?(user)
  end

  def accessible?(%Bitstream{} = bitstream, user, %Item{} = item) do
    cond do
      user_is_staff?(user) ->
        true

      bitstream_locked?(bitstream) and not user_is_internal?(user) ->
        false

      Item.files_embargoed?(item) and not abstract?(bitstream) ->
        false

      true ->
        access_level_allows?(bitstream.access_level, item.access_level, user)
    end
  end

  @doc """
  Returns true if the bitstream's description matches a globally locked
  pattern (configured in admin settings).
  """
  def bitstream_locked?(%Bitstream{description: description}) when is_binary(description) do
    description in Kiroku.Settings.locked_bitstream_descriptions()
  end

  def bitstream_locked?(_), do: false

  # ORIGINAL bundle, sequence 1 is the abstract PDF — exempt from embargo.
  defp abstract?(%Bitstream{bundle_name: :ORIGINAL, sequence: 1}), do: true
  defp abstract?(%Bitstream{}), do: false

  defp access_level_allows?(:open, _item_level, _user), do: true

  # :internal = any authenticated user (logged-in). Anonymous (nil) is denied;
  # any non-nil user — including submitters — is granted.
  defp access_level_allows?(:internal, _item_level, nil), do: false
  defp access_level_allows?(:internal, _item_level, _user), do: true

  defp access_level_allows?(:inherit, item_level, user),
    do: access_level_allows?(item_level, item_level, user)

  defp access_level_allows?(:restricted, _item_level, user), do: user_is_staff?(user)

  defp access_level_allows?(:closed, _item_level, _user), do: false

  defp user_is_staff?(%{user_type: type}), do: type in [:reviewer, :admin, :superadmin]
  defp user_is_staff?(_), do: false

  defp user_is_internal?(%{user_type: :internal}), do: true
  defp user_is_internal?(_), do: false
end

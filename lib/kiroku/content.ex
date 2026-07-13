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

  # ── Fixity (checksum verification) ─────────────────────────────────────────
  #
  # Bitstreams store an MD5 checksum at upload time. A periodic Oban job
  # (FixityWorker) recomputes the checksum from the stored bytes and compares
  # it to the stored value, recording each result in bitstream_fixity_checks.

  alias Kiroku.Content.BitstreamFixityCheck
  alias Kiroku.Storage.Uploader

  @fixity_batch_size 50
  @fixity_recheck_after_days 30

  @doc """
  Verifies a single bitstream's checksum against its stored bytes.

    * If the bytes are readable and a stored checksum exists → verify, record,
      and update `last_fixity_at`/`last_fixity_ok`.
    * If the bytes are readable but no checksum is stored yet → record a
      baseline (establishes the checksum for the first time, e.g. for legacy
      bitstreams uploaded before checksum-on-upload existed).
    * If the bytes can't be read → record a check with `ok: nil` and the error.

  Returns `{:ok, boolean | nil}` (the check outcome) | `{:error, reason}`.
  """
  def check_bitstream(%Bitstream{} = bitstream) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Uploader.read_bytes(bitstream) do
      {:ok, bytes} ->
        actual = Uploader.checksum(bytes)

        {expected, ok, changes} =
          case bitstream.checksum do
            nil ->
              # No baseline yet — establish it.
              {actual, true, %{checksum: actual, checksum_algorithm: "MD5"}}

            stored ->
              {stored, stored == actual, %{}}
          end

        {:ok, _} =
          %BitstreamFixityCheck{}
          |> BitstreamFixityCheck.changeset(%{
            bitstream_id: bitstream.id,
            expected_checksum: expected,
            actual_checksum: actual,
            ok: ok
          })
          |> Repo.insert()

        {:ok, _} =
          bitstream
          |> Ecto.Changeset.cast(
            Map.merge(changes, %{last_fixity_at: now, last_fixity_ok: ok}),
            [:checksum, :checksum_algorithm, :last_fixity_at, :last_fixity_ok]
          )
          |> Repo.update()

        {:ok, ok}

      {:error, reason} ->
        {:ok, _} =
          %BitstreamFixityCheck{}
          |> BitstreamFixityCheck.changeset(%{
            bitstream_id: bitstream.id,
            expected_checksum: bitstream.checksum || "",
            ok: nil,
            error: inspect(reason)
          })
          |> Repo.insert()

        {:ok, _} =
          bitstream
          |> Ecto.Changeset.cast(
            %{last_fixity_at: now, last_fixity_ok: nil},
            [:last_fixity_at, :last_fixity_ok]
          )
          |> Repo.update()

        {:error, reason}
    end
  end

  def check_bitstream(id) when is_binary(id) do
    case get_bitstream(id) do
      %Bitstream{} = bs -> check_bitstream(bs)
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Runs fixity checks for a batch of bitstreams that are due (never checked, or
  last checked more than `@fixity_recheck_after_days` days ago). Skips
  `:url`-hosted bitstreams (not verifiable).

  Returns a map of counts: `%{checked: n, ok: n, failed: n, errored: n}`.
  """
  def run_fixity_batch(opts \\ []) do
    limit = Keyword.get(opts, :limit, @fixity_batch_size)
    cutoff = DateTime.utc_now() |> DateTime.add(-@fixity_recheck_after_days * 86_400, :second)

    bitstreams =
      Repo.all(
        from b in Bitstream,
          where:
            b.storage_type in [:local, :s3] and
              (is_nil(b.last_fixity_at) or b.last_fixity_at < ^cutoff),
          order_by: [asc_nulls_first: b.last_fixity_at],
          limit: ^limit
      )

    Enum.reduce(bitstreams, %{checked: 0, ok: 0, failed: 0, errored: 0}, fn bs, acc ->
      case check_bitstream(bs) do
        {:ok, true} -> %{acc | checked: acc.checked + 1, ok: acc.ok + 1}
        {:ok, false} -> %{acc | checked: acc.checked + 1, failed: acc.failed + 1}
        {:ok, nil} -> %{acc | checked: acc.checked + 1, errored: acc.errored + 1}
        {:error, _} -> %{acc | checked: acc.checked + 1, errored: acc.errored + 1}
      end
    end)
  end

  @doc """
  Aggregate fixity status across all verifiable bitstreams, for the admin
  dashboard: counts of verified-ok, verified-failed, never-checked, and
  externally-hosted (unverifiable).
  """
  def fixity_summary do
    base = from b in Bitstream, where: b.storage_type in [:local, :s3]

    %{
      ok: Repo.aggregate(where(base, [b], b.last_fixity_ok == true), :count, :id),
      failed: Repo.aggregate(where(base, [b], b.last_fixity_ok == false), :count, :id),
      unchecked: Repo.aggregate(where(base, [b], is_nil(b.last_fixity_at)), :count, :id),
      unverifiable:
        Repo.aggregate(from(b in Bitstream, where: b.storage_type == :url), :count, :id)
    }
  end

  @doc "Recent fixity-check failures (for an admin report)."
  def list_fixity_failures(limit \\ 20) do
    Repo.all(
      from c in BitstreamFixityCheck,
        where: c.ok == false,
        order_by: [desc: c.inserted_at],
        limit: ^limit,
        preload: [:bitstream]
    )
  end
end

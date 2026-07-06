defmodule Kiroku.Repository do
  @moduledoc """
  Context module for Community, Collection, Item, and all item-child schemas.
  All authorization checks happen in the caller (LiveView / controller) before
  calling any function here.
  """

  import Ecto.Query
  alias Kiroku.Repo

  alias Kiroku.Repository.{
    Community,
    Collection,
    Item,
    ItemKeyword,
    ItemAuthor,
    ItemAdvisor,
    ItemExaminer,
    ItemTeamMember,
    ItemMetadata
  }

  # ── Communities ─────────────────────────────────────────────────────────────

  def list_communities do
    Repo.all(from c in Community, where: c.is_active == true, order_by: c.position)
  end

  @doc """
  Returns top-level (root) communities — those without a parent.
  """
  def list_root_communities do
    Repo.all(
      from c in Community,
        where: c.is_active == true and is_nil(c.parent_community_id),
        order_by: c.position
    )
  end

  @doc """
  Returns the direct subcommunities of a given community.
  """
  def list_subcommunities(community_id) do
    Repo.all(
      from c in Community,
        where: c.parent_community_id == ^community_id and c.is_active == true,
        order_by: c.position
    )
  end

  @doc """
  Returns all active communities as a flat list annotated with a virtual
  `depth` field, ordered in hierarchy traversal order (parents before
  children). Used by the admin UI to render a tree with indentation.
  """
  def list_communities_tree do
    communities =
      Repo.all(from c in Community, where: c.is_active == true, order_by: c.position)

    build_community_tree(communities, nil, 0)
  end

  defp build_community_tree(all, parent_id, depth) do
    all
    |> Enum.filter(fn %Community{parent_community_id: pid} ->
      same_parent?(pid, parent_id)
    end)
    |> Enum.flat_map(fn community ->
      community = %{community | depth: depth}
      [community | build_community_tree(all, community.id, depth + 1)]
    end)
  end

  defp same_parent?(nil, nil), do: true

  defp same_parent?(pid, parent_id) when is_binary(pid) and is_binary(parent_id),
    do: pid == parent_id

  defp same_parent?(_, _), do: false

  @doc """
  Returns communities eligible to be set as the parent of `community`,
  as a depth-annotated tree (parents before children, with indentation
  depth set on each struct). Excludes the community itself and its
  descendants to prevent cycles. Pass `nil` to list all active
  communities.
  """
  def list_possible_parents_tree(community) do
    raw =
      Repo.all(from c in Community, where: c.is_active == true, order_by: c.position)

    excluded = descendant_ids(raw, community && community.id)

    build_community_tree(raw, nil, 0)
    |> Enum.reject(fn %Community{id: id} -> id in excluded end)
  end

  # Returns the set of ids for `community_id` and all of its descendants.
  defp descendant_ids(_communities, nil), do: MapSet.new()

  defp descendant_ids(communities, community_id),
    do: collect_descendants(communities, community_id, MapSet.new([community_id]))

  defp collect_descendants(communities, community_id, acc) do
    children =
      communities
      |> Enum.filter(fn %Community{parent_community_id: pid} -> pid == community_id end)
      |> Enum.map(& &1.id)
      |> Enum.reject(&MapSet.member?(acc, &1))

    Enum.reduce(children, acc, fn child_id, set ->
      collect_descendants(communities, child_id, MapSet.put(set, child_id))
    end)
  end

  @doc """
  Fetches a community with its parent and subcommunities preloaded.
  """
  def get_community_with_relations!(id) do
    ordered_subq = from(c in Community, where: c.is_active == true, order_by: c.position)

    Repo.get!(Community, id)
    |> Repo.preload(parent_community: :parent_community, subcommunities: ordered_subq)
  end

  @doc """
  Fetches a community by handle with its parent and subcommunities preloaded.
  """
  def get_community_with_relations_by_handle!(handle) do
    ordered_subq = from(c in Community, where: c.is_active == true, order_by: c.position)

    Repo.get_by!(Community, handle: handle)
    |> Repo.preload(parent_community: :parent_community, subcommunities: ordered_subq)
  end

  def get_community!(id), do: Repo.get!(Community, id)

  def get_community(id), do: Repo.get(Community, id)

  def get_community_by_handle!(handle), do: Repo.get_by!(Community, handle: handle)

  def get_community_by_handle(handle), do: Repo.get_by(Community, handle: handle)

  def create_community(attrs) do
    %Community{}
    |> Community.changeset(attrs)
    |> validate_parent_allowed(nil)
    |> Repo.insert()
  end

  def update_community(%Community{} = community, attrs) do
    community
    |> Community.changeset(attrs)
    |> validate_parent_allowed(community.id)
    |> Repo.update()
  end

  # Prevents creating a cycle by ensuring the chosen parent is not the
  # community itself or one of its descendants.
  defp validate_parent_allowed(changeset, community_id) do
    parent_id = Ecto.Changeset.get_field(changeset, :parent_community_id)

    if parent_id do
      communities =
        Repo.all(
          from c in Community, where: c.is_active == true, select: [:id, :parent_community_id]
        )

      excluded = descendant_ids(communities, community_id)

      if parent_id in excluded do
        Ecto.Changeset.add_error(changeset, :parent_community_id, "cannot be a descendant")
      else
        changeset
      end
    else
      changeset
    end
  end

  def delete_community(%Community{} = community), do: Repo.delete(community)

  # ── Collections ─────────────────────────────────────────────────────────────

  def list_collections do
    Repo.all(from c in Collection, order_by: c.name)
  end

  def list_collections_for_community(community_id) do
    Repo.all(
      from c in Collection,
        where: c.community_id == ^community_id and c.is_active == true,
        order_by: c.position
    )
  end

  def get_collection!(id), do: Repo.get!(Collection, id)

  def get_collection(id), do: Repo.get(Collection, id)

  def get_collection_by_handle!(handle), do: Repo.get_by!(Collection, handle: handle)

  def get_collection_by_handle(handle), do: Repo.get_by(Collection, handle: handle)

  def create_collection(attrs) do
    %Collection{}
    |> Collection.changeset(attrs)
    |> Repo.insert()
  end

  def update_collection(%Collection{} = collection, attrs) do
    collection
    |> Collection.changeset(attrs)
    |> Repo.update()
  end

  def delete_collection(%Collection{} = collection), do: Repo.delete(collection)

  # ── Items ────────────────────────────────────────────────────────────────────

  def get_item!(id), do: Repo.get!(Item, id)

  def get_item(id), do: Repo.get(Item, id)

  def get_item_by_handle!(handle), do: Repo.get_by!(Item, handle: handle)

  def get_item_by_handle(handle), do: Repo.get_by(Item, handle: handle)

  def get_item_with_preloads!(id) do
    Repo.get!(Item, id)
    |> Repo.preload([
      :collection,
      :submitter,
      :item_keywords,
      :item_authors,
      :item_advisors,
      :item_examiners,
      :item_team_members,
      :bitstreams,
      :metadata_extras
    ])
  end

  def list_items(%{} = filters) do
    query = from i in Item, order_by: [desc: i.inserted_at]

    query =
      case Map.get(filters, :status) do
        nil -> query
        status -> from i in query, where: i.status == ^status
      end

    Repo.all(query)
  end

  @doc """
  Returns aggregate counts used by the admin dashboard, in a single query pass.
  Returns a map with keys: `:communities`, `:collections`, `:items_total`,
  `:items_draft`, `:items_submitted`, `:items_published`, `:items_embargoed`,
  `:items_withdrawn`.
  """
  def dashboard_stats do
    item_counts =
      Repo.all(
        from i in Item,
          group_by: i.status,
          select: {i.status, count(i.id)}
      )
      |> Map.new()

    %{
      communities: Repo.aggregate(Community, :count, :id),
      collections: Repo.aggregate(Collection, :count, :id),
      items_total: item_counts |> Map.values() |> Enum.sum(),
      items_draft: Map.get(item_counts, :draft, 0),
      items_submitted: Map.get(item_counts, :submitted, 0),
      items_published: Map.get(item_counts, :published, 0),
      items_embargoed: Map.get(item_counts, :embargoed, 0),
      items_withdrawn: Map.get(item_counts, :withdrawn, 0)
    }
  end

  @doc """
  Returns up to `limit` submitted items, oldest first (most urgent for review),
  with the submitter association preloaded.
  """
  def list_pending_items(limit \\ 5) do
    Repo.all(
      from i in Item,
        where: i.status == :submitted,
        order_by: [asc: i.inserted_at],
        limit: ^limit,
        preload: :submitter
    )
  end

  @doc """
  Returns up to `limit` most recently published items.
  """
  def list_recent_published(limit \\ 5) do
    Repo.all(
      from i in Item,
        where: i.status == :published,
        order_by: [desc: i.published_at],
        limit: ^limit
    )
  end

  def list_published_items(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    offset = (page - 1) * per_page

    Repo.all(
      from i in Item,
        where: i.status == :published and i.discoverable == true,
        order_by: [desc: i.published_at],
        limit: ^per_page,
        offset: ^offset
    )
  end

  def list_items_for_collection(collection_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    offset = (page - 1) * per_page

    Repo.all(
      from i in Item,
        where:
          i.collection_id == ^collection_id and
            i.status == :published and
            i.discoverable == true,
        order_by: [desc: i.published_at],
        limit: ^per_page,
        offset: ^offset
    )
  end

  def list_items_by_submitter(user_id) do
    Repo.all(
      from i in Item,
        where: i.submitter_id == ^user_id,
        order_by: [desc: i.inserted_at]
    )
  end

  def count_items_for_collection(collection_id) do
    Repo.one(
      from i in Item,
        where: i.collection_id == ^collection_id and i.status == :published,
        select: count(i.id)
    )
  end

  @doc """
  Full-text and filtered search over published, discoverable items.
  Accepted params: `:term`, `:department`, `:faculty`, `:year`, `:item_type`,
  `:collection_id`, `:page`, `:per_page`.
  """
  def search_items(%{} = params) do
    term = Map.get(params, :term)
    department = Map.get(params, :department)
    faculty = Map.get(params, :faculty)
    year = Map.get(params, :year)
    item_type = Map.get(params, :item_type)
    collection_id = Map.get(params, :collection_id)
    page = Map.get(params, :page, 1)
    per_page = Map.get(params, :per_page, 20)
    offset = (page - 1) * per_page

    from(i in Item,
      where: i.status == :published and i.discoverable == true
    )
    |> maybe_full_text_filter(term)
    |> maybe_filter(:department, department)
    |> maybe_filter(:faculty, faculty)
    |> maybe_filter(:publication_year, year)
    |> maybe_filter(:item_type, item_type)
    |> maybe_filter(:collection_id, collection_id)
    |> order_by([i], desc: i.published_at)
    |> limit(^per_page)
    |> offset(^offset)
    |> Repo.all()
  end

  defp maybe_full_text_filter(query, nil), do: query

  defp maybe_full_text_filter(query, term) do
    from i in query,
      where:
        fragment(
          """
          to_tsvector('indonesian', coalesce(?, '') || ' ' || coalesce(?, ''))
          @@ plainto_tsquery('indonesian', ?)
          """,
          i.title,
          i.abstract,
          ^term
        )
  end

  defp maybe_filter(query, _field, nil), do: query

  defp maybe_filter(query, field, value) do
    from i in query, where: field(i, ^field) == ^value
  end

  def create_item(attrs) do
    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert()
  end

  def update_item(%Item{} = item, attrs) do
    item
    |> Item.changeset(attrs)
    |> Repo.update()
  end

  def publish_item(%Item{} = item) do
    item
    |> Ecto.Changeset.change(
      status: :published,
      published_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second),
      discoverable: true
    )
    |> Repo.update()
  end

  def lift_embargo(%Item{} = item) do
    item
    |> Ecto.Changeset.change(status: :published, embargo_open_date: nil)
    |> Repo.update()
  end

  # ── Review workflow FSM ──────────────────────────────────────────────────────

  @doc "Submitter moves a draft item to :submitted."
  def submit_item(%Item{status: :draft} = item) do
    item
    |> Item.status_changeset(%{status: :submitted, submitted_at: DateTime.utc_now()})
    |> Repo.update()
    |> tap_notify(:submitted)
  end

  def submit_item(%Item{}), do: {:error, :invalid_transition}

  @doc "A reviewer picks up the submission and begins review."
  def start_review(%Item{status: :submitted} = item, reviewer) do
    item
    |> Item.review_changeset(%{
      status: :under_review,
      reviewed_by_id: reviewer.id,
      reviewed_at: DateTime.utc_now()
    })
    |> Repo.update()
    |> tap_notify(:review_started)
  end

  def start_review(%Item{}, _), do: {:error, :invalid_transition}

  @doc "Admin approves and publishes the item."
  def approve_item(%Item{status: :under_review} = item, reviewer) do
    item
    |> Item.review_changeset(%{
      status: :published,
      discoverable: true,
      reviewed_by_id: reviewer.id,
      reviewed_at: DateTime.utc_now(),
      review_note: nil
    })
    |> Repo.update()
    |> tap_notify(:approved)
  end

  def approve_item(%Item{}, _), do: {:error, :invalid_transition}

  @doc "Reviewer/Admin requests revisions. Returns item to :submitted."
  def request_revision(%Item{status: :under_review} = item, reviewer, note) do
    item
    |> Item.review_changeset(%{
      status: :submitted,
      reviewed_by_id: reviewer.id,
      reviewed_at: DateTime.utc_now(),
      review_note: note
    })
    |> Repo.update()
    |> tap_notify(:revision_requested)
  end

  def request_revision(%Item{}, _, _), do: {:error, :invalid_transition}

  @doc "Admin rejects the item outright."
  def reject_item(%Item{status: :under_review} = item, reviewer, note) do
    item
    |> Item.review_changeset(%{
      status: :withdrawn,
      discoverable: false,
      reviewed_by_id: reviewer.id,
      reviewed_at: DateTime.utc_now(),
      review_note: note
    })
    |> Repo.update()
    |> tap_notify(:rejected)
  end

  def reject_item(%Item{}, _, _), do: {:error, :invalid_transition}

  @doc "Withdraws an item — allowed from :submitted, :under_review, or :published."
  def withdraw_item_fsm(%Item{status: status} = item)
      when status in [:submitted, :under_review, :published] do
    item
    |> Item.status_changeset(%{status: :withdrawn, discoverable: false})
    |> Repo.update()
    |> tap_notify(:withdrawn)
  end

  def withdraw_item_fsm(%Item{}), do: {:error, :invalid_transition}

  defp tap_notify({:ok, item} = result, event) do
    %{item_id: item.id, event: to_string(event)}
    |> Kiroku.Workers.ReviewNotifier.new()
    |> Oban.insert()

    result
  end

  defp tap_notify(error, _event), do: error

  def delete_item(%Item{} = item), do: Repo.delete(item)

  # ── Import (mix kiroku.import_from_mssql only) ──────────────────────────────

  @doc """
  Upserts an item from the MSSQL import. Uses legacy_id as the conflict target;
  on conflict it replaces all fields except id and inserted_at.
  """
  def import_item(attrs) do
    %Item{}
    |> Item.import_changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: :legacy_id
    )
  end

  # ── Keywords ────────────────────────────────────────────────────────────────

  def upsert_keywords_for_item(item_id, keywords) when is_list(keywords) do
    Repo.delete_all(from k in ItemKeyword, where: k.item_id == ^item_id)

    keywords
    |> Enum.with_index(0)
    |> Enum.map(fn {attrs, idx} ->
      %ItemKeyword{}
      |> ItemKeyword.changeset(Map.merge(attrs, %{item_id: item_id, position: idx}))
      |> Repo.insert()
    end)
  end

  # ── Advisors, Authors, Examiners, Team Members ───────────────────────────────

  def create_item_author(attrs) do
    %ItemAuthor{}
    |> ItemAuthor.changeset(attrs)
    |> Repo.insert()
  end

  def create_item_advisor(attrs) do
    %ItemAdvisor{}
    |> ItemAdvisor.changeset(attrs)
    |> Repo.insert()
  end

  def create_item_examiner(attrs) do
    %ItemExaminer{}
    |> ItemExaminer.changeset(attrs)
    |> Repo.insert()
  end

  def create_item_team_member(attrs) do
    %ItemTeamMember{}
    |> ItemTeamMember.changeset(attrs)
    |> Repo.insert()
  end

  # ── Supplementary Metadata ──────────────────────────────────────────────────

  def put_metadata(item_id, field_schema, field_element, qualifier \\ nil, value, opts \\ []) do
    attrs = %{
      item_id: item_id,
      field_schema: field_schema,
      field_element: field_element,
      field_qualifier: qualifier,
      field_value: value,
      language: Keyword.get(opts, :language),
      position: Keyword.get(opts, :position, 0)
    }

    %ItemMetadata{}
    |> ItemMetadata.changeset(attrs)
    |> Repo.insert()
  end

  def list_metadata_for_item(item_id) do
    Repo.all(from m in ItemMetadata, where: m.item_id == ^item_id, order_by: m.position)
  end
end

defmodule Kiroku.Repository do
  @moduledoc """
  Context module for Community, Collection, Item, and all item-child schemas.
  All authorization checks happen in the caller (LiveView / controller) before
  calling any function here.
  """

  import Ecto.Query
  alias Kiroku.Repo
  alias Kiroku.Pagination
  alias Kiroku.Access.Authorization

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

  @item_preloads [
    :submitter,
    :item_keywords,
    :item_authors,
    :item_advisors,
    :item_examiners,
    :item_team_members,
    {:bitstreams, from(b in Kiroku.Content.Bitstream, order_by: [b.bundle_name, b.sequence])},
    :metadata_extras,
    :collection
  ]

  # Fields needed for card/list displays. Using select: with this list avoids
  # transferring 100+ columns (including massive abstracts) from the DB.
  @item_display_fields [
    :id,
    :handle,
    :legacy_id,
    :title,
    :abstract,
    :item_type,
    :faculty,
    :program_study,
    :department,
    :student_id,
    :student_name,
    :status,
    :access_level,
    :publication_year,
    :date_submitted,
    :date_issued,
    :published_at,
    :inserted_at,
    :collection_id,
    :submitter_id
  ]

  # ── Communities ─────────────────────────────────────────────────────────────

  def list_communities(opts \\ []) do
    scope = Keyword.get(opts, :scope, :public)
    levels = Authorization.visible_access_levels(scope)

    Repo.all(
      from c in Community,
        where: c.is_active == true and c.access_level in ^levels,
        order_by: c.position
    )
  end

  @doc """
  Returns top-level (root) communities — those without a parent.

  Accepts a `:scope` opt (default `:public`) to restrict by access level.
  """
  def list_root_communities(opts \\ []) do
    scope = Keyword.get(opts, :scope, :public)
    levels = Authorization.visible_access_levels(scope)

    Repo.all(
      from c in Community,
        where:
          c.is_active == true and is_nil(c.parent_community_id) and
            c.access_level in ^levels,
        order_by: c.position
    )
  end

  @doc """
  Returns the direct subcommunities of a given community.

  Accepts a `:scope` opt (default `:public`) to restrict by access level.
  """
  def list_subcommunities(community_id, opts \\ []) do
    scope = Keyword.get(opts, :scope, :public)
    levels = Authorization.visible_access_levels(scope)

    Repo.all(
      from c in Community,
        where:
          c.parent_community_id == ^community_id and c.is_active == true and
            c.access_level in ^levels,
        order_by: c.position
    )
  end

  @doc """
  Returns all active communities as a flat list annotated with a virtual
  `depth` field, ordered in hierarchy traversal order (parents before
  children). Used by the admin UI to render a tree with indentation.
  """
  def list_communities_tree(opts \\ []) do
    scope = Keyword.get(opts, :scope, :public)
    levels = Authorization.visible_access_levels(scope)

    communities =
      Repo.all(
        from c in Community,
          where: c.is_active == true and c.access_level in ^levels,
          order_by: c.position
      )

    build_community_tree(communities, nil, 0)
  end

  @doc """
  Paginated version of `list_communities_tree/1`.
  Returns `{communities, %Pagination{}}` as a flat paginated list of active
  communities (not a nested tree), ordered by position.

  Accepts a `:scope` opt (default `:public`).
  """
  def list_communities_tree_pagination(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    scope = Keyword.get(opts, :scope, :public)
    levels = Authorization.visible_access_levels(scope)

    count =
      Repo.one(
        from c in Community,
          where: c.is_active == true and c.access_level in ^levels,
          select: count(c.id)
      )

    pagination = Pagination.build(count, page, per_page)

    communities =
      Repo.all(
        from c in Community,
          where: c.is_active == true and c.access_level in ^levels,
          order_by: c.position,
          limit: ^per_page,
          offset: ^Pagination.offset(pagination)
      )

    {communities, pagination}
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

  Always shows all access levels (admin-only selection aid).
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

  The subcommunities preload respects `:scope` (default `:public`) so that a
  viewer only sees child communities they may access.
  """
  def get_community_with_relations!(id, opts \\ []) do
    scope = Keyword.get(opts, :scope, :public)
    levels = Authorization.visible_access_levels(scope)

    ordered_subq =
      from(c in Community,
        where: c.is_active == true and c.access_level in ^levels,
        order_by: c.position
      )

    Repo.get!(Community, id)
    |> Repo.preload(parent_community: :parent_community, subcommunities: ordered_subq)
  end

  @doc """
  Fetches a community by handle with its parent and subcommunities preloaded.

  The subcommunities preload respects `:scope` (default `:public`).
  """
  def get_community_with_relations_by_handle!(handle, opts \\ []) do
    scope = Keyword.get(opts, :scope, :public)
    levels = Authorization.visible_access_levels(scope)

    ordered_subq =
      from(c in Community,
        where: c.is_active == true and c.access_level in ^levels,
        order_by: c.position
      )

    Repo.get_by!(Community, handle: handle)
    |> Repo.preload(subcommunities: ordered_subq)
  end

  def get_community!(id), do: Repo.get!(Community, id)

  def get_community(id), do: Repo.get(Community, id)

  def get_community_by_handle!(handle), do: Repo.get_by!(Community, handle: handle)

  def get_community_by_handle(handle), do: Repo.get_by(Community, handle: handle)

  @doc """
  Returns the full ancestor chain of a community as a list of maps,
  ordered from root → … → current. Supports arbitrary hierarchy depth
  via a recursive CTE — no Ecto preload depth limit.

      [%{id: ..., name: "Root",   handle: "unpad-ta"},
       %{id: ..., name: "Fakultas", handle: "fakultas-hukum"},
       %{id: ..., name: "Sarjana",  handle: "hukum-s1"}]
  """
  def community_ancestor_chain(community_id) do
    {:ok, uuid} = Ecto.UUID.dump(community_id)

    {:ok, %{rows: rows}} =
      Repo.query(
        """
        WITH RECURSIVE ancestors AS (
          SELECT id, name, handle, parent_community_id, 0 AS depth
          FROM communities
          WHERE id = $1
          UNION ALL
          SELECT c.id, c.name, c.handle, c.parent_community_id, a.depth + 1
          FROM communities c
          JOIN ancestors a ON c.id = a.parent_community_id
        )
        SELECT id, name, handle FROM ancestors ORDER BY depth DESC
        """,
        [uuid]
      )

    Enum.map(rows, fn [id, name, handle] -> %{id: id, name: name, handle: handle} end)
  end

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

  def list_collections(opts \\ []) do
    scope = Keyword.get(opts, :scope, :public)
    levels = Authorization.visible_access_levels(scope)

    Repo.all(
      from c in Collection,
        where: c.access_level in ^levels,
        order_by: c.name
    )
  end

  @doc """
  Paginated version of `list_collections/1`.
  Returns `{collections, %Pagination{}}`.

  Accepts a `:scope` opt (default `:public`).
  """
  def list_collections_pagination(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    scope = Keyword.get(opts, :scope, :public)
    levels = Authorization.visible_access_levels(scope)

    count =
      Repo.one(
        from c in Collection,
          where: c.access_level in ^levels,
          select: count(c.id)
      )

    pagination = Pagination.build(count, page, per_page)

    collections =
      Repo.all(
        from c in Collection,
          where: c.access_level in ^levels,
          order_by: c.name,
          limit: ^per_page,
          offset: ^Pagination.offset(pagination)
      )

    {collections, pagination}
  end

  @doc """
  Returns all active collections in a single query (avoids N+1 when paired
  with communities). Use `Enum.group_by(&1.community_id)` to associate them.

  Not scope-filtered — used for submission dropdowns behind authentication.
  """
  def list_active_collections do
    Repo.all(
      from c in Collection,
        where: c.is_active == true,
        order_by: c.position
    )
  end

  @doc """
  Returns all active communities with their active collections preloaded in
  exactly two queries (regardless of community count).

  Both levels respect `:scope` (default `:public`) — internal/restricted
  communities and collections are hidden from anonymous viewers.
  """
  def list_communities_with_collections(opts \\ []) do
    communities = list_communities(opts)
    levels = Authorization.visible_access_levels(Keyword.get(opts, :scope, :public))

    collections =
      Repo.all(
        from c in Collection,
          where:
            c.is_active == true and
              c.access_level in ^levels and
              c.community_id in ^Enum.map(communities, & &1.id),
          order_by: c.position
      )

    grouped = Enum.group_by(collections, & &1.community_id)

    Enum.map(communities, fn community ->
      Map.put(community, :collections, Map.get(grouped, community.id, []))
    end)
  end

  @doc """
  Returns active collections belonging to `community_id`.

  Accepts a `:scope` opt (default `:public`).
  """
  def list_collections_for_community(community_id, opts \\ []) do
    scope = Keyword.get(opts, :scope, :public)
    levels = Authorization.visible_access_levels(scope)

    Repo.all(
      from c in Collection,
        where:
          c.community_id == ^community_id and c.is_active == true and
            c.access_level in ^levels,
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

  def get_item!(id_or_handle) do
    case Ecto.UUID.cast(id_or_handle) do
      {:ok, _} -> Repo.get!(Item, id_or_handle)
      :error -> Repo.get_by!(Item, handle: id_or_handle)
    end
  end

  def get_item(id_or_handle) do
    case Ecto.UUID.cast(id_or_handle) do
      {:ok, _} -> Repo.get(Item, id_or_handle)
      :error -> Repo.get_by(Item, handle: id_or_handle)
    end
  end

  def get_item_by_handle!(handle), do: Repo.get_by!(Item, handle: handle)

  def get_item_by_handle(handle), do: Repo.get_by(Item, handle: handle)

  def get_item_with_preloads!(id_or_handle) do
    item =
      case Ecto.UUID.cast(id_or_handle) do
        {:ok, _} -> Repo.get!(Item, id_or_handle)
        :error -> Repo.get_by!(Item, handle: id_or_handle)
      end

    Repo.preload(item, @item_preloads)
  end

  def get_item_with_preloads(id_or_handle) do
    item =
      case Ecto.UUID.cast(id_or_handle) do
        {:ok, _} -> Repo.get(Item, id_or_handle)
        :error -> Repo.get_by(Item, handle: id_or_handle)
      end

    if item, do: Repo.preload(item, @item_preloads)
  end

  def list_items(%{} = filters) do
    query = from i in Item, order_by: [desc: i.inserted_at]

    query =
      case Map.get(filters, :status) do
        nil -> query
        status -> from i in query, where: i.status == ^status
      end

    query =
      case Map.get(filters, :item_type) do
        nil -> query
        item_type -> from i in query, where: i.item_type == ^item_type
      end

    query =
      case Map.get(filters, :search) do
        nil ->
          query

        "" ->
          query

        search ->
          search_term = "%#{search}%"

          from i in query,
            where:
              ilike(i.title, ^search_term) or
                ilike(i.handle, ^search_term) or
                ilike(i.student_name, ^search_term)
      end

    Repo.all(query)
  end

  @doc """
  Lightweight version of `list_items/1` that selects only the fields needed
  for card/list displays. Avoids transferring large text columns (abstracts,
  type-specific fields) from the database.
  """
  def list_items_for_display(%{} = filters) do
    filters
    |> items_for_display_query()
    |> Repo.all()
  end

  @doc """
  Paginated version of `list_items_for_display/1`.

  Returns `{items, %Pagination{}}`. The same filters map is accepted; page
  and per_page are read from the keyword opts.

  ## Options

    * `:page` — page number (default 1)
    * `:per_page` — items per page (default 20)

  ## Example

      {items, pagination} =
        Repository.list_items_for_display_pagination(
          %{status: :submitted, search: "thesis"},
          page: 2, per_page: 15
        )
  """
  def list_items_for_display_pagination(%{} = filters, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    count =
      filters
      |> items_for_display_query()
      |> Repo.aggregate(:count, :id)

    pagination = Pagination.build(count, page, per_page)

    items =
      filters
      |> items_for_display_query()
      |> limit(^per_page)
      |> offset(^Pagination.offset(pagination))
      |> Repo.all()

    {items, pagination}
  end

  defp items_for_display_query(%{} = filters) do
    query =
      from i in Item,
        select: ^@item_display_fields,
        order_by: [desc: i.inserted_at]

    query =
      case Map.get(filters, :status) do
        nil -> query
        status -> from i in query, where: i.status == ^status
      end

    query =
      case Map.get(filters, :item_type) do
        nil -> query
        item_type -> from i in query, where: i.item_type == ^item_type
      end

    case Map.get(filters, :search) do
      nil ->
        query

      "" ->
        query

      search ->
        search_term = "%#{search}%"

        from i in query,
          where:
            ilike(i.title, ^search_term) or
              ilike(i.handle, ^search_term) or
              ilike(i.student_name, ^search_term)
    end
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
        select: ^@item_display_fields,
        preload: :submitter
    )
  end

  @doc """
  Returns up to `limit` most recently published items.

  Accepts `:limit` (default 5) and `:scope` (default `:public`) opts.
  """
  def list_recent_published(opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    scope = Keyword.get(opts, :scope, :public)
    levels = Authorization.visible_access_levels(scope)

    Repo.all(
      from i in Item,
        where:
          i.status == :published and
            i.access_level in ^levels,
        order_by: [desc: i.published_at],
        limit: ^limit,
        select: ^@item_display_fields
    )
  end

  def list_published_items(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    scope = Keyword.get(opts, :scope, :public)
    offset = (page - 1) * per_page
    levels = Authorization.visible_access_levels(scope)

    Repo.all(
      from i in Item,
        where:
          i.status == :published and
            i.discoverable == true and
            i.access_level in ^levels,
        order_by: [desc: i.published_at],
        limit: ^per_page,
        offset: ^offset,
        select: ^@item_display_fields
    )
  end

  @doc """
  Paginated version of `list_published_items/1`.
  Returns `{items, %Pagination{}}`.

  Accepts a `:scope` opt (`:public` | `:internal` | `:staff`, default `:public`)
  to restrict results to the access levels the viewer may see.
  """
  def list_published_items_pagination(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    scope = Keyword.get(opts, :scope, :public)
    levels = Authorization.visible_access_levels(scope)

    count =
      Repo.one(
        from i in Item,
          where:
            i.status == :published and
              i.discoverable == true and
              i.access_level in ^levels,
          select: count(i.id)
      )

    pagination = Pagination.build(count, page, per_page)

    items =
      Repo.all(
        from i in Item,
          where:
            i.status == :published and
              i.discoverable == true and
              i.access_level in ^levels,
          order_by: [desc: i.published_at],
          limit: ^per_page,
          offset: ^Pagination.offset(pagination),
          select: ^@item_display_fields
      )

    {items, pagination}
  end

  def list_items_for_collection(collection_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    scope = Keyword.get(opts, :scope, :public)
    levels = Authorization.visible_access_levels(scope)
    offset = (page - 1) * per_page

    Repo.all(
      from i in Item,
        where:
          i.collection_id == ^collection_id and
            i.status == :published and
            i.discoverable == true and
            i.access_level in ^levels,
        order_by: [desc: i.published_at],
        limit: ^per_page,
        offset: ^offset,
        select: ^@item_display_fields
    )
  end

  @doc """
  Paginated version of `list_items_for_collection/2`.
  Returns `{items, %Pagination{}}`.

  In addition to `:page` / `:per_page`, accepts filter options:

    * `:term`         — full-text search over title + abstract
    * `:item_type`     — atom exact match (e.g. `:skripsi`)
    * `:year`          — integer exact match on `publication_year`
    * `:faculty`       — string exact match
    * `:department`    — string exact match
    * `:degree_level`  — atom exact match (e.g. `:s1`)
    * `:scope`         — visibility scope (default `:public`)

  """
  def list_items_for_collection_pagination(collection_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    scope = Keyword.get(opts, :scope, :public)
    term = Keyword.get(opts, :term)
    item_type = Keyword.get(opts, :item_type)
    year = Keyword.get(opts, :year)
    faculty = Keyword.get(opts, :faculty)
    department = Keyword.get(opts, :department)
    degree_level = Keyword.get(opts, :degree_level)

    base =
      from(i in Item,
        where:
          i.collection_id == ^collection_id and
            i.status == :published and
            i.discoverable == true
      )
      |> visibility_filter(scope)
      |> maybe_full_text_filter(term)
      |> maybe_filter(:item_type, item_type)
      |> maybe_filter(:publication_year, year)
      |> maybe_filter(:faculty, faculty)
      |> maybe_filter(:department, department)
      |> maybe_filter(:degree_level, degree_level)

    count = Repo.aggregate(base, :count, :id)
    pagination = Pagination.build(count, page, per_page)

    items =
      base
      |> order_by([i], desc: i.published_at)
      |> limit(^per_page)
      |> offset(^Pagination.offset(pagination))
      |> select([i], ^@item_display_fields)
      |> Repo.all()

    {items, pagination}
  end

  @doc """
  Returns the distinct, non-nil values of `field` among published & discoverable
  items in the given collection. Used to populate filter dropdowns.
  """
  def list_distinct_values_for_collection(collection_id, field) do
    Repo.all(
      from i in Item,
        where:
          i.collection_id == ^collection_id and
            i.status == :published and
            i.discoverable == true and
            not is_nil(field(i, ^field)),
        select: field(i, ^field),
        distinct: true,
        order_by: field(i, ^field)
    )
  end

  def list_items_by_submitter(user_id) do
    Repo.all(
      from i in Item,
        where: i.submitter_id == ^user_id,
        order_by: [desc: i.inserted_at],
        select: ^@item_display_fields
    )
  end

  @doc """
  Paginated version of `list_items_by_submitter/1`.
  Returns `{items, %Pagination{}}`.
  """
  def list_items_by_submitter_pagination(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)

    count =
      Repo.one(
        from i in Item,
          where: i.submitter_id == ^user_id,
          select: count(i.id)
      )

    pagination = Pagination.build(count, page, per_page)

    items =
      Repo.all(
        from i in Item,
          where: i.submitter_id == ^user_id,
          order_by: [desc: i.inserted_at],
          limit: ^per_page,
          offset: ^Pagination.offset(pagination),
          select: ^@item_display_fields
      )

    {items, pagination}
  end

  @doc """
  Counts published items in `collection_id` visible to `scope` (default
  `:public`). Keeps the collection header count consistent with the scoped
  item listing beneath it.
  """
  def count_items_for_collection(collection_id, opts \\ []) do
    scope = Keyword.get(opts, :scope, :public)
    levels = Authorization.visible_access_levels(scope)

    Repo.one(
      from i in Item,
        where:
          i.collection_id == ^collection_id and i.status == :published and
            i.access_level in ^levels,
        select: count(i.id)
    )
  end

  @doc """
  Full-text and filtered search over published, discoverable items.
  Accepted params: `:term`, `:department`, `:faculty`, `:year`, `:item_type`,
  `:collection_id`, `:page`, `:per_page`, `:scope`.

  `:scope` (`:public` | `:internal` | `:staff`, default `:public`) restricts
  results to the access levels the viewer may see.
  """
  def search_items(%{} = params) do
    term = Map.get(params, :term)
    department = Map.get(params, :department)
    faculty = Map.get(params, :faculty)
    year = Map.get(params, :year)
    item_type = Map.get(params, :item_type)
    collection_id = Map.get(params, :collection_id)
    scope = Map.get(params, :scope, :public)
    page = Map.get(params, :page, 1)
    per_page = Map.get(params, :per_page, 20)
    offset = (page - 1) * per_page

    from(i in Item,
      where: i.status == :published and i.discoverable == true
    )
    |> visibility_filter(scope)
    |> maybe_full_text_filter(term)
    |> maybe_filter(:department, department)
    |> maybe_filter(:faculty, faculty)
    |> maybe_filter(:publication_year, year)
    |> maybe_filter(:item_type, item_type)
    |> maybe_filter(:collection_id, collection_id)
    |> order_by([i], desc: i.published_at)
    |> limit(^per_page)
    |> offset(^offset)
    |> select([i], ^@item_display_fields)
    |> Repo.all()
  end

  @doc """
  Paginated version of `search_items/1`.
  Returns `{items, %Pagination{}}`. Accepts the same params map as `search_items/1`
  (page and per_page are read from the map).
  """
  def search_items_pagination(%{} = params) do
    term = Map.get(params, :term)
    department = Map.get(params, :department)
    faculty = Map.get(params, :faculty)
    year = Map.get(params, :year)
    item_type = Map.get(params, :item_type)
    collection_id = Map.get(params, :collection_id)
    scope = Map.get(params, :scope, :public)
    page = Map.get(params, :page, 1)
    per_page = Map.get(params, :per_page, 20)

    base =
      from(i in Item,
        where: i.status == :published and i.discoverable == true
      )
      |> visibility_filter(scope)
      |> maybe_full_text_filter(term)
      |> maybe_filter(:department, department)
      |> maybe_filter(:faculty, faculty)
      |> maybe_filter(:publication_year, year)
      |> maybe_filter(:item_type, item_type)
      |> maybe_filter(:collection_id, collection_id)

    count = Repo.aggregate(base, :count, :id)
    pagination = Pagination.build(count, page, per_page)

    items =
      base
      |> order_by([i], desc: i.published_at)
      |> limit(^per_page)
      |> offset(^Pagination.offset(pagination))
      |> select([i], ^@item_display_fields)
      |> Repo.all()

    {items, pagination}
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

  # Restricts an item query to the access levels the given visibility scope may
  # see. Combined with the `status: :published, discoverable: true` predicate
  # this is what enforces the public / internal / private discovery model.
  # See Kiroku.Access.Authorization for scope derivation.
  defp visibility_filter(query, scope) do
    levels = Authorization.visible_access_levels(scope)
    from i in query, where: i.access_level in ^levels
  end

  def create_item(attrs) do
    attrs
    |> maybe_apply_collection_default_access()
    |> then(fn final_attrs ->
      %Item{}
      |> Item.changeset(final_attrs)
      |> Repo.insert()
    end)
  end

  # When the caller does not specify an access_level, inherit the collection's
  # configured default. This lets a "Tugas Akhir" collection default all new
  # submissions to :internal, for example. Explicit access_level values are
  # always preserved.
  defp maybe_apply_collection_default_access(attrs) do
    has_level? = Map.has_key?(attrs, :access_level) or Map.has_key?(attrs, "access_level")

    if has_level? do
      attrs
    else
      collection_id = attrs[:collection_id] || attrs["collection_id"]

      case collection_id && get_collection(collection_id) do
        %Collection{default_item_access_level: level} when not is_nil(level) ->
          # Preserve the key type already present in attrs — Ecto.cast rejects
          # maps that mix atom and string keys.
          Map.put(attrs, access_level_key(attrs), level)

        _ ->
          attrs
      end
    end
  end

  defp access_level_key(attrs) do
    has_string_key? =
      Enum.any?(attrs, fn
        {k, _} when is_binary(k) -> true
        _ -> false
      end)

    if has_string_key?, do: "access_level", else: :access_level
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

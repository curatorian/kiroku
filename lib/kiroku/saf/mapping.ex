defmodule Kiroku.Saf.Mapping do
  @moduledoc """
  Bidirectional mapping between a `Kiroku.Repository.Item` (with its typed
  columns, contributors, keywords, and metadata extras) and the DSpace Simple
  Archive Format metadata values.

  ## Two-file strategy

  Every item is described by two metadata files:

  * `dublin_core.xml` (`dc` schema) — a DSpace-compatible subset. Carries the
    same values as the local file for the curated fields, plus bare
    `dc.contributor.author` / `dc.subject` summaries. A real DSpace can read
    this file alone and get a usable item.

  * `metadata_local.xml` (`local` schema) — the authoritative, lossless
    representation of Kiroku's typed fields (including type-specific columns
    like `legal_subject_matter`, `case_reference`, etc.) and the full
    structured contributor records.

  On import, values from `local.*` are preferred; `dc.*` is only consulted for
    fields not present in `local.*` (i.e. when ingesting a DSpace-authored
    archive that has no `metadata_local.xml`). Unmappable `dc.*` values become
    `ItemMetadata` extras.
  """

  alias Kiroku.Repository.Item

  # ── Curated dc.* scalar mapping (kiroku_field, element, qualifier) ──────────
  # These fields ALSO appear under local.* (authoritative). The dc.* copy is the
  # DSpace-readable representation carrying the same value.
  @dc_scalar [
    {:title, "title", "none"},
    {:title_alt, "title", "alternative"},
    {:language, "language", "iso"},
    {:date_issued, "date", "issued"},
    {:date_available, "date", "available"},
    {:date_submitted, "date", "submitted"},
    {:publisher, "publisher", "none"},
    {:doi, "identifier", "doi"},
    {:issn, "identifier", "issn"},
    {:eissn, "identifier", "eissn"},
    {:isbn, "identifier", "isbn"},
    {:journal_name, "relation", "ispartof"},
    {:conference_name, "relation", "ispartofseries"},
    {:item_type, "type", "none"}
  ]

  # Item scalar fields that are never serialized to local.* (handled elsewhere:
  # associations, timestamps, internal ids, or curated into dc.* only).
  @local_excluded ~w(
    id inserted_at updated_at
    collection_id submitter_id reviewed_by_id
    title title_alt
    handle legacy_id
  )a

  # ── Export: Item → %{dc: [value], local: [value]} ──────────────────────────

  @doc """
  Converts a fully-preloaded item into SAF metadata values, split by schema.

  The item must have `:item_keywords`, `:item_authors`, `:item_advisors`,
  `:item_examiners`, `:item_team_members`, `:bitstreams`, and `:metadata_extras`
  preloaded (use `Repository.get_item_with_preloads!/1`).
  """
  def from_item(%Item{} = item) do
    dc_values =
      dc_scalar_values(item) ++
        dc_abstract_values(item) ++
        dc_contributor_values(item) ++
        dc_keyword_values(item) ++
        dc_extras_values(item, "dc")

    local_values =
      local_scalar_values(item) ++
        local_abstract_alt_value(item) ++
        local_contributor_values(item) ++
        local_extras_values(item)

    %{dc: Enum.reject(dc_values, &is_nil/1), local: Enum.reject(local_values, &is_nil/1)}
  end

  defp dc_scalar_values(item) do
    Enum.flat_map(@dc_scalar, fn {field, element, qualifier} ->
      case field_value(item, field) do
        nil ->
          []

        value ->
          [%{element: element, qualifier: qualifier, language: nil, value: to_string(value)}]
      end
    end)
  end

  # The abstract goes to dc.description.abstract; a second language variant is
  # emitted with language="en" when an English abstract exists.
  defp dc_abstract_values(item) do
    main =
      unless blank?(item.abstract) do
        %{element: "description", qualifier: "abstract", language: nil, value: item.abstract}
      end

    alt =
      unless blank?(item.abstract_alt) do
        %{element: "description", qualifier: "abstract", language: "en", value: item.abstract_alt}
      end

    [main, alt]
  end

  defp dc_contributor_values(item) do
    authors =
      (author_names(item) ++ bare_student(item))
      |> Enum.map(&%{element: "contributor", qualifier: "author", language: nil, value: &1})

    advisors =
      (item.item_advisors || [])
      |> Enum.map(& &1.advisor_name)
      |> Enum.reject(&blank?/1)
      |> Enum.map(&%{element: "contributor", qualifier: "advisor", language: nil, value: &1})

    authors ++ advisors
  end

  defp author_names(item), do: Enum.map(item.item_authors || [], & &1.author_name)

  defp bare_student(%Item{student_name: nil}), do: []
  defp bare_student(%Item{student_name: ""}), do: []
  defp bare_student(%Item{student_name: name}), do: [name]

  defp dc_keyword_values(item) do
    Enum.map(item.item_keywords || [], fn kw ->
      %{
        element: "subject",
        qualifier: "none",
        language: kw.language && to_string(kw.language),
        value: kw.keyword
      }
    end)
  end

  # Round-trip existing metadata_extras into their declared schema file.
  defp dc_extras_values(item, "dc") do
    Enum.map(extras_for_schema(item, "dc"), fn m ->
      %{
        element: m.field_element,
        qualifier: m.field_qualifier || "none",
        language: m.language,
        value: m.field_value
      }
    end)
  end

  defp local_extras_values(item) do
    (extras_for_schema(item, "local") ++
       extras_for_schema(item, nil))
    |> Enum.map(fn m ->
      %{
        element: m.field_element,
        qualifier: m.field_qualifier || "none",
        language: m.language,
        value: m.field_value
      }
    end)
  end

  defp extras_for_schema(item, schema) do
    Enum.filter(item.metadata_extras || [], &(&1.field_schema == schema))
  end

  # All typed scalar fields not in the exclusion list → local.{field}.none
  defp local_scalar_values(item) do
    Item.__schema__(:fields)
    |> Enum.reject(&(&1 in @local_excluded))
    |> Enum.flat_map(fn field ->
      case field_value(item, field) do
        nil ->
          []

        value ->
          [
            %{
              element: Atom.to_string(field),
              qualifier: "none",
              language: nil,
              value: to_string(value)
            }
          ]
      end
    end)
  end

  # abstract_alt also lives in local for authoritative round-trip.
  defp local_abstract_alt_value(item) do
    unless blank?(item.abstract_alt) do
      [%{element: "abstract_alt", qualifier: "none", language: "en", value: item.abstract_alt}]
    end
  end

  # Full structured contributor records under local.contributor.{role}.{seq}.{sub}
  defp local_contributor_values(item) do
    author_vals =
      (item.item_authors || [])
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {a, seq} ->
        [
          local_contributor("author", seq, "name", a.author_name),
          local_contributor("author", seq, "name_alt", a.author_name_alt),
          local_contributor("author", seq, "affiliation", a.affiliation),
          local_contributor("author", seq, "email", a.email),
          local_contributor("author", seq, "orcid", a.orcid),
          local_contributor("author", seq, "scopus_author_id", a.scopus_author_id)
        ]
      end)

    advisor_vals =
      (item.item_advisors || [])
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {a, seq} ->
        [
          local_contributor("advisor", seq, "name", a.advisor_name),
          local_contributor("advisor", seq, "name_alt", a.advisor_name_alt),
          local_contributor("advisor", seq, "role", a.advisor_role && to_string(a.advisor_role)),
          local_contributor("advisor", seq, "affiliation", a.affiliation),
          local_contributor("advisor", seq, "nidn", a.nidn)
        ]
      end)

    examiner_vals =
      (item.item_examiners || [])
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {e, seq} ->
        [
          local_contributor("examiner", seq, "name", e.examiner_name),
          local_contributor("examiner", seq, "name_alt", e.examiner_name_alt),
          local_contributor("examiner", seq, "affiliation", e.affiliation),
          local_contributor("examiner", seq, "nidn", e.nidn)
        ]
      end)

    team_vals =
      (item.item_team_members || [])
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {m, seq} ->
        [
          local_contributor("team", seq, "name", m.member_name),
          local_contributor("team", seq, "name_alt", m.member_name_alt),
          local_contributor("team", seq, "role", m.role && to_string(m.role)),
          local_contributor("team", seq, "student_id", m.student_id),
          local_contributor("team", seq, "affiliation", m.affiliation)
        ]
      end)

    Enum.reject(author_vals ++ advisor_vals ++ examiner_vals ++ team_vals, &is_nil/1)
  end

  defp local_contributor(_role, _seq, _sub, nil), do: nil

  defp local_contributor(role, seq, sub, value) do
    %{
      element: "contributor",
      qualifier: "#{role}.#{seq}.#{sub}",
      language: nil,
      value: to_string(value)
    }
  end

  # ── Import: values → item shape ────────────────────────────────────────────

  @doc """
  Reconstructs an "item shape" from parsed SAF metadata values.

  `local_values` is authoritative when present (Kiroku archives); `dc_values`
  is the fallback for DSpace-authored archives. Returns:

      %{
        attrs: %{atom => value},           # typed Item column values
        authors: [%{...}], advisors: [...], examiners: [...], team_members: [...],
        keywords: [%{...}],
        extras: [%{field_schema, field_element, field_qualifier, field_value, language}]
      }

  """
  def to_item_shape(dc_values, local_values) do
    local_attrs = local_values_to_attrs(local_values)
    dc_attrs = dc_values_to_attrs(dc_values)

    # local wins; dc fills gaps for fields local didn't provide.
    attrs = Map.merge(dc_attrs, local_attrs)

    {local_contributors, local_have?} = local_values_to_contributors(local_values)

    contributors =
      if local_have? do
        local_contributors
      else
        dc_values_to_contributors(dc_values)
      end

    keywords =
      case local_values_to_keywords(local_values) do
        [] -> dc_values_to_keywords(dc_values)
        kws -> kws
      end

    extras = unmapped_extras(dc_values, attrs)

    %{
      attrs: attrs,
      authors: contributors.authors,
      advisors: contributors.advisors,
      examiners: contributors.examiners,
      team_members: contributors.team_members,
      keywords: keywords,
      extras: extras
    }
  end

  # local.{field}.none → attrs[field]. Ecto.Enum/:integer/:boolean/:date all
  # cast from strings via the changeset, so we pass strings through unchanged
  # except for date fields which need full ISO form.
  defp local_values_to_attrs(values) do
    values
    |> Enum.filter(fn v ->
      v.element != "contributor" and v.element != "subject" and v.element != "abstract_alt"
    end)
    |> Enum.filter(fn v -> String.contains?(v.qualifier || "", ".") == false end)
    |> Enum.reduce(%{}, fn v, acc ->
      key = String.to_atom(v.element)
      Map.put(acc, key, coerce_local_value(key, v.value))
    end)
  end

  # Coerce dates from possibly-partial forms; leave everything else as a string
  # so the changeset's cast can do the right thing per column type.
  defp coerce_local_value(field, value) do
    cond do
      date_field?(field) -> normalize_date(value)
      true -> value
    end
  end

  @date_fields ~w(date_submitted date_issued date_available embargo_open_date embargo_close_date exhibition_date)a
  defp date_field?(field), do: field in @date_fields

  defp normalize_date(""), do: nil
  defp normalize_date(nil), do: nil

  defp normalize_date(value) do
    cond do
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, value) -> value
      Regex.match?(~r/^\d{4}-\d{2}$/, value) -> value <> "-01"
      Regex.match?(~r/^\d{4}$/, value) -> value <> "-01-01"
      true -> value
    end
  end

  # dc.* scalar mapping (reverse) — only fills fields not already set by local.
  defp dc_values_to_attrs(values) do
    Enum.reduce(values, %{}, fn v, acc ->
      case dc_to_field(v) do
        nil -> acc
        field -> Map.put_new(acc, field, dc_coerce(field, v.value, v.language))
      end
    end)
  end

  defp dc_to_field(%{element: "title", qualifier: "none"}), do: :title
  defp dc_to_field(%{element: "title", qualifier: "alternative"}), do: :title_alt

  defp dc_to_field(%{element: "description", qualifier: "abstract", language: nil}),
    do: :abstract

  defp dc_to_field(%{element: "description", qualifier: "abstract", language: "en"}),
    do: :abstract_alt

  defp dc_to_field(%{element: "language", qualifier: "iso"}), do: :language
  defp dc_to_field(%{element: "date", qualifier: "issued"}), do: :date_issued
  defp dc_to_field(%{element: "date", qualifier: "available"}), do: :date_available
  defp dc_to_field(%{element: "date", qualifier: "submitted"}), do: :date_submitted
  defp dc_to_field(%{element: "publisher", qualifier: "none"}), do: :publisher
  defp dc_to_field(%{element: "identifier", qualifier: "doi"}), do: :doi
  defp dc_to_field(%{element: "identifier", qualifier: "issn"}), do: :issn
  defp dc_to_field(%{element: "identifier", qualifier: "eissn"}), do: :eissn
  defp dc_to_field(%{element: "identifier", qualifier: "isbn"}), do: :isbn
  defp dc_to_field(%{element: "relation", qualifier: "ispartof"}), do: :journal_name

  defp dc_to_field(%{element: "relation", qualifier: "ispartofseries"}),
    do: :conference_name

  defp dc_to_field(%{element: "type", qualifier: "none"}), do: :item_type
  defp dc_to_field(_), do: nil

  defp dc_coerce(field, value, _) when field in @date_fields, do: normalize_date(value)
  defp dc_coerce(_, value, _), do: value

  # ── Contributors (import) ──────────────────────────────────────────────────

  defp local_values_to_contributors(values) do
    # Group structured local.contributor.{role}.{seq}.{sub} values by {role, seq},
    # then build one record per (role, seq) and order by seq within each role.
    grouped =
      values
      |> Enum.filter(fn v ->
        v.element == "contributor" and String.contains?(v.qualifier || "", ".")
      end)
      |> Enum.group_by(fn v ->
        [role, seq_str | _] = String.split(v.qualifier, ".")
        {role, String.to_integer(seq_str)}
      end)

    have? = map_size(grouped) > 0

    by_role =
      grouped
      |> Enum.map(fn {{role, _seq} = key, vs} ->
        {key, build_contributor_from_values(role, vs)}
      end)
      |> Enum.group_by(fn {{role, _}, _} -> role end, fn {{_, seq}, rec} -> {seq, rec} end)
      |> Enum.into(%{}, fn {role, seq_records} ->
        ordered =
          seq_records
          |> Enum.sort_by(fn {seq, _} -> seq end)
          |> Enum.with_index(1)
          |> Enum.map(fn {{_orig_seq, rec}, idx} -> Map.put(rec, :sequence, idx) end)

        {role, ordered}
      end)

    result = %{
      authors: Map.get(by_role, "author", []),
      advisors: Map.get(by_role, "advisor", []),
      examiners: Map.get(by_role, "examiner", []),
      team_members: Map.get(by_role, "team", [])
    }

    {result, have?}
  end

  defp build_contributor_from_values("author", vals),
    do: contributor_record(:author, vals)

  defp build_contributor_from_values("advisor", vals),
    do: contributor_record(:advisor, vals)

  defp build_contributor_from_values("examiner", vals),
    do: contributor_record(:examiner, vals)

  defp build_contributor_from_values("team", vals),
    do: contributor_record(:team, vals)

  defp contributor_record(:author, vals) do
    map = value_map(vals)

    %{
      author_name: map["name"],
      author_name_alt: map["name_alt"],
      affiliation: map["affiliation"],
      email: map["email"],
      orcid: map["orcid"],
      scopus_author_id: map["scopus_author_id"]
    }
  end

  defp contributor_record(:advisor, vals) do
    map = value_map(vals)

    %{
      advisor_name: map["name"],
      advisor_name_alt: map["name_alt"],
      advisor_role: map["role"],
      affiliation: map["affiliation"],
      nidn: map["nidn"]
    }
  end

  defp contributor_record(:examiner, vals) do
    map = value_map(vals)

    %{
      examiner_name: map["name"],
      examiner_name_alt: map["name_alt"],
      affiliation: map["affiliation"],
      nidn: map["nidn"]
    }
  end

  defp contributor_record(:team, vals) do
    map = value_map(vals)

    %{
      member_name: map["name"],
      member_name_alt: map["name_alt"],
      role: map["role"],
      student_id: map["student_id"],
      affiliation: map["affiliation"]
    }
  end

  defp value_map(vals) do
    # vals are maps with qualifier "role.seq.sub"; pick out the sub.
    Enum.into(vals, %{}, fn v ->
      sub = v.qualifier |> String.split(".") |> List.last()
      {sub, v.value}
    end)
  end

  # DSpace-authored archives: bare dc.contributor.author / .advisor names only.
  defp dc_values_to_contributors(values) do
    authors =
      values
      |> Enum.filter(&(&1.element == "contributor" and &1.qualifier == "author"))
      |> Enum.with_index(1)
      |> Enum.map(fn {v, seq} -> %{author_name: v.value, sequence: seq} end)

    advisors =
      values
      |> Enum.filter(&(&1.element == "contributor" and &1.qualifier == "advisor"))
      |> Enum.with_index(1)
      |> Enum.map(fn {v, seq} ->
        %{advisor_name: v.value, advisor_role: :main_advisor, sequence: seq}
      end)

    %{authors: authors, advisors: advisors, examiners: [], team_members: []}
  end

  defp local_values_to_keywords(values) do
    # Keywords aren't currently emitted to local; reserved for future use.
    _ = values
    []
  end

  defp dc_values_to_keywords(values) do
    values
    |> Enum.filter(&(&1.element == "subject"))
    |> Enum.with_index(1)
    |> Enum.map(fn {v, pos} ->
      %{keyword: v.value, language: kw_language(v.language), position: pos - 1}
    end)
  end

  defp kw_language(nil), do: :id
  defp kw_language("en"), do: :en
  defp kw_language("id"), do: :id
  defp kw_language(_), do: :id

  # dc.* values that didn't map to a typed field become metadata_extras rows.
  defp unmapped_extras(dc_values, attrs) do
    dc_values
    |> Enum.reject(fn v -> v.element == "contributor" or v.element == "subject" end)
    |> Enum.reject(fn v -> Map.has_key?(attrs, dc_to_field(v)) end)
    |> Enum.map(fn v ->
      %{
        field_schema: "dc",
        field_element: v.element,
        field_qualifier: v.qualifier,
        field_value: v.value,
        language: v.language
      }
    end)
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp field_value(item, field) do
    case Map.get(item, field) do
      nil -> nil
      %Date{} = d -> Date.to_iso8601(d)
      %DateTime{} = dt -> DateTime.to_iso8601(dt)
      %NaiveDateTime{} = dt -> NaiveDateTime.to_iso8601(dt)
      atom when is_atom(atom) -> Atom.to_string(atom)
      bool when is_boolean(bool) -> to_string(bool)
      other -> other
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  @doc false
  # Used by the exporter to know whether an item has structured local contributors.
  def has_local_contributors?(local_values) do
    Enum.any?(local_values, fn v ->
      v.element == "contributor" and String.contains?(v.qualifier || "", ".")
    end)
  end
end

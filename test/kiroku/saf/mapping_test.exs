defmodule Kiroku.Saf.MappingTest do
  use ExUnit.Case, async: true

  alias Kiroku.Repository.{
    Item,
    ItemAdvisor,
    ItemAuthor,
    ItemExaminer,
    ItemKeyword,
    ItemMetadata
  }

  alias Kiroku.Saf.Mapping

  # Build a representative item directly as a struct (no DB). Ecto schema
  # defaults fill in language/status/etc.
  defp sample_item do
    %Item{
      handle: "123456789/100",
      title: "Analisis Hukum Pidana",
      title_alt: "Criminal Law Analysis",
      abstract: "Abstrak bahasa Indonesia",
      abstract_alt: "English abstract",
      language: :id,
      item_type: :skripsi,
      degree_level: :s1,
      date_issued: ~D[2024-01-15],
      publisher: "Unpad",
      faculty: "Hukum",
      department: "DH",
      program_study: "Ilmu Hukum",
      doi: "10.1234/abc",
      student_name: "Budi Santoso",
      student_id: "1402001234",
      legal_subject_matter: :pidana,
      case_reference: "123/Pid.B/2023",
      status: :published,
      item_authors: [
        %ItemAuthor{author_name: "Budi Santoso", sequence: 1, orcid: "0000-0001-2345-6789"},
        %ItemAuthor{author_name: "Sari Dewi", sequence: 2}
      ],
      item_advisors: [
        %ItemAdvisor{
          advisor_name: "Prof. Hartono",
          advisor_role: :main_advisor,
          nidn: "0011223344"
        }
      ],
      item_examiners: [%ItemExaminer{examiner_name: "Dr. Wati", sequence: 1}],
      item_team_members: [],
      item_keywords: [
        %ItemKeyword{keyword: "hukum pidana", language: :id, position: 0},
        %ItemKeyword{keyword: "criminal law", language: :en, position: 1}
      ],
      metadata_extras: [
        %ItemMetadata{
          field_schema: "dc",
          field_element: "relation",
          field_qualifier: "uri",
          field_value: "https://example.org/work/1"
        }
      ],
      bitstreams: [],
      collection: nil
    }
  end

  describe "from_item/1" do
    test "splits values into dc and local schema buckets" do
      %{dc: dc, local: local} = Mapping.from_item(sample_item())

      dc_elements = Enum.map(dc, & &1.element) |> Enum.uniq()

      # DSpace-readable subset
      assert "title" in dc_elements
      assert "description" in dc_elements
      assert "date" in dc_elements
      assert "contributor" in dc_elements
      assert "subject" in dc_elements
      assert "type" in dc_elements
      assert "identifier" in dc_elements

      # Kiroku-specific typed fields live under local
      local_elements = Enum.map(local, & &1.element) |> Enum.uniq()
      assert "faculty" in local_elements
      assert "department" in local_elements
      assert "program_study" in local_elements
      assert "legal_subject_matter" in local_elements
      assert "case_reference" in local_elements
      assert "student_id" in local_elements
    end

    test "exports keywords as dc.subject with language" do
      %{dc: dc} = Mapping.from_item(sample_item())

      subjects = Enum.filter(dc, &(&1.element == "subject"))
      assert length(subjects) == 2
      assert Enum.any?(subjects, &(&1.value == "hukum pidana" and &1.language == "id"))
      assert Enum.any?(subjects, &(&1.value == "criminal law" and &1.language == "en"))
    end

    test "emits structured contributor records under local.contributor.{role}.{seq}.sub" do
      %{local: local} = Mapping.from_item(sample_item())

      author_names =
        local
        |> Enum.filter(
          &(&1.element == "contributor" and String.starts_with?(&1.qualifier, "author."))
        )
        |> Enum.filter(&String.ends_with?(&1.qualifier, ".name"))
        |> Enum.map(& &1.value)

      assert author_names == ["Budi Santoso", "Sari Dewi"]

      orcid =
        Enum.find(local, &(&1.qualifier == "author.1.orcid"))

      assert orcid.value == "0000-0001-2345-6789"
    end

    test "round-trips metadata_extras into their declared schema" do
      %{dc: dc} = Mapping.from_item(sample_item())

      relation_uri = Enum.find(dc, &(&1.element == "relation" and &1.qualifier == "uri"))
      assert relation_uri.value == "https://example.org/work/1"
    end
  end

  describe "to_item_shape/2 round-trip" do
    test "recovers typed scalar fields from a Kiroku archive (local authoritative)" do
      item = sample_item()
      %{dc: dc, local: local} = Mapping.from_item(item)
      shape = Mapping.to_item_shape(dc, local)

      assert shape.attrs[:title] == "Analisis Hukum Pidana"
      assert shape.attrs[:title_alt] == "Criminal Law Analysis"
      assert shape.attrs[:item_type] == "skripsi"
      assert shape.attrs[:degree_level] == "s1"
      assert shape.attrs[:date_issued] == "2024-01-15"
      assert shape.attrs[:legal_subject_matter] == "pidana"
      assert shape.attrs[:case_reference] == "123/Pid.B/2023"
      assert shape.attrs[:student_id] == "1402001234"
    end

    test "recovers abstract and english abstract" do
      %{dc: dc, local: local} = Mapping.from_item(sample_item())
      shape = Mapping.to_item_shape(dc, local)

      assert shape.attrs[:abstract] == "Abstrak bahasa Indonesia"
      assert shape.attrs[:abstract_alt] == "English abstract"
    end

    test "reconstructs contributors with full detail and ordering" do
      %{dc: dc, local: local} = Mapping.from_item(sample_item())
      shape = Mapping.to_item_shape(dc, local)

      assert length(shape.authors) == 2
      [a1, a2] = shape.authors
      assert a1.author_name == "Budi Santoso"
      assert a1.orcid == "0000-0001-2345-6789"
      assert a1.sequence == 1
      assert a2.author_name == "Sari Dewi"
      assert a2.sequence == 2

      assert length(shape.advisors) == 1
      assert hd(shape.advisors).advisor_name == "Prof. Hartono"
      assert hd(shape.advisors).advisor_role == "main_advisor"
      assert hd(shape.advisors).nidn == "0011223344"

      assert length(shape.examiners) == 1
      assert hd(shape.examiners).examiner_name == "Dr. Wati"
    end

    test "reconstructs keywords preserving order and language" do
      %{dc: dc, local: local} = Mapping.from_item(sample_item())
      shape = Mapping.to_item_shape(dc, local)

      assert length(shape.keywords) == 2
      [kw1, kw2] = shape.keywords
      assert kw1.keyword == "hukum pidana"
      assert kw1.language == :id
      assert kw2.keyword == "criminal law"
      assert kw2.language == :en
    end

    test "falls back to dc.* when no metadata_local.xml (DSpace-authored archive)" do
      # Only dc values, simulating a real DSpace export.
      dc = [
        %{element: "title", qualifier: "none", language: nil, value: "DSpace Item"},
        %{element: "description", qualifier: "abstract", language: nil, value: "Abs"},
        %{element: "contributor", qualifier: "author", language: nil, value: "Author One"},
        %{element: "contributor", qualifier: "author", language: nil, value: "Author Two"},
        %{element: "subject", qualifier: "none", language: nil, value: "topic"},
        %{element: "type", qualifier: "none", language: nil, value: "thesis"},
        %{element: "date", qualifier: "issued", language: nil, value: "2020"}
      ]

      shape = Mapping.to_item_shape(dc, [])

      assert shape.attrs[:title] == "DSpace Item"
      assert shape.attrs[:abstract] == "Abs"
      assert shape.attrs[:date_issued] == "2020-01-01"
      assert length(shape.authors) == 2
      assert Enum.at(shape.authors, 0).author_name == "Author One"
      assert length(shape.keywords) == 1
    end

    test "unmappable dc.* values become metadata_extras" do
      dc = [
        %{element: "coverage", qualifier: "spatial", language: nil, value: "Bandung"},
        %{element: "title", qualifier: "none", language: nil, value: "X"}
      ]

      shape = Mapping.to_item_shape(dc, [])

      extra = Enum.find(shape.extras, &(&1.field_element == "coverage"))
      assert extra.field_qualifier == "spatial"
      assert extra.field_value == "Bandung"
      assert extra.field_schema == "dc"
    end

    test "normalizes partial dates from dc.date.issued" do
      dc = [
        %{element: "date", qualifier: "issued", language: nil, value: "1990"}
      ]

      shape = Mapping.to_item_shape(dc, [])
      assert shape.attrs[:date_issued] == "1990-01-01"

      dc2 = [%{element: "date", qualifier: "issued", language: nil, value: "1990-06"}]
      shape2 = Mapping.to_item_shape(dc2, [])
      assert shape2.attrs[:date_issued] == "1990-06-01"
    end
  end
end

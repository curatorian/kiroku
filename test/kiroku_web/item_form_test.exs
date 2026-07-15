defmodule KirokuWeb.ItemFormTest do
  use ExUnit.Case, async: true

  alias KirokuWeb.ItemForm

  describe "bundles_for_type/1" do
    test "thesis types include per-chapter uploads" do
      for type <- ~w(skripsi tesis disertasi tugas_akhir) do
        bundles = ItemForm.bundles_for_type(type)

        assert :chapters in bundles
        assert :fulltext in bundles
        assert :cover in bundles
        assert :administrative in bundles
      end
    end

    test "non-thesis types never include chapters" do
      for type <-
            ~w(memorandum_hukum studi_kasus laporan_proyek karya_kreatif karya_teknologi
              jurnal_nasional jurnal_internasional prosiding capstone) do
        refute :chapters in ItemForm.bundles_for_type(type)
      end
    end

    test "journals need neither chapters nor media" do
      for type <- ~w(jurnal_nasional jurnal_internasional) do
        bundles = ItemForm.bundles_for_type(type)

        refute :chapters in bundles
        refute :media in bundles
        assert :fulltext in bundles
      end
    end

    test "tech and creative types include source/media" do
      assert :source in ItemForm.bundles_for_type("karya_teknologi")
      assert :media in ItemForm.bundles_for_type("karya_teknologi")
      assert :media in ItemForm.bundles_for_type("karya_kreatif")
    end

    test "nil returns the full set; unknown type falls back to a safe subset" do
      all = [
        :cover,
        :abstract,
        :fulltext,
        :chapters,
        :supplemental,
        :media,
        :source,
        :administrative
      ]

      assert ItemForm.bundles_for_type(nil) == all

      fallback = ItemForm.bundles_for_type("does_not_exist")
      assert :cover in fallback
      assert :fulltext in fallback
      # Unknown types never expose type-specific bundles like chapters/media.
      refute :chapters in fallback
      refute :media in fallback
    end

    test "cover and administrative are universal across known types" do
      for type <-
            ~w(skripsi memorandum_hukum studi_kasus laporan_proyek karya_kreatif karya_teknologi
              jurnal_nasional prosiding capstone) do
        bundles = ItemForm.bundles_for_type(type)

        assert :cover in bundles
        assert :administrative in bundles
      end
    end
  end
end

defmodule KirokuWeb.Live.Helpers.FieldVisibility do
  @moduledoc """
  Determines which field groups to show/hide in the submission wizard
  and admin edit form based on item_type.
  """

  @legal_types [:memorandum_hukum]
  @ethics_types [:studi_kasus]
  @project_types [:laporan_proyek, :capstone]
  @creative_types [:karya_kreatif]
  @tech_types [:karya_teknologi]
  @journal_types [:jurnal_nasional, :jurnal_internasional]
  @intl_journal_types [:jurnal_internasional]
  @conf_types [:prosiding]
  @capstone_types [:capstone]
  @has_examiners [:skripsi, :memorandum_hukum, :studi_kasus]
  @has_degree [
    :skripsi,
    :memorandum_hukum,
    :studi_kasus,
    :laporan_proyek,
    :karya_kreatif,
    :karya_teknologi,
    :capstone
  ]

  def show_field_group?(item_type, :legal), do: item_type in @legal_types
  def show_field_group?(item_type, :ethics), do: item_type in @ethics_types
  def show_field_group?(item_type, :project_client), do: item_type in @project_types

  def show_field_group?(item_type, :team_members),
    do: item_type in (@project_types ++ @creative_types ++ @tech_types)

  def show_field_group?(item_type, :creative), do: item_type in @creative_types
  def show_field_group?(item_type, :technology), do: item_type in @tech_types
  def show_field_group?(item_type, :journal), do: item_type in @journal_types
  def show_field_group?(item_type, :scopus_wos), do: item_type in @intl_journal_types
  def show_field_group?(item_type, :conference), do: item_type in @conf_types
  def show_field_group?(item_type, :mbkm), do: item_type in @capstone_types
  def show_field_group?(item_type, :examiners), do: item_type in @has_examiners
  def show_field_group?(item_type, :degree_level), do: item_type in @has_degree
  def show_field_group?(_item_type, _group), do: false
end

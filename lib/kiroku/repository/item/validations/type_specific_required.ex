defmodule Kiroku.Repository.Item.Validations.TypeSpecificRequired do
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    item_type = Ash.Changeset.get_attribute(changeset, :item_type)
    run_type_rules(changeset, item_type)
  end

  # Skripsi / Tesis / Disertasi
  defp run_type_rules(changeset, :skripsi),
    do: require_fields(changeset, [:degree_level, :date_issued])

  # Legal Memorandum
  defp run_type_rules(changeset, :memorandum_hukum),
    do:
      require_fields(changeset, [
        :degree_level,
        :legal_subject_matter,
        :case_reference,
        :court_level,
        :legal_issue,
        :date_issued
      ])

  # Case Study
  defp run_type_rules(changeset, :studi_kasus),
    do:
      require_fields(changeset, [
        :degree_level,
        :case_study_type,
        :case_subject,
        :case_period,
        :case_location,
        :analysis_framework,
        :date_issued
      ])

  # Project Report
  defp run_type_rules(changeset, :laporan_proyek),
    do:
      require_fields(changeset, [
        :degree_level,
        :project_title,
        :project_type,
        :project_client,
        :project_period,
        :project_location,
        :project_deliverable,
        :date_issued
      ])

  # Creative Work
  defp run_type_rules(changeset, :karya_kreatif),
    do:
      require_fields(changeset, [
        :degree_level,
        :creative_work_type,
        :medium_material,
        :dimensions_duration,
        :creation_period,
        :artistic_statement,
        :date_issued
      ])

  # Technological Work
  defp run_type_rules(changeset, :karya_teknologi),
    do:
      require_fields(changeset, [
        :degree_level,
        :technology_type,
        :problem_solved,
        :target_user,
        :implementation_status,
        :testing_method,
        :date_issued
      ])

  # National Journal
  defp run_type_rules(changeset, :jurnal_nasional),
    do:
      require_fields(changeset, [
        :journal_name,
        :sinta_id,
        :sinta_accreditation,
        :issn_print,
        :volume,
        :issue,
        :page_start,
        :page_end,
        :doi,
        :date_issued
      ])

  # International Journal
  defp run_type_rules(changeset, :jurnal_internasional),
    do:
      require_fields(changeset, [
        :journal_name,
        :doi,
        :date_issued,
        :scopus_id,
        :quartile,
        :indexed_in
      ])

  # Conference Proceedings
  defp run_type_rules(changeset, :prosiding),
    do:
      require_fields(changeset, [
        :conference_name,
        :conference_acronym,
        :conference_date,
        :conference_location,
        :conference_type,
        :proceeding_publisher,
        :doi,
        :presentation_type,
        :page_start,
        :page_end,
        :date_issued
      ])

  # Capstone
  defp run_type_rules(changeset, :capstone),
    do:
      require_fields(changeset, [
        :degree_level,
        :capstone_theme,
        :project_type,
        :team_lead,
        :partner_institution,
        :problem_statement,
        :solution_description,
        :impact_target,
        :duration_semester,
        :date_issued
      ])

  # No additional rules for unknown type
  defp run_type_rules(_changeset, _), do: :ok

  defp require_fields(changeset, fields) do
    Enum.find_value(fields, :ok, fn field ->
      case Ash.Changeset.get_attribute(changeset, field) do
        nil ->
          {:error,
           field: field,
           message: "is required for #{Ash.Changeset.get_attribute(changeset, :item_type)}"}

        _ ->
          nil
      end
    end)
  end
end

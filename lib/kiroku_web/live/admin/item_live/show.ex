defmodule KirokuWeb.Admin.ItemLive.Show do
  use KirokuWeb, :live_view

  alias Kiroku.{Repository, Content}
  alias Kiroku.Repository.Item

  @tabs ~w(status metadata details contributors files history)a

  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_scope={@current_user} page_title="Items">
      <div class="max-w-5xl mx-auto space-y-6">
        <%!-- Breadcrumb + header --%>
        <div class="flex items-center justify-between gap-4">
          <div class="flex items-center gap-4">
            <.link
              navigate={~p"/admin/items"}
              style="color: var(--color-lavender);"
              class="text-sm hover:text-white transition-colors"
            >
              ← Items
            </.link>
            <span class="badge-item-type">{@item.item_type}</span>
            <span class={["status-badge", to_string(@item.status)]}>{@item.status}</span>
          </div>

          <%!-- Quick actions --%>
          <div class="flex items-center gap-2">
            <%= if @item.handle do %>
              <.link
                navigate={~p"/items/#{@item.handle}"}
                class="text-xs px-3 py-1.5 rounded-lg transition-colors"
                style="background: rgba(155,126,200,0.08); color: var(--color-wisteria);"
                target="_blank"
              >
                View Public ↗
              </.link>
            <% end %>
            <.link
              navigate={~p"/admin/items/#{@item.id}/review"}
              class="text-xs px-3 py-1.5 rounded-lg transition-colors"
              style="background: rgba(123,79,166,0.12); color: var(--color-patchouli);"
            >
              Review →
            </.link>
          </div>
        </div>

        <%!-- Title card --%>
        <div class="kiroku-card p-6">
          <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">{@item.title}</h1>
          <p class="kiroku-handle mt-1">{@item.handle || @item.id}</p>
          <%= if @item.student_name do %>
            <p class="text-sm mt-2" style="color: var(--color-quill);">
              {@item.student_name}
              <%= if @item.student_id do %>
                · NPM: {@item.student_id}
              <% end %>
              <%= if @item.faculty do %>
                · {@item.faculty}
              <% end %>
            </p>
          <% end %>
        </div>

        <%!-- Tab navigation --%>
        <div class="flex flex-wrap gap-2 border-b pb-2" style="border-color: rgba(155,126,200,0.12);">
          <.tab_link item_id={@item.id} tab="status" active={@tab} count={nil} label="Status" />
          <.tab_link item_id={@item.id} tab="metadata" active={@tab} count={nil} label="Metadata" />
          <.tab_link item_id={@item.id} tab="details" active={@tab} count={nil} label="Details" />
          <.tab_link
            item_id={@item.id}
            tab="contributors"
            active={@tab}
            count={contributor_count(@item)}
            label="Contributors"
          />
          <.tab_link
            item_id={@item.id}
            tab="files"
            active={@tab}
            count={length(@item.bitstreams)}
            label="Files"
          />
          <.tab_link
            item_id={@item.id}
            tab="history"
            active={@tab}
            count={length(@versions)}
            label="History"
          />
        </div>

        <%!-- Tab content --%>
        <%= case @tab do %>
          <% :status -> %>
            <.status_tab item={@item} />
          <% :metadata -> %>
            <.metadata_tab item={@item} form={@metadata_form} collections={@collections} />
          <% :details -> %>
            <.details_tab item={@item} />
          <% :contributors -> %>
            <.contributors_tab item={@item} />
          <% :files -> %>
            <.files_tab item={@item} editing_bs_id={@editing_bs_id} />
          <% :history -> %>
            <.history_tab versions={@versions} />
        <% end %>
      </div>
    </Layouts.admin>
    """
  end

  # ── Tab link ─────────────────────────────────────────────────────────────────

  attr :item_id, :string, required: true
  attr :tab, :string, required: true
  attr :active, :atom, required: true
  attr :count, :any, default: nil
  attr :label, :string, required: true

  defp tab_link(assigns) do
    ~H"""
    <.link
      patch={~p"/admin/items/#{@item_id}?tab=#{@tab}"}
      class={[
        "flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all",
        @active == String.to_existing_atom(@tab) &&
          "bg-[color-mix(in_srgb,var(--color-patchouli)_18%,transparent)]"
      ]}
      style={
        if @active == String.to_existing_atom(@tab),
          do: "color: var(--color-wisteria); border-left: 2px solid var(--color-patchouli);",
          else: "color: var(--color-quill);"
      }
    >
      {@label}
      <%= if @count do %>
        <span class="text-xs px-1.5 py-0.5 rounded-full" style="background: rgba(155,126,200,0.12);">
          {@count}
        </span>
      <% end %>
    </.link>
    """
  end

  defp contributor_count(item) do
    length(item.item_authors || []) +
      length(item.item_advisors || []) +
      length(item.item_examiners || []) +
      length(item.item_keywords || [])
  end

  # ── Status tab ───────────────────────────────────────────────────────────────

  defp status_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Lifecycle actions --%>
      <div class="kiroku-card p-5 space-y-3">
        <h3 class="font-heading text-lg" style="color: var(--color-lilac);">Lifecycle</h3>
        <div class="flex flex-wrap gap-3">
          <%= if @item.status in [:submitted, :draft] do %>
            <button
              phx-click="publish"
              data-confirm="Publish this item?"
              class="px-4 py-2 rounded-lg text-sm font-medium"
              style="background: rgba(90,158,114,0.15); color: #5A9E72; border: 1px solid rgba(90,158,114,0.3);"
            >
              Publish
            </button>
          <% end %>
          <%= if @item.status == :published do %>
            <button
              phx-click="withdraw"
              data-confirm="Withdraw this item?"
              class="px-4 py-2 rounded-lg text-sm font-medium"
              style="background: rgba(196,65,90,0.12); color: var(--color-ribbon-red); border: 1px solid rgba(196,65,90,0.2);"
            >
              Withdraw
            </button>
          <% end %>
          <%= if @item.status == :embargoed do %>
            <button
              phx-click="lift_embargo"
              data-confirm="Lift the embargo?"
              class="px-4 py-2 rounded-lg text-sm font-medium"
              style="background: rgba(212,160,23,0.15); color: var(--color-ribbon-gold);"
            >
              Lift Embargo
            </button>
          <% end %>
          <button
            phx-click="delete"
            data-confirm="Permanently delete this item? This cannot be undone."
            class="px-4 py-2 rounded-lg text-sm font-medium"
            style="background: rgba(196,65,90,0.08); color: var(--color-ribbon-red); border: 1px solid rgba(196,65,90,0.15);"
          >
            Delete Item
          </button>
        </div>
      </div>

      <%!-- Access & visibility --%>
      <div class="kiroku-card p-5 space-y-3">
        <h3 class="font-heading text-lg" style="color: var(--color-lilac);">Access & Visibility</h3>
        <div class="grid grid-cols-2 gap-4 text-sm" style="color: var(--color-quill);">
          <div>
            <span class="font-medium" style="color: var(--color-wisteria);">Access level:</span>
            <span class="ml-2">{@item.access_level}</span>
          </div>
          <div>
            <span class="font-medium" style="color: var(--color-wisteria);">Discoverable:</span>
            <span class="ml-2">{if @item.discoverable, do: "Yes", else: "No"}</span>
          </div>
          <%= if @item.embargo_open_date do %>
            <div>
              <span class="font-medium" style="color: var(--color-wisteria);">Embargo until:</span>
              <span class="ml-2">{@item.embargo_open_date}</span>
            </div>
          <% end %>
          <%= if @item.collection do %>
            <div>
              <span class="font-medium" style="color: var(--color-wisteria);">Collection:</span>
              <span class="ml-2">{@item.collection.name}</span>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Metadata keys --%>
      <div class="kiroku-card p-5 space-y-3">
        <h3 class="font-heading text-lg" style="color: var(--color-lilac);">Identifiers</h3>
        <div class="grid grid-cols-2 gap-4 text-sm" style="color: var(--color-quill);">
          <%= if @item.doi do %>
            <div>
              <span class="font-medium" style="color: var(--color-wisteria);">DOI:</span>
              <span class="ml-2">{@item.doi}</span>
            </div>
          <% end %>
          <%= if @item.legacy_id do %>
            <div>
              <span class="font-medium" style="color: var(--color-wisteria);">Legacy ID:</span>
              <span class="ml-2">{@item.legacy_id}</span>
            </div>
          <% end %>
          <%= if @item.idpustaka do %>
            <div>
              <span class="font-medium" style="color: var(--color-wisteria);">ID Pustaka:</span>
              <span class="ml-2">{@item.idpustaka}</span>
            </div>
          <% end %>
          <div>
            <span class="font-medium" style="color: var(--color-wisteria);">DOI status:</span>
            <span class="ml-2">{@item.doi_status}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Metadata tab ─────────────────────────────────────────────────────────────

  defp metadata_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <.form
        for={@form}
        id="metadata-edit-form"
        phx-change="validate_metadata"
        phx-submit="save_metadata"
        class="space-y-4"
      >
        <div class="kiroku-card p-5 space-y-4">
          <h3 class="font-heading text-lg" style="color: var(--color-lilac);">Core Metadata</h3>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input
              field={@form[:title]}
              type="text"
              label="Title"
              class="kiroku-search-input w-full"
            />
            <.input
              field={@form[:title_alt]}
              type="text"
              label="Alternate title"
              class="kiroku-search-input w-full"
            />
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <.input
              field={@form[:item_type]}
              type="select"
              label="Item type"
              options={item_type_options()}
              class="kiroku-search-input w-full"
            />
            <.input
              field={@form[:collection_id]}
              type="select"
              label="Collection"
              options={collection_options(@collections)}
              class="kiroku-search-input w-full"
            />
          </div>

          <.input
            field={@form[:abstract]}
            type="textarea"
            label="Abstract"
            rows="4"
            class="kiroku-search-input w-full"
          />

          <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <.input
              field={@form[:student_name]}
              type="text"
              label="Student name"
              class="kiroku-search-input w-full"
            />
            <.input
              field={@form[:student_id]}
              type="text"
              label="Student ID (NPM)"
              class="kiroku-search-input w-full"
            />
            <.input
              field={@form[:faculty]}
              type="text"
              label="Faculty"
              class="kiroku-search-input w-full"
            />
            <.input
              field={@form[:publication_year]}
              type="number"
              label="Year"
              class="kiroku-search-input w-full"
            />
          </div>

          <div class="grid grid-cols-2 sm:grid-cols-3 gap-4">
            <.input
              field={@form[:department]}
              type="text"
              label="Department"
              class="kiroku-search-input w-full"
            />
            <.input
              field={@form[:program_study]}
              type="text"
              label="Program study"
              class="kiroku-search-input w-full"
            />
            <.input
              field={@form[:language]}
              type="select"
              label="Language"
              options={[{"Indonesian", "id"}, {"English", "en"}]}
              class="kiroku-search-input w-full"
            />
          </div>
        </div>

        <%!-- Access settings --%>
        <div class="kiroku-card p-5 space-y-4">
          <h3 class="font-heading text-lg" style="color: var(--color-lilac);">Access Settings</h3>
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-4">
            <.input
              field={@form[:access_level]}
              type="select"
              label="Access level"
              options={[
                {"Open", "open"},
                {"Internal", "internal"},
                {"Restricted", "restricted"},
                {"Closed", "closed"}
              ]}
              class="kiroku-search-input w-full"
            />
            <.input
              field={@form[:doi]}
              type="text"
              label="DOI"
              class="kiroku-search-input w-full"
            />
            <.input
              field={@form[:publication_year]}
              type="number"
              label="Publication year"
              class="kiroku-search-input w-full"
            />
          </div>
        </div>

        <div class="flex justify-end">
          <button
            type="submit"
            class="px-5 py-2 rounded-lg font-medium text-sm transition-colors"
            style="background: var(--color-patchouli); color: white;"
          >
            Save Metadata
          </button>
        </div>
      </.form>
    </div>
    """
  end

  # ── Details tab (type-specific fields) ──────────────────────────────────────

  defp details_tab(assigns) do
    ~H"""
    <% fields = type_detail_fields(@item) %>
    <%= if fields == [] do %>
      <div class="kiroku-card p-8 text-center">
        <.icon name="hero-document-magnifying-glass" class="w-10 h-10 mx-auto opacity-30" />
        <p class="mt-3 text-sm" style="color: var(--color-quill);">
          No type-specific details recorded for this item.
        </p>
      </div>
    <% else %>
      <div class="kiroku-card p-5 space-y-4">
        <h3 class="font-heading text-lg flex items-center gap-2" style="color: var(--color-lilac);">
          <.icon name="hero-clipboard-document-list" class="w-5 h-5" />
          {humanize_type(@item.item_type)} Details
        </h3>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-4">
          <%= for {label, value} <- fields do %>
            <div>
              <p class="text-xs font-medium mb-0.5" style="color: var(--color-quill);">
                {label}
              </p>
              <p class="text-sm" style="color: var(--color-wisteria);">
                {value}
              </p>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  # Maps an item to a list of {display_label, formatted_value} pairs for the
  # type-specific fields that apply to it. Nil/empty values are filtered out.
  defp type_detail_fields(%Item{} = item) do
    item
    |> fields_for_type()
    |> Enum.map(fn {label, field} -> {label, format_field(item, field)} end)
    |> Enum.reject(fn {_, v} -> blank?(v) end)
  end

  defp fields_for_type(%Item{item_type: t})
       when t in [:skripsi, :tesis, :disertasi, :tugas_akhir] do
    [
      {"Research Method", :thesis_type_detail},
      {"Research Location", :research_location},
      {"Research Period", :research_period},
      {"Funding Source", :funding_source},
      {"Subject Classification", :subject_classification},
      {"Originality Statement", :originality_statement}
    ]
  end

  defp fields_for_type(%Item{item_type: :memorandum_hukum}) do
    [
      {"Legal Subject Matter", :legal_subject_matter},
      {"Analysis Method", :legal_analysis_method},
      {"Jurisdiction", :jurisdiction},
      {"Court Level", :court_level},
      {"Case Reference", :case_reference},
      {"Legal Issue", :legal_issue}
    ]
  end

  defp fields_for_type(%Item{item_type: :studi_kasus}) do
    [
      {"Case Study Type", :case_study_type},
      {"Data Collection Method", :data_collection_method},
      {"Subject", :case_subject},
      {"Period", :case_period},
      {"Location", :case_location},
      {"Analysis Framework", :analysis_framework},
      {"Industry Partner", :industry_partner},
      {"Subject Anonymized", :subject_anonymized},
      {"Informed Consent", :informed_consent},
      {"Ethics Approval Number", :ethics_approval_number}
    ]
  end

  defp fields_for_type(%Item{item_type: :laporan_proyek}) do
    [
      {"Project Type", :project_type},
      {"Team Role", :team_role},
      {"Client", :project_client},
      {"Partner Institution", :partner_institution},
      {"Period", :project_period},
      {"Location", :project_location},
      {"Deliverable", :project_deliverable},
      {"Budget", :project_budget},
      {"Problem Statement", :problem_statement},
      {"Solution / Result", :solution_description},
      {"Patent Pending", :patent_pending}
    ]
  end

  defp fields_for_type(%Item{item_type: :karya_kreatif}) do
    [
      {"Creative Work Type", :creative_work_type},
      {"Copyright Type", :copyright_type},
      {"Medium / Material", :medium_material},
      {"Dimensions / Duration", :dimensions_duration},
      {"Creation Period", :creation_period},
      {"Artistic Statement", :artistic_statement},
      {"Exhibition / Performance", :exhibition_performance},
      {"Exhibition Venue", :exhibition_venue},
      {"Exhibition Date", :exhibition_date},
      {"Collection Owner", :collection_owner}
    ]
  end

  defp fields_for_type(%Item{item_type: :karya_teknologi}) do
    [
      {"Technology Type", :technology_type},
      {"Implementation Status", :implementation_status},
      {"License Type", :license_type},
      {"Testing Method", :testing_method},
      {"Problem Solved", :problem_solved},
      {"Target User", :target_user},
      {"Patent Status", :patent_status},
      {"HKI Number", :hki_number},
      {"Industry Tested At", :industry_tested_at}
    ]
  end

  defp fields_for_type(%Item{item_type: t})
       when t in [:jurnal_nasional, :jurnal_internasional] do
    [
      {"Journal Name", :journal_name},
      {"ISSN", :issn},
      {"e-ISSN", :eissn},
      {"DOI", :doi},
      {"Volume", :volume},
      {"Issue", :issue},
      {"Pages", :page_range},
      {"Publisher", :publisher},
      {"Sinta Accreditation", :sinta_accreditation},
      {"Quartile", :quartile},
      {"Article Type", :article_type},
      {"Peer Review Type", :peer_review_type},
      {"Scopus Indexed", :scopus_indexed},
      {"WoS Indexed", :wos_indexed}
    ]
  end

  defp fields_for_type(%Item{item_type: :prosiding}) do
    [
      {"Conference Name", :conference_name},
      {"Conference Location", :conference_location},
      {"Conference Date", :conference_date},
      {"DOI", :doi},
      {"ISBN", :isbn},
      {"Publisher", :publisher},
      {"Best Paper Award", :best_paper_award}
    ]
  end

  defp fields_for_type(%Item{item_type: :capstone}) do
    [
      {"Capstone Theme", :capstone_theme},
      {"Capstone Partner", :capstone_partner},
      {"MBKM Scheme", :mbkm_scheme},
      {"Project Type", :project_type},
      {"Partner Institution", :partner_institution},
      {"Period", :project_period},
      {"Location", :project_location},
      {"Team Role", :team_role},
      {"Problem Statement", :problem_statement},
      {"Solution / Result", :solution_description}
    ]
  end

  defp fields_for_type(_), do: []

  defp format_field(item, :page_range) do
    case {item.page_start, item.page_end} do
      {nil, nil} -> nil
      {s, nil} -> "#{s}"
      {nil, e} -> "#{e}"
      {s, e} -> "#{s}–#{e}"
    end
  end

  defp format_field(item, field) do
    case Map.get(item, field) do
      nil -> nil
      v when is_atom(v) -> humanize_atom(v)
      v when is_boolean(v) -> if v, do: "Yes", else: "No"
      v -> to_string(v)
    end
  end

  defp humanize_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp humanize_type(type) do
    type
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false

  # ── Contributors tab ─────────────────────────────────────────────────────────

  defp contributors_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Authors --%>
      <.contributor_section
        title="Authors"
        icon="hero-user"
        items={@item.item_authors}
        name_field={:author_name}
        delete_event="delete_author"
        id_prefix="author"
      />

      <%!-- Advisors --%>
      <.contributor_section
        title="Advisors"
        icon="hero-academic-cap"
        items={@item.item_advisors}
        name_field={:advisor_name}
        delete_event="delete_advisor"
        id_prefix="advisor"
      />

      <%!-- Examiners --%>
      <.contributor_section
        title="Examiners"
        icon="hero-user-group"
        items={@item.item_examiners}
        name_field={:examiner_name}
        delete_event="delete_examiner"
        id_prefix="examiner"
      />

      <%!-- Keywords --%>
      <div class="kiroku-card p-5 space-y-3">
        <h3 class="font-heading text-lg flex items-center gap-2" style="color: var(--color-lilac);">
          <.icon name="hero-tag" class="w-5 h-5" /> Keywords
        </h3>
        <%= if @item.item_keywords != [] do %>
          <div class="flex flex-wrap gap-2">
            <%= for kw <- @item.item_keywords do %>
              <span
                class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-sm"
                style="background: rgba(155,126,200,0.08); color: var(--color-wisteria);"
              >
                {kw.keyword}
                <button
                  phx-click="delete_keyword"
                  phx-value-id={kw.id}
                  class="hover:text-red-400 transition-colors"
                  data-confirm="Remove this keyword?"
                >
                  <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
                </button>
              </span>
            <% end %>
          </div>
        <% else %>
          <p class="text-sm" style="color: var(--color-quill);">No keywords.</p>
        <% end %>

        <%!-- Add keyword --%>
        <form phx-submit="add_keyword" class="flex gap-2">
          <input
            type="text"
            name="keyword"
            placeholder="Add keyword…"
            class="kiroku-search-input flex-1"
            required
          />
          <button
            type="submit"
            class="px-4 py-2 rounded-lg text-sm font-medium"
            style="background: var(--color-patchouli); color: white;"
          >
            Add
          </button>
        </form>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :items, :list, required: true
  attr :name_field, :atom, required: true
  attr :delete_event, :string, required: true
  attr :id_prefix, :string, required: true

  defp contributor_section(assigns) do
    ~H"""
    <%!-- Compute singular label for prompts --%>
    <% singular = @title |> String.downcase() |> String.slice(0..-2//1) %>
    <div class="kiroku-card p-5 space-y-3">
      <h3 class="font-heading text-lg flex items-center gap-2" style="color: var(--color-lilac);">
        <.icon name={@icon} class="w-5 h-5" /> {@title}
        <span class="text-xs ml-1" style="color: var(--color-quill);">
          ({length(@items)})
        </span>
      </h3>
      <%= if @items != [] do %>
        <div class="space-y-2">
          <%= for item <- @items do %>
            <div
              class="flex items-center gap-3 p-2.5 rounded-lg"
              style="background: rgba(123,79,166,0.04);"
            >
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium truncate" style="color: var(--color-wisteria);">
                  {Map.get(item, @name_field)}
                </p>
                <%= if Map.get(item, :affiliation) do %>
                  <p class="text-xs truncate" style="color: var(--color-quill);">
                    {Map.get(item, :affiliation)}
                  </p>
                <% end %>
                <%= if Map.get(item, :orcid) do %>
                  <p class="text-xs font-mono" style="color: var(--color-quill);">
                    ORCID: {Map.get(item, :orcid)}
                  </p>
                <% end %>
              </div>
              <button
                phx-click={@delete_event}
                phx-value-id={item.id}
                class="text-sm hover:text-red-400 transition-colors shrink-0"
                style="color: var(--color-quill);"
                data-confirm={"Remove this " <> singular <> "?"}
              >
                <.icon name="hero-trash" class="w-4 h-4" />
              </button>
            </div>
          <% end %>
        </div>
      <% else %>
        <p class="text-sm" style="color: var(--color-quill);">None.</p>
      <% end %>

      <%!-- Add contributor --%>
      <form phx-submit={"add_#{@id_prefix}"} class="grid grid-cols-1 sm:grid-cols-3 gap-2">
        <input
          type="text"
          name="name"
          placeholder={"Add " <> singular <> " name…"}
          class="kiroku-search-input sm:col-span-2"
          required
        />
        <button
          type="submit"
          class="px-4 py-2 rounded-lg text-sm font-medium"
          style="background: var(--color-patchouli); color: white;"
        >
          Add
        </button>
      </form>
    </div>
    """
  end

  # ── Files tab ────────────────────────────────────────────────────────────────

  defp files_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <%= if @item.bitstreams != [] do %>
        <div class="kiroku-card p-5 space-y-3">
          <h3 class="font-heading text-lg" style="color: var(--color-lilac);">
            Files ({length(@item.bitstreams)})
          </h3>
          <div class="space-y-2">
            <%= for bs <- @item.bitstreams do %>
              <%= if @editing_bs_id == bs.id do %>
                <%!-- Inline edit mode --%>
                <div
                  class="p-3 rounded-lg space-y-2"
                  style="background: rgba(123,79,166,0.08); border: 1px solid var(--color-patchouli);"
                >
                  <div class="flex items-center gap-2 text-xs" style="color: var(--color-quill);">
                    <.icon
                      name="hero-document-text"
                      class="w-4 h-4"
                      style="color: var(--color-patchouli);"
                    />
                    {bs.filename}
                  </div>
                  <form phx-submit="save_bitstream" class="space-y-2">
                    <input type="hidden" name="bs_id" value={bs.id} />
                    <input
                      type="text"
                      name="description"
                      value={bs.description || ""}
                      placeholder="Description (e.g. Bab 1, Daftar Pustaka)"
                      class="kiroku-search-input w-full"
                      autofocus
                    />
                    <div class="flex items-center gap-2">
                      <label class="text-xs" style="color: var(--color-quill);">Access:</label>
                      <select name="access_level" class="kiroku-search-input" style="width: auto;">
                        <%= for {label, val} <- [
                               {"Open", "open"},
                               {"Internal", "internal"},
                               {"Inherit", "inherit"},
                               {"Restricted", "restricted"},
                               {"Closed", "closed"}
                             ] do %>
                          <option value={val} selected={to_string(bs.access_level) == val}>
                            {label}
                          </option>
                        <% end %>
                      </select>
                      <button
                        type="submit"
                        class="px-3 py-1.5 rounded-lg text-xs font-medium ml-auto"
                        style="background: var(--color-patchouli); color: white;"
                      >
                        Save
                      </button>
                      <button
                        type="button"
                        phx-click="cancel_edit_bitstream"
                        class="px-3 py-1.5 rounded-lg text-xs font-medium"
                        style="background: rgba(155,126,200,0.08); color: var(--color-quill);"
                      >
                        Cancel
                      </button>
                    </div>
                  </form>
                </div>
              <% else %>
                <%!-- Display mode --%>
                <div
                  class="flex items-center gap-3 p-3 rounded-lg"
                  style="background: rgba(123,79,166,0.04); border: 1px solid rgba(123,79,166,0.08);"
                >
                  <.icon
                    name="hero-document-text"
                    class="w-5 h-5 shrink-0"
                    style="color: var(--color-patchouli);"
                  />
                  <div class="min-w-0 flex-1">
                    <a
                      href={bitstream_url(bs, @item.handle)}
                      target="_blank"
                      rel="noopener"
                      class="text-sm font-medium truncate hover:underline"
                      style="color: var(--color-wisteria);"
                    >
                      {bs.description || bs.filename}
                    </a>
                    <p class="text-xs" style="color: var(--color-quill);">
                      {bs.bundle_name} · seq {bs.sequence}
                      <%= if bs.file_size do %>
                        · {div(bs.file_size, 1024)} KB
                      <% end %>
                      · {bs.storage_type} · {bs.access_level}
                      <%= if bs.mime_type do %>
                        · {bs.mime_type}
                      <% end %>
                    </p>
                  </div>
                  <div class="flex items-center gap-1 shrink-0">
                    <a
                      href={bitstream_url(bs, @item.handle)}
                      target="_blank"
                      rel="noopener"
                      class="text-xs px-2 py-1 rounded hover:bg-white/5 transition-colors"
                      style="color: var(--color-quill);"
                      title="Open file"
                    >
                      <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
                    </a>
                    <button
                      phx-click="edit_bitstream"
                      phx-value-id={bs.id}
                      class="text-xs px-2 py-1 rounded hover:bg-white/5 transition-colors"
                      style="color: var(--color-quill);"
                      title="Edit"
                    >
                      <.icon name="hero-pencil" class="w-4 h-4" />
                    </button>
                    <button
                      phx-click="delete_bitstream"
                      phx-value-id={bs.id}
                      class="text-xs px-2 py-1 rounded hover:text-red-400 transition-colors"
                      style="color: var(--color-quill);"
                      data-confirm="Remove this file?"
                    >
                      <.icon name="hero-trash" class="w-4 h-4" />
                    </button>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      <% else %>
        <div class="kiroku-card p-8 text-center">
          <.icon name="hero-folder-open" class="w-12 h-12 mx-auto opacity-30" />
          <p class="mt-3 text-sm" style="color: var(--color-quill);">
            No files attached to this item.
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  # ── History tab ──────────────────────────────────────────────────────────────

  defp history_tab(assigns) do
    ~H"""
    <div class="kiroku-card p-5 space-y-3">
      <h3 class="font-heading text-lg" style="color: var(--color-lilac);">Version History</h3>
      <%= if @versions == [] do %>
        <p class="text-sm" style="color: var(--color-quill);">No version history.</p>
      <% else %>
        <div class="space-y-2">
          <%= for v <- @versions do %>
            <div
              class="flex items-start gap-3 p-3 rounded-lg"
              style="background: rgba(155,126,200,0.04);"
            >
              <div
                class="w-8 h-8 rounded-full flex items-center justify-center shrink-0 text-xs font-bold"
                style="background: rgba(123,79,166,0.15); color: var(--color-patchouli);"
              >
                {v.version_number}
              </div>
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <span class="text-sm font-medium" style="color: var(--color-wisteria);">
                    {v.action}
                  </span>
                  <%= if v.actor_name do %>
                    <span class="text-xs" style="color: var(--color-quill);">
                      by {v.actor_name}
                    </span>
                  <% end %>
                  <span class="text-xs ml-auto tabular-nums" style="color: var(--color-quill);">
                    {Calendar.strftime(v.inserted_at, "%b %d, %Y %H:%M")}
                  </span>
                </div>
                <%= if v.summary do %>
                  <p class="text-xs mt-0.5" style="color: var(--color-quill);">
                    {v.summary}
                  </p>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # ── Options helpers ──────────────────────────────────────────────────────────

  defp item_type_options do
    [
      {"Skripsi", "skripsi"},
      {"Tesis", "tesis"},
      {"Disertasi", "disertasi"},
      {"Tugas Akhir", "tugas_akhir"},
      {"Memorandum Hukum", "memorandum_hukum"},
      {"Studi Kasus", "studi_kasus"},
      {"Laporan Proyek", "laporan_proyek"},
      {"Karya Kreatif", "karya_kreatif"},
      {"Karya Teknologi", "karya_teknologi"},
      {"Jurnal Nasional", "jurnal_nasional"},
      {"Jurnal Internasional", "jurnal_internasional"},
      {"Prosiding", "prosiding"},
      {"Capstone", "capstone"}
    ]
  end

  defp collection_options(collections) do
    Enum.map(collections, fn c -> {c.name, c.id} end)
  end

  # ── Mount / Params ───────────────────────────────────────────────────────────

  def mount(%{"id" => id}, _session, socket) do
    item = Repository.get_item_with_preloads!(id)
    versions = Repository.list_item_versions(item.id)
    collections = Repository.list_collections()

    {:ok,
     socket
     |> assign(:item, item)
     |> assign(:versions, versions)
     |> assign(:collections, collections)
     |> assign(:tab, :status)
     |> assign(:editing_bs_id, nil)
     |> assign(:metadata_form, to_form(item_changeset(item)))}
  end

  def handle_params(%{"tab" => tab_str}, _uri, socket) do
    tab =
      if tab_str in Enum.map(@tabs, &to_string/1),
        do: String.to_existing_atom(tab_str),
        else: :status

    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp item_changeset(item), do: Kiroku.Repository.Item.changeset(item, %{})

  # ── Lifecycle events ─────────────────────────────────────────────────────────

  def handle_event("publish", _params, socket) do
    case Repository.publish_item(socket.assigns.item) do
      {:ok, item} ->
        {:noreply, socket |> put_flash(:info, "Item published.") |> reload_item(item)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to publish item.")}
    end
  end

  def handle_event("withdraw", _params, socket) do
    case Repository.withdraw_item_fsm(socket.assigns.item) do
      {:ok, item} ->
        {:noreply, socket |> put_flash(:info, "Item withdrawn.") |> reload_item(item)}

      {:error, :invalid_transition} ->
        {:noreply, put_flash(socket, :error, "Cannot withdraw from current status.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to withdraw item.")}
    end
  end

  def handle_event("lift_embargo", _params, socket) do
    case Repository.lift_embargo(socket.assigns.item) do
      {:ok, item} ->
        {:noreply, socket |> put_flash(:info, "Embargo lifted.") |> reload_item(item)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to lift embargo.")}
    end
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Repository.delete_item(socket.assigns.item)
    {:noreply, socket |> put_flash(:info, "Item deleted.") |> push_navigate(to: ~p"/admin/items")}
  end

  # ── Metadata editing ─────────────────────────────────────────────────────────

  def handle_event("validate_metadata", %{"item" => params}, socket) do
    changeset =
      socket.assigns.item
      |> Repository.Item.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :metadata_form, to_form(changeset))}
  end

  def handle_event("save_metadata", %{"item" => params}, socket) do
    case Repository.update_item(socket.assigns.item, params) do
      {:ok, item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Metadata saved.")
         |> reload_item(item)}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Validation failed.")
         |> assign(:metadata_form, to_form(changeset))}
    end
  end

  # ── Contributor management ───────────────────────────────────────────────────

  def handle_event("add_author", %{"name" => name}, socket) do
    {:ok, _} =
      Repository.create_item_author(%{
        "item_id" => socket.assigns.item.id,
        "author_name" => name
      })

    {:noreply, socket |> put_flash(:info, "Author added.") |> reload_item(socket.assigns.item)}
  end

  def handle_event("delete_author", %{"id" => id}, socket) do
    author = Enum.find(socket.assigns.item.item_authors, &(&1.id == id))
    if author, do: {:ok, _} = Repository.delete_item_author(author)
    {:noreply, socket |> put_flash(:info, "Author removed.") |> reload_item(socket.assigns.item)}
  end

  def handle_event("add_advisor", %{"name" => name}, socket) do
    {:ok, _} =
      Repository.create_item_advisor(%{
        "item_id" => socket.assigns.item.id,
        "advisor_name" => name,
        "advisor_role" => "main_advisor"
      })

    {:noreply, socket |> put_flash(:info, "Advisor added.") |> reload_item(socket.assigns.item)}
  end

  def handle_event("delete_advisor", %{"id" => id}, socket) do
    advisor = Enum.find(socket.assigns.item.item_advisors, &(&1.id == id))
    if advisor, do: {:ok, _} = Repository.delete_item_advisor(advisor)
    {:noreply, socket |> put_flash(:info, "Advisor removed.") |> reload_item(socket.assigns.item)}
  end

  def handle_event("add_examiner", %{"name" => name}, socket) do
    {:ok, _} =
      Repository.create_item_examiner(%{
        "item_id" => socket.assigns.item.id,
        "examiner_name" => name
      })

    {:noreply, socket |> put_flash(:info, "Examiner added.") |> reload_item(socket.assigns.item)}
  end

  def handle_event("delete_examiner", %{"id" => id}, socket) do
    examiner = Enum.find(socket.assigns.item.item_examiners, &(&1.id == id))
    if examiner, do: {:ok, _} = Repository.delete_item_examiner(examiner)

    {:noreply,
     socket |> put_flash(:info, "Examiner removed.") |> reload_item(socket.assigns.item)}
  end

  def handle_event("add_keyword", %{"keyword" => keyword}, socket) do
    existing = Enum.map(socket.assigns.item.item_keywords, &%{keyword: &1.keyword})
    Repository.upsert_keywords_for_item(socket.assigns.item.id, existing ++ [%{keyword: keyword}])
    {:noreply, socket |> put_flash(:info, "Keyword added.") |> reload_item(socket.assigns.item)}
  end

  def handle_event("delete_keyword", %{"id" => id}, socket) do
    remaining =
      socket.assigns.item.item_keywords
      |> Enum.reject(&(&1.id == id))
      |> Enum.map(&%{keyword: &1.keyword})

    Repository.upsert_keywords_for_item(socket.assigns.item.id, remaining)
    {:noreply, socket |> put_flash(:info, "Keyword removed.") |> reload_item(socket.assigns.item)}
  end

  # ── Bitstream management ─────────────────────────────────────────────────────

  def handle_event("delete_bitstream", %{"id" => id}, socket) do
    bs = Enum.find(socket.assigns.item.bitstreams, &(&1.id == id))
    if bs, do: {:ok, _} = Content.delete_bitstream(bs)
    {:noreply, socket |> put_flash(:info, "File removed.") |> reload_item(socket.assigns.item)}
  end

  def handle_event("edit_bitstream", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_bs_id, id)}
  end

  def handle_event("cancel_edit_bitstream", _params, socket) do
    {:noreply, assign(socket, :editing_bs_id, nil)}
  end

  def handle_event(
        "save_bitstream",
        %{"bs_id" => id, "description" => desc, "access_level" => access},
        socket
      ) do
    bs = Enum.find(socket.assigns.item.bitstreams, &(&1.id == id))

    case bs && Content.update_bitstream(bs, %{"description" => desc, "access_level" => access}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "File updated.")
         |> assign(:editing_bs_id, nil)
         |> reload_item(socket.assigns.item)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update file.")}

      nil ->
        {:noreply, put_flash(socket, :error, "File not found.")}
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp reload_item(socket, item) do
    reloaded = Repository.get_item_with_preloads!(item.id)
    versions = Repository.list_item_versions(item.id)

    socket
    |> assign(:item, reloaded)
    |> assign(:versions, versions)
    |> assign(:metadata_form, to_form(item_changeset(reloaded)))
  end

  # External :url bitstreams link directly to their storage_url; local/s3
  # go through the BitstreamController download route.
  defp bitstream_url(%{storage_type: :url, storage_url: url}, _handle) when is_binary(url),
    do: url

  defp bitstream_url(bs, nil), do: "/admin/items/#{bs.item_id}/bitstreams/#{bs.id}"
  defp bitstream_url(bs, handle), do: "/items/#{handle}/bitstreams/#{bs.id}"
end

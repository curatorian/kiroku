defmodule KirokuWeb.ItemForm do
  @moduledoc """
  Shared form components for item creation/submission.
  Used by both SubmissionLive.New (submitter) and Admin.ItemLive.Index (staff).

  Import this module in any LiveView that renders item forms:
      import KirokuWeb.ItemForm
  """
  use KirokuWeb, :html

  # ── Options helpers ────────────────────────────────────────────────────────

  def item_type_options do
    [
      {"Skripsi / Tesis / Disertasi", "skripsi"},
      {"Memorandum Hukum", "memorandum_hukum"},
      {"Studi Kasus", "studi_kasus"},
      {"Laporan Proyek", "laporan_proyek"},
      {"Karya Kreatif (Seni & Desain)", "karya_kreatif"},
      {"Karya Teknologi", "karya_teknologi"},
      {"Artikel Jurnal Nasional", "jurnal_nasional"},
      {"Artikel Jurnal Internasional", "jurnal_internasional"},
      {"Prosiding Konferensi", "prosiding"},
      {"Capstone / Tugas Akhir", "capstone"}
    ]
  end

  defp degree_options do
    [
      {"D3 – Diploma 3", "d3"},
      {"D4 – Diploma 4", "d4"},
      {"S1 – Sarjana", "s1"},
      {"S1 Terapan", "s1_terapan"},
      {"S2 – Magister", "s2"},
      {"S3 – Doktor", "s3"}
    ]
  end

  defp language_options, do: [{"Indonesia", "id"}, {"English", "en"}]

  defp thesis_method_options do
    [
      {"Kuantitatif", "kuantitatif"},
      {"Kualitatif", "kualitatif"},
      {"Mixed Methods", "mixed_methods"},
      {"Research & Development (R&D)", "rnd"},
      {"Penelitian Tindakan Kelas (PTK)", "ptk"}
    ]
  end

  defp legal_subject_options do
    [
      {"Hukum Pidana", "pidana"},
      {"Hukum Perdata", "perdata"},
      {"Hukum Tata Negara", "tata_negara"},
      {"Hukum Internasional", "internasional"},
      {"Hukum Bisnis", "bisnis"},
      {"Hukum Adat", "adat"},
      {"Hukum Agraria", "agraria"},
      {"Hukum Lingkungan", "lingkungan"}
    ]
  end

  defp court_level_options do
    [
      {"Pengadilan Negeri (PN)", "pn"},
      {"Pengadilan Tinggi (PT)", "pt"},
      {"Mahkamah Agung (MA)", "ma"},
      {"Mahkamah Konstitusi (MK)", "mk"},
      {"PTUN", "ptun"},
      {"Arbitrase", "arbitrase"},
      {"BANI", "bani"},
      {"ICC", "icc"}
    ]
  end

  defp legal_analysis_options do
    [
      {"Normatif", "normatif"},
      {"Empiris", "empiris"},
      {"Komparatif", "komparatif"},
      {"Socio-Legal", "socio_legal"}
    ]
  end

  defp jurisdiction_options do
    [{"Indonesia", "indonesia"}, {"Internasional", "internasional"}, {"Komparatif", "komparatif"}]
  end

  defp case_study_type_options do
    [
      {"Bisnis", "bisnis"},
      {"Klinis", "klinis"},
      {"Hukum", "hukum"},
      {"Psikologi", "psikologi"},
      {"Pendidikan", "pendidikan"},
      {"Teknik", "teknik"}
    ]
  end

  defp data_collection_options do
    [
      {"Wawancara", "wawancara"},
      {"Observasi", "observasi"},
      {"Dokumen Sekunder", "dokumen_sekunder"},
      {"Mixed Methods", "mix"}
    ]
  end

  defp project_type_options do
    [
      {"Desain", "desain"},
      {"Konstruksi", "konstruksi"},
      {"Implementasi Software", "implementasi_software"},
      {"Manufaktur", "manufaktur"},
      {"Sistem", "sistem"},
      {"Perencanaan Wilayah", "perencanaan_wilayah"},
      {"Product", "product"},
      {"Service", "service"},
      {"Policy", "policy"},
      {"Research", "research"},
      {"Community", "community"}
    ]
  end

  defp team_role_options do
    [{"Ketua Tim", "ketua"}, {"Anggota Tim", "anggota"}, {"PIC Teknis", "pic_teknis"}]
  end

  defp creative_work_type_options do
    [
      {"Novel", "novel"},
      {"Antologi Puisi", "antologi_puisi"},
      {"Film Pendek", "film_pendek"},
      {"Komposisi Musik", "komposisi_musik"},
      {"Lukisan", "lukisan"},
      {"Desain Produk", "desain_produk"},
      {"Animasi", "animasi"},
      {"Game", "game"},
      {"Arsitektur", "arsitektur"},
      {"Kriya", "kriya"}
    ]
  end

  defp copyright_options do
    [
      {"All Rights Reserved", "all_rights_reserved"},
      {"CC BY", "cc_by"},
      {"CC BY-SA", "cc_by_sa"},
      {"CC BY-NC", "cc_by_nc"},
      {"CC BY-NC-SA", "cc_by_nc_sa"}
    ]
  end

  defp technology_type_options do
    [
      {"Aplikasi Mobile", "aplikasi_mobile"},
      {"Web App", "web_app"},
      {"Embedded System", "embedded_system"},
      {"Perangkat Keras", "perangkat_keras"},
      {"Dataset", "dataset"},
      {"Model AI / ML", "model_ai_ml"},
      {"Algoritma", "algoritma"},
      {"Inovasi Proses", "inovasi_proses"}
    ]
  end

  defp implementation_status_options do
    [
      {"Prototipe", "prototipe"},
      {"MVP", "mvp"},
      {"Deployed / Live", "deployed"},
      {"Published", "published"}
    ]
  end

  defp testing_method_options do
    [
      {"Black Box", "black_box"},
      {"White Box", "white_box"},
      {"User Testing", "user_testing"},
      {"Benchmark", "benchmark"},
      {"Usability Testing", "usability"}
    ]
  end

  defp license_type_options do
    [
      {"MIT", "mit"},
      {"Apache 2.0", "apache_2"},
      {"GPL", "gpl"},
      {"BSD", "bsd"},
      {"Proprietary", "proprietary"}
    ]
  end

  defp patent_status_options do
    [{"Tidak Ada", "tidak_ada"}, {"Dalam Proses", "dalam_proses"}, {"Granted", "granted"}]
  end

  defp sinta_options do
    [
      {"SINTA 1 (Tertinggi)", "s1"},
      {"SINTA 2", "s2"},
      {"SINTA 3", "s3"},
      {"SINTA 4", "s4"},
      {"SINTA 5", "s5"},
      {"SINTA 6", "s6"}
    ]
  end

  defp peer_review_options do
    [
      {"Single Blind", "single_blind"},
      {"Double Blind", "double_blind"},
      {"Open Review", "open_review"}
    ]
  end

  defp article_type_options do
    [
      {"Research Article", "research_article"},
      {"Review Article", "review"},
      {"Short Communication", "short_communication"},
      {"Letter", "letter"}
    ]
  end

  defp quartile_options, do: [{"Q1", "q1"}, {"Q2", "q2"}, {"Q3", "q3"}, {"Q4", "q4"}]

  defp mbkm_scheme_options do
    [
      {"Magang", "magang"},
      {"KKN-T", "kkn_t"},
      {"Penelitian", "penelitian"},
      {"Proyek Independen", "proyek_independen"},
      {"Pertukaran Mahasiswa", "pertukaran_mahasiswa"},
      {"Wirausaha", "wirausaha"}
    ]
  end

  # ── Section card header (private — used within this module only) ───────────

  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil

  defp section_header(assigns) do
    ~H"""
    <div
      class="flex items-center gap-3 pb-4 mb-1 border-b"
      style="border-color: rgba(155,126,200,0.15);"
    >
      <div
        class="w-9 h-9 rounded-xl flex items-center justify-center shrink-0"
        style="background: color-mix(in srgb, var(--color-patchouli) 14%, transparent); color: var(--color-patchouli);"
      >
        <.icon name={@icon} class="w-5 h-5" />
      </div>
      <div>
        <p
          class="font-heading font-semibold text-base leading-tight"
          style="color: var(--color-wisteria);"
        >
          {@title}
        </p>
        <p :if={@subtitle} class="text-xs leading-tight mt-0.5" style="color: var(--color-quill);">
          {@subtitle}
        </p>
      </div>
    </div>
    """
  end

  # ── Shared: item type select + common identity fields ─────────────────────

  attr :form, :any, required: true
  attr :collections, :list, default: []

  def identity_section(assigns) do
    assigns = assign(assigns, :type_options, item_type_options())
    assigns = assign(assigns, :lang_options, language_options())

    ~H"""
    <div id="identity-section" class="kiroku-card p-6 space-y-5">
      <.section_header
        icon="hero-document-text"
        title="Identitas Karya"
        subtitle="Informasi dasar tentang karya yang diajukan"
      />

      <%!-- Item type — most prominent choice --%>
      <div>
        <label class="block text-sm font-medium mb-1.5" style="color: var(--color-wisteria);">
          Jenis Karya <span class="text-red-400">*</span>
        </label>
        <select
          name="item[item_type]"
          id="item-type-select"
          class="kiroku-search-input w-full"
          phx-change="type_changed"
        >
          <option value="">Pilih jenis karya…</option>
          <%= for {label, val} <- @type_options do %>
            <option value={val} selected={to_string(@form[:item_type].value) == val}>
              {label}
            </option>
          <% end %>
        </select>
        <p class="text-xs mt-1" style="color: var(--color-quill);">
          Memilih jenis karya akan menampilkan kolom yang relevan di bawah.
        </p>
      </div>

      <.input
        field={@form[:title]}
        type="text"
        label="Judul Karya"
        required
        placeholder="Judul lengkap karya"
      />
      <.input
        field={@form[:title_alt]}
        type="text"
        label="Judul Alternatif (Bahasa Lain)"
        placeholder="Opsional — judul dalam bahasa lain"
      />

      <%!-- Collection --%>
      <div>
        <label class="block text-sm font-medium mb-1.5" style="color: var(--color-wisteria);">
          Koleksi <span class="text-red-400">*</span>
        </label>
        <select
          name="item[collection_id]"
          id="collection-select"
          class="kiroku-search-input w-full"
          required
        >
          <option value="">Pilih koleksi…</option>
          <%= for collection <- @collections do %>
            <option
              value={collection.id}
              selected={to_string(@form[:collection_id].value) == to_string(collection.id)}
            >
              {collection.name}
            </option>
          <% end %>
        </select>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div>
          <label class="block text-sm font-medium mb-1.5" style="color: var(--color-wisteria);">
            Bahasa
          </label>
          <select name="item[language]" id="item-language-select" class="kiroku-search-input w-full">
            <%= for {label, val} <- @lang_options do %>
              <option value={val} selected={to_string(@form[:language].value) == val}>
                {label}
              </option>
            <% end %>
          </select>
        </div>
        <.input
          field={@form[:publication_year]}
          type="number"
          label="Tahun Terbit"
          placeholder="e.g. 2024"
        />
      </div>
    </div>
    """
  end

  # ── Shared: abstract ──────────────────────────────────────────────────────

  attr :form, :any, required: true

  def abstract_section(assigns) do
    ~H"""
    <div id="abstract-section" class="kiroku-card p-6 space-y-4">
      <.section_header
        icon="hero-chat-bubble-bottom-center-text"
        title="Abstrak"
        subtitle="Ringkasan singkat isi karya"
      />
      <.input
        field={@form[:abstract]}
        type="textarea"
        label="Abstrak"
        placeholder="Tuliskan abstrak dalam bahasa utama karya ini…"
        rows={5}
      />
      <.input
        field={@form[:abstract_alt]}
        type="textarea"
        label="Abstrak (Bahasa Alternatif)"
        placeholder="Opsional — abstrak dalam bahasa lain"
        rows={4}
      />
    </div>
    """
  end

  # ── Shared: academic contributor (thesis-like types) ─────────────────────

  attr :form, :any, required: true

  def contributor_section(assigns) do
    assigns = assign(assigns, :degree_opts, degree_options())

    ~H"""
    <div id="contributor-section" class="kiroku-card p-6 space-y-4">
      <.section_header
        icon="hero-academic-cap"
        title="Identitas Penyusun"
        subtitle="Data mahasiswa / peneliti yang mengajukan karya"
      />
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:student_name]}
          type="text"
          label="Nama Lengkap"
          placeholder="e.g. Budi Santoso"
        />
        <.input
          field={@form[:student_id]}
          type="text"
          label="NIM / NPM"
          placeholder="e.g. 260110190001"
        />
      </div>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:degree_level]}
          type="select"
          label="Jenjang Studi"
          prompt="Pilih jenjang…"
          options={@degree_opts}
          class="kiroku-search-input w-full"
        />
        <.input
          field={@form[:institution]}
          type="text"
          label="Institusi"
          placeholder="Universitas Padjadjaran"
        />
      </div>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:faculty]}
          type="text"
          label="Fakultas"
          placeholder="e.g. Fakultas Hukum"
        />
        <.input
          field={@form[:department]}
          type="text"
          label="Departemen / Program Studi"
          placeholder="e.g. Ilmu Hukum"
        />
      </div>
    </div>
    """
  end

  # ── Type section dispatcher ────────────────────────────────────────────────

  attr :form, :any, required: true
  attr :type, :string, default: ""

  def type_section(assigns) do
    ~H"""
    <.skripsi_section :if={@type == "skripsi"} form={@form} />
    <.memorandum_hukum_section :if={@type == "memorandum_hukum"} form={@form} />
    <.studi_kasus_section :if={@type == "studi_kasus"} form={@form} />
    <.laporan_proyek_section :if={@type == "laporan_proyek"} form={@form} />
    <.karya_kreatif_section :if={@type == "karya_kreatif"} form={@form} />
    <.karya_teknologi_section :if={@type == "karya_teknologi"} form={@form} />
    <.jurnal_nasional_section :if={@type == "jurnal_nasional"} form={@form} />
    <.jurnal_internasional_section :if={@type == "jurnal_internasional"} form={@form} />
    <.prosiding_section :if={@type == "prosiding"} form={@form} />
    <.capstone_section :if={@type == "capstone"} form={@form} />
    """
  end

  # Returns true if the type should show the academic contributor section.
  def academic_type?(type)
      when type in ~w(skripsi memorandum_hukum studi_kasus laporan_proyek capstone),
      do: true

  def academic_type?(_), do: false

  # ── Skripsi / Tesis / Disertasi ───────────────────────────────────────────

  attr :form, :any, required: true

  def skripsi_section(assigns) do
    assigns =
      assigns
      |> assign(:method_opts, thesis_method_options())

    ~H"""
    <div id="type-section-skripsi" class="kiroku-card p-6 space-y-4">
      <.section_header
        icon="hero-book-open"
        title="Detail Skripsi / Tesis / Disertasi"
        subtitle="Informasi spesifik karya tulis ilmiah akademik"
      />

      <.input
        field={@form[:thesis_type_detail]}
        type="select"
        label="Metode Penelitian"
        prompt="Pilih metode…"
        options={@method_opts}
        class="kiroku-search-input w-full"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:research_location]}
          type="text"
          label="Lokasi Penelitian"
          placeholder="e.g. Bandung, Jawa Barat"
        />
        <.input
          field={@form[:research_period]}
          type="text"
          label="Periode Penelitian"
          placeholder="e.g. Maret – Agustus 2024"
        />
      </div>

      <.input
        field={@form[:funding_source]}
        type="text"
        label="Sumber Dana / Sponsor"
        placeholder="e.g. Mandiri / Beasiswa Unpad"
      />

      <.input
        field={@form[:subject_classification]}
        type="text"
        label="Klasifikasi Subjek (DDC / Kata Kunci Topik)"
        placeholder="e.g. 346.07 atau Hukum Kontrak Elektronik"
      />

      <div
        class="flex items-start gap-3 p-4 rounded-xl"
        style="background: color-mix(in srgb, var(--color-patchouli) 8%, transparent); border: 1px solid color-mix(in srgb, var(--color-patchouli) 20%, transparent);"
      >
        <.input
          field={@form[:originality_statement]}
          type="checkbox"
          label="Saya menyatakan karya ini adalah karya sendiri dan bukan hasil penjiplakan (plagiarism)"
        />
      </div>
    </div>
    """
  end

  # ── Memorandum Hukum ──────────────────────────────────────────────────────

  attr :form, :any, required: true

  def memorandum_hukum_section(assigns) do
    assigns =
      assigns
      |> assign(:legal_subject_opts, legal_subject_options())
      |> assign(:analysis_opts, legal_analysis_options())
      |> assign(:jurisdiction_opts, jurisdiction_options())
      |> assign(:court_opts, court_level_options())

    ~H"""
    <div id="type-section-memorandum-hukum" class="kiroku-card p-6 space-y-4">
      <.section_header
        icon="hero-scale"
        title="Detail Memorandum Hukum"
        subtitle="Informasi spesifik analisis dan memorandum hukum"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:legal_subject_matter]}
          type="select"
          label="Bidang Hukum"
          prompt="Pilih bidang…"
          options={@legal_subject_opts}
          class="kiroku-search-input w-full"
        />
        <.input
          field={@form[:legal_analysis_method]}
          type="select"
          label="Metode Analisis Hukum"
          prompt="Pilih metode…"
          options={@analysis_opts}
          class="kiroku-search-input w-full"
        />
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:jurisdiction]}
          type="select"
          label="Yurisdiksi"
          prompt="Pilih yurisdiksi…"
          options={@jurisdiction_opts}
          class="kiroku-search-input w-full"
        />
        <.input
          field={@form[:court_level]}
          type="select"
          label="Tingkat Pengadilan"
          prompt="Pilih tingkat…"
          options={@court_opts}
          class="kiroku-search-input w-full"
        />
      </div>

      <.input
        field={@form[:case_reference]}
        type="text"
        label="Nomor Perkara / Referensi Kasus"
        placeholder="e.g. 123/Pid.B/2024/PN.Bdg"
      />

      <.input
        field={@form[:legal_issue]}
        type="textarea"
        label="Isu Hukum Utama"
        placeholder="Deskripsikan permasalahan hukum yang dianalisis dalam karya ini…"
        rows={3}
      />
    </div>
    """
  end

  # ── Studi Kasus ───────────────────────────────────────────────────────────

  attr :form, :any, required: true

  def studi_kasus_section(assigns) do
    assigns =
      assigns
      |> assign(:case_type_opts, case_study_type_options())
      |> assign(:data_collection_opts, data_collection_options())

    ~H"""
    <div id="type-section-studi-kasus" class="kiroku-card p-6 space-y-4">
      <.section_header
        icon="hero-magnifying-glass-circle"
        title="Detail Studi Kasus"
        subtitle="Informasi spesifik penelitian berbasis studi kasus"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:case_study_type]}
          type="select"
          label="Jenis Studi Kasus"
          prompt="Pilih jenis…"
          options={@case_type_opts}
          class="kiroku-search-input w-full"
        />
        <.input
          field={@form[:data_collection_method]}
          type="select"
          label="Metode Pengumpulan Data"
          prompt="Pilih metode…"
          options={@data_collection_opts}
          class="kiroku-search-input w-full"
        />
      </div>

      <.input
        field={@form[:case_subject]}
        type="text"
        label="Subjek / Entitas Kasus"
        placeholder="e.g. PT. XYZ, Pasien NN, SD Negeri ABC"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:case_period]}
          type="text"
          label="Periode Kasus"
          placeholder="e.g. 2022–2024"
        />
        <.input
          field={@form[:case_location]}
          type="text"
          label="Lokasi Kasus"
          placeholder="e.g. Bandung, Jawa Barat"
        />
      </div>

      <.input
        field={@form[:analysis_framework]}
        type="text"
        label="Kerangka Analisis"
        placeholder="e.g. Balanced Scorecard, SWOT, DSM-5"
      />

      <.input
        field={@form[:industry_partner]}
        type="text"
        label="Mitra Industri / Institusi Pendukung"
        placeholder="e.g. PT. XYZ, Rumah Sakit ABC"
      />

      <div
        class="space-y-3 p-4 rounded-xl"
        style="background: color-mix(in srgb, var(--color-patchouli) 8%, transparent); border: 1px solid color-mix(in srgb, var(--color-patchouli) 20%, transparent);"
      >
        <p class="text-xs font-semibold" style="color: var(--color-wisteria);">Etika Penelitian</p>
        <.input
          field={@form[:subject_anonymized]}
          type="checkbox"
          label="Identitas subjek telah dianonimkan"
        />
        <.input
          field={@form[:informed_consent]}
          type="checkbox"
          label="Informed consent telah diperoleh dari subjek"
        />
        <.input
          field={@form[:ethics_approval_number]}
          type="text"
          label="Nomor Persetujuan Etik (jika ada)"
          placeholder="e.g. 001/KEP/FK/2024"
        />
      </div>
    </div>
    """
  end

  # ── Laporan Proyek ────────────────────────────────────────────────────────

  attr :form, :any, required: true

  def laporan_proyek_section(assigns) do
    assigns =
      assigns
      |> assign(:project_type_opts, project_type_options())
      |> assign(:team_role_opts, team_role_options())

    ~H"""
    <div id="type-section-laporan-proyek" class="kiroku-card p-6 space-y-4">
      <.section_header
        icon="hero-briefcase"
        title="Detail Laporan Proyek"
        subtitle="Informasi spesifik laporan kerja atau proyek profesional"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:project_type]}
          type="select"
          label="Jenis Proyek"
          prompt="Pilih jenis…"
          options={@project_type_opts}
          class="kiroku-search-input w-full"
        />
        <.input
          field={@form[:team_role]}
          type="select"
          label="Peran dalam Tim"
          prompt="Pilih peran…"
          options={@team_role_opts}
          class="kiroku-search-input w-full"
        />
      </div>

      <.input
        field={@form[:project_client]}
        type="text"
        label="Klien / Pemberi Kerja"
        placeholder="e.g. PT. XYZ atau Dinas ABC Kota Bandung"
      />

      <.input
        field={@form[:partner_institution]}
        type="text"
        label="Institusi Mitra"
        placeholder="e.g. Kementerian Perindustrian RI"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:project_period]}
          type="text"
          label="Periode Proyek"
          placeholder="e.g. Feb – Agustus 2024"
        />
        <.input
          field={@form[:project_location]}
          type="text"
          label="Lokasi Proyek"
          placeholder="e.g. Jakarta Selatan"
        />
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:project_deliverable]}
          type="text"
          label="Deliverable Utama"
          placeholder="e.g. Aplikasi Web, Laporan Teknis, Prototipe"
        />
        <.input
          field={@form[:project_budget]}
          type="text"
          label="Nilai Anggaran (Opsional)"
          placeholder="e.g. Rp 50.000.000"
        />
      </div>

      <.input
        field={@form[:problem_statement]}
        type="textarea"
        label="Rumusan Masalah"
        placeholder="Deskripsikan masalah yang menjadi dasar proyek ini…"
        rows={3}
      />

      <.input
        field={@form[:solution_description]}
        type="textarea"
        label="Solusi / Hasil yang Dicapai"
        placeholder="Deskripsikan solusi atau output yang berhasil dihasilkan…"
        rows={3}
      />

      <div
        class="flex items-start gap-3 p-4 rounded-xl"
        style="background: color-mix(in srgb, var(--color-patchouli) 8%, transparent); border: 1px solid color-mix(in srgb, var(--color-patchouli) 20%, transparent);"
      >
        <.input
          field={@form[:patent_pending]}
          type="checkbox"
          label="Pendaftaran paten / HKI sedang diproses untuk hasil proyek ini"
        />
      </div>
    </div>
    """
  end

  # ── Karya Kreatif ─────────────────────────────────────────────────────────

  attr :form, :any, required: true

  def karya_kreatif_section(assigns) do
    assigns =
      assigns
      |> assign(:work_type_opts, creative_work_type_options())
      |> assign(:copyright_opts, copyright_options())

    ~H"""
    <div id="type-section-karya-kreatif" class="kiroku-card p-6 space-y-4">
      <.section_header
        icon="hero-paint-brush"
        title="Detail Karya Kreatif"
        subtitle="Informasi spesifik karya seni, desain, dan budaya"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:creative_work_type]}
          type="select"
          label="Jenis Karya"
          prompt="Pilih jenis karya…"
          options={@work_type_opts}
          class="kiroku-search-input w-full"
        />
        <.input
          field={@form[:copyright_type]}
          type="select"
          label="Lisensi / Hak Cipta"
          prompt="Pilih lisensi…"
          options={@copyright_opts}
          class="kiroku-search-input w-full"
        />
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:medium_material]}
          type="text"
          label="Medium / Material"
          placeholder="e.g. Cat Minyak, Unity Engine, Benang Tenun"
        />
        <.input
          field={@form[:dimensions_duration]}
          type="text"
          label="Dimensi / Durasi"
          placeholder="e.g. 60×80 cm / 12 menit / 200 hlm"
        />
      </div>

      <.input
        field={@form[:creation_period]}
        type="text"
        label="Periode Penciptaan"
        placeholder="e.g. Januari – Maret 2024"
      />

      <.input
        field={@form[:artistic_statement]}
        type="textarea"
        label="Pernyataan Artistik"
        placeholder="Deskripsikan konsep, inspirasi, dan makna di balik karya ini…"
        rows={4}
      />

      <.input
        field={@form[:exhibition_performance]}
        type="text"
        label="Nama Pameran / Pertunjukan"
        placeholder="e.g. Festival Seni Nasional 2024"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:exhibition_venue]}
          type="text"
          label="Lokasi Venue"
          placeholder="e.g. Galeri Soemardja, Bandung"
        />
        <.input field={@form[:exhibition_date]} type="date" label="Tanggal Pameran / Pertunjukan" />
      </div>

      <.input
        field={@form[:collection_owner]}
        type="text"
        label="Pemilik Koleksi (jika relevan)"
        placeholder="e.g. Museum Nasional Indonesia"
      />
    </div>
    """
  end

  # ── Karya Teknologi ───────────────────────────────────────────────────────

  attr :form, :any, required: true

  def karya_teknologi_section(assigns) do
    assigns =
      assigns
      |> assign(:tech_type_opts, technology_type_options())
      |> assign(:impl_status_opts, implementation_status_options())
      |> assign(:license_opts, license_type_options())
      |> assign(:testing_opts, testing_method_options())
      |> assign(:patent_opts, patent_status_options())

    ~H"""
    <div id="type-section-karya-teknologi" class="kiroku-card p-6 space-y-4">
      <.section_header
        icon="hero-cpu-chip"
        title="Detail Karya Teknologi"
        subtitle="Informasi spesifik produk dan inovasi teknologi"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:technology_type]}
          type="select"
          label="Jenis Teknologi"
          prompt="Pilih jenis…"
          options={@tech_type_opts}
          class="kiroku-search-input w-full"
        />
        <.input
          field={@form[:implementation_status]}
          type="select"
          label="Status Implementasi"
          prompt="Pilih status…"
          options={@impl_status_opts}
          class="kiroku-search-input w-full"
        />
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:license_type]}
          type="select"
          label="Lisensi Perangkat Lunak"
          prompt="Pilih lisensi…"
          options={@license_opts}
          class="kiroku-search-input w-full"
        />
        <.input
          field={@form[:testing_method]}
          type="select"
          label="Metode Pengujian"
          prompt="Pilih metode…"
          options={@testing_opts}
          class="kiroku-search-input w-full"
        />
      </div>

      <.input
        field={@form[:problem_solved]}
        type="textarea"
        label="Masalah yang Diselesaikan"
        placeholder="Deskripsikan secara singkat masalah nyata yang diselesaikan oleh teknologi ini…"
        rows={3}
      />

      <.input
        field={@form[:target_user]}
        type="text"
        label="Target Pengguna"
        placeholder="e.g. Mahasiswa, Tenaga Kesehatan, UMKM"
      />

      <div
        class="space-y-3 p-4 rounded-xl"
        style="background: color-mix(in srgb, var(--color-patchouli) 8%, transparent); border: 1px solid color-mix(in srgb, var(--color-patchouli) 20%, transparent);"
      >
        <p class="text-xs font-semibold" style="color: var(--color-wisteria);">HKI / Paten</p>
        <.input
          field={@form[:patent_status]}
          type="select"
          label="Status Paten"
          prompt="Pilih status…"
          options={@patent_opts}
          class="kiroku-search-input w-full"
        />
        <.input
          field={@form[:hki_number]}
          type="text"
          label="Nomor HKI / Paten"
          placeholder="e.g. EC00202412345"
        />
      </div>

      <.input
        field={@form[:industry_tested_at]}
        type="text"
        label="Diuji / Diimplementasikan di"
        placeholder="e.g. PT. XYZ, RS. ABC, Dinas Pendidikan Kota Bandung"
      />
    </div>
    """
  end

  # ── Jurnal Nasional ───────────────────────────────────────────────────────

  attr :form, :any, required: true

  def jurnal_nasional_section(assigns) do
    assigns =
      assigns
      |> assign(:sinta_opts, sinta_options())
      |> assign(:peer_review_opts, peer_review_options())
      |> assign(:article_type_opts, article_type_options())

    ~H"""
    <div id="type-section-jurnal-nasional" class="kiroku-card p-6 space-y-4">
      <.section_header
        icon="hero-newspaper"
        title="Detail Jurnal Nasional"
        subtitle="Informasi spesifik artikel jurnal nasional terakreditasi"
      />

      <.input
        field={@form[:journal_name]}
        type="text"
        label="Nama Jurnal"
        placeholder="e.g. Jurnal Hukum Padjadjaran"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input field={@form[:issn]} type="text" label="ISSN (cetak)" placeholder="e.g. 2580-1279" />
        <.input
          field={@form[:eissn]}
          type="text"
          label="E-ISSN (elektronik)"
          placeholder="e.g. 2580-1287"
        />
      </div>

      <.input
        field={@form[:doi]}
        type="text"
        label="DOI"
        placeholder="e.g. 10.23920/jphk.v1i1.100"
      />

      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <.input field={@form[:volume]} type="text" label="Volume" placeholder="e.g. 12" />
        <.input field={@form[:issue]} type="text" label="Nomor" placeholder="e.g. 2" />
        <.input field={@form[:publication_year]} type="number" label="Tahun" placeholder="2024" />
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input field={@form[:page_start]} type="number" label="Halaman Awal" placeholder="e.g. 101" />
        <.input field={@form[:page_end]} type="number" label="Halaman Akhir" placeholder="e.g. 120" />
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:publisher]}
          type="text"
          label="Penerbit"
          placeholder="e.g. Universitas Padjadjaran"
        />
        <.input
          field={@form[:sinta_accreditation]}
          type="select"
          label="Akreditasi SINTA"
          prompt="Pilih akreditasi…"
          options={@sinta_opts}
          class="kiroku-search-input w-full"
        />
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:article_type]}
          type="select"
          label="Jenis Artikel"
          prompt="Pilih jenis…"
          options={@article_type_opts}
          class="kiroku-search-input w-full"
        />
        <.input
          field={@form[:peer_review_type]}
          type="select"
          label="Tipe Peer Review"
          prompt="Pilih tipe…"
          options={@peer_review_opts}
          class="kiroku-search-input w-full"
        />
      </div>
    </div>
    """
  end

  # ── Jurnal Internasional ──────────────────────────────────────────────────

  attr :form, :any, required: true

  def jurnal_internasional_section(assigns) do
    assigns =
      assigns
      |> assign(:peer_review_opts, peer_review_options())
      |> assign(:article_type_opts, article_type_options())
      |> assign(:quartile_opts, quartile_options())

    ~H"""
    <div id="type-section-jurnal-internasional" class="kiroku-card p-6 space-y-4">
      <.section_header
        icon="hero-globe-alt"
        title="Detail Jurnal Internasional"
        subtitle="Informasi spesifik artikel jurnal internasional"
      />

      <.input
        field={@form[:journal_name]}
        type="text"
        label="Journal Name"
        placeholder="e.g. International Journal of Law & Technology"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input field={@form[:issn]} type="text" label="ISSN (print)" placeholder="e.g. 1234-5678" />
        <.input
          field={@form[:eissn]}
          type="text"
          label="E-ISSN (online)"
          placeholder="e.g. 1234-5679"
        />
      </div>

      <.input
        field={@form[:doi]}
        type="text"
        label="DOI"
        placeholder="e.g. 10.1016/j.journal.2024.01.001"
      />

      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <.input field={@form[:volume]} type="text" label="Volume" placeholder="e.g. 24" />
        <.input field={@form[:issue]} type="text" label="Issue" placeholder="e.g. 3" />
        <.input field={@form[:publication_year]} type="number" label="Year" placeholder="2024" />
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input field={@form[:page_start]} type="number" label="Page Start" placeholder="e.g. 101" />
        <.input field={@form[:page_end]} type="number" label="Page End" placeholder="e.g. 120" />
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:publisher]}
          type="text"
          label="Publisher"
          placeholder="e.g. Elsevier, Springer, Wiley"
        />
        <.input
          field={@form[:quartile]}
          type="select"
          label="Quartile (SCImago / JCR)"
          prompt="Select quartile…"
          options={@quartile_opts}
          class="kiroku-search-input w-full"
        />
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:article_type]}
          type="select"
          label="Article Type"
          prompt="Select type…"
          options={@article_type_opts}
          class="kiroku-search-input w-full"
        />
        <.input
          field={@form[:peer_review_type]}
          type="select"
          label="Peer Review Type"
          prompt="Select…"
          options={@peer_review_opts}
          class="kiroku-search-input w-full"
        />
      </div>

      <div
        class="flex flex-wrap gap-4 p-4 rounded-xl"
        style="background: color-mix(in srgb, var(--color-patchouli) 8%, transparent); border: 1px solid color-mix(in srgb, var(--color-patchouli) 20%, transparent);"
      >
        <p class="w-full text-xs font-semibold" style="color: var(--color-wisteria);">Indexing</p>
        <.input field={@form[:scopus_indexed]} type="checkbox" label="Terindeks Scopus" />
        <.input field={@form[:wos_indexed]} type="checkbox" label="Terindeks Web of Science (WoS)" />
      </div>
    </div>
    """
  end

  # ── Prosiding ─────────────────────────────────────────────────────────────

  attr :form, :any, required: true

  def prosiding_section(assigns) do
    ~H"""
    <div id="type-section-prosiding" class="kiroku-card p-6 space-y-4">
      <.section_header
        icon="hero-presentation-chart-bar"
        title="Detail Prosiding Konferensi"
        subtitle="Informasi spesifik konferensi dan publikasi prosiding"
      />

      <.input
        field={@form[:conference_name]}
        type="text"
        label="Nama Konferensi"
        placeholder="e.g. International Conference on Law & Technology 2024"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:conference_location]}
          type="text"
          label="Lokasi Konferensi"
          placeholder="e.g. Bandung, Indonesia"
        />
        <.input
          field={@form[:conference_date]}
          type="text"
          label="Tanggal Konferensi"
          placeholder="e.g. 12–14 Maret 2024"
        />
      </div>

      <.input
        field={@form[:doi]}
        type="text"
        label="DOI Artikel"
        placeholder="e.g. 10.1234/conf.2024.001"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:isbn]}
          type="text"
          label="ISBN Prosiding"
          placeholder="e.g. 978-602-1234-56-7"
        />
        <.input
          field={@form[:publisher]}
          type="text"
          label="Penerbit Prosiding"
          placeholder="e.g. IEEE, ACM, Unpad Press"
        />
      </div>

      <.input
        field={@form[:best_paper_award]}
        type="text"
        label="Penghargaan Best Paper (jika ada)"
        placeholder="e.g. Best Paper Award — Track Hukum Pidana"
      />
    </div>
    """
  end

  # ── Capstone / Tugas Akhir ────────────────────────────────────────────────

  attr :form, :any, required: true

  def capstone_section(assigns) do
    assigns =
      assigns
      |> assign(:mbkm_opts, mbkm_scheme_options())
      |> assign(:project_type_opts, project_type_options())
      |> assign(:team_role_opts, team_role_options())

    ~H"""
    <div id="type-section-capstone" class="kiroku-card p-6 space-y-4">
      <.section_header
        icon="hero-flag"
        title="Detail Capstone / Tugas Akhir"
        subtitle="Informasi proyek akhir studi dan skema MBKM"
      />

      <.input
        field={@form[:capstone_theme]}
        type="text"
        label="Tema Capstone"
        placeholder="e.g. Smart City, Kesehatan Digital, SDGs, Ketahanan Pangan"
      />

      <.input
        field={@form[:capstone_partner]}
        type="text"
        label="Mitra Capstone"
        placeholder="e.g. PT. XYZ, Pemerintah Kota Bandung"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:mbkm_scheme]}
          type="select"
          label="Skema MBKM (jika berlaku)"
          prompt="Pilih skema…"
          options={@mbkm_opts}
          class="kiroku-search-input w-full"
        />
        <.input
          field={@form[:project_type]}
          type="select"
          label="Jenis Proyek"
          prompt="Pilih jenis…"
          options={@project_type_opts}
          class="kiroku-search-input w-full"
        />
      </div>

      <.input
        field={@form[:partner_institution]}
        type="text"
        label="Institusi Mitra"
        placeholder="e.g. Kementerian Pendidikan, Dinas Sosial Kota Bandung"
      />

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <.input
          field={@form[:project_period]}
          type="text"
          label="Periode Proyek"
          placeholder="e.g. Feb – Juli 2024"
        />
        <.input
          field={@form[:project_location]}
          type="text"
          label="Lokasi Proyek"
          placeholder="e.g. Jakarta Selatan"
        />
      </div>

      <.input
        field={@form[:team_role]}
        type="select"
        label="Peran dalam Tim"
        prompt="Pilih peran…"
        options={@team_role_opts}
        class="kiroku-search-input w-full"
      />

      <.input
        field={@form[:problem_statement]}
        type="textarea"
        label="Rumusan Masalah"
        placeholder="Deskripsikan permasalahan yang diselesaikan dalam proyek capstone ini…"
        rows={3}
      />

      <.input
        field={@form[:solution_description]}
        type="textarea"
        label="Solusi / Hasil Capstone"
        placeholder="Deskripsikan solusi, luaran, atau dampak yang dihasilkan…"
        rows={3}
      />
    </div>
    """
  end
end

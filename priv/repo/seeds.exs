# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Credentials can be overridden via environment variables:
#
#     ADMIN_EMAIL=admin@example.com ADMIN_PASSWORD=secret123456 mix run priv/repo/seeds.exs

# import Ecto.Changeset
# alias Kiroku.Accounts.User
# alias Kiroku.Repo
alias Kiroku.Settings

# ── Admin seed ────────────────────────────────────────────────────────────────

# admin_email = System.get_env("ADMIN_EMAIL", "admin@kiroku.local")
# admin_password = System.get_env("ADMIN_PASSWORD", "kiroku_admin_2025!")
# admin_name = System.get_env("ADMIN_NAME", "Administrator")

# case Repo.get_by(User, email: admin_email) do
#   %User{} ->
#     IO.puts("  [seeds] Admin user #{admin_email} already exists, skipping.")

#   nil ->
#     now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

#     %User{}
#     |> User.registration_changeset(%{
#       email: admin_email,
#       password: admin_password,
#       display_name: admin_name
#     })
#     |> put_change(:user_type, :superadmin)
#     |> put_change(:confirmed_at, now)
#     |> Repo.insert!()

#     IO.puts("  [seeds] Created admin user: #{admin_email}")
#     IO.puts("  [seeds] Password: #{admin_password}")
#     IO.puts("  [seeds] Change this password immediately after first login!")
# end

setting_defaults = [
  {"allow_user_submit", "false", "Let the user submit an item to the repository"},
  # Fresh installs must trigger the first-run wizard. Seeding "false" keeps the
  # row present (with its description) while still leaving setup incomplete until
  # the wizard runs `Settings.mark_setup_complete/0`.
  {"setup_complete", "false", "Whether the first-run onboarding wizard has been completed"}
]

Enum.each(setting_defaults, fn {key, value, description} ->
  case Settings.get(key) do
    nil ->
      if value do
        Settings.put(key, value, description)
        IO.puts("  [seeds] Set default setting: #{key} = #{value}")
      else
        IO.puts("  [seeds] Skipped default setting: #{key} (no default value)")
      end

    _existing ->
      IO.puts("  [seeds] Default setting #{key} already exists, skipping")
  end
end)

# ── Brand settings seed ────────────────────────────────────────────────────

brand_defaults = [
  {"brand_name", "Kiroku", "Display name of the repository shown site-wide"},
  {"brand_tagline", "Every work recorded. Every scholar remembered.",
   "Short tagline shown on the homepage hero"},
  {"brand_description",
   "The institutional repository for scholarly works — theses, legal memoranda, creative works, and research by the academic community.",
   "Longer description shown on the homepage hero"},
  {"brand_contact_email", "curatorian@proton.me", "Public contact e-mail address"},
  {"brand_contact_phone", "08123456789", "Public contact phone number"},
  {"brand_logo_url", nil, "URL of the brand logo image (nil = use text wordmark)"},
  {"brand_primary_color", "#7B4FA6",
   "Primary brand colour (hex) — overrides the default Patchouli violet"}
]

Enum.each(brand_defaults, fn {key, value, description} ->
  case Settings.get(key) do
    nil ->
      if value do
        Settings.put(key, value, description)
        IO.puts("  [seeds] Set brand setting: #{key} = #{value}")
      else
        IO.puts("  [seeds] Skipped brand setting: #{key} (no default value)")
      end

    _existing ->
      IO.puts("  [seeds] Brand setting #{key} already exists, skipping.")
  end
end)

# ── Repository handle prefix seed ───────────────────────────────────────────

case Settings.get("handle_prefix") do
  nil ->
    Settings.put(
      "handle_prefix",
      "kandaga",
      "Prefix for DSpace-style handles (e.g. kandaga/12345)"
    )

    IO.puts("  [seeds] Set handle_prefix = kandaga")

  existing ->
    IO.puts("  [seeds] handle_prefix already set: #{existing}, skipping")
end

defmodule KirokuWeb.UserRegistrationLive do
  use KirokuWeb, :live_view

  alias Kiroku.Accounts
  alias Kiroku.Accounts.User

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={assigns[:current_user]}>
      <div class="max-w-md mx-auto mt-16">
        <div class="kiroku-card p-8 space-y-6">
          <div class="text-center space-y-1">
            <span class="kiroku-kanji text-4xl">記</span>
            <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">Create Account</h1>
            <p class="text-sm" style="color: var(--color-quill);">Join the Kiroku Repository</p>
          </div>

          <.form
            for={@form}
            id="registration-form"
            phx-submit="save"
            phx-change="validate"
            class="space-y-4"
          >
            <.input
              field={@form[:email]}
              type="email"
              label="Email"
              required
              autocomplete="email"
              phx-debounce="blur"
            />
            <.input field={@form[:display_name]} type="text" label="Full Name" />
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              required
              autocomplete="new-password"
              phx-debounce="blur"
            />
            <button
              type="submit"
              class="w-full py-2.5 rounded-lg font-semibold text-sm transition-colors"
              style="background: var(--color-patchouli); color: white;"
            >
              Register
            </button>
          </.form>

          <p class="text-center text-sm" style="color: var(--color-quill);">
            Already have an account?
            <.link
              href={~p"/users/log_in"}
              class="hover:text-white transition-colors"
              style="color: var(--color-lavender);"
            >
              Sign in
            </.link>
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    if Kiroku.Settings.allow_registration?() do
      changeset = Accounts.change_user_registration(%User{})
      {:ok, assign(socket, form: to_form(changeset, as: :user))}
    else
      {:ok,
       socket
       |> put_flash(:error, "Self-registration is disabled. Please sign in with PAuS.")
       |> push_navigate(to: ~p"/users/log_in")}
    end
  end

  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      %User{}
      |> Accounts.change_user_registration(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :user))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    if not Kiroku.Settings.allow_registration?() do
      {:noreply,
       socket
       |> put_flash(:error, "Self-registration is disabled.")
       |> push_navigate(to: ~p"/users/log_in")}
    else
      case Accounts.register_user(params) do
        {:ok, user} ->
          {:ok, _} =
            Accounts.deliver_user_confirmation_instructions(
              user,
              &url(~p"/users/confirm/#{&1}")
            )

          {:noreply,
           socket
           |> put_flash(
             :info,
             "Akun berhasil dibuat. Silakan periksa email Anda untuk konfirmasi."
           )
           |> redirect(to: ~p"/users/log_in")}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(changeset, as: :user))}
      end
    end
  end
end

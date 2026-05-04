defmodule KirokuWeb.UserResetPasswordLive do
  use KirokuWeb, :live_view

  alias Kiroku.Accounts

  def render(%{live_action: :new} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={assigns[:current_user]}>
      <div class="max-w-md mx-auto mt-16">
        <div class="kiroku-card p-8 space-y-6">
          <div class="text-center">
            <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">Reset Password</h1>
            <p class="text-sm mt-1" style="color: var(--color-quill);">
              Enter your email and we'll send reset instructions.
            </p>
          </div>
          <.form for={@form} id="reset-password-form" phx-submit="request_reset" class="space-y-4">
            <.input field={@form[:email]} type="email" label="Email" required />
            <button
              type="submit"
              class="w-full py-2.5 rounded-lg font-semibold text-sm"
              style="background: var(--color-patchouli); color: white;"
            >
              Send Reset Instructions
            </button>
          </.form>
          <p class="text-center text-sm">
            <.link
              href={~p"/users/log_in"}
              class="transition-colors hover:text-white"
              style="color: var(--color-lavender);"
            >
              Back to Sign In
            </.link>
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def render(%{live_action: :edit} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={assigns[:current_user]}>
      <div class="max-w-md mx-auto mt-16">
        <div class="kiroku-card p-8 space-y-6">
          <div class="text-center">
            <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">Set New Password</h1>
          </div>
          <.form
            for={@form}
            id="reset-password-edit-form"
            phx-submit="reset_password"
            phx-change="validate"
            class="space-y-4"
          >
            <.input
              field={@form[:password]}
              type="password"
              label="New Password"
              required
              autocomplete="new-password"
            />
            <.input
              field={@form[:password_confirmation]}
              type="password"
              label="Confirm Password"
              required
              autocomplete="new-password"
            />
            <button
              type="submit"
              class="w-full py-2.5 rounded-lg font-semibold text-sm"
              style="background: var(--color-patchouli); color: white;"
            >
              Reset Password
            </button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def mount(params, _session, socket) do
    socket =
      case socket.assigns.live_action do
        :new ->
          assign(socket, form: to_form(%{}, as: :user))

        :edit ->
          with token when not is_nil(token) <- params["token"],
               user when not is_nil(user) <- Accounts.get_user_by_reset_password_token(token) do
            changeset = Accounts.change_user_registration(user)
            assign(socket, form: to_form(changeset, as: :user), user: user, token: token)
          else
            _ ->
              socket
              |> put_flash(:error, "Tautan reset kata sandi tidak valid atau sudah kadaluarsa.")
              |> redirect(to: ~p"/users/reset_password")
          end
      end

    {:ok, socket}
  end

  def handle_event("request_reset", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset_password/#{&1}")
      )
    end

    {:noreply,
     socket
     |> put_flash(:info, "Jika email terdaftar, instruksi reset kata sandi telah dikirimkan.")
     |> redirect(to: ~p"/users/log_in")}
  end

  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user_registration(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :user))}
  end

  def handle_event("reset_password", %{"user" => params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Kata sandi berhasil diperbarui.")
         |> redirect(to: ~p"/users/log_in")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :user))}
    end
  end
end

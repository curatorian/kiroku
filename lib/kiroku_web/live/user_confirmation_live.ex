defmodule KirokuWeb.UserConfirmationLive do
  use KirokuWeb, :live_view

  alias Kiroku.Accounts

  def render(%{live_action: :new} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="max-w-md mx-auto mt-16">
        <div class="kiroku-card p-8 space-y-6 text-center">
          <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">
            Confirm Your Account
          </h1>
          <p class="text-sm" style="color: var(--color-quill);">
            Didn't receive a confirmation email? Request a new one.
          </p>
          <.form
            for={@form}
            id="resend-confirmation-form"
            phx-submit="resend"
            class="space-y-4 text-left"
          >
            <.input field={@form[:email]} type="email" label="Email" required />
            <button
              type="submit"
              class="w-full py-2.5 rounded-lg font-semibold text-sm"
              style="background: var(--color-patchouli); color: white;"
            >
              Resend Confirmation
            </button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def render(%{live_action: :edit} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="max-w-md mx-auto mt-16">
        <div class="kiroku-card p-8 space-y-6 text-center">
          <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">Confirm Account</h1>
          <p class="text-sm" style="color: var(--color-quill);">
            Click the button to confirm your account.
          </p>
          <button
            phx-click="confirm"
            phx-value-token={@token}
            class="w-full py-2.5 rounded-lg font-semibold text-sm"
            style="background: var(--color-patchouli); color: white;"
          >
            Confirm Account
          </button>
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
          assign(socket, token: params["token"])
      end

    {:ok, socket}
  end

  def handle_event("resend", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(
        user,
        &url(~p"/users/confirm/#{&1}")
      )
    end

    {:noreply,
     socket
     |> put_flash(
       :info,
       "Jika email terdaftar dan belum dikonfirmasi, email konfirmasi telah dikirimkan."
     )
     |> redirect(to: ~p"/")}
  end

  def handle_event("confirm", %{"token" => token}, socket) do
    case Accounts.confirm_user(token) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Akun berhasil dikonfirmasi.")
         |> redirect(to: ~p"/")}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "Tautan konfirmasi tidak valid atau sudah kadaluarsa.")
         |> redirect(to: ~p"/")}
    end
  end
end

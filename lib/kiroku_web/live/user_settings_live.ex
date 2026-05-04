defmodule KirokuWeb.UserSettingsLive do
  use KirokuWeb, :live_view

  alias Kiroku.Accounts

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_user}>
      <div class="max-w-2xl mx-auto space-y-8">
        <h1 class="font-heading text-3xl" style="color: var(--color-lilac);">Account Settings</h1>

        <%!-- Change email --%>
        <div class="kiroku-card p-6 space-y-4">
          <h2 class="font-heading text-xl" style="color: var(--color-lilac);">Change Email</h2>
          <.form
            for={@email_form}
            id="email-form"
            phx-submit="update_email"
            phx-change="validate_email"
            class="space-y-4"
          >
            <.input field={@email_form[:email]} type="email" label="New Email" required />
            <.input
              field={@email_form[:current_password]}
              name="current_password"
              type="password"
              label="Current Password"
              required
              value={@email_form_current_password}
            />
            <button
              type="submit"
              class="px-5 py-2 rounded-lg font-medium text-sm"
              style="background: var(--color-patchouli); color: white;"
            >
              Update Email
            </button>
          </.form>
        </div>

        <%!-- Change password --%>
        <div class="kiroku-card p-6 space-y-4">
          <h2 class="font-heading text-xl" style="color: var(--color-lilac);">Change Password</h2>
          <.form
            for={@password_form}
            id="password-form"
            phx-submit="update_password"
            phx-change="validate_password"
            class="space-y-4"
          >
            <.input
              field={@password_form[:current_password]}
              name="current_password"
              type="password"
              label="Current Password"
              required
              value={@password_form_current_password}
            />
            <.input
              field={@password_form[:password]}
              type="password"
              label="New Password"
              required
              autocomplete="new-password"
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              label="Confirm New Password"
              required
              autocomplete="new-password"
            />
            <button
              type="submit"
              class="px-5 py-2 rounded-lg font-medium text-sm"
              style="background: var(--color-patchouli); color: white;"
            >
              Update Password
            </button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def mount(params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      case socket.assigns.live_action do
        :confirm_email ->
          token = params["token"]

          case Accounts.update_user_email(user, token) do
            :ok ->
              socket |> put_flash(:info, "Email berhasil diperbarui.")

            :error ->
              socket
              |> put_flash(:error, "Tautan konfirmasi email tidak valid atau sudah kadaluarsa.")
          end

        _ ->
          socket
      end

    email_changeset = Accounts.change_user_registration(user)
    password_changeset = Accounts.change_user_registration(user)

    {:ok,
     socket
     |> assign(:email_form_current_password, nil)
     |> assign(:password_form_current_password, nil)
     |> assign(:email_form, to_form(email_changeset, as: :user))
     |> assign(:password_form, to_form(password_changeset, as: :user))}
  end

  def handle_event(
        "validate_email",
        %{"user" => params, "current_password" => current_password},
        socket
      ) do
    user = socket.assigns.current_user

    changeset =
      user
      |> Accounts.change_user_registration(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:email_form_current_password, current_password)
     |> assign(:email_form, to_form(changeset, as: :user))}
  end

  def handle_event(
        "update_email",
        %{"user" => user_params, "current_password" => current_password},
        socket
      ) do
    user = socket.assigns.current_user

    case Accounts.apply_user_email(user, current_password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_user_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/users/settings/confirm_email/#{&1}")
        )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Konfirmasi perubahan email telah dikirimkan ke alamat email baru Anda."
         )
         |> assign(:email_form_current_password, nil)}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:email_form_current_password, current_password)
         |> assign(:email_form, to_form(Map.put(changeset, :action, :insert), as: :user))}
    end
  end

  def handle_event(
        "validate_password",
        %{"user" => params, "current_password" => current_password},
        socket
      ) do
    user = socket.assigns.current_user

    changeset =
      user
      |> Accounts.change_user_registration(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:password_form_current_password, current_password)
     |> assign(:password_form, to_form(changeset, as: :user))}
  end

  def handle_event(
        "update_password",
        %{"user" => user_params, "current_password" => current_password},
        socket
      ) do
    user = socket.assigns.current_user

    case Accounts.get_user_by_email_and_password(user.email, current_password) do
      nil ->
        changeset =
          user
          |> Accounts.change_user_registration(user_params)
          |> Ecto.Changeset.add_error(:current_password, "tidak valid")
          |> Map.put(:action, :validate)

        {:noreply,
         socket
         |> assign(:password_form_current_password, current_password)
         |> assign(:password_form, to_form(changeset, as: :user))}

      _authenticated ->
        case Accounts.reset_user_password(user, user_params) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Kata sandi berhasil diperbarui. Silakan masuk kembali.")
             |> redirect(to: ~p"/users/log_in")}

          {:error, changeset} ->
            {:noreply, assign(socket, :password_form, to_form(changeset, as: :user))}
        end
    end
  end
end

defmodule KirokuWeb.UserSessionLive do
  use KirokuWeb, :live_view

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={assigns[:current_user]}>
      <div class="max-w-md mx-auto mt-16">
        <div class="kiroku-card p-8 space-y-6">
          <div class="text-center space-y-1">
            <span class="kiroku-kanji text-4xl">記</span>
            <h1 class="font-heading text-2xl" style="color: var(--color-lilac);">Sign In</h1>
            <p class="text-sm" style="color: var(--color-quill);">Kiroku Institutional Repository</p>
          </div>

          <.form
            for={@form}
            id="login-form"
            action={~p"/users/log_in"}
            method="post"
            class="space-y-4"
          >
            <.input field={@form[:email]} type="email" label="Email" required autocomplete="email" />
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              required
              autocomplete="current-password"
            />
            <div class="flex items-center justify-between">
              <label
                class="flex items-center gap-2 text-sm cursor-pointer"
                style="color: var(--color-quill);"
              >
                <input
                  type="checkbox"
                  name="user[remember_me]"
                  value="true"
                  style="accent-color: var(--color-patchouli);"
                /> Remember me
              </label>
              <.link
                href={~p"/users/reset_password"}
                class="text-sm transition-colors hover:text-white"
                style="color: var(--color-lavender);"
              >
                Forgot password?
              </.link>
            </div>
            <button
              type="submit"
              class="w-full py-2.5 rounded-lg font-semibold text-sm transition-colors"
              style="background: var(--color-patchouli); color: white;"
            >
              Sign In
            </button>
          </.form>

          <.link
            href="/auth/paus"
            class="w-full inline-flex items-center justify-center rounded-lg border border-white/10 bg-white/5 py-2.5 text-sm font-semibold transition hover:bg-white/10"
            style="color: var(--color-lavender);"
          >
            Sign in with PAuS
          </.link>

          <p class="text-center text-sm" style="color: var(--color-quill);">
            Don't have an account?
            <.link
              href={~p"/users/register"}
              class="hover:text-white transition-colors"
              style="color: var(--color-lavender);"
            >
              Register
            </.link>
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    form = to_form(%{}, as: :user)
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end

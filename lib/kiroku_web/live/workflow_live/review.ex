defmodule KirokuWeb.WorkflowLive.Review do
  @moduledoc "Review queued submissions awaiting approval."
  use KirokuWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-4xl mx-auto py-8">
        <h1 class="text-2xl font-bold">Workflow Review</h1>
        <p class="text-zinc-500 mt-2">Not yet implemented.</p>
      </div>
    </Layouts.app>
    """
  end
end

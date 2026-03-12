defmodule KirokuWeb.ItemLive.ShowFull do
  @moduledoc "Display a single item's full metadata view."
  use KirokuWeb, :live_view

  @impl true
  def mount(%{"id" => _id}, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto py-8">
        <h1 class="text-2xl font-bold">Item Full Metadata</h1>
        <p class="text-zinc-500 mt-2">Not yet implemented.</p>
      </div>
    </Layouts.app>
    """
  end
end

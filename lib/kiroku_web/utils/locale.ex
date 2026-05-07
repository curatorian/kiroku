defmodule KirokuWeb.Utils.Locale do
  @moduledoc "Supported locales metadata."

  @locales [
    %{code: "id", name: "Bahasa Indonesia", flag: "🇮🇩"},
    %{code: "en", name: "English", flag: "🇬🇧"}
  ]

  def all_locales, do: @locales

  def locale_name(code) do
    case Enum.find(@locales, &(&1.code == code)) do
      nil -> code
      locale -> locale.name
    end
  end

  def flag(code) do
    case Enum.find(@locales, &(&1.code == code)) do
      nil -> "🌐"
      locale -> locale.flag
    end
  end
end

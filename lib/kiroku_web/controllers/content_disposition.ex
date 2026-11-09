defmodule KirokuWeb.ContentDisposition do
  @moduledoc """
  Builds RFC 6266 `Content-Disposition` header values that survive
  non-ASCII (non-Latin script) filenames.

  Pure-ASCII names use the simple quoted form. Non-ASCII names send both an
  ASCII fallback (`filename=`) and the RFC 5987 encoding
  (`filename*=UTF-8''…`, percent-encoded), so browsers and download managers
  get the real name while the header value itself stays ASCII-only — raw
  UTF-8 bytes in a header are invalid per RFC 7230 and get mangled or
  rejected by clients.
  """

  @spec header(String.t(), String.t()) :: String.t()
  def header(disposition, filename) do
    filename = normalize(filename)

    if ascii_printable?(filename) do
      ~s(#{disposition}; filename="#{filename}")
    else
      ~s(#{disposition}; filename="#{ascii_fallback(filename)}"; filename*=UTF-8''#{rfc5987(filename)})
    end
  end

  # The simple quoted form must never contain quotes, backslashes, or control
  # characters — any of those breaks the quoted-string (a CRLF would even be
  # header injection).
  defp normalize(filename) do
    String.replace(filename, ~r/[\x00-\x1F\x7F"\\]/, "'")
  end

  defp ascii_printable?(filename), do: filename =~ ~r/^[\x20-\x7E]*$/

  defp ascii_fallback(filename) do
    # /u = character mode, not byte mode — one underscore per non-ASCII
    # character keeps the fallback length aligned with the real name.
    String.replace(filename, ~r/[^\x20-\x7E]/u, "_")
  end

  defp rfc5987(filename), do: URI.encode(filename, &URI.char_unreserved?/1)
end

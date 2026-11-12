defmodule Taamol.Markdown do
  @moduledoc """
  Renders article Markdown to safe HTML (GitHub-flavoured: tables,
  strikethrough, autolinks, task lists). Raw HTML and unsafe URLs such as
  `javascript:` are stripped by the sanitizer.
  """

  @options [
    extension: [strikethrough: true, table: true, autolink: true, tasklist: true],
    parse: [smart: true],
    render: [unsafe: false],
    sanitize: MDEx.Document.default_sanitize_options()
  ]

  @doc "Markdown to sanitized HTML (a string)."
  def to_html(nil), do: ""
  def to_html(""), do: ""

  def to_html(markdown) when is_binary(markdown) do
    case MDEx.to_html(markdown, @options) do
      {:ok, html} -> html
      {:error, _} -> ""
    end
  end
end

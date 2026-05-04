defmodule Kiroku.Workers.ReviewNotifier do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Kiroku.{Repo, Repository}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_id" => item_id, "event" => event}}) do
    item =
      Repository.get_item!(item_id)
      |> Repo.preload(:submitter)

    case event do
      "approved" -> notify_approved(item)
      "rejected" -> notify_rejected(item)
      "revision_requested" -> notify_revision_requested(item)
      "submitted" -> notify_submitted(item)
      _ -> :ok
    end
  end

  defp notify_approved(item) do
    if item.submitter && item.submitter.email do
      Swoosh.Email.new()
      |> Swoosh.Email.to(
        {item.submitter.display_name || item.submitter.email, item.submitter.email}
      )
      |> Swoosh.Email.from({"Kiroku Repository", mailer_from()})
      |> Swoosh.Email.subject("Your submission has been approved — #{item.title}")
      |> Swoosh.Email.text_body("""
      Dear #{item.submitter.display_name || "Submitter"},

      Your submission "#{item.title}" has been approved and published to the repository.

      You may view it at: #{base_url()}/items/#{item.id}

      — Kiroku Repository
      """)
      |> Kiroku.Mailer.deliver()
    end

    :ok
  end

  defp notify_rejected(item) do
    if item.submitter && item.submitter.email do
      Swoosh.Email.new()
      |> Swoosh.Email.to(
        {item.submitter.display_name || item.submitter.email, item.submitter.email}
      )
      |> Swoosh.Email.from({"Kiroku Repository", mailer_from()})
      |> Swoosh.Email.subject("Your submission was not accepted — #{item.title}")
      |> Swoosh.Email.text_body("""
      Dear #{item.submitter.display_name || "Submitter"},

      Your submission "#{item.title}" was not accepted.

      #{if item.review_note, do: "Reviewer note: #{item.review_note}\n", else: ""}
      If you have questions, please contact the repository administrator.

      — Kiroku Repository
      """)
      |> Kiroku.Mailer.deliver()
    end

    :ok
  end

  defp notify_revision_requested(item) do
    if item.submitter && item.submitter.email do
      Swoosh.Email.new()
      |> Swoosh.Email.to(
        {item.submitter.display_name || item.submitter.email, item.submitter.email}
      )
      |> Swoosh.Email.from({"Kiroku Repository", mailer_from()})
      |> Swoosh.Email.subject("Revisions requested for your submission — #{item.title}")
      |> Swoosh.Email.text_body("""
      Dear #{item.submitter.display_name || "Submitter"},

      The reviewer has requested revisions to your submission "#{item.title}".

      #{if item.review_note, do: "Reviewer note: #{item.review_note}\n", else: ""}
      Please log in to #{base_url()}/my/items and resubmit after making the requested changes.

      — Kiroku Repository
      """)
      |> Kiroku.Mailer.deliver()
    end

    :ok
  end

  defp notify_submitted(item) do
    # Notify admin users about new submission
    Kiroku.Accounts.list_admins()
    |> Enum.each(fn admin ->
      Swoosh.Email.new()
      |> Swoosh.Email.to({admin.display_name || admin.email, admin.email})
      |> Swoosh.Email.from({"Kiroku Repository", mailer_from()})
      |> Swoosh.Email.subject("New submission awaiting review — #{item.title}")
      |> Swoosh.Email.text_body("""
      A new submission is awaiting review.

      Title: #{item.title}
      Submitted by: #{item.submitter && (item.submitter.display_name || item.submitter.email)}

      Review at: #{base_url()}/admin/items/#{item.id}/review

      — Kiroku Repository
      """)
      |> Kiroku.Mailer.deliver()
    end)

    :ok
  end

  defp mailer_from do
    domain = Application.get_env(:kiroku, :institution_domain, "kiroku.example.com")
    "no-reply@#{domain}"
  end

  defp base_url do
    host = Application.get_env(:kiroku, KirokuWeb.Endpoint)[:url][:host] || "localhost"
    "https://#{host}"
  end
end

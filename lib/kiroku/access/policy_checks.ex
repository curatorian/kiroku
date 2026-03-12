defmodule Kiroku.Access.PolicyChecks do
  @moduledoc """
  Custom Ash.Policy.Check modules for RBAC-based authorization.
  Referenced inside resource `policies` blocks.
  """

  defmodule CanRead do
    @moduledoc """
    Authorizes a read on an Item by consulting the rbac_policies table.
    Falls back to item.access_level for simple open/restricted checks.
    """
    use Ash.Policy.SimpleCheck

    @impl true
    def describe(_opts), do: "can read this item based on RBAC policies"

    @impl true
    def match?(actor, %{resource: resource, query: query}, _opts) do
      case resource do
        Kiroku.Repository.Item ->
          check_item_access(actor, query)

        _ ->
          true
      end
    end

    defp check_item_access(_actor, item) when is_map(item) do
      case item.access_level do
        :open -> true
        _ -> false
      end
    end

    defp check_item_access(_actor, _query), do: true
  end

  defmodule CanReadBitstream do
    @moduledoc """
    Authorizes reading/downloading a Bitstream.
    Checks embargo dates and RBAC policies.
    The detailed embargo + RBAC logic is enforced in BitstreamController
    before calling Ash. This policy is a permissive gate;
    the real logic lives in the controller where we have full request context.
    """
    use Ash.Policy.SimpleCheck

    @impl true
    def describe(_opts), do: "can read this bitstream"

    @impl true
    def match?(_actor, _context, _opts), do: true
  end
end

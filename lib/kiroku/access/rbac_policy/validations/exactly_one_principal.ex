defmodule Kiroku.Access.RbacPolicy.Validations.ExactlyOnePrincipal do
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    group_id = Ash.Changeset.get_attribute(changeset, :group_id)
    user_id = Ash.Changeset.get_attribute(changeset, :user_id)

    cond do
      is_nil(group_id) and is_nil(user_id) ->
        {:error, field: :group_id, message: "either group_id or user_id is required"}

      not is_nil(group_id) and not is_nil(user_id) ->
        {:error, field: :group_id, message: "cannot set both group_id and user_id"}

      true ->
        :ok
    end
  end
end

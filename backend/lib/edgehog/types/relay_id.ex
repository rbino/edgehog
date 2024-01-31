defmodule Edgehog.Types.RelayId do
  use Ash.Type.NewType, subtype_of: :integer
  use AshGraphql.Type

  @impl true
  def graphql_input_type(_), do: :id
end

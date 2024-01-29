defmodule Edgehog.Types.RelayId do
  use Ash.Type
  use AshGraphql.Type

  @constraints [
    type: [
      type: :atom,
      doc: "The GraphQL type of the resource",
      required: true
    ]
  ]

  @impl true
  def graphql_input_type(_), do: :id

  @impl true
  def storage_type(_), do: :integer

  @impl true
  def constraints, do: @constraints

  @impl true
  def cast_input(nil, _), do: {:ok, nil}
  def cast_input(value, _) when is_integer(value), do: {:ok, value}

  def cast_input(value, constraints) when is_binary(value) do
    # Strong assumption: if it's a binary, and it contains at least a letter, it's a global relay ID
    if String.match?(value, ~r/[:alpha]/) do
      type = constraints[:type]

      case AshGraphql.Resource.decode_relay_id(value) do
        {:ok, %{type: ^type, id: id}} ->
          Ecto.Type.cast(:integer, id)

        {:ok, _} ->
          {:error, "invalid id for type #{type}"}

        {:error, _reason} = error ->
          error
      end
    else
      Ecto.Type.cast(:integer, value)
    end
  end

  @impl true
  def cast_stored(nil, _), do: {:ok, nil}
  def cast_stored(value, _), do: Ecto.Type.load(:integer, value)

  @impl true
  def dump_to_native(nil, _), do: {:ok, nil}
  def dump_to_native(value, _), do: Ecto.Type.dump(:integer, value)
end

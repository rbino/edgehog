defmodule Edgehog.Repo.Migrations.AddPublicKeyToTenants do
  use Ecto.Migration

  def change do
    alter table(:tenants) do
      add :public_key, :text, null: false
    end
  end
end

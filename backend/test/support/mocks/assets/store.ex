#
# This file is part of Edgehog.
#
# Copyright 2021 SECO Mind Srl
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

alias Ecto.Changeset
alias Edgehog.Appliances.ApplianceModel
alias Edgehog.Repo

defmodule Edgehog.Mocks.Assets.Store do
  @behaviour Edgehog.Assets.Store.Behaviour

  @bucket_url "https://sample-storage.com/bucket"

  @impl true
  def cast_asset_upload(%ApplianceModel{} = ecto_schema, :picture_url, %Plug.Upload{} = upload) do
    changeset = Changeset.change(ecto_schema)
    tenant_id = Repo.get_tenant_id()

    file_name =
      "tenants/#{tenant_id}/appliance_models/#{ecto_schema.handle}/picture/#{upload.filename}"

    file_url = "#{@bucket_url}/#{file_name}"
    Changeset.put_change(changeset, :picture_url, file_url)
  end

  @impl true
  def cast_asset_upload(ecto_schema, dest_key, nil) do
    Changeset.change(ecto_schema, %{dest_key => nil})
  end

  @impl true
  def cast_asset_deletion(ecto_schema, schema_key) do
    Changeset.change(ecto_schema, %{schema_key => nil})
  end
end

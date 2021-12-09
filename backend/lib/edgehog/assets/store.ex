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
alias Edgehog.Assets.Uploaders.ApplianceModelPicture

defmodule Edgehog.Assets.Store do
  def cast_asset_upload(ecto_schema, schema_key, upload) do
    storage_enabled? = Application.get_env(:edgehog, :enable_s3_storage?, false)

    if storage_enabled? do
      upload(ecto_schema, schema_key, upload)
    else
      # Return an empty changeset
      Changeset.change(ecto_schema)
    end
  end

  def cast_asset_deletion(ecto_schema, schema_key) do
    storage_enabled? = Application.get_env(:edgehog, :enable_s3_storage?, false)

    if storage_enabled? do
      delete(ecto_schema, schema_key)
    else
      # Return an empty changeset
      Changeset.change(ecto_schema)
    end
  end

  defp upload(%ApplianceModel{} = ecto_schema, :picture_url, nil) do
    # A specified nil value means to delete the picture
    Changeset.change(ecto_schema, %{picture_url: nil})
  end

  defp upload(
         %ApplianceModel{} = ecto_schema,
         :picture_url,
         %Plug.Upload{} = upload
       ) do
    changeset = Changeset.change(ecto_schema)

    case ApplianceModelPicture.store({upload, ecto_schema}) do
      {:ok, file_name} ->
        file_url = ApplianceModelPicture.url({file_name, ecto_schema})
        Changeset.put_change(changeset, :picture_url, file_url)

      _ ->
        Changeset.add_error(changeset, :picture_file, "Could not upload the asset")
    end
  end

  defp delete(%ApplianceModel{} = ecto_schema, schema_key) do
    asset_ref = ecto_schema |> Map.from_struct() |> Map.get(schema_key)

    unless is_nil(asset_ref) do
      # Will delete the asset asynchronously, if it exists
      :ok = ApplianceModelPicture.delete({asset_ref, ecto_schema})
    end

    # Remove the asset ref from the model
    Changeset.change(ecto_schema, %{schema_key => nil})
  end
end

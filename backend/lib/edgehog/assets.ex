defmodule Edgehog.Assets do
  alias Edgehog.Assets.ApplianceModelPicture

  @assets_appliance_model_picture_module Application.compile_env(
                                           :edgehog,
                                           :assets_appliance_model_picture_module,
                                           ApplianceModelPicture
                                         )

  def upload_appliance_model_picture(appliance_model, picture_file) do
    with :ok <- ensure_storage_enabled() do
      @assets_appliance_model_picture_module.upload(appliance_model, picture_file)
    end
  end

  def delete_appliance_model_picture(appliance_model, picture_url) do
    with :ok <- ensure_storage_enabled() do
      @assets_appliance_model_picture_module.delete(appliance_model, picture_url)
    end
  end

  defp ensure_storage_enabled do
    if Application.get_env(:edgehog, :enable_s3_storage?, false) do
      :ok
    else
      {:error, :storage_disabled}
    end
  end
end

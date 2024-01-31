#
# This file is part of Edgehog.
#
# Copyright 2021-2023 SECO Mind Srl
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
# SPDX-License-Identifier: Apache-2.0
#

defmodule EdgehogWeb.Resolvers.Devices do
  alias Edgehog.Devices
  alias Edgehog.Devices.Device
  alias Edgehog.Devices.SystemModel
  alias Edgehog.Labeling.DeviceAttribute
  alias EdgehogWeb.Schema.VariantTypes
  alias I18nHelpers.Ecto.Translator

  def find_device(%{id: id}, _resolution) do
    device =
      Devices.get_device!(id)
      |> Devices.preload_astarte_resources_for_device()

    {:ok, device}
  end

  def list_devices(_parent, %{filter: filter}, _resolution) do
    devices =
      Devices.list_devices(filter)
      |> Devices.preload_astarte_resources_for_device()

    {:ok, devices}
  end

  def list_devices(_parent, _args, _resolution) do
    devices =
      Devices.list_devices()
      |> Devices.preload_astarte_resources_for_device()

    {:ok, devices}
  end

  def update_device(%{device_id: id} = attrs, _resolution) do
    device = Devices.get_device!(id)
    attrs = maybe_wrap_typed_values(attrs)

    with {:ok, device} <- Devices.update_device(device, attrs) do
      device = Devices.preload_astarte_resources_for_device(device)

      {:ok, %{device: device}}
    end
  end

  def find_system_model(%{id: id}, _resolution) do
    Devices.fetch_system_model(id)
  end

  def list_system_models(_parent, _args, _resolution) do
    system_models = Devices.list_system_models()

    {:ok, system_models}
  end

  def extract_system_model_part_numbers(
        %SystemModel{part_numbers: part_numbers},
        _args,
        _context
      ) do
    part_numbers = Enum.map(part_numbers, &Map.get(&1, :part_number))

    {:ok, part_numbers}
  end

  def create_system_model(_parent, %{hardware_type_id: hw_type_id} = attrs, resolution) do
    default_locale = resolution.context.current_tenant.default_locale

    with {:ok, hardware_type} <- Devices.fetch_hardware_type(hw_type_id),
         :ok <- check_description_locale(attrs[:description], default_locale),
         attrs = wrap_description(attrs),
         {:ok, system_model} <-
           Devices.create_system_model(hardware_type, attrs) do
      {:ok, %{system_model: system_model}}
    end
  end

  def update_system_model(_parent, %{system_model_id: id} = attrs, resolution) do
    default_locale = resolution.context.current_tenant.default_locale

    with {:ok, %SystemModel{} = system_model} <- Devices.fetch_system_model(id),
         :ok <- check_description_locale(attrs[:description], default_locale),
         attrs = wrap_description(attrs),
         {:ok, %SystemModel{} = system_model} <-
           Devices.update_system_model(system_model, attrs) do
      {:ok, %{system_model: system_model}}
    end
  end

  def delete_system_model(%{system_model_id: id}, _resolution) do
    with {:ok, %SystemModel{} = system_model} <- Devices.fetch_system_model(id),
         {:ok, %SystemModel{} = system_model} <- Devices.delete_system_model(system_model) do
      {:ok, %{system_model: system_model}}
    end
  end

  # Only allow a description that uses the tenant default locale in {create,update}_system_model
  defp check_description_locale(nil, _default_locale), do: :ok
  defp check_description_locale(%{locale: default_locale}, default_locale), do: :ok
  defp check_description_locale(%{locale: _other}, _default), do: {:error, :not_default_locale}

  # If it's there, wraps description in a map, as {create,update}_system_model expect a map
  defp wrap_description(%{description: description} = attrs) when is_map(description) do
    %{locale: locale, text: text} = description
    %{attrs | description: %{locale => text}}
  end

  defp wrap_description(attrs), do: attrs

  def extract_localized_description(%SystemModel{} = system_model, _args, resolution) do
    %{
      context: %{
        preferred_locales: preferred_locales,
        tenant_locale: tenant_locale
      }
    } = resolution

    # TODO: move this in a middleware
    %SystemModel{translated_description: translated_description} =
      Translator.translate(system_model, preferred_locales, fallback_locale: tenant_locale)

    # TODO: fix the library to return nil on empty translations
    if translated_description == "" do
      {:ok, nil}
    else
      {:ok, translated_description}
    end
  end

  def extract_device_tags(%Device{tags: tags}, _args, _context) do
    tag_names = for t <- tags, do: t.name
    {:ok, tag_names}
  end

  def extract_attribute_type(%DeviceAttribute{typed_value: typed_value}, _args, _context) do
    {:ok, typed_value.type}
  end

  def extract_attribute_value(%DeviceAttribute{typed_value: typed_value}, _args, _context) do
    %Ecto.JSONVariant{type: type, value: value} = typed_value
    VariantTypes.encode_variant_value(type, value)
  end

  defp maybe_wrap_typed_values(%{custom_attributes: custom_attributes} = attrs)
       when is_list(custom_attributes) do
    wrapped_attributes =
      Enum.map(custom_attributes, fn attr ->
        %{
          namespace: namespace,
          key: key,
          type: type,
          value: value
        } = attr

        # Wrap type and value under the :typed_value key, as expected by the Ecto schema
        %{
          namespace: namespace,
          key: key,
          typed_value: %{type: type, value: value}
        }
      end)

    %{attrs | custom_attributes: wrapped_attributes}
  end

  defp maybe_wrap_typed_values(attrs), do: attrs
end

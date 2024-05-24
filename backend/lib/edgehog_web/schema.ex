#
# This file is part of Edgehog.
#
# Copyright 2021-2024 SECO Mind Srl
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

defmodule EdgehogWeb.Schema do
  use Absinthe.Schema
  use Absinthe.Relay.Schema, :modern
  import_types EdgehogWeb.Schema.AstarteTypes
  import_types EdgehogWeb.Schema.UpdateCampaignsTypes
  import_types EdgehogWeb.Schema.VariantTypes
  import_types Absinthe.Plug.Types
  import_types Absinthe.Type.Custom

  @domains [
    Edgehog.BaseImages,
    Edgehog.Devices,
    Edgehog.Forwarder,
    Edgehog.Groups,
    Edgehog.Labeling,
    Edgehog.OSManagement,
    Edgehog.Tenants
  ]

  # TODO: remove define_relay_types?: false once we convert everything to Ash
  use AshGraphql,
    domains: @domains,
    define_relay_types?: false,
    relay_ids?: true

  alias EdgehogWeb.Resolvers

  node interface do
    resolve_type fn
      %Edgehog.BaseImages.BaseImage{}, _ ->
        :base_image

      %Edgehog.BaseImages.BaseImageCollection{}, _ ->
        :base_image_collection

      %Edgehog.Devices.Device{}, _ ->
        :device

      %Edgehog.Devices.HardwareType{}, _ ->
        :hardware_type

      %Edgehog.Devices.SystemModel{}, _ ->
        :system_model

      %Edgehog.Groups.DeviceGroup{}, _ ->
        :device_group

      %Edgehog.OSManagement.OTAOperation{}, _ ->
        :ota_operation

      %Edgehog.UpdateCampaigns.UpdateCampaign{}, _ ->
        :update_campaign

      %Edgehog.UpdateCampaigns.Target{}, _ ->
        :update_target

      _, _ ->
        nil
    end
  end

  query do
    node field do
      resolve fn
        %{type: :base_image, id: id}, context ->
          Resolvers.BaseImages.find_base_image(%{id: id}, context)

        %{type: :base_image_collection, id: id}, context ->
          Resolvers.BaseImages.find_base_image_collection(%{id: id}, context)

        %{type: :device, id: id}, context ->
          Resolvers.Devices.find_device(%{id: id}, context)

        %{type: :hardware_type, id: id}, context ->
          Resolvers.Devices.find_hardware_type(%{id: id}, context)

        %{type: :system_model, id: id}, context ->
          Resolvers.Devices.find_system_model(%{id: id}, context)

        %{type: :device_group, id: id}, context ->
          Resolvers.Groups.find_device_group(%{id: id}, context)

        %{type: :ota_operation, id: id}, context ->
          Resolvers.OSManagement.find_ota_operation(%{id: id}, context)

        %{type: :update_campaign, id: id}, context ->
          Resolvers.UpdateCampaigns.find_update_campaign(%{id: id}, context)

        %{type: :update_target, id: id}, context ->
          Resolvers.UpdateCampaigns.find_target(%{id: id}, context)
      end
    end

    import_fields :update_campaigns_queries
  end

  mutation do
    import_fields :astarte_mutations
    import_fields :update_campaigns_mutations
  end
end

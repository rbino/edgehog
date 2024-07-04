#
# This file is part of Edgehog.
#
# Copyright 2023 SECO Mind Srl
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

defmodule Edgehog.Tenants.AstarteConfig do
  @moduledoc false
  use Ash.Resource,
    data_layer: :embedded

  actions do
    defaults [:read, :update]

    create :create do
      primary? true
      accept [:base_api_url, :realm_name, :realm_private_key]
    end
  end

  attributes do
    attribute :base_api_url, :string do
      public? true
      allow_nil? false
    end

    attribute :realm_name, :string do
      public? true
      allow_nil? false
    end

    attribute :realm_private_key, :string do
      public? true
      allow_nil? false
    end
  end
end

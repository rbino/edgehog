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

defmodule Edgehog.Assets.Store.Behaviour do
  @type ecto_schema :: any

  @type schema_key :: atom()

  @type upload :: %Plug.Upload{}

  @type changeset :: %Ecto.Changeset{}

  @callback cast_asset_upload(ecto_schema(), schema_key(), upload()) :: changeset()

  @callback cast_asset_deletion(ecto_schema(), schema_key()) :: changeset()
end

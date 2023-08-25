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

defmodule Edgehog.OSManagement.Event.OTAOperationStatusChanged do
  use TypedStruct

  @typedoc "An event indicating that an OTA Operation changed its status"
  typedstruct do
    field :id, any(), enforce: true
    field :status, atom(), enforce: true
    field :status_code, atom()
    field :status_progress, non_neg_integer()
    field :message, String.t()
  end
end

#
# This file is part of Edgehog.
#
# Copyright 2022 SECO Mind Srl
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

defmodule EdgehogWeb.Auth.Pipeline do
  use Plug.Builder

  import Plug.Conn

  require Logger

  plug Guardian.Plug.Pipeline,
    otp_app: :edgehog,
    module: EdgehogWeb.Auth.Token,
    error_handler: EdgehogWeb.Auth.ErrorHandler

  plug EdgehogWeb.Auth.VerifyHeader
  plug Guardian.Plug.LoadResource
  plug Guardian.Plug.EnsureAuthenticated
end

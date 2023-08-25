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

defmodule Edgehog.OSManagement.Event do
  alias Edgehog.OSManagement.OTAOperation

  alias Edgehog.OSManagement.Event.OTAOperationCreated
  alias Edgehog.OSManagement.Event.OTAOperationFinished
  alias Edgehog.OSManagement.Event.OTAOperationStatusChanged
  alias Edgehog.OSManagement.Event.OTAOperationStatusProgressUpdated

  @doc """
  This function builds a list of business events from a given changeset. The fact that they are
  business events means that it's possible to group multiple field changes in a single event.
  """
  def events_from_changeset(%Ecto.Changeset{} = changeset) do
    build_events_from_changes(changeset.data, changeset.changes, [])
  end

  def creation_event(%OTAOperation{} = ota_operation) do
    %OTAOperationCreated{ota_operation: ota_operation}
  end

  defp build_events_from_changes(
         %OTAOperation{} = ota_operation,
         %{status: status} = changes,
         events
       ) do
    final_state = status in [:success, :failure]

    {event, updated_changes} =
      ota_operation_state_change_event(ota_operation.id, changes, final_state: final_state)

    build_events_from_changes(ota_operation, updated_changes, [event | events])
  end

  defp build_events_from_changes(
         %OTAOperation{} = ota_operation,
         %{status_progress: progress} = changes,
         events
       ) do
    event = %OTAOperationStatusProgressUpdated{id: ota_operation.id, status_progress: progress}
    updated_changes = Map.drop(changes, [:status_progress])

    build_events_from_changes(ota_operation, updated_changes, [event | events])
  end

  defp build_events_from_changes(data, changes, events) do
    if changes != %{} do
      # TODO: track this so we know if we're missing some 
      Logger.info(
        "Finished building events with leftover changes: data #{inspect(data)} changes #{inspect(changes)}"
      )
    end

    events
  end

  defp ota_operation_state_change_event(ota_operation_id, changes, opts) do
    # This must be in the map
    status = Map.fetch!(changes, :status)
    # These _could_ be in the map also
    status_code = Map.get(changes, :status_code)
    message = Map.get(changes, :message)

    event =
      if opts[:final_state] do
        %OTAOperationFinished{
          id: ota_operation_id,
          status: status,
          status_code: status_code,
          message: message
        }
      else
        %OTAOperationStatusChanged{
          id: ota_operation_id,
          status: status,
          status_code: status_code,
          message: message
        }
      end

    # We also drop :status_progress since it's not relevant if we're already changing state
    updated_changes = Map.drop(changes, [:status, :status_code, :message, :status_progress])
    {event, updated_changes}
  end
end

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

defmodule Edgehog.PubSub do
  @moduledoc """
  This module implements a PubSub system for events happening inside Edgehog
  """

  alias Edgehog.OSManagement.OTAOperation
  alias Edgehog.OSManagement.Event.OTAOperationCreated
  alias Edgehog.OSManagement.Event.OTAOperationFinished
  alias Edgehog.OSManagement.Event.OTAOperationStatusChanged
  alias Edgehog.OSManagement.Event.OTAOperationStatusProgressUpdated

  @type event :: :ota_operation_created | :ota_operation_updated

  @type id :: non_neg_integer() | String.t()
  @type subject :: :ota_operation

  @doc """
  Publish an event to the relevant PubSub channels. Raises if any of the publish fails.
  """
  @spec publish!(event :: event(), subject :: any) :: :ok
  def publish!(%OTAOperationCreated{} = event) do
    Phoenix.PubSub.broadcast!(Edgehog.PubSub, "ota_operations:#{event.id}", event)

    Absinthe.Subscription.publish(EdgehogWeb.Endpoint, event,
      update_target: "ota_operations:#{event.id}"
    )

    :ok
  end

  @doc """
  Publish an event to the PubSub. Raises if any of the publish fails.
  """
  @spec publish!(event :: event(), subject :: any) :: :ok | {:error, reason :: any()}
  def publish!(event, subject)

  def publish!(:ota_operation_updated = event, %OTAOperation{} = ota_operation) do
    payload = {event, ota_operation}

    topics = [
      topic_for_subject(ota_operation),
      wildcard_topic_for_subject(ota_operation)
    ]

    broadcast_many!(topics, payload)
  end

  defp broadcast_many!(topics, payload) do
    Enum.each(topics, fn topic ->
      Phoenix.PubSub.broadcast!(Edgehog.PubSub, topic, payload)
    end)
  end

  @doc """
  Subscribe to events for a specific subject on a channel. A channel indicates
  a specific instance of the subject (e.g. an id for a resource, or a tenant
  id for a group of resources).
  """
  @spec subscribe_to_updates(tenant_id :: id(), subject :: subject(), id :: id())
  def subscribe_to_updates(tenant_id, subject, id) do
    topic = update_topic_for_subject(tenant_id, subject, id)

    Phoenix.PubSub.subscribe(Edgehog.PubSub, topic)
  end

  def subscribe_to_creation(tenant_id, subject) do
    topic = creation_topic_for_subject(subject)

    Phoenix.PubSub.subscribe(Edgehog.PubSub, topic)
  end

  def subscribe_to_deletion(tenant_id, subject) do
    topic = topic_for_subject(subject)

    Phoenix.PubSub.subscribe(Edgehog.PubSub, topic)
  end

  defp wildcard_topic_for_subject(%OTAOperation{}), do: topic_for_subject(:ota_operations)

  defp topic_for_subject(:ota_operation, id), do: "ota_operation:#{id}"
  defp topic_for_subject(:ota_operations, tenant_id), do: "ota_operation_by_tenant:#{tenant_id}"
end

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

defmodule Edgehog.UpdateCampaigns.PushRollout.ExecutorTest do
  use Edgehog.DataCase, async: true
  use Edgehog.AstarteMockCase

  alias Edgehog.UpdateCampaigns.PushRollout.Core
  alias Edgehog.UpdateCampaigns.PushRollout.Executor

  import Edgehog.BaseImagesFixtures
  import Edgehog.UpdateCampaignsFixtures

  describe "PushRollout.Executor immediately terminates" do
    test "when the update campaign has no targets" do
      update_campaign = update_campaign_fixture()

      %{pid: pid, ref: ref} = start_and_monitor_executor!(update_campaign)

      assert_normal_exit(pid, ref)
    end

    test "when campaign is already marked as failed" do
      update_campaign = update_campaign_with_targets_fixture(1)
      [target] = update_campaign.update_targets
      _ = Core.mark_target_as_failed!(target)
      _ = Core.mark_update_campaign_as_failed!(update_campaign)

      %{pid: pid, ref: ref} = start_and_monitor_executor!(update_campaign)

      assert_normal_exit(pid, ref)
    end

    test "when campaign is already marked as successful" do
      update_campaign = update_campaign_with_targets_fixture(1)
      [target] = update_campaign.update_targets
      _ = Core.mark_target_as_successful!(target)
      _ = Core.mark_update_campaign_as_successful!(update_campaign)

      %{pid: pid, ref: ref} = start_and_monitor_executor!(update_campaign)

      assert_normal_exit(pid, ref)
    end
  end

  describe "PushRollout.Executor resumes :in_progress campaign" do
    test "when it already has max_in_progress_updates pending updates" do
      target_count = Enum.random(10..20)
      max_in_progress_updates = Enum.random(2..5)

      update_campaign =
        update_campaign_with_targets_fixture(target_count,
          rollout_mechanism: [max_in_progress_updates: max_in_progress_updates]
        )

      pid = start_executor!(update_campaign)

      # Wait for the Executor to arrive at :wait_for_available_slot
      wait_for_state(pid, :wait_for_available_slot, 1000)

      # Stop the executor
      stop_supervised(Executor)

      # Start another executor for the same update campaign
      resumed_pid = start_executor!(update_campaign)

      # Expect no new OTA Requests
      _ = expect_ota_requests_and_send_sync(0)

      # Expect the Executor to arrive at :wait_for_available_slot
      wait_for_state(resumed_pid, :wait_for_available_slot)
    end

    test "when it is waiting for completion" do
      target_count = Enum.random(2..20)

      update_campaign =
        update_campaign_with_targets_fixture(target_count,
          rollout_mechanism: [max_in_progress_updates: target_count]
        )

      pid = start_executor!(update_campaign)

      # Wait for the Executor to arrive at :wait_for_campaign_completion
      wait_for_state(pid, :wait_for_campaign_completion, 1000)

      # Stop the executor
      stop_supervised(Executor)

      # Start another executor for the same update campaign
      resumed_pid = start_executor!(update_campaign)

      # Expect no OTA Requests
      _ = expect_ota_requests_and_send_sync(0)

      # Expect the Executor to arrive at :wait_for_campaign_completion
      wait_for_state(resumed_pid, :wait_for_campaign_completion)
    end
  end

  describe "PushRollout.Executor sends" do
    test "all target OTA Requests in parallel if there are enough available slots" do
      target_count = Enum.random(2..20)

      update_campaign =
        update_campaign_with_targets_fixture(target_count,
          rollout_mechanism: [max_in_progress_updates: target_count]
        )

      parent = self()
      ref = make_ref()
      base_image_url = update_campaign.base_image.url
      target_device_ids = Enum.map(update_campaign.update_targets, & &1.device.device_id)

      # Set an expectation for each target on the OTARequest mock and send back a message
      # to wait for all devices
      Enum.each(target_device_ids, fn device_id ->
        Edgehog.Astarte.Device.OTARequestV1Mock
        |> expect(:update, fn _client, ^device_id, _uuid, ^base_image_url ->
          send_sync(parent, {ref, device_id})
          :ok
        end)
      end)

      pid = start_executor!(update_campaign)

      # Wait for all the device sync messages
      target_device_ids
      |> Enum.map(&{ref, &1})
      |> wait_for_sync!()

      # Expect the Executor to arrive at :wait_for_campaign_completion
      wait_for_state(pid, :wait_for_campaign_completion)
    end

    test "at most max_in_progress_updates OTA Requests" do
      target_count = Enum.random(10..20)
      max_in_progress_updates = Enum.random(2..5)

      update_campaign =
        update_campaign_with_targets_fixture(target_count,
          rollout_mechanism: [max_in_progress_updates: max_in_progress_updates]
        )

      # Expect max_in_progress_updates OTA Requests
      ref = expect_ota_requests_and_send_sync(max_in_progress_updates)

      pid = start_executor!(update_campaign)

      # Wait for max_in_progress_updates sync messages
      repeat(ref, max_in_progress_updates)
      |> wait_for_sync!()

      # Expect the Executor to arrive at :wait_for_available_slot
      wait_for_state(pid, :wait_for_available_slot)
    end

    test "OTA Requests only to online targets" do
      target_count = Enum.random(10..20)
      # We want at least 1 offline target to test that we arrive in :wait_for_target
      offline_count = Enum.random(1..target_count)
      online_count = target_count - offline_count

      update_campaign = update_campaign_with_targets_fixture(target_count)

      {offline_targets, online_targets} =
        Enum.split(update_campaign.update_targets, offline_count)

      # Mark the online targets as online
      update_device_online_for_targets(online_targets, true)
      # Mark the offline targets as offline
      update_device_online_for_targets(offline_targets, false)

      # Expect online_count calls to the mock
      ref = expect_ota_requests_and_send_sync(online_count)

      pid = start_executor!(update_campaign)

      # Wait for online_count sync messages
      ref
      |> repeat(online_count)
      |> wait_for_sync!()

      # Expect the Executor to arrive at :wait_for_target
      wait_for_state(pid, :wait_for_target)
    end
  end

  describe "PushRollout.Executor receiving an OTAOperation update" do
    setup do
      target_count = 10
      max_updates = 5

      update_campaign =
        update_campaign_with_targets_fixture(target_count,
          rollout_mechanism: [max_in_progress_updates: max_updates]
        )

      parent = self()

      Edgehog.Astarte.Device.OTARequestV1Mock
      |> expect(:update, max_updates, fn _client, _device_id, ota_operation_id, _url ->
        # Since we don't know _which_ target will receive the request, we send it back from here
        send(parent, {:updated_target, ota_operation_id})
        :ok
      end)

      pid = start_executor!(update_campaign)

      # Wait for the Executor to arrive at :wait_for_available_slot
      wait_for_state(pid, :wait_for_available_slot)

      # Verify that all the expectations we defined until now were called
      verify!()

      # Extract OTA Operation for a taget that received the OTA Request
      ota_operation_id =
        receive do
          {:updated_target, ota_operation_id} ->
            ota_operation_id
        after
          100 -> flunk()
        end

      # Throw away the other messages
      flush_messages()

      {:ok, executor_pid: pid, ota_operation_id: ota_operation_id}
    end

    for status <- [:success, :failure] do
      test "frees up slot if OTA Operation status is #{status}", ctx do
        %{
          executor_pid: pid,
          ota_operation_id: ota_operation_id
        } = ctx

        # Expect another call to the mock since a slot has freed up
        ref = expect_ota_requests_and_send_sync()

        update_ota_operation_status!(ota_operation_id, unquote(status))

        wait_for_sync!(ref)

        # Wait for the Executor to arrive at :wait_for_available_slot
        wait_for_state(pid, :wait_for_available_slot)
      end
    end

    for status <- [:acknowledged, :downloading, :deploying, :deployed, :rebooting, :error] do
      test "doesn't free up slots if OTA Operation status is #{status}", ctx do
        %{
          executor_pid: pid,
          ota_operation_id: ota_operation_id
        } = ctx

        # Expect no calls to the mock
        Edgehog.Astarte.Device.OTARequestV1Mock
        |> expect(:update, 0, fn _client, _device_id, _uuid, _base_image_url ->
          :ok
        end)

        update_ota_operation_status!(ota_operation_id, unquote(status))

        # Expect the executor to remain in the :wait_for_available_slot state
        wait_for_state(pid, :wait_for_available_slot)
      end
    end
  end

  describe "PushRollout.Executor marks campaign as successful" do
    setup do
      target_count = Enum.random(10..20)
      # 20 < x <= 70
      max_errors_percentage = 20 + :rand.uniform() * 50

      # Create a base image with a specific version
      base_image_version = "2.1.0"
      base_image = base_image_fixture(version: base_image_version)

      # Also define an higher version to test downgrade
      higher_base_image_version = "2.2.0"

      update_campaign =
        update_campaign_with_targets_fixture(target_count,
          base_image: base_image,
          rollout_mechanism: [
            force_downgrade: true,
            max_in_progress_updates: target_count,
            max_errors_percentage: max_errors_percentage
          ]
        )

      %{pid: pid, ref: ref} = start_and_monitor_executor!(update_campaign, start_execution: false)

      ctx = [
        base_image_version: base_image_version,
        executor_pid: pid,
        higher_base_image_version: higher_base_image_version,
        max_errors_percentage: max_errors_percentage,
        monitor_ref: ref,
        target_count: target_count,
        update_campaign_id: update_campaign.id
      ]

      {:ok, ctx}
    end

    test "if all targets are successful", ctx do
      %{
        executor_pid: pid,
        monitor_ref: ref,
        update_campaign_id: update_campaign_id
      } = ctx

      start_execution(pid)

      # Wait for the Executor to arrive at :wait_for_campaign_completion
      wait_for_state(pid, :wait_for_campaign_completion)

      mark_all_pending_ota_operations_with_status(update_campaign_id, :success)

      assert_normal_exit(pid, ref)
      assert_update_campaign_outcome(update_campaign_id, :success)
    end

    test "if all targets already have the base image version it's being rolled out", ctx do
      %{
        base_image_version: base_image_version,
        executor_pid: pid,
        monitor_ref: ref,
        target_count: target_count,
        update_campaign_id: update_campaign_id
      } = ctx

      Edgehog.Astarte.Device.BaseImageMock
      |> expect(:get, target_count, fn _client, _device_id ->
        # Reply like the target already has the correct base image version
        {:ok, astarte_base_image_with_version(base_image_version)}
      end)

      start_execution(pid)

      assert_normal_exit(pid, ref)
      assert_update_campaign_outcome(update_campaign_id, :success)
    end

    test "if targets get downgraded when the rollout has force_downgrade: true", ctx do
      %{
        executor_pid: pid,
        higher_base_image_version: higher_base_image_version,
        monitor_ref: ref,
        target_count: target_count,
        update_campaign_id: update_campaign_id
      } = ctx

      Edgehog.Astarte.Device.BaseImageMock
      |> expect(:get, target_count, fn _client, _device_id ->
        # Reply like the target already has an higher version
        {:ok, astarte_base_image_with_version(higher_base_image_version)}
      end)

      start_execution(pid)

      # Wait for the Executor to arrive at :wait_for_campaign_completion
      wait_for_state(pid, :wait_for_campaign_completion)

      mark_all_pending_ota_operations_with_status(update_campaign_id, :success)

      assert_normal_exit(pid, ref)
      assert_update_campaign_outcome(update_campaign_id, :success)
    end

    test "if just less than max_errors_percentage targets fail", ctx do
      %{
        executor_pid: pid,
        max_errors_percentage: max_errors_percentage,
        monitor_ref: ref,
        target_count: target_count,
        update_campaign_id: update_campaign_id
      } = ctx

      start_execution(pid)

      # Wait for the Executor to arrive at :wait_for_campaign_completion
      wait_for_state(pid, :wait_for_campaign_completion)

      ota_operation_ids =
        Core.list_targets_with_pending_ota_operation(update_campaign_id)
        |> Enum.map(& &1.ota_operation_id)

      failing_target_count = max_failed_targets_for_success(target_count, max_errors_percentage)

      {failing_ota_operation_ids, successful_ota_operation_ids} =
        Enum.split(ota_operation_ids, failing_target_count)

      # Mark all failing OTA Operations as successful
      Enum.each(failing_ota_operation_ids, &update_ota_operation_status!(&1, :failure))

      # Mark all successful OTA Operations as successful
      Enum.each(successful_ota_operation_ids, &update_ota_operation_status!(&1, :success))

      assert_normal_exit(pid, ref)
      assert_update_campaign_outcome(update_campaign_id, :success)
    end
  end

  describe "PushRollout.Executor marks campaign as failed if max_errors_percentage is exceeded" do
    setup do
      target_count = Enum.random(10..20)
      # 20 < x <= 70
      max_errors_percentage = 20 + :rand.uniform() * 50

      # The minimum number of targets that have to fail to trigger a failure
      failing_target_count = min_failed_targets_for_failure(target_count, max_errors_percentage)

      # Create a base image with a specific version and starting_version_requirement
      base_image_version = "2.1.0"
      starting_version_requirement = ">= 2.0.0"

      base_image =
        base_image_fixture(
          version: base_image_version,
          starting_version_requirement: starting_version_requirement
        )

      # Also define an higher version to test downgrade
      higher_base_image_version = "2.2.0"

      # And an incompatible base image version to test compatibility
      incompatible_base_image_version = "1.4.2"

      # Stub BaseImage with a compatible base image by default
      Edgehog.Astarte.Device.BaseImageMock
      |> stub(:get, fn _client, _device_id ->
        # Reply like the target already has an incompatible version
        {:ok, astarte_base_image_with_version("2.0.0")}
      end)

      update_campaign =
        update_campaign_with_targets_fixture(target_count,
          base_image: base_image,
          rollout_mechanism: [
            force_downgrade: false,
            max_in_progress_updates: target_count,
            max_errors_percentage: max_errors_percentage
          ]
        )

      %{pid: pid, ref: ref} = start_and_monitor_executor!(update_campaign, start_execution: false)

      ctx = [
        executor_pid: pid,
        failing_target_count: failing_target_count,
        higher_base_image_version: higher_base_image_version,
        incompatible_base_image_version: incompatible_base_image_version,
        monitor_ref: ref,
        update_campaign_id: update_campaign.id
      ]

      {:ok, ctx}
    end

    test "by failed OTA Operations", ctx do
      %{
        executor_pid: pid,
        failing_target_count: failing_target_count,
        monitor_ref: ref,
        update_campaign_id: update_campaign_id
      } = ctx

      # Start the execution
      start_execution(pid)

      # Wait for the Executor to arrive at :wait_for_campaign_completion
      wait_for_state(pid, :wait_for_campaign_completion)

      # Produce failing_target_count failures
      Core.list_targets_with_pending_ota_operation(update_campaign_id)
      |> Enum.take(failing_target_count)
      |> Enum.each(fn target ->
        update_ota_operation_status!(target.ota_operation_id, :failure)
      end)

      assert_normal_exit(pid, ref)
      assert_update_campaign_outcome(update_campaign_id, :failure)
    end

    test "by targets failing during the initial rollout with a non-temporary API failure", ctx do
      %{
        executor_pid: pid,
        failing_target_count: failing_target_count,
        monitor_ref: ref,
        update_campaign_id: update_campaign_id
      } = ctx

      # Expect failing_target_count calls to the mock and return a non-temporary error
      Edgehog.Astarte.Device.OTARequestV1Mock
      |> expect(:update, failing_target_count, fn _client, _device_id, _uuid, _base_image_url ->
        status = Enum.random(400..499)
        {:error, %Astarte.Client.APIError{status: status, response: "F"}}
      end)

      # Start the execution
      start_execution(pid)

      assert_normal_exit(pid, ref)
      assert_update_campaign_outcome(update_campaign_id, :failure)
    end

    test "by targets that would be downgraded when rollout has force_downgrade: false", ctx do
      %{
        executor_pid: pid,
        failing_target_count: failing_target_count,
        higher_base_image_version: higher_base_image_version,
        monitor_ref: ref,
        update_campaign_id: update_campaign_id
      } = ctx

      Edgehog.Astarte.Device.BaseImageMock
      |> expect(:get, failing_target_count, fn _client, _device_id ->
        # Reply like the target already has an higher version
        {:ok, astarte_base_image_with_version(higher_base_image_version)}
      end)

      start_execution(pid)

      assert_normal_exit(pid, ref)
      assert_update_campaign_outcome(update_campaign_id, :failure)
    end

    test "by targets incompatible with the base image", ctx do
      %{
        executor_pid: pid,
        failing_target_count: failing_target_count,
        incompatible_base_image_version: incompatible_base_image_version,
        monitor_ref: ref,
        update_campaign_id: update_campaign_id
      } = ctx

      Edgehog.Astarte.Device.BaseImageMock
      |> expect(:get, failing_target_count, fn _client, _device_id ->
        # Reply like the target already has an incompatible version
        {:ok, astarte_base_image_with_version(incompatible_base_image_version)}
      end)

      start_execution(pid)

      assert_normal_exit(pid, ref)
      assert_update_campaign_outcome(update_campaign_id, :failure)
    end
  end

  # Helper functions

  # This functions are used to coordinate the test, waiting for a specific ref or a list of
  # refs regardless of the reception order. It's useful to coordinate with the executor process
  # by sending messages from Mox expectations.
  defp send_sync(dest, ref) do
    send(dest, {:sync, ref})
  end

  # Waits for a list of refs to be received with {:sync, ref}
  defp wait_for_sync!([] = _refs) do
    :ok
  end

  defp wait_for_sync!(refs) when is_list(refs) do
    receive do
      {:sync, ref} ->
        if ref in refs do
          refs
          |> List.delete(ref)
          |> wait_for_sync!()
        else
          flunk("Received unexpected ref: #{inspect(ref)}")
        end
    after
      100 -> flunk("Sync timeout, not received: #{inspect(refs)}")
    end
  end

  defp wait_for_sync!(ref) do
    assert_receive {:sync, ^ref}
  end

  # Waits for the Executor to reach a specific state in the state machine
  defp wait_for_state(executor_pid, state, timeout \\ 1000) do
    start_time = DateTime.utc_now()

    loop_until_state!(executor_pid, state, start_time, timeout)
  end

  defp loop_until_state!(_executor_pid, state, _start_time, remaining_time)
       when remaining_time <= 0 do
    flunk("State #{state} not reached")
  end

  defp loop_until_state!(executor_pid, state, start_time, _remaining_time) do
    case :sys.get_state(executor_pid) do
      {^state, _data} ->
        :ok

      _other ->
        Process.sleep(100)
        remaining_time = DateTime.diff(start_time, DateTime.utc_now(), :millisecond)
        loop_until_state!(executor_pid, state, start_time, remaining_time)
    end
  end

  @executor_allowed_mocks [
    Edgehog.Astarte.Device.BaseImageMock,
    Edgehog.Astarte.Device.DeviceStatusMock,
    Edgehog.Astarte.Device.OTARequestV1Mock
  ]

  defp start_and_monitor_executor!(update_campaign, opts \\ []) do
    # We don't start the execution so we can monitor it before it completes
    pid = start_executor!(update_campaign, start_execution: false)
    ref = Process.monitor(pid)
    # After we monitor it, we can (maybe) manually start it
    maybe_start_execution(pid, opts)

    %{pid: pid, ref: ref}
  end

  defp start_executor!(update_campaign, opts \\ []) do
    args = executor_args(update_campaign)

    start_supervised!({Executor, args})
    |> allow_test_resources()
    |> maybe_start_execution(opts)
  end

  defp executor_args(update_campaign) do
    [
      tenant_id: update_campaign.tenant_id,
      update_campaign_id: update_campaign.id,
      # This ensures the Executor waits for our :start_execution message to start
      wait_for_start_execution: true
    ]
  end

  defp allow_test_resources(pid) do
    # Allow all relevant Mox mocks to be called by the Executor process
    Enum.each(@executor_allowed_mocks, &Mox.allow(&1, self(), pid))

    # Also allow the pid to use SQL Sandbox
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)

    pid
  end

  defp maybe_start_execution(pid, opts) do
    # We start the execution by default, but the test can decide to manually start it
    # from the outside by passing [start_execution: false] in the start options
    if Keyword.get(opts, :start_execution, true) do
      start_execution(pid)
    else
      pid
    end
  end

  def start_execution(pid) do
    # Unlock an Executor that was started with wait_for_start_execution: true
    send(pid, :start_execution)

    pid
  end

  defp mark_all_pending_ota_operations_with_status(update_campaign_id, status) do
    update_campaign_id
    |> Core.list_targets_with_pending_ota_operation()
    |> Enum.each(fn target ->
      update_ota_operation_status!(target.ota_operation_id, status)
    end)
  end

  defp expect_ota_requests_and_send_sync(count \\ 1) do
    # Asserts that count OTA Requests where sent and sends a sync message for each of them
    # Returns the ref contained in the sync message
    parent = self()
    ref = make_ref()

    # Expect count calls to the mock
    Edgehog.Astarte.Device.OTARequestV1Mock
    |> expect(:update, count, fn _client, _device_id, _uuid, _url ->
      # Send the sync
      send_sync(parent, ref)
      :ok
    end)

    ref
  end

  defp assert_normal_exit(pid, ref, timeout \\ 1000) do
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal},
                   timeout,
                   "Process did not terminate with reason :normal as expected"
  end

  defp assert_update_campaign_outcome(id, outcome) do
    update_campaign = Core.get_update_campaign!(id)
    assert update_campaign.status == :finished
    assert update_campaign.outcome == outcome
  end

  defp max_failed_targets_for_success(target_count, max_errors_percentage) do
    # Returns the maximum number of targets that can fail and still produce a successful campaign
    floor(target_count * max_errors_percentage / 100)
  end

  defp min_failed_targets_for_failure(target_count, max_errors_percentage) do
    # Returns the minimum number of targets that must fail to produce a failed campaign
    1 + max_failed_targets_for_success(target_count, max_errors_percentage)
  end

  defp update_device_online_for_targets(targets, online) do
    alias Edgehog.Astarte

    targets
    |> Core.preload_defaults_for_target()
    |> Enum.each(fn target ->
      Astarte.get_device!(target.device.id)
      |> Astarte.update_device(%{online: online})
    end)
  end

  defp update_ota_operation_status!(ota_operation_id, status) do
    assert {:ok, ota_operation} =
             Edgehog.OSManagement.get_ota_operation!(ota_operation_id)
             |> Edgehog.OSManagement.update_ota_operation(%{status: status})

    ota_operation
  end

  defp repeat(value, n) do
    # Repeats value for n times and returns a list of them
    Stream.repeatedly(fn -> value end)
    |> Enum.take(n)
  end

  defp astarte_base_image_with_version(version) do
    %Edgehog.Astarte.Device.BaseImage{
      name: "esp-idf",
      version: version,
      build_id: "foo",
      fingerprint: "bar"
    }
  end

  defp flush_messages do
    receive do
      _msg -> flush_messages()
    after
      100 -> :ok
    end
  end
end

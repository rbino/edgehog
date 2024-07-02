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
# SPDX-License-Identifier: Apache-2.0
#

defmodule Edgehog.Selector.AST.AttributeFilterTest do
  use Edgehog.DataCase, async: true

  import Ecto.Query
  import Edgehog.AstarteFixtures
  import Edgehog.DevicesFixtures
  alias Edgehog.Devices
  alias Edgehog.Selector.AST.AttributeFilter
  alias Edgehog.Selector.Parser.Error
  alias Edgehog.Repo

  describe "to_ecto_dynamic_query/1 returns %Parser.Error{}" do
    test "with invalid operator for string" do
      invalid_operators = [:>, :>=, :<, :<=]

      Enum.each(invalid_operators, fn operator ->
        assert {:error, %Error{message: message}} =
                 %AttributeFilter{
                   namespace: "custom",
                   key: "foo",
                   operator: operator,
                   type: :string,
                   value: "bar"
                 }
                 |> AttributeFilter.to_ecto_dynamic_query()

        assert message =~ "invalid operator"
      end)
    end

    test "with invalid operator for binaryblob" do
      invalid_operators = [:>, :>=, :<, :<=]

      Enum.each(invalid_operators, fn operator ->
        assert {:error, %Error{message: message}} =
                 %AttributeFilter{
                   namespace: "custom",
                   key: "foo",
                   operator: operator,
                   type: :binaryblob,
                   value: "YmFy"
                 }
                 |> AttributeFilter.to_ecto_dynamic_query()

        assert message =~ "invalid operator"
      end)
    end

    test "with invalid namespace" do
      assert {:error, %Error{message: message}} =
               %AttributeFilter{
                 namespace: "invalid",
                 key: "foo",
                 operator: :==,
                 type: :string,
                 value: "bar"
               }
               |> AttributeFilter.to_ecto_dynamic_query()

      assert message =~ "invalid namespace"
    end

    test "with invalid datetime value" do
      assert {:error, %Error{message: message}} =
               %AttributeFilter{
                 namespace: "custom",
                 key: "foo",
                 operator: :>,
                 type: :datetime,
                 value: "not ISO8601"
               }
               |> AttributeFilter.to_ecto_dynamic_query()

      assert message =~ "invalid ISO8601 value"
    end

    test "with invalid binaryblob value" do
      assert {:error, %Error{message: message}} =
               %AttributeFilter{
                 namespace: "custom",
                 key: "foo",
                 operator: :==,
                 type: :binaryblob,
                 value: "not base64"
               }
               |> AttributeFilter.to_ecto_dynamic_query()

      assert message =~ "invalid base64 value"
    end
  end
end

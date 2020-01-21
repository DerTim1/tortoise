defmodule Tortoise.Connection.Info.Capabilities do
  @moduledoc false

  alias Tortoise.Package.Subscribe

  defstruct session_expiry_interval: 0,
            receive_maximum: 0xFFFF,
            maximum_qos: 2,
            retain_available: true,
            maximum_packet_size: 268_435_455,
            assigned_client_identifier: nil,
            topic_alias_maximum: 0,
            wildcard_subscription_available: true,
            subscription_identifiers_available: true,
            shared_subscription_available: true,
            server_keep_alive: nil

  def validate(%__MODULE__{} = config, package) do
    config
    |> Map.from_struct()
    |> Map.to_list()
    |> do_validate(package, [])

    # todo, make tests that setup connections with each of them
    # disabled and attempt to subscribe with that feature
  end

  defp do_validate([], _, []), do: :valid
  defp do_validate([], _, reasons), do: {:invalid, reasons}

  # assigned client identifier (ignored)
  defp do_validate([{:assigned_client_identifier, _ignore} | rest], package, acc) do
    do_validate(rest, package, acc)
  end

  # wildcard subscriptions ---------------------------------------------
  defp do_validate(
         [{:wildcard_subscription_available, false} | rest],
         %Subscribe{topics: topics} = package,
         acc
       ) do
    issues =
      Enum.reduce(topics, [], fn {topic, _opts}, acc ->
        topic_list = String.split(topic, "/")

        cond do
          Enum.member?(topic_list, "+") ->
            [{:wildcard_subscription_not_available, topic} | acc]

          Enum.member?(topic_list, "#") ->
            # multi-level wildcards are only allowed on the last
            # position, but we test for each of the positions because
            # we would have to iterate all the elements if we did a
            # `List.last/1` anyways
            [{:wildcard_subscription_not_available, topic} | acc]

          true ->
            acc
        end
      end)

    do_validate(rest, package, issues ++ acc)
  end

  defp do_validate([{:wildcard_subscription_available, _ignored} | rest], package, acc) do
    # This is only relevant for Subscribe packages
    do_validate(rest, package, acc)
  end

  # shared subscriptions -----------------------------------------------
  defp do_validate(
         [{:shared_subscription_available, false} | rest],
         %Subscribe{topics: topics} = package,
         acc
       ) do
    issues =
      for {topic, _opts} <- topics, match?("$share/" <> _, topic) do
        {:shared_subscription_not_available, topic}
      end

    do_validate(rest, package, issues ++ acc)
  end

  defp do_validate(
         [{:shared_subscription_available, true} | rest],
         %Subscribe{topics: _topics} = package,
         acc
       ) do
    # todo!

    # The ShareName MUST NOT contain the characters "/", "+" or "#",
    # but MUST be followed by a "/" character. This "/" character MUST
    # be followed by a Topic Filter [MQTT-4.8.2-2] as described in
    # section 4.7.

    do_validate(rest, package, acc)
  end

  defp do_validate([{:shared_subscription_available, _ignored} | rest], package, acc) do
    # This is only relevant for Subscribe packages
    do_validate(rest, package, acc)
  end

  # subscription identifiers -------------------------------------------
  defp do_validate(
         [{:subscription_identifiers_available, false} | rest],
         %Subscribe{properties: properties} = package,
         acc
       ) do
    if Enum.any?(properties, &match?({:subscription_identifier, _}, &1)) do
      do_validate(rest, package, [:subscription_identifier_not_available | acc])
    else
      do_validate(rest, package, acc)
    end
  end

  defp do_validate([{:subscription_identifiers_available, _ignored} | rest], package, acc) do
    # This is only relevant for Subscribe packages
    do_validate(rest, package, acc)
  end

  # catch all; if an option is enabled, or not accounted for, we just
  # assume it is okay at this point
  defp do_validate([{_option, _value} | rest], subscribe, acc) do
    do_validate(rest, subscribe, acc)
  end
end

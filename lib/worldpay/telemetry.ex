defmodule Worldpay.Telemetry do
  @moduledoc """
  Telemetry integration for all Worldpay API calls.

  ## Events

  All events live under the `[:worldpay, :request, *]` prefix.

  | Event | Measurements | Metadata |
  |---|---|---|
  | `[:worldpay, :request, :start]` | `%{system_time: integer}` | `%{api: atom, operation: atom}` |
  | `[:worldpay, :request, :stop]` | `%{duration: integer}` | `%{api: atom, operation: atom, status: integer, outcome: :ok | :error}` |
  | `[:worldpay, :request, :exception]` | `%{duration: integer}` | `%{api: atom, operation: atom, kind: atom, reason: term}` |

  ## Attaching handlers

      :telemetry.attach_many(
        "worldpay-logger",
        [
          [:worldpay, :request, :start],
          [:worldpay, :request, :stop],
          [:worldpay, :request, :exception]
        ],
        &Worldpay.Telemetry.log_handler/4,
        nil
      )
  """

  use GenServer
  require Logger

  @start_event [:worldpay, :request, :start]
  @stop_event [:worldpay, :request, :stop]
  @exception_event [:worldpay, :request, :exception]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts), do: {:ok, %{}}

  @doc "Emit the start event and return a monotonic start time."
  @spec start(atom(), atom(), map()) :: integer()
  def start(api, operation, metadata \\ %{}) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      @start_event,
      %{system_time: System.system_time()},
      Map.merge(metadata, %{api: api, operation: operation})
    )

    start_time
  end

  @doc "Emit stop event."
  @spec stop(atom(), atom(), integer(), non_neg_integer(), :ok | :error) :: :ok
  def stop(api, operation, start_time, status, outcome) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      @stop_event,
      %{duration: duration},
      %{api: api, operation: operation, status: status, outcome: outcome}
    )
  end

  @doc "Emit exception event."
  @spec exception(atom(), atom(), integer(), atom(), term()) :: :ok
  def exception(api, operation, start_time, kind, reason) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      @exception_event,
      %{duration: duration},
      %{api: api, operation: operation, kind: kind, reason: reason}
    )
  end

  @doc "Default structured logger handler — attach in your application if desired."
  @spec log_handler(list(), map(), map(), term()) :: :ok
  def log_handler(event, measurements, meta, config)

  def log_handler(@start_event, _measurements, meta, _config) do
    Logger.debug("[Worldpay] #{meta.api}.#{meta.operation} starting")
  end

  def log_handler(@stop_event, %{duration: d}, meta, _config) do
    ms = System.convert_time_unit(d, :native, :millisecond)

    case meta.outcome do
      :ok ->
        Logger.debug(
          "[Worldpay] #{meta.api}.#{meta.operation} completed status=#{meta.status} duration=#{ms}ms"
        )

      :error ->
        Logger.warning(
          "[Worldpay] #{meta.api}.#{meta.operation} failed status=#{meta.status} duration=#{ms}ms"
        )
    end
  end

  def log_handler(@exception_event, %{duration: d}, meta, _config) do
    ms = System.convert_time_unit(d, :native, :millisecond)

    Logger.error(
      "[Worldpay] #{meta.api}.#{meta.operation} exception " <>
        "kind=#{meta.kind} reason=#{inspect(meta.reason)} duration=#{ms}ms"
    )
  end

  def log_handler(_event, _measurements, _meta, _config), do: :ok
end

defmodule Kino.Explorer do
  @moduledoc """
  A widget for interactively viewing `Explorer.DataFrame`.

  ## Examples

      df = Explorer.Datasets.fossil_fuels()
      Kino.Explorer.new(df)
  """

  use GenServer, restart: :temporary

  alias Kino.Utils.Table

  defstruct [:pid]

  @type t :: %__MODULE__{pid: pid()}

  @typedoc false
  @type state :: %{
          parent_monitor_ref: reference(),
          df: Explorer.DataFrame.t(),
          total_rows: non_neg_integer()
        }

  @doc """
  Starts a widget process with a data frame.
  """
  @spec new(Explorer.DataFrame.t()) :: t()
  def new(df) do
    parent = self()
    opts = [df: df, parent: parent]

    {:ok, pid} = DynamicSupervisor.start_child(Kino.WidgetSupervisor, {__MODULE__, opts})

    %__MODULE__{pid: pid}
  end

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    df = Keyword.fetch!(opts, :df)
    parent = Keyword.fetch!(opts, :parent)

    parent_monitor_ref = Process.monitor(parent)

    total_rows = Explorer.DataFrame.n_rows(df)
    keys = Explorer.DataFrame.names(df)

    {:ok,
     %{
       parent_monitor_ref: parent_monitor_ref,
       df: df,
       keys: keys,
       total_rows: total_rows
     }}
  end

  @impl true
  def handle_info({:connect, pid}, state) do
    columns = Table.keys_to_columns(state.keys)
    features = [:pagination, :sorting]

    send(pid, {:connect_reply, %{name: "DataFrame", columns: columns, features: features}})

    {:noreply, state}
  end

  def handle_info({:get_rows, pid, rows_spec}, state) do
    records = get_records(state.df, rows_spec)
    rows = Enum.map(records, &Table.record_to_row(&1, state.keys))

    send(pid, {:rows, %{rows: rows, total_rows: state.total_rows, columns: :initial}})

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _object, _reason}, %{parent_monitor_ref: ref} = state) do
    {:stop, :shutdown, state}
  end

  defp get_records(df, rows_spec) do
    df =
      if order_by = rows_spec[:order_by] do
        Explorer.DataFrame.arrange(df, [{order_by, rows_spec.order}])
      else
        df
      end

    df = Explorer.DataFrame.slice(df, rows_spec.offset, rows_spec.limit)

    {cols, lists} = df |> Explorer.DataFrame.to_map() |> Enum.unzip()
    cols = Enum.map(cols, &to_string/1)

    lists
    |> Enum.zip()
    |> Enum.map(fn row ->
      cols
      |> Enum.zip(Tuple.to_list(row))
      |> Map.new()
    end)
  end
end

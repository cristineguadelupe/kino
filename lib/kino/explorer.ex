defmodule Kino.Explorer do
  @moduledoc """
  A widget for interactively viewing `Explorer.DataFrame`.

  ## Examples

      df = Explorer.Datasets.fossil_fuels()
      Kino.Explorer.new(df)
  """

  use GenServer, restart: :temporary

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

    {:ok,
     %{
       parent_monitor_ref: parent_monitor_ref,
       df: df,
       total_rows: total_rows
     }}
  end

  @impl true
  def handle_info({:connect, pid}, state) do
    names = Explorer.DataFrame.names(state.df)
    dtypes = Explorer.DataFrame.dtypes(state.df)

    columns =
      names
      |> Enum.zip(dtypes)
      |> Enum.map(fn {name, dtype} ->
        %{key: name, label: to_string(name), type: to_string(dtype)}
      end)

    features = [:pagination, :sorting]

    send(pid, {:connect_reply, %{name: "DataFrame", columns: columns, features: features}})

    {:noreply, state}
  end

  def handle_info({:get_rows, pid, rows_spec}, state) do
    records = get_records(state.df, rows_spec)

    rows =
      Enum.map(records, fn record ->
        fields =
          Map.new(record, fn {col_name, value} ->
            {col_name, to_string(value)}
          end)

        %{id: nil, fields: fields}
      end)

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
      Enum.zip(cols, Tuple.to_list(row))
    end)
  end
end

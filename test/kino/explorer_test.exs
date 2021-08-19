defmodule Kino.ExplorerTest do
  use ExUnit.Case, async: true

  defp people_df() do
    Explorer.DataFrame.from_map(%{
      id: [3, 1, 2],
      name: ["Amy Santiago", "Jake Peralta", "Terry Jeffords"]
    })
  end

  describe "connecting" do
    test "connect reply contains columns definition" do
      widget = Kino.Explorer.new(people_df())

      send(widget.pid, {:connect, self()})

      assert_receive {:connect_reply,
                      %{
                        columns: [
                          %{key: "id", label: "id", type: "integer"},
                          %{key: "name", label: "name", type: "string"}
                        ],
                        features: [:pagination, :sorting]
                      }}
    end
  end

  @default_rows_spec %{offset: 0, limit: 10, order_by: nil, order: :asc}

  describe "querying rows" do
    test "rows order matches the given data frame by default" do
      widget = Kino.Explorer.new(people_df())
      connect_self(widget)

      send(widget.pid, {:get_rows, self(), @default_rows_spec})

      assert_receive {:rows,
                      %{
                        rows: [
                          %{id: _, fields: %{"id" => "3", "name" => "Amy Santiago"}},
                          %{id: _, fields: %{"id" => "1", "name" => "Jake Peralta"}},
                          %{id: _, fields: %{"id" => "2", "name" => "Terry Jeffords"}}
                        ],
                        total_rows: 3,
                        columns: :initial
                      }}
    end

    test "supports sorting by other columns" do
      widget = Kino.Explorer.new(people_df())
      connect_self(widget)

      spec = %{
        offset: 0,
        limit: 10,
        order_by: "name",
        order: :desc
      }

      send(widget.pid, {:get_rows, self(), spec})

      assert_receive {:rows,
                      %{
                        rows: [
                          %{id: _, fields: %{"id" => "2", "name" => "Terry Jeffords"}},
                          %{id: _, fields: %{"id" => "1", "name" => "Jake Peralta"}},
                          %{id: _, fields: %{"id" => "3", "name" => "Amy Santiago"}}
                        ],
                        total_rows: 3,
                        columns: :initial
                      }}
    end

    test "supports offset and limit" do
      widget = Kino.Explorer.new(people_df())
      connect_self(widget)

      spec = %{
        offset: 1,
        limit: 1,
        order_by: "id",
        order: :asc
      }

      send(widget.pid, {:get_rows, self(), spec})

      assert_receive {:rows,
                      %{
                        rows: [
                          %{id: _, fields: %{"id" => "2", "name" => "Terry Jeffords"}}
                        ],
                        total_rows: 3,
                        columns: :initial
                      }}
    end
  end

  defp connect_self(widget) do
    send(widget.pid, {:connect, self()})
    assert_receive {:connect_reply, %{}}
  end
end

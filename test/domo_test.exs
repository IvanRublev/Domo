defmodule DomoTest do
  use Domo.FileCase, async: false

  doctest Domo

  alias Mix.Tasks.Compile.Domo, as: DomoMixTask

  Code.compiler_options(no_warn_undefined: [Receiver, Game, Customer, Airplane, Airplane.Seat])

  setup_all do
    Code.compiler_options(ignore_module_conflict: true)
    File.mkdir_p!(tmp_path())

    on_exit(fn ->
      File.rm_rf(tmp_path())
      Code.compiler_options(ignore_module_conflict: false)
    end)

    on_exit(fn ->
      ResolverTestHelper.stop_project_palnner()
    end)
  end

  describe "Domo library" do
    test "adds the constructor and verification functions to a struct" do
      [path] = compile_receiver_struct!()
      on_exit(fn -> File.rm!(path) end)

      {:ok, []} = DomoMixTask.run([])

      assert Kernel.function_exported?(Receiver, :new, 1)
      assert Kernel.function_exported?(Receiver, :new_ok, 1)
      assert Kernel.function_exported?(Receiver, :ensure_type!, 1)
      assert Kernel.function_exported?(Receiver, :ensure_type_ok, 1)
    end

    test "ensures data integrity of a struct by matching to it's type" do
      [path] = compile_receiver_struct!()
      on_exit(fn -> File.rm!(path) end)

      {:ok, []} = DomoMixTask.run([])

      bob = Receiver.new(title: :mr, name: "Bob", age: 27)
      assert %{__struct__: Receiver, title: :mr, name: "Bob", age: 27} = bob

      assert_raise ArgumentError,
                   """
                   the following values mismatch expected types of fields of \
                   struct Receiver:

                   Invalid value 27.5 for field :age. Expected the value matching \
                   the integer() type.\
                   """,
                   fn ->
                     _ = Receiver.new(title: :mr, name: "Bob", age: 27.5)
                   end

      assert %{__struct__: Receiver, title: :dr, age: 33} =
               Receiver.ensure_type!(%{bob | title: :dr, age: 33})

      assert_raise ArgumentError, ~r/Invalid value.*field :title.*field :age/s, fn ->
        _ = Receiver.ensure_type!(%{bob | title: "dr", age: 33.0})
      end
    end

    test "ensures data integrity of a struct with a sum type field" do
      [path] = compile_game_struct!()
      on_exit(fn -> File.rm!(path) end)

      {:ok, []} = DomoMixTask.run([])

      assert_raise ArgumentError, ~r/Invalid value nil for field :status/s, fn ->
        _ = Game.new(status: nil)
      end

      game = Game.new(status: :not_started)
      assert %{__struct__: Game} = game

      assert_raise ArgumentError, ~r/Invalid value :in_progress for field :status/s, fn ->
        _ = %{game | status: :in_progress} |> Game.ensure_type!()
      end

      assert %{__struct__: Game} =
               %{game | status: {:in_progress, ["player1", "player2"]}} |> Game.ensure_type!()

      assert_raise ArgumentError,
                   ~r/Invalid value {:wining_player, :second} for field :status/s,
                   fn ->
                     _ = %{game | status: {:wining_player, :second}} |> Game.ensure_type!()
                   end

      assert %{__struct__: Game} =
               %{game | status: {:wining_player, "player2"}} |> Game.ensure_type!()
    end

    test "ensures data integrity of composed structs" do
      paths = compile_customer_structs!()

      on_exit(fn ->
        Enum.map(paths, &File.rm!/1)
      end)

      {:ok, []} = DomoMixTask.run([])

      alias Customer.{
        Address,
        DeliveryInfo
      }

      address = struct!(Address, %{country: "DE", city: "HH", line1: "Rathausmarkt, 1"})
      delivery_info = struct!(DeliveryInfo, %{address: address})

      assert %{__struct__: Customer} = Customer.new(delivery_info: delivery_info)

      assert_raise ArgumentError,
                   ~r/Invalid value.*for field :delivery_info.*Value of field :address.*is invalid/s,
                   fn ->
                     malformed_address =
                       struct!(Address, %{
                         country: :de,
                         city: :hh,
                         line1: "Rathausmarkt, 1"
                       })

                     delivery_info = struct!(DeliveryInfo, %{address: malformed_address})

                     _ = Customer.new(delivery_info: delivery_info)
                   end
    end

    test """
    ensures data integrity of the depending struct when the type of dependant struct \
    Not using Domo changes alongside with adding of a struct using Domo
    """ do
      paths = compile_airplane_and_seat_structs!()

      on_exit(fn ->
        Enum.each(paths, &File.rm!(&1))
      end)

      {:ok, []} = DomoMixTask.run([])

      seat = struct!(Airplane.Seat, id: "A2")
      assert _ = apply(Airplane, :new, [[seats: [seat]]])

      :code.delete(Airplane.Seat)
      :code.purge(Airplane.Seat)

      compile_seat_with_atom_id!()
      compile_side_module_using_domo!()

      {:ok, []} = DomoMixTask.run([])

      assert_raise ArgumentError,
                   ~r/Invalid value.*for field :seats.*The field with key :id.*is invalid/s,
                   fn ->
                     seat = struct!(Airplane.Seat, id: "A2")
                     _ = apply(Airplane, :new, [[seats: [seat]]])
                   end
    end

    test "provides tagged tuple --- operator and helper functions" do
      alias Domo.TaggedTuple
      use TaggedTuple

      autumn = :temperature --- :celcius --- 15

      assert autumn === {:temperature, {:celcius, 15}}

      assert :temperature --- measure --- value = autumn
      assert measure == :celcius
      assert value == 15

      assert TaggedTuple.tag(15, :temperature --- :celcius) == autumn

      assert TaggedTuple.untag!(autumn, :temperature) ==
               :celcius --- 15

      assert TaggedTuple.untag!(autumn, :temperature --- :celcius) ==
               15
    end
  end

  defp compile_receiver_struct! do
    path = tmp_path("/receiver.ex")

    File.write!(path, """
    defmodule Receiver do
      use Domo

      @enforce_keys [:title, :name]
      defstruct [:title, :name, :age]

      @type title :: :mr | :ms | :dr
      @type name :: String.t()
      @type age :: integer
      @type t :: %__MODULE__{title: title(), name: name(), age: age()}
    end
    """)

    compile_path_to_beam!([path])
  end

  defp compile_game_struct! do
    path = tmp_path("/game.ex")

    File.write!(path, """
    defmodule Game do
      use Domo

      @enforce_keys [:status]
      defstruct [:status]

      @type player :: String.t()
      @type t :: %__MODULE__{
            status: :not_started | {:in_progress, [player()]} | {:wining_player, player()}
          }
    end
    """)

    compile_path_to_beam!([path])
  end

  defp compile_customer_structs! do
    address_path = tmp_path("/address.ex")

    File.write!(address_path, """
    defmodule Customer.Address do
      use Domo

      @enforce_keys [:country, :city, :line1]
      defstruct [:country, :city, :line1, :line2]

      @type t :: %__MODULE__{
              country: String.t(),
              city: String.t(),
              line1: String.t(),
              line2: String.t() | nil
            }
    end
    """)

    delivery_path = tmp_path("/delivery.ex")

    File.write!(delivery_path, """
    defmodule Customer.DeliveryInfo do
      use Domo

      alias Customer.Address

      @enforce_keys [:address]
      defstruct [:address]

      @type t :: %__MODULE__{address: Address.t()}
    end
    """)

    customer_path = tmp_path("/customer.ex")

    File.write!(customer_path, """
    defmodule Customer do
      use Domo

      alias Customer.DeliveryInfo

      @enforce_keys [:delivery_info]
      defstruct [:delivery_info]

      @type t :: %__MODULE__{delivery_info: DeliveryInfo.t()}
    end
    """)

    compile_path_to_beam!([address_path, delivery_path, customer_path])
  end

  defp compile_airplane_and_seat_structs! do
    airplane_path = tmp_path("/airplane.ex")

    File.write!(airplane_path, """
    defmodule Airplane do
      use Domo

      @enforce_keys [:seats]
      defstruct [:seats]

      @type t :: %__MODULE__{seats: [Airplane.Seat.t()]}
    end
    """)

    seat_path = tmp_path("/seat.ex")

    File.write!(seat_path, """
    defmodule Airplane.Seat do
      @enforce_keys [:id]
      defstruct [:id]

      @type t :: %__MODULE__{id: String.t()}
    end
    """)

    compile_path_to_beam!([seat_path, airplane_path])
  end

  defp compile_seat_with_atom_id! do
    seat_path = tmp_path("/seat.ex")

    File.write!(seat_path, """
    defmodule Airplane.Seat do
      @enforce_keys [:id]
      defstruct [:id]

      @type t :: %__MODULE__{id: atom()}
    end
    """)

    compile_path_to_beam!([seat_path])
  end

  defp compile_side_module_using_domo! do
    side_module_path = tmp_path("/side_module.ex")

    File.write!(side_module_path, """
    defmodule SideModule do
      use Domo

      defstruct [:first]
      @type t :: %__MODULE__{first: atom}
    end
    """)

    compile_path_to_beam!([side_module_path])
  end

  defp compile_path_to_beam!(path_list) do
    Kernel.ParallelCompiler.compile_to_path(path_list, Mix.Project.compile_path())
    path_list
  end
end

defmodule DomoTest do
  use Domo.FileCase, async: false
  use Placebo

  import ExUnit.CaptureIO

  alias Mix.Task.Compiler.Diagnostic
  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask
  alias Domo.CodeEvaluation
  alias Domo.ElixirVersion
  alias Domo.MixProject

  CompilerHelpers.join_compiler_option(
    :no_warn_undefined,
    [
      Account,
      AccountAnyPrecond,
      AccountCustomErrors,
      AccountCustomizedMessages,
      AccountOpaquePrecond,
      Airplane,
      Airplane.Seat,
      Article,
      Apple,
      Arena,
      Book,
      Customer,
      EctoPassenger,
      FruitBasket,
      Game,
      Leaf,
      LeafHolder,
      Library,
      Library.Book,
      Library.Book.Author,
      Library.Shelve,
      MemonlyStruct,
      Money,
      Orange,
      Order,
      PostFieldAndNestedPrecond,
      PostFieldPrecond,
      PostFieldPrecond.CommentNoTPrecond,
      PostNestedPecond,
      PostNestedPecond.CommentTPrecond,
      PublicLibrary,
      Receiver,
      ReceiverUserTypeAfterT,
      Shelf,
      WebService
    ]
  )

  describe "Domo library" do
    test "adds the constructor and verification functions to a struct" do
      DomoMixTask.start_plan_collection()
      compile_receiver_struct()
      DomoMixTask.process_plan({:ok, []}, [])

      assert Kernel.function_exported?(Receiver, :new!, 1)
      assert Kernel.function_exported?(Receiver, :new, 1)
      assert Kernel.function_exported?(Receiver, :ensure_type!, 1)
      assert Kernel.function_exported?(Receiver, :ensure_type, 1)
    end

    test "generates TypeEnsurer modules for Elixir structs from standard library" do
      for elixir_module <- [
            Macro.Env,
            IO.Stream,
            GenEvent.Stream,
            Date.Range,
            Range,
            Regex,
            Task,
            URI,
            Version,
            Date,
            DateTime,
            NaiveDateTime,
            Time,
            File.Stat,
            File.Stream
          ] do
        type_ensurer = Module.concat(elixir_module, TypeEnsurer)
        assert Code.ensure_loaded?(type_ensurer) == true, "#{elixir_module} has no TypeEnsurer"
      end
    end

    test "returns error for MapSet due to unsupported of t(value) types" do
      DomoMixTask.start_plan_collection()
      compile_mapset_holder_struct()
      assert {:error, [%{message: message}]} = DomoMixTask.process_plan({:ok, []}, [])

      assert message =~ """
             Domo.TypeEnsurerFactory.Resolver failed to resolve fields type \
             of the MapSetHolder struct due to parametrized type referenced \
             by MapSet.t() is not supported.\
             Please, define custom user type and validate fields of MapSet \
             in the precondition function attached like the following:

                 @type remote_type :: term()
                 precond remote_type: &validate_fields_of_struct/1

             Then reference remote_type instead of MapSet.t()
             """
    end

    test "returns error for owned module with local t(value) type" do
      DomoMixTask.start_plan_collection()
      compile_parametrized_field_struct()
      assert {:error, [%{message: message}]} = DomoMixTask.process_plan({:ok, []}, [])

      assert message =~ """
             Domo.TypeEnsurerFactory.Resolver failed to resolve fields type \
             of the ParametrizedField struct due to parametrized type referenced \
             by ParametrizedField.set() is not supported.\
             Please, define custom user type and validate fields of ParametrizedField \
             in the precondition function attached like the following:

                 @type remote_type :: term()
                 precond remote_type: &validate_fields_of_struct/1

             Then reference remote_type instead of ParametrizedField.set()
             """
    end

    test "tells whether struct module has TypeEnsurer" do
      DomoMixTask.start_plan_collection()
      compile_receiver_struct()
      DomoMixTask.process_plan({:ok, []}, [])

      assert Domo.has_type_ensurer?(Receiver) == true
      assert Domo.has_type_ensurer?(CustomStruct) == false
    end

    test "ensures data integrity of a struct by matching to it's type" do
      DomoMixTask.start_plan_collection()
      compile_receiver_struct()
      DomoMixTask.process_plan({:ok, []}, [])

      bob = Receiver.new!(title: :mr, name: "Bob", age: 27)
      assert %{__struct__: Receiver, title: :mr, name: "Bob", age: 27} = bob

      assert_raise ArgumentError,
                   """
                   the following values should have types defined for fields of the Receiver struct:
                    * Invalid value 27.5 for field :age of %Receiver{}. Expected the value matching \
                   the integer() type.\
                   """,
                   fn ->
                     _ = Receiver.new!(title: :mr, name: "Bob", age: 27.5)
                   end

      assert %{__struct__: Receiver, title: :dr, age: 33} = Receiver.ensure_type!(%{bob | title: :dr, age: 33})

      assert_raise ArgumentError, ~r/Invalid value.*field :title.*field :age/s, fn ->
        _ = Receiver.ensure_type!(%{bob | title: "dr", age: 33.0})
      end
    end

    test "ensures data integrity of a struct that has referenced user types defined after t type" do
      DomoMixTask.start_plan_collection()
      compile_receiver_user_type_after_t_struct()
      DomoMixTask.process_plan({:ok, []}, [])

      bob = ReceiverUserTypeAfterT.new!(title: :mr, name: "Bob", age: 27)
      assert %{__struct__: ReceiverUserTypeAfterT, title: :mr, name: "Bob", age: 27} = bob

      assert_raise ArgumentError,
                   """
                   the following values should have types defined for fields of the ReceiverUserTypeAfterT struct:
                    * Invalid value 27.5 for field :age of %ReceiverUserTypeAfterT{}. Expected the value matching \
                   the integer() type.\
                   """,
                   fn ->
                     _ = ReceiverUserTypeAfterT.new!(title: :mr, name: "Bob", age: 27.5)
                   end

      assert %{__struct__: ReceiverUserTypeAfterT, title: :dr, age: 33} = ReceiverUserTypeAfterT.ensure_type!(%{bob | title: :dr, age: 33})

      assert_raise ArgumentError, ~r/Invalid value.*field :title.*field :age/s, fn ->
        _ = ReceiverUserTypeAfterT.ensure_type!(%{bob | title: "dr", age: 33.0})
      end
    end

    test "ensures data integrity of a struct with a sum | type field" do
      DomoMixTask.start_plan_collection()
      compile_game_struct()
      DomoMixTask.process_plan({:ok, []}, [])

      assert_raise ArgumentError, ~r/Invalid value nil for field :status/s, fn ->
        _ = Game.new!(status: nil)
      end

      game = Game.new!(status: :not_started)
      assert %{__struct__: Game} = game

      assert_raise ArgumentError, ~r/Invalid value :in_progress for field :status/s, fn ->
        _ = %{game | status: :in_progress} |> Game.ensure_type!()
      end

      assert %{__struct__: Game} = %{game | status: {:in_progress, ["player1", "player2"]}} |> Game.ensure_type!()

      assert_raise ArgumentError,
                   ~r/Invalid value {:wining_player, :second} for field :status/s,
                   fn ->
                     _ = %{game | status: {:wining_player, :second}} |> Game.ensure_type!()
                   end

      assert %{__struct__: Game} = %{game | status: {:wining_player, "player2"}} |> Game.ensure_type!()
    end

    test "ensures data integrity of a struct with list field having sum | element type" do
      DomoMixTask.start_plan_collection()
      compile_fruit_structs()
      DomoMixTask.process_plan({:ok, []}, [])

      apple = Apple.new!()
      orange = Orange.new!()

      assert_raise ArgumentError, ~r/Invalid value nil for field :fruits/s, fn ->
        _ = FruitBasket.new!(fruits: nil)
      end

      basket = FruitBasket.new!(fruits: [])

      assert_raise ArgumentError, ~r/- The element at index 1 has value nil that is invalid./s, fn ->
        _ = %{basket | fruits: [apple, nil]} |> FruitBasket.ensure_type!()
      end

      FruitBasket.new!(fruits: [apple, orange])
      assert %{__struct__: FruitBasket} = %{basket | fruits: [apple, orange]} |> FruitBasket.ensure_type!()
    end

    test "ensures data integrity of a struct with a field referencing erlang type" do
      DomoMixTask.start_plan_collection()
      compile_web_service_struct()
      DomoMixTask.process_plan({:ok, []}, [])

      assert_raise ArgumentError, ~r/Invalid value nil for field :port/s, fn ->
        _ = WebService.new!(port: nil)
      end

      game = WebService.new!(port: 8080)
      assert %{__struct__: WebService} = game
    end

    test "ensures data integrity of nested structs" do
      DomoMixTask.start_plan_collection()
      compile_customer_structs()
      {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

      alias Customer.{
        Address,
        DeliveryInfo
      }

      address = struct!(Address, %{country: "DE", city: "HH", line1: "Rathausmarkt, 1"})
      delivery_info = struct!(DeliveryInfo, %{address: address})

      assert %{__struct__: Customer} = Customer.new!(delivery_info: delivery_info)

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

                     _ = Customer.new!(delivery_info: delivery_info)
                   end
    end

    test "ensures data integrity of a struct with a field referencing the same struct" do
      DomoMixTask.start_plan_collection()
      compile_leaf_structs("LeafHolder.a_leaf() | nil")
      {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

      assert {:ok, _} = Leaf.new(value: 0, next_leaf: Leaf.new!(value: 1, next_leaf: nil))
      assert {:error, _} = Leaf.new(value: 0, next_leaf: :atom)

      DomoMixTask.start_plan_collection()
      compile_leaf_structs("t() | nil")
      {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

      assert {:ok, _} = Leaf.new(value: 0, next_leaf: Leaf.new!(value: 1, next_leaf: nil))
      assert {:error, _} = Leaf.new(value: 0, next_leaf: :atom)
    end

    test "return error for Non struct type referencing itself" do
      DomoMixTask.start_plan_collection()
      compile_leaf_structs("LeafHolder.self_ref()")
      assert {:error, [%{message: message}]} = DomoMixTask.process_plan({:ok, []}, [])

      assert message =~
               "Leaf struct because of the self referencing type LeafHolder.self_ref(). Only struct types referencing themselves are supported."

      DomoMixTask.start_plan_collection()
      compile_leaf_structs("LeafHolder.rem_self_ref()")
      assert {:error, [%{message: message}]} = DomoMixTask.process_plan({:ok, []}, [])

      assert message =~
               "Leaf struct because of the self referencing type LeafHolder.rem_self_ref(). Only struct types referencing themselves are supported."
    end

    test "ensures Ecto schema" do
      DomoMixTask.start_plan_collection()
      compile_ecto_passenger_struct()
      {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

      assert %{__struct__: EctoPassenger, __meta__: _} =
               EctoPassenger.new!(
                 first_name: "John",
                 belonging: 1,
                 love: :one,
                 items: [0.5, 0.6],
                 list: [:one, :two],
                 forest: 7,
                 ideas: [0.1, 10.1]
               )

      not_loaded_association = %Ecto.Association.NotLoaded{
        __field__: :filed,
        __owner__: "owner",
        __cardinality__: :cardinality
      }

      assert %{__struct__: EctoPassenger, __meta__: _} =
               EctoPassenger.new!(
                 first_name: "John",
                 belonging: not_loaded_association,
                 love: not_loaded_association,
                 items: not_loaded_association,
                 list: not_loaded_association,
                 forest: not_loaded_association,
                 ideas: not_loaded_association
               )

      assert_raise ArgumentError,
                   ~r/Invalid value.*for field :first_name/s,
                   fn ->
                     _ = EctoPassenger.new!(first_name: :john)
                   end

      assert_raise ArgumentError,
                   ~r/Invalid value.*for field :belonging/s,
                   fn ->
                     _ = EctoPassenger.new!(belonging: :john)
                   end

      assert_raise ArgumentError,
                   ~r/Invalid value.*for field :love/s,
                   fn ->
                     _ = EctoPassenger.new!(love: "one")
                   end

      assert_raise ArgumentError,
                   ~r/Invalid value.*for field :items/s,
                   fn ->
                     _ = EctoPassenger.new!(items: ["one"])
                   end

      assert_raise ArgumentError,
                   ~r/Invalid value.*for field :list/s,
                   fn ->
                     _ = EctoPassenger.new!(list: [1])
                   end

      assert_raise ArgumentError,
                   ~r/Invalid value.*for field :forest/s,
                   fn ->
                     _ = EctoPassenger.new!(forest: "tall")
                   end

      assert_raise ArgumentError,
                   ~r/Invalid value.*for field :ideas/s,
                   fn ->
                     _ = EctoPassenger.new!(ideas: ["tall"])
                   end
    end

    test "ensures data integrity with struct field type precondition" do
      DomoMixTask.start_plan_collection()
      compile_account_struct()
      {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

      account = Account.new!(id: "adk-47896", name: "John Smith", money: 2578)
      assert %{__struct__: Account} = account

      message_regex =
        Regex.compile!(
          Regex.escape("""
          the following values should have types defined for fields of the Account struct:
           * Invalid value "ak47896" for field :id of %Account{}. Expected the value matching the <<_::_*8>> type. \
          And a true value from the precondition function \
          """) <> ".* defined for Account.id"
        )

      assert_raise ArgumentError, message_regex, fn ->
        _ = Account.new!(id: "ak47896", name: "John Smith", money: 2578)
      end

      assert_raise ArgumentError, ~r/Invalid value %Account{.*id: \"adk-47896\".*}.*\
a true value from the precondition.*defined for Account.t\(\) type./s, fn ->
        _ = Account.new!(id: "adk-47896", name: "John Smith", money: 2)
      end

      assert %{__struct__: Account} = %{account | money: 3500} |> Account.ensure_type!()

      assert_raise ArgumentError, ~r/Invalid value -1 for field :money/s, fn ->
        _ = %{account | money: -1} |> Account.ensure_type!()
      end

      assert_raise ArgumentError, ~r/Invalid value %Account{.*id: \"adk-47896\".*}.*\
a true value from the precondition.*defined for Account.t\(\) type./s, fn ->
        _ = %{account | money: 3} |> Account.ensure_type!()
      end
    end

    test "ensures data integrity with either field precondition or t() type precondition for field's struct value" do
      DomoMixTask.start_plan_collection()
      compile_post_comment_structs()
      DomoMixTask.process_plan({:ok, []}, [])

      assert %{__struct__: PostFieldPrecond} = PostFieldPrecond.new!(comment: struct!(PostFieldPrecond.CommentNoTPrecond, id: 1))

      assert_raise ArgumentError, ~r/&1.id > 0/, fn ->
        _ = PostFieldPrecond.new!(comment: struct!(PostFieldPrecond.CommentNoTPrecond, id: 0))
      end

      assert %{__struct__: PostNestedPecond} = PostNestedPecond.new!(comment: struct!(PostNestedPecond.CommentTPrecond, id: 2))

      assert_raise ArgumentError, ~r/&1.id > 1/, fn ->
        _ = PostNestedPecond.new!(comment: struct!(PostNestedPecond.CommentTPrecond, id: 1))
      end

      DomoMixTask.start_plan_collection()
      [path] = compile_post_field_and_nested_precond_struct()

      me = self()

      msg =
        capture_io(fn ->
          assert {:error, [diagnostic]} = DomoMixTask.process_plan({:ok, []}, [])
          send(me, diagnostic)
        end)

      assert_receive %Diagnostic{
        compiler_name: "Domo",
        file: ^path,
        position: 1,
        message:
          "Domo.TypeEnsurerFactory.Resolver failed to resolve fields type of the PostFieldAndNestedPrecond struct due to \"Precondition conflict " <>
            _,
        severity: :error
      }

      assert msg =~ "== Type ensurer compilation error in file #{path}"

      assert msg =~
               "Domo.TypeEnsurerFactory.Resolver failed to resolve fields type of the PostFieldAndNestedPrecond struct due to \"Precondition conflict"
    end

    test "ensures data integrity with struct field type referencing any and having precondition" do
      DomoMixTask.start_plan_collection()
      compile_account_any_precond_struct()
      {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

      account = AccountAnyPrecond.new!(id: 1)
      assert %{__struct__: AccountAnyPrecond} = account

      assert_raise ArgumentError, ~r/Expected the value matching the any\(\) type. And a true value from the precondition function/s, fn ->
        _ = AccountAnyPrecond.new!(id: "adk-47896")
      end
    end

    test "ensures data integrity with @opaque struct field type and having precondition" do
      DomoMixTask.start_plan_collection()
      compile_account_opaque_precond_struct()
      {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

      account = AccountOpaquePrecond.new!(id: 101)
      assert %{__struct__: AccountOpaquePrecond} = account

      assert_raise ArgumentError,
                   ~r/Expected the value matching the integer\(\) | float\(\) type. And a true value from the precondition function/s,
                   fn ->
                     _ = AccountOpaquePrecond.new!(id: -500)
                   end

      assert_raise ArgumentError,
                   ~r/Invalid value %AccountOpaquePrecond{id: 100}. Expected the value matching the AccountOpaquePrecond.t\(\) type. And a true value from the precondition function/s,
                   fn ->
                     _ = AccountOpaquePrecond.new!(id: 100)
                   end
    end

    test "return custom error from preconditions" do
      DomoMixTask.start_plan_collection()
      compile_account_custom_errors_struct()
      {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

      account = AccountCustomErrors.new!(id: "adk-47896", name: "John Smith", money: 2)
      assert %{__struct__: AccountCustomErrors} = account

      assert_raise RuntimeError,
                   "precond function defined for AccountCustomErrors.money\(\) type should return true | false | :ok | {:error, any()} value",
                   fn ->
                     _ = AccountCustomErrors.new!(id: "adk-47896", name: "John Smith", money: 1)
                   end

      assert_raise ArgumentError,
                   "the following values should have types defined for fields of the AccountCustomErrors struct:\n * Id should match format xxx-12345",
                   fn ->
                     _ = AccountCustomErrors.new!(id: "ak47896", name: "John Smith", money: 2)
                   end

      assert {:error, id: "Id should match format xxx-12345"} = AccountCustomErrors.new(id: "ak47896", name: "John Smith", money: 2)

      assert_raise ArgumentError,
                   "the following values should have types defined for fields of the AccountCustomErrors struct:\n * :empty_name_string",
                   fn ->
                     _ = AccountCustomErrors.new!(id: "adk-47896", name: "", money: 2)
                   end

      assert {:error, name: :empty_name_string} = AccountCustomErrors.new(id: "adk-47896", name: "", money: 2)
    end

    test "returns list of precondition errors or single string message for each field given maybe_filter_precond_errors: true option for *_ok functions" do
      DomoMixTask.start_plan_collection()
      compile_account_struct()
      DomoMixTask.process_plan({:ok, []}, [])

      assert {:error, messages} = Account.new([id: "ak47896", name: :john_smith, money: 0], maybe_filter_precond_errors: true)

      assert [
               name: [
                 "Invalid value :john_smith for field :name of %Account{}. Expected the value matching the <<_::_*8>> type."
               ],
               money: [
                 """
                 Expected the value matching the integer() type. And a true value from \
                 the precondition function "&(&1 > 0 and &1 < 10_000_000)" defined for Account.money() type.\
                 """
               ],
               id: [
                 id_message
               ]
             ] = messages

      assert id_message =~ "String.match?"

      account = struct!(Account, id: "ak47896", name: :john_smith, money: 0)

      assert {:error, messages} = Account.ensure_type(account, maybe_filter_precond_errors: true)

      assert [
               name: [
                 "Invalid value :john_smith for field :name of %Account{}. Expected the value matching the <<_::_*8>> type."
               ],
               money: [
                 """
                 Expected the value matching the integer() type. And a true value from \
                 the precondition function "&(&1 > 0 and &1 < 10_000_000)" defined for Account.money() type.\
                 """
               ],
               id: [
                 id_message
               ]
             ] = messages

      assert id_message =~ "String.match?"

      expected_messages = [
        """
        Expected the value matching the Account.t() type. And a true value from \
        the precondition function \"&(&1.money >= 10)\" defined for Account.t() type.\
        """
      ]

      assert Account.new([id: "akz-47896", name: "John Smith", money: 1], maybe_filter_precond_errors: true) == {:error, t: expected_messages}

      account = struct!(Account, id: "akz-47896", name: "John Smith", money: 1)

      assert Account.ensure_type(account, maybe_filter_precond_errors: true) == {:error, t: expected_messages}

      DomoMixTask.start_plan_collection()
      compile_account_custom_errors_struct()
      DomoMixTask.process_plan({:ok, []}, [])

      expected_messages = ["Id should match format xxx-12345"]

      assert AccountCustomErrors.new([id: "ak47896", name: "John Smith", money: 2], maybe_filter_precond_errors: true) ==
               {:error, id: expected_messages}

      account = struct!(AccountCustomErrors, id: "ak47896", name: "John Smith", money: 2)

      assert AccountCustomErrors.ensure_type(account, maybe_filter_precond_errors: true) == {:error, id: expected_messages}

      DomoMixTask.start_plan_collection()
      compile_money_struct()
      DomoMixTask.process_plan({:ok, []}, [])

      expected_messages = [
        """
        Expected the value matching the float() type. And a true value from the \
        precondition function "&(&1 > 0.5)" defined for Money.float_amount() type.\
        """
      ]

      assert Money.new([amount: 0.3], maybe_filter_precond_errors: true) == {:error, amount: expected_messages}

      money = struct!(Money, amount: 0.3)

      assert Money.ensure_type(money, maybe_filter_precond_errors: true) == {:error, amount: expected_messages}
    end

    test "custom error messages are bypassed as in shape given in precond functions" do
      DomoMixTask.start_plan_collection()
      compile_account_customized_messages_struct()
      {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

      assert {:error, messages} = AccountCustomizedMessages.new(id: "ak47896", money: 0)

      assert messages == [
               money: """
               Invalid value 0 for field :money of %AccountCustomizedMessages{}. Expected the value matching \
               the integer() type. And a true value from the precondition function \"&(&1 > 0 and &1 < 10_000_000)\" defined for AccountCustomizedMessages.money() type.\
               """,
               id: {:format_mismatch, "xxx-yyyyy where x = a-z, y = 0-9"}
             ]

      assert {:error, messages} = AccountCustomizedMessages.new([id: "ak47896", money: 0], maybe_filter_precond_errors: true)

      assert messages == [
               money: [
                 """
                 Expected the value matching the integer() type. And a true value \
                 from the precondition function \"&(&1 > 0 and &1 < 10_000_000)\" defined for AccountCustomizedMessages.money() type.\
                 """
               ],
               id: [{:format_mismatch, "xxx-yyyyy where x = a-z, y = 0-9"}]
             ]

      assert {:error, messages} = AccountCustomizedMessages.new(id: "aky-47896", money: 1)

      assert messages == [t: {:overdraft, :overflow}]

      assert {:error, messages} = AccountCustomizedMessages.new([id: "aky-47896", money: 1], maybe_filter_precond_errors: true)

      assert messages == [t: [{:overdraft, :overflow}]]
    end

    test "returns list of precondition errors lifted from nested structs given maybe_filter_precond_errors: true option for *_ok functions" do
      DomoMixTask.start_plan_collection()

      compile_line_item_order_structs(
        """
        precond id: &if(&1 > 10, do: :ok, else: {:error, "Expected id > 10. Got \#{&1}."})
        """,
        "",
        ""
      )

      DomoMixTask.process_plan({:ok, []}, [])

      assert {:error, messages} = Order.new([items: [struct!(LineItem, id: 9)]], maybe_filter_precond_errors: true)
      assert [items: ["Expected id > 10. Got 9."]] = messages

      DomoMixTask.start_plan_collection()
      compile_line_item_order_structs("precond id: &(&1 > 10)", "", "")
      DomoMixTask.process_plan({:ok, []}, [])

      assert {:error, messages} = Order.new([items: [struct!(LineItem, id: 9)]], maybe_filter_precond_errors: true)

      assert [
               items: [
                 "Expected the value matching the integer() type. And a true value from the precondition function \"&(&1 > 10)\" defined for LineItem.id() type."
               ]
             ] = messages

      DomoMixTask.start_plan_collection()

      compile_line_item_order_structs(
        "",
        """
        precond t: &if(&1.id > 10, do: :ok, else: {:error, "Expected struct's id > 10. Got \#{&1.id}."})
        """,
        ""
      )

      DomoMixTask.process_plan({:ok, []}, [])

      assert {:error, messages} = Order.new([items: [struct!(LineItem, id: 9)]], maybe_filter_precond_errors: true)
      assert [items: ["Expected struct's id > 10. Got 9."]] = messages

      DomoMixTask.start_plan_collection()

      compile_line_item_order_structs(
        "",
        """
        precond t: &(&1.id > 10)
        """,
        ""
      )

      DomoMixTask.process_plan({:ok, []}, [])

      assert {:error, messages} = Order.new([items: [struct!(LineItem, id: 9)]], maybe_filter_precond_errors: true)

      assert [
               items: [
                 "Expected the value matching the LineItem.t() type. And a true value from the precondition function \"&(&1.id > 10)\" defined for LineItem.t() type."
               ]
             ] = messages

      DomoMixTask.start_plan_collection()

      compile_line_item_order_structs("", "", """
      precond item: &if(&1.id > 10, do: :ok, else: {:error, "Expected item's id > 10. Got \#{&1.id}."})
      """)

      DomoMixTask.process_plan({:ok, []}, [])

      assert {:error, messages} = Order.new([items: [struct!(LineItem, id: 9)]], maybe_filter_precond_errors: true)
      assert [items: ["Expected item's id > 10. Got 9."]] = messages

      DomoMixTask.start_plan_collection()

      compile_line_item_order_structs("", "", """
      precond item: &(&1.id > 10)
      """)

      DomoMixTask.process_plan({:ok, []}, [])

      assert {:error, messages} = Order.new([items: [struct!(LineItem, id: 9)]], maybe_filter_precond_errors: true)

      assert [
               items: [
                 "Expected the value matching the %LineItem{} type. And a true value from the precondition function \"&(&1.id > 10)\" defined for Order.item() type."
               ]
             ] = messages
    end

    test "returns list of multiple precondition errors lifted from nested structs given maybe_filter_precond_errors: true option for *_ok functions" do
      DomoMixTask.start_plan_collection()

      compile_line_item_order_structs(
        """
        precond id: &if(&1 > 10, do: :ok, else: {:error, "Expected id > 10. Got \#{&1}."})
        """,
        "",
        ""
      )

      DomoMixTask.process_plan({:ok, []}, [])

      assert {:error, messages} = Order.new([items: [struct!(LineItem, id: 9, amount: 0)]], maybe_filter_precond_errors: true)

      assert [
               items: [
                 "Expected id > 10. Got 9.",
                 "Expected the value matching the integer() type. And a true value from the precondition function \"&(&1 > 0)\" defined for LineItem.amount() type."
               ]
             ] = messages

      DomoMixTask.start_plan_collection()

      compile_line_item_order_structs(
        "",
        """
        precond t: &if(&1.id > 10, do: :ok, else: {:error, "Expected struct's id > 10. Got \#{&1.id}."})
        """,
        ""
      )

      DomoMixTask.process_plan({:ok, []}, [])

      assert {:error, messages} = Order.new([items: [struct!(LineItem, id: 9, amount: 0)]], maybe_filter_precond_errors: true)

      assert [
               items: [
                 "Expected the value matching the integer() type. And a true value from the precondition function \"&(&1 > 0)\" defined for LineItem.amount() type."
               ]
             ] = messages
    end

    test "returns list of precondition errors from 3 level deep nested struct" do
      DomoMixTask.start_plan_collection()
      compile_public_library_struct()
      DomoMixTask.process_plan({:ok, []}, [])

      library = struct!(PublicLibrary, %{shelves: [struct!(Shelf, %{books: [struct!(Book, %{title: "", pages: 1})]})]})

      assert {:error, messages} = PublicLibrary.ensure_type(library, maybe_filter_precond_errors: true)
      assert [shelves: ["Book title is required.", "Book should have more then 3 pages. Given (1)."]] = messages
    end

    test "recompiles type ensurer of depending struct when the type of the struct it depends on changes" do
      DomoMixTask.start_plan_collection([])
      [_airplane_path, seat_path] = compile_airplane_and_seat_structs()
      {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

      seat = struct!(Airplane.Seat, id: "A2")
      assert _ = Airplane.new!(seats: [seat])

      File.rm!(seat_path)
      :code.purge(Airplane.Seat)
      :code.delete(Airplane.Seat)

      DomoMixTask.start_plan_collection([])
      compile_seat_with_atom_id()
      {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

      assert_raise ArgumentError,
                   ~r/Invalid value.*for field :seats.*Value of field :id is invalid/s,
                   fn ->
                     seat = struct!(Airplane.Seat, id: "A2")
                     _ = Airplane.new!(seats: [seat])
                   end
    end

    for {fun, correct_fun_call, wrong_fun_call} <- [
          {"new!/1", "Foo.new!(title: \"hello\")", "Foo.new!(title: :hello)"},
          {"new/1", "Foo.new(title: \"hello\")", "Foo.new(title: :hello)"},
          {"ensure_type!/1", "Foo.ensure_type!(%Foo{title: \"hello\"})", "Foo.ensure_type!(%Foo{title: :hello})"},
          {"ensure_type/1", "Foo.ensure_type(%Foo{title: \"hello\"})", "Foo.ensure_type(%Foo{title: :hello})"}
        ] do
      test "ensures data integrity of a struct built at the compile time via #{fun} for being a default value" do
        DomoMixTask.start_plan_collection()
        compile_module_with_default_struct(unquote(correct_fun_call))
        assert {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

        refute is_nil(struct!(FooHolder))

        :code.purge(Elixir.Foo.TypeEnsurer)
        :code.delete(Elixir.Foo.TypeEnsurer)
        File.rm(Path.join(Mix.Project.compile_path(), "Elixir.Foo.TypeEnsurer.beam"))

        DomoMixTask.start_plan_collection()
        [path] = compile_module_with_default_struct(unquote(wrong_fun_call))

        me = self()

        msg =
          capture_io(fn ->
            assert {:error, [diagnostic]} = DomoMixTask.process_plan({:ok, []}, [])
            send(me, diagnostic)
          end)

        assert_receive %Diagnostic{
          compiler_name: "Elixir",
          file: ^path,
          position: 9,
          message: "Failed to build Foo struct." <> _,
          severity: :error
        }

        assert msg =~ "== Compilation error in file #{path}:9 ==\n** Failed to build Foo struct."

        plan_file = DomoMixTask.manifest_path(MixProjectStubCorrect, :plan)
        refute File.exists?(plan_file)

        types_file = DomoMixTask.manifest_path(MixProjectStubCorrect, :types)
        refute File.exists?(types_file)
      end
    end

    test "ensures that struct default values conform to t() type" do
      DomoMixTask.start_plan_collection()
      compile_struct_with_defaults("id: 1, field: :hello", enforce_keys: nil, t: "id: integer(), field: atom()")
      assert {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

      :code.purge(Elixir.Bar.TypeEnsurer)
      :code.delete(Elixir.Bar.TypeEnsurer)
      File.rm(Path.join(Mix.Project.compile_path(), "Elixir.Bar.TypeEnsurer.beam"))

      DomoMixTask.start_plan_collection()
      [path] = compile_struct_with_defaults(":id, field: :hello", enforce_keys: nil, t: "id: integer(), field: atom()")

      me = self()

      msg =
        capture_io(fn ->
          assert {:error, [diagnostic]} = DomoMixTask.process_plan({:ok, []}, [])
          send(me, diagnostic)
        end)

      assert_receive %Diagnostic{
        compiler_name: "Elixir",
        file: ^path,
        position: 1,
        message: "A default value given via defstruct/1 in Bar module mismatches the type." <> _,
        severity: :error
      }

      assert msg =~ "== Compilation error in file #{path}:1 ==\n** A default value given via defstruct/1 in Bar module mismatches the type."
      assert msg =~ "Invalid value nil for field :id of %Bar{}. Expected the value matching the integer() type."

      :code.purge(Elixir.Bar.TypeEnsurer)
      :code.delete(Elixir.Bar.TypeEnsurer)
      File.rm(Path.join(Mix.Project.compile_path(), "Elixir.Bar.TypeEnsurer.beam"))

      DomoMixTask.start_plan_collection()

      [path] =
        compile_struct_with_defaults(":id, field: :hello",
          enforce_keys: ":id",
          t: "id: integer(), field: integer()"
        )

      me = self()

      msg =
        capture_io(fn ->
          assert {:error, [diagnostic]} = DomoMixTask.process_plan({:ok, []}, [])
          send(me, diagnostic)
        end)

      assert_receive %Diagnostic{
        compiler_name: "Elixir",
        file: ^path,
        position: 1,
        message: "A default value given via defstruct/1 in Bar module mismatches the type." <> _,
        severity: :error
      }

      assert msg =~ "== Compilation error in file #{path}:1 ==\n** A default value given via defstruct/1 in Bar module mismatches the type."
      assert msg =~ "Invalid value :hello for field :field of %Bar{}. Expected the value matching the integer() type."

      :code.purge(Elixir.Bar.TypeEnsurer)
      :code.delete(Elixir.Bar.TypeEnsurer)
      File.rm(Path.join(Mix.Project.compile_path(), "Elixir.Bar.TypeEnsurer.beam"))

      DomoMixTask.start_plan_collection()

      [path] =
        compile_struct_with_defaults("id: 1, field: :hello",
          enforce_keys: nil,
          t: "id: integer(), field: String.t() | nil"
        )

      me = self()

      msg =
        capture_io(fn ->
          assert {:error, [diagnostic]} = DomoMixTask.process_plan({:ok, []}, [])
          send(me, diagnostic)
        end)

      assert_receive %Diagnostic{
        compiler_name: "Elixir",
        file: ^path,
        position: 1,
        message: "A default value given via defstruct/1 in Bar module mismatches the type." <> _,
        severity: :error
      }

      assert msg =~ "== Compilation error in file #{path}:1 ==\n** A default value given via defstruct/1 in Bar module mismatches the type."
      assert msg =~ "Invalid value :hello for field :field of %Bar{}. Expected the value matching the <<_::_*8>> | nil type."

      :code.purge(Elixir.Bar.TypeEnsurer)
      :code.delete(Elixir.Bar.TypeEnsurer)
      File.rm(Path.join(Mix.Project.compile_path(), "Elixir.Bar.TypeEnsurer.beam"))

      DomoMixTask.start_plan_collection()

      [path] =
        compile_struct_with_defaults("id: 1, field: :hello",
          enforce_keys: nil,
          t: "id: integer(), field: atom()",
          precond_t: "precond t: &(&1.id > 10)"
        )

      me = self()

      msg =
        capture_io(fn ->
          assert {:error, [diagnostic]} = DomoMixTask.process_plan({:ok, []}, [])
          send(me, diagnostic)
        end)

      assert_receive %Diagnostic{
        compiler_name: "Elixir",
        file: ^path,
        position: 1,
        message: "A default value given via defstruct/1 in Bar module mismatches the type." <> _,
        severity: :error
      }

      assert msg =~ "== Compilation error in file #{path}:1 ==\n** A default value given via defstruct/1 in Bar module mismatches the type."
      assert msg =~ "And a true value from the precondition function"
      assert msg =~ "&(&1.id > 10)"

      plan_file = DomoMixTask.manifest_path(MixProjectStubCorrect, :plan)
      refute File.exists?(plan_file)

      types_file = DomoMixTask.manifest_path(MixProjectStubCorrect, :types)
      refute File.exists?(types_file)
    end

    test "skips enforced keys during the struct defaults values ensurance" do
      DomoMixTask.start_plan_collection()
      compile_struct_with_defaults("id: 0, field: :hello", enforce_keys: ":id", t: "id: integer(), field: atom()")
      assert {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])
    end

    test "skip keys that are not in t() type during defaults ensurance" do
      DomoMixTask.start_plan_collection()
      compile_struct_with_defaults(":id, :leaf, field: :hello", enforce_keys: nil, t: "field: atom()")
      assert {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])
    end

    test "skips ensurance of struct default values given skip_defaults: true option" do
      Application.put_env(:domo, :skip_defaults, true)

      DomoMixTask.start_plan_collection()
      compile_struct_with_defaults(":id, field: :hello", enforce_keys: nil, t: "id: integer(), field: atom()")
      assert {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

      :code.purge(Elixir.Bar.TypeEnsurer)
      :code.delete(Elixir.Bar.TypeEnsurer)
      File.rm(Path.join(Mix.Project.compile_path(), "Elixir.Bar.TypeEnsurer.beam"))

      Application.put_env(:domo, :skip_defaults, false)

      DomoMixTask.start_plan_collection()

      compile_struct_with_defaults(":id, field: :hello",
        use_opts: "skip_defaults: true",
        enforce_keys: nil,
        t: "id: integer(), field: atom()"
      )

      assert {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])
    after
      Application.delete_env(:domo, :skip_defaults)
    end

    test "skips ensurance of struct default values given ensure_struct_defaults: false option" do
      Application.put_env(:domo, :ensure_struct_defaults, false)

      DomoMixTask.start_plan_collection()
      compile_struct_with_defaults(":id, field: :hello", enforce_keys: nil, t: "id: integer(), field: atom()")
      assert {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

      :code.purge(Elixir.Bar.TypeEnsurer)
      :code.delete(Elixir.Bar.TypeEnsurer)
      File.rm(Path.join(Mix.Project.compile_path(), "Elixir.Bar.TypeEnsurer.beam"))

      Application.put_env(:domo, :ensure_struct_defaults, true)

      DomoMixTask.start_plan_collection()

      compile_struct_with_defaults(":id, field: :hello",
        use_opts: "ensure_struct_defaults: false",
        enforce_keys: nil,
        t: "id: integer(), field: atom()"
      )

      assert {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])
    after
      Application.delete_env(:domo, :ensure_struct_defaults)
    end

    test "recompile module that builds struct using Domo at compile time when the struct's type changes" do
      :code.purge(Elixir.Game.TypeEnsurer)
      :code.delete(Elixir.Game.TypeEnsurer)
      File.rm(Path.join(Mix.Project.compile_path(), "Elixir.Game.TypeEnsurer.beam"))

      DomoMixTask.start_plan_collection()
      compile_game_struct()
      arena_paths = compile_arena_struct()
      DomoMixTask.process_plan({:ok, []}, [])

      assert %{__struct__: Arena, game: %{__struct__: Game, status: :not_started}} = struct!(Arena)

      :code.purge(Game)
      :code.delete(Game)

      DomoMixTask.start_plan_collection()
      compile_game_with_string_status()

      me = self()

      msg =
        capture_io(fn ->
          assert {:error, [diagnostic]} = DomoMixTask.process_plan({:ok, []}, [])
          send(me, diagnostic)
        end)

      expected_output = "Failed to build Game struct.\nInvalid value :not_started for field :status of %Game{}."

      assert msg =~ "/arena.ex:2 ==\n** #{expected_output}"

      assert_receive %Diagnostic{
        compiler_name: "Elixir",
        file: path,
        message: message,
        severity: :error
      }

      assert [path] == arena_paths
      assert message =~ expected_output
    end

    test "pass without crash when the struct using Domo and its dependencies were removed" do
      DomoMixTask.start_plan_collection([])
      [airplane_path, seat_path] = compile_airplane_and_seat_structs()
      {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

      seat = struct!(Airplane.Seat, id: "A2")
      assert _ = Airplane.new!(seats: [seat])

      File.rm!(seat_path)
      :code.purge(Airplane.Seat)
      :code.delete(Airplane.Seat)
      File.rm(Path.join(Mix.Project.compile_path(), "Elixir.Airplane.Seat.TypeEnsurer.beam"))
      File.rm(Path.join(Mix.Project.compile_path(), "Elixir.Airplane.Seat.beam"))
      File.rm!(airplane_path)
      :code.purge(Airplane)
      :code.delete(Airplane)
      File.rm(Path.join(Mix.Project.compile_path(), "Elixir.Airplane.TypeEnsurer.beam"))
      File.rm(Path.join(Mix.Project.compile_path(), "Elixir.Airplane.beam"))

      # when a module was removed and no other module was compiled -> Elixir hasn't been activated -> im_mix_compile?/0 returns false and that were leading to crash
      allow CodeEvaluation.in_mix_compile?(), meck_options: [:passthrough], return: false

      DomoMixTask.start_plan_collection([])
      assert {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])
    end
  end

  describe "Domo library error messages should" do
    test "have underlying error printed for | sum type" do
      DomoMixTask.start_plan_collection()
      compile_money_struct()
      DomoMixTask.process_plan({:ok, []}, [])

      assert_raise ArgumentError,
                   """
                   the following values should have types defined for fields of the Money struct:
                    * Invalid value 0.3 for field :amount of %Money{}. Expected the value \
                   matching the :none | float() | integer() type.
                   Underlying errors:
                      - Expected the value matching the :none type.
                      - Expected the value matching the float() type. And a true value from the precondition function \"&(&1 > 0.5)\" defined for Money.float_amount() type.
                      - Expected the value matching the integer() type.\
                   """,
                   fn ->
                     _ = Money.new!(amount: 0.3)
                   end
    end

    test "returns error for | sum type with details about part that matches most deeply" do
      DomoMixTask.start_plan_collection()
      compile_article_struct()
      {:ok, _} = DomoMixTask.process_plan({:ok, []}, [])

      field_type_str =
        case ElixirVersion.version() do
          [1, minor, _] when minor < 12 ->
            ":none | {:simple, %{author: <<_::_*8>>, published: <<_::_*8>>}} | {:detail, <<_::_*8>> | %{author: <<_::_*8>>, published_updated: :never | <<_::_*8>>}}"

          [1, minor, _] when minor >= 12 ->
            ":none\n| {:simple, %{author: <<_::_*8>>, published: <<_::_*8>>}}\n| {:detail, <<_::_*8>> | %{author: <<_::_*8>>, published_updated: :never | <<_::_*8>>}}"
        end

      assert_raise ArgumentError,
                   """
                   the following values should have types defined for fields of the Article struct:
                    * Invalid value {:detail, %{author: "John Smith", published_updated: {~D[2021-06-20], nil}}} \
                   for field :metadata of %Article{}. Expected the value matching the #{field_type_str} type.
                   Underlying errors:
                      - Expected the value matching the :none type.
                      - The element at index 0 has value :detail that is invalid.
                      - Expected the value matching the :simple type.
                      - The element at index 1 has value %{author: "John Smith", published_updated: {~D[2021-06-20], nil}} that is invalid.
                      - Expected the value matching the <<_::_*8>> type.
                      - The field with key :published_updated has value {~D[2021-06-20], nil} that is invalid.
                      - Expected the value matching the :never type.
                      - Expected the value matching the <<_::_*8>> type.\
                   """,
                   fn ->
                     _ = Article.new!(metadata: {:detail, %{author: "John Smith", published_updated: {~D[2021-06-20], nil}}})
                   end
    end

    test "returns error for most deepest error for nested structs" do
      DomoMixTask.start_plan_collection()
      compile_library_struct()
      DomoMixTask.process_plan({:ok, []}, [])

      message_regex =
        """
        the following values should have types defined for fields of the Library struct:
         * Invalid value [%Library.Shelve{__a5_pattern__}, \
        %Library.Shelve{__b1_pattern__}] for field :shelves of %Library{}. \
        Expected the value matching the [%Library.Shelve{}] type.
        Underlying errors:
           - The element at index 1 has value %Library.Shelve{__b1_pattern__} that is invalid.
           - Value of field :books is invalid due to the following:
             - The element at index 1 has value %Library.Book{__howl_title_pattern__} that is invalid.
             - Value of field :author is invalid due to Invalid value %Library.Book.Author{__name_allen_pattern__} for field :author of %Library.Book{}. \
        Value of field :second_name is invalid due to Invalid value :ginsberg for field :second_name of %Library.Book.Author{}. Expected the value matching the <<_::_*8>> type.
         * Invalid value 1 for field :name of %Library{}. Expected the value matching the <<_::_*8>> type.\
        """
        |> Regex.escape()
        |> String.replace("__a5_pattern__", ".*address: \"A5\".*")
        |> String.replace("__b1_pattern__", ".*address: \"B1\".*")
        |> String.replace("__howl_title_pattern__", ".*title: \"Howl and Other Poems\".*")
        |> String.replace("__name_allen_pattern__", ".*first_name: \"Allen\".*")
        |> Regex.compile!()

      assert_raise ArgumentError,
                   message_regex,
                   fn ->
                     alias Library.Shelve
                     alias Library.Book
                     alias Library.Book.Author

                     _ =
                       Library.new!(
                         name: 1,
                         shelves: [
                           Shelve.new!(
                             address: "A5",
                             books: [Book.new!(title: "On the Road", author: Author.new!(first_name: "Jack", second_name: "Kerouac"))]
                           ),
                           %{
                             Shelve.new!(
                               address: "B1",
                               books: []
                             )
                             | books: [
                                 Book.new!(title: "Naked Lunch", author: Author.new!(first_name: "William S.", second_name: "Burroughs")),
                                 %{
                                   Book.new!(title: "Howl and Other Poems", author: Author.new!(first_name: "-", second_name: "-"))
                                   | author: %{Author.new!(first_name: "Allen", second_name: "") | second_name: :ginsberg}
                                 }
                               ]
                           }
                         ]
                       )
                   end
    end
  end

  defp compile_account_any_precond_struct do
    path = MixProject.out_of_project_tmp_path("/account_any_precond.ex")

    File.write!(path, """
    defmodule AccountAnyPrecond do
      use Domo, skip_defaults: true

      @enforce_keys [:id]
      defstruct @enforce_keys

      @type any_number :: term()
      precond any_number: &is_number(&1)

      @type t :: %__MODULE__{id: any_number()}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_account_opaque_precond_struct do
    path = MixProject.out_of_project_tmp_path("/account_opaque_precond.ex")

    File.write!(path, """
    defmodule AccountOpaquePrecond do
      use Domo, skip_defaults: true

      @enforce_keys [:id]
      defstruct @enforce_keys

      @opaque any_number :: number()
      precond any_number: &(&1) > 0

      @opaque t :: %__MODULE__{id: any_number()}
      precond t: &(&1.id > 100)
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_account_custom_errors_struct do
    path = MixProject.out_of_project_tmp_path("/account_custom_errors.ex")

    File.write!(path, """
    defmodule AccountCustomErrors do
      use Domo, skip_defaults: true

      @enforce_keys [:id, :name, :money]
      defstruct @enforce_keys

      @type any_number :: term()
      precond any_number: &is_number(&1)

      @type name :: String.t()
      precond name: &(if byte_size(&1) > 0, do: :ok, else: {:error, :empty_name_string})

      @type id :: String.t()
      precond id: &(if String.match?(&1, ~r/[a-z]{3}-\\d{5}/), do: :ok, else: {:error, "Id should match format xxx-12345"})

      @type money :: integer()
      precond money: fn value -> if rem(value, 2) == 0, do: true, else: 1 end

      @type t :: %__MODULE__{id: id(), name: name(), money: money()}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_account_struct do
    path = MixProject.out_of_project_tmp_path("/account.ex")

    File.write!(path, """
    defmodule Account do
      use Domo, skip_defaults: true

      @enforce_keys [:id, :name, :money]
      defstruct @enforce_keys

      @type id :: String.t()
      precond id: &(String.match?(&1, ~r/[a-z]{3}-\\d{5}/))

      @type name :: String.t()
      precond name: &(byte_size(&1) > 0)

      @type money :: integer()
      precond money: &(&1 > 0 and &1 < 10_000_000)

      @type t :: %__MODULE__{id: id(), name: name(), money: money()}
      precond t: &(&1.money >= 10)
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_post_comment_structs do
    path = MixProject.out_of_project_tmp_path("/post_comment.ex")

    File.write!(path, """
    defmodule PostFieldPrecond.CommentNoTPrecond do
      use Domo, skip_defaults: true

      @enforce_keys [:id]
      defstruct @enforce_keys

      @type t :: %__MODULE__{id: integer()}
    end

    defmodule PostFieldPrecond do
      use Domo, skip_defaults: true

      alias PostFieldPrecond.CommentNoTPrecond

      @enforce_keys [:comment]
      defstruct @enforce_keys

      @type t :: %__MODULE__{comment: comment_positive_id()}

      @type comment_positive_id :: CommentNoTPrecond.t()
      precond comment_positive_id: &(&1.id > 0)
    end

    defmodule PostNestedPecond.CommentTPrecond do
      use Domo, skip_defaults: true

      @enforce_keys [:id]
      defstruct @enforce_keys

      @type t :: %__MODULE__{id: integer()}
      precond t: &(&1.id > 1)
    end

    defmodule PostNestedPecond do
      use Domo, skip_defaults: true

      alias PostNestedPecond.CommentTPrecond

      @enforce_keys [:comment]
      defstruct @enforce_keys

      @type t :: %__MODULE__{comment: CommentTPrecond.t()}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_post_field_and_nested_precond_struct do
    path = MixProject.out_of_project_tmp_path("/post_field_and_nested_precond.ex")

    File.write!(path, """
    defmodule PostFieldAndNestedPrecond do
      use Domo, skip_defaults: true

      alias PostNestedPecond.CommentTPrecond

      @enforce_keys [:comment]
      defstruct @enforce_keys

      @type t :: %__MODULE__{comment: comment_positive_id()}

      @type comment_positive_id :: CommentTPrecond.t()
      precond comment_positive_id: &(&1 > 2)
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_account_customized_messages_struct do
    path = MixProject.out_of_project_tmp_path("/account_customized_messages.ex")

    File.write!(path, """
    defmodule AccountCustomizedMessages do
      use Domo, skip_defaults: true

      @enforce_keys [:id, :money]
      defstruct @enforce_keys

      @type id :: String.t()
      precond id: &if(String.match?(&1, ~r/[a-z]{3}-\\d{5}/), do: :ok, else: {:error, {:format_mismatch, "xxx-yyyyy where x = a-z, y = 0-9"}})

      @type money :: integer()
      precond money: &(&1 > 0 and &1 < 10_000_000)

      @type t :: %__MODULE__{id: id(), money: money()}
      precond t: &if(&1.money >= 10, do: :ok, else: {:error, {:overdraft, :overflow}})
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_line_item_order_structs(precond_line_item_id, precond_line_item_t, precond_ref_t) do
    path = MixProject.out_of_project_tmp_path("/line_order.ex")

    File.write!(path, """
    defmodule LineItem do
      use Domo, skip_defaults: true
      defstruct [:id, :amount]

      @type id :: integer()
      #{precond_line_item_id}

      @type amount :: integer()
      precond amount: &(&1 > 0)

      @type t :: %__MODULE__{id: id(), amount: amount() | nil}
      #{precond_line_item_t}
    end

    defmodule Order do
      use Domo, skip_defaults: true
      defstruct [:items]

      @type t :: %__MODULE__{items: [item()]}

      @type item :: LineItem.t()
      #{precond_ref_t}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_public_library_struct do
    path = MixProject.out_of_project_tmp_path("/public_library.ex")

    File.write!(path, """
    defmodule Book do
      use Domo

      defstruct [:title, :pages]

      @type title :: String.t()
      precond title: &(if String.length(&1) > 1, do: :ok, else: {:error, "Book title is required."})

      @type pages :: pos_integer()
      precond pages: &(if &1 > 2, do: :ok, else: {:error, "Book should have more then 3 pages. Given (\#{&1})."})

      @type t :: %__MODULE__{title: nil | title(), pages: nil | pages()}
    end

    defmodule Shelf do
      use Domo

      defstruct books: []

      @type t :: %__MODULE__{books: [Book.t()]}
    end

    defmodule PublicLibrary do
      use Domo

      defstruct shelves: []

      @type t :: %__MODULE__{shelves: [Shelf.t()]}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_money_struct do
    path = MixProject.out_of_project_tmp_path("/money.ex")

    File.write!(path, """
    defmodule Money do
      use Domo, skip_defaults: true

      @enforce_keys [:amount]
      defstruct @enforce_keys

      @type float_amount :: float()
      precond float_amount: &(&1 > 0.5)

      @type int_amount :: integer()
      precond int_amount: &(&1 >= 1)

      @type t :: %__MODULE__{amount: :none | float_amount() | int_amount()}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_article_struct do
    path = MixProject.out_of_project_tmp_path("/article.ex")

    File.write!(path, """
    defmodule Article do
      use Domo, skip_defaults: true

      @enforce_keys [:metadata]
      defstruct @enforce_keys

      @type t :: %__MODULE__{metadata: :none | simple_metadata() | detail_metadata()}

      @type simple_metadata :: {:simple, %{author: String.t(), published: String.t()}}
      @type detail_metadata :: {:detail, String.t() | %{author: String.t(), published_updated: :never | String.t()}}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_library_struct do
    path = MixProject.out_of_project_tmp_path("/library.ex")

    File.write!(path, """
    defmodule Library do
      use Domo, skip_defaults: true

      alias Library.Shelve

      @enforce_keys [:name, :shelves]
      defstruct @enforce_keys

      @type t :: %__MODULE__{name: String.t(), shelves: [Shelve.t()]}
    end

    defmodule Library.Shelve do
      use Domo, skip_defaults: true

      alias Library.Book

      @enforce_keys [:address, :books]
      defstruct @enforce_keys

      @type t :: %__MODULE__{address: String.t(), books: [Book.t()]}
    end

    defmodule Library.Book do
      use Domo, skip_defaults: true

      alias Library.Book.Author

      @enforce_keys [:title, :author]
      defstruct @enforce_keys

      @type t :: %__MODULE__{title: String.t(), author: Author.t()}
    end

    defmodule Library.Book.Author do
      use Domo, skip_defaults: true

      @enforce_keys [:first_name, :second_name]
      defstruct @enforce_keys

      @type t :: %__MODULE__{first_name: String.t(), second_name: String.t()}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_receiver_struct do
    path = MixProject.out_of_project_tmp_path("/receiver.ex")

    File.write!(path, """
    defmodule Receiver do
      use Domo, skip_defaults: true

      @enforce_keys [:title, :name]
      defstruct [:title, :name, age: 0, module: Atom]

      @type title :: :mr | :ms | :dr
      @type name :: String.t()
      @type age :: integer
      @type t :: %__MODULE__{title: title(), name: name(), age: age(), module: module()}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_receiver_user_type_after_t_struct do
    path = MixProject.out_of_project_tmp_path("/receiver_user_type_after_t.ex")

    File.write!(path, """
    defmodule ReceiverUserTypeAfterT do
      use Domo, skip_defaults: true

      @enforce_keys [:title, :name]
      defstruct [:title, :name, age: 0]

      @type t :: %__MODULE__{title: title(), name: name(), age: age()}
      @type title :: :mr | :ms | :dr
      @type name :: String.t()
      @type age :: integer
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_game_struct do
    path = MixProject.out_of_project_tmp_path("/game.ex")

    File.write!(path, """
    defmodule Game do
      use Domo, skip_defaults: true

      @enforce_keys [:status]
      defstruct [:status]

      @type player :: String.t()
      @type t :: %__MODULE__{
            status: :not_started | {:in_progress, [player()]} | {:wining_player, player()}
          }
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_fruit_structs do
    path = MixProject.out_of_project_tmp_path("/fruits.ex")

    File.write!(path, """
    defmodule Apple do
      use Domo, skip_defaults: true
      defstruct []
      @type t() :: %__MODULE__{}
    end

    defmodule Orange do
      use Domo, skip_defaults: true
      defstruct []
      @type t() :: %__MODULE__{}
    end

    defmodule FruitBasket do
      use Domo, skip_defaults: true
      defstruct fruits: []
      @type t() :: %__MODULE__{fruits: [Apple.t() | Orange.t()]}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_game_with_string_status do
    path = MixProject.out_of_project_tmp_path("/game.ex")

    File.write!(path, """
    defmodule Game do
      use Domo, skip_defaults: true

      @enforce_keys [:status]
      defstruct [:status]

      @type t :: %__MODULE__{status: String.t()}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_arena_struct do
    path = MixProject.out_of_project_tmp_path("/arena.ex")

    File.write!(path, """
    defmodule Arena do
      defstruct [game: Game.new!(status: :not_started)]

      @type t :: %__MODULE__{game: Game.t()}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_web_service_struct do
    path = MixProject.out_of_project_tmp_path("/web_service.ex")

    File.write!(path, """
    defmodule WebService do
      use Domo, skip_defaults: true

      @enforce_keys [:port]
      defstruct @enforce_keys

      @type t :: %__MODULE__{port: :inet.port_number()}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_mapset_holder_struct do
    path = MixProject.out_of_project_tmp_path("/mapset_holder.ex")

    File.write!(path, """
    defmodule MapSetHolder do
      use Domo

      defstruct [:set]

      @type t :: %__MODULE__{set: MapSet.t() | nil}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_parametrized_field_struct do
    path = MixProject.out_of_project_tmp_path("/parametrized_field.ex")

    File.write!(path, """
    defmodule ParametrizedField do
      use Domo

      defstruct [:set]

      @typep value(t) :: t
      @typep set :: value(any)
      @type t :: %__MODULE__{set: set() | nil}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_ecto_passenger_struct do
    path = MixProject.out_of_project_tmp_path("/ecto_passenger.ex")

    File.write!(path, """
    defmodule EctoPassenger do
      use Ecto.Schema
      use Domo, skip_defaults: true

      alias Ecto.Schema

      schema "passengers" do
        field :first_name, :string
        field :belonging, :string
        field :love, :string
        field :items, :string
        field :list, :string
        field :forest, :string
        field :ideas, :string

        timestamps()
      end

      @type t :: %__MODULE__{
              first_name: String.t(),
              belonging: Schema.belongs_to(integer()), # t
              love: Schema.has_one(atom()), # t
              items: Schema.has_many(float()), # [t]
              list: Schema.many_to_many(atom()), # [t]
              forest: Schema.embeds_one(integer()), # t
              ideas: Schema.embeds_many(float()) # [t]
            }
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_customer_structs do
    address_path = MixProject.out_of_project_tmp_path("/address.ex")

    File.write!(address_path, """
    defmodule Customer.Address do
      use Domo, skip_defaults: true

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

    delivery_path = MixProject.out_of_project_tmp_path("/delivery.ex")

    File.write!(delivery_path, """
    defmodule Customer.DeliveryInfo do
      use Domo, skip_defaults: true

      alias Customer.Address

      @enforce_keys [:address]
      defstruct [:address]

      @type t :: %__MODULE__{address: Address.t()}
    end
    """)

    customer_path = MixProject.out_of_project_tmp_path("/customer.ex")

    File.write!(customer_path, """
    defmodule Customer do
      use Domo, skip_defaults: true

      alias Customer.DeliveryInfo

      @enforce_keys [:delivery_info]
      defstruct [:delivery_info]

      @type t :: %__MODULE__{delivery_info: DeliveryInfo.t()}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [address_path, delivery_path, customer_path]
  end

  defp compile_leaf_structs(next_leaf_type) do
    leaf_path = MixProject.out_of_project_tmp_path("/leaf.ex")

    File.write!(leaf_path, """
    defmodule LeafHolder do
      @type a_leaf :: Leaf.t()
      @type self_ref :: {self_ref()}
      @type rem_self_ref :: Leaf.rem_rem_self_ref()
    end

    defmodule Leaf do
      use Domo, skip_defaults: true

      defstruct [:value, :next_leaf]

      @type t :: %__MODULE__{value: integer(), next_leaf: #{next_leaf_type}}
      @type rem_rem_self_ref :: LeafHolder.rem_self_ref()
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [leaf_path]
  end

  defp compile_airplane_and_seat_structs do
    airplane_path = MixProject.out_of_project_tmp_path("/airplane.ex")

    File.write!(airplane_path, """
    defmodule Airplane do
      use Domo, skip_defaults: true

      @enforce_keys [:seats]
      defstruct [:seats]

      @type t :: %__MODULE__{seats: [Airplane.Seat.t()]}
    end
    """)

    seat_path = MixProject.out_of_project_tmp_path("/seat.ex")

    File.write!(seat_path, """
    defmodule Airplane.Seat do
      use Domo, skip_defaults: true

      @enforce_keys [:id]
      defstruct [:id]

      @type t :: %__MODULE__{id: String.t()}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [airplane_path, seat_path]
  end

  defp compile_seat_with_atom_id do
    seat_path = MixProject.out_of_project_tmp_path("/seat.ex")

    File.write!(seat_path, """
    defmodule Airplane.Seat do
      use Domo, skip_defaults: true

      @enforce_keys [:id]
      defstruct [:id]

      @type t :: %__MODULE__{id: atom()}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [seat_path]
  end

  defp compile_module_with_default_struct(default_command) do
    path = MixProject.out_of_project_tmp_path("/valid_foo_default.ex")

    File.write!(path, """
    defmodule Foo do
      use Domo

      defstruct [title: ""]
      @type t :: %__MODULE__{title: String.t()}
    end

    defmodule FooHolder do
      defstruct [foo: #{default_command}]
      @type t :: %__MODULE__{foo: Foo.t()}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end

  defp compile_struct_with_defaults(fields, opts) do
    path = MixProject.out_of_project_tmp_path("/valid_bar_default.ex")

    File.write!(path, """
    defmodule Bar do
      use Domo#{if opts[:use_opts], do: ", #{opts[:use_opts]}", else: ""}

      #{if opts[:enforce_keys], do: "@enforce_keys [" <> opts[:enforce_keys] <> "]", else: ""}
      defstruct [#{fields}]
      @type t :: %__MODULE__{#{opts[:t]}}

      #{opts[:precond_t]}
    end
    """)

    CompilerHelpers.compile_with_elixir()
    [path]
  end
end

defmodule DomoTest do
  use Domo.FileCase, async: false
  use Placebo

  import ExUnit.CaptureIO

  alias Domo.MixProjectHelper
  alias Mix.Task.Compiler.Diagnostic
  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask

  Code.compiler_options(
    no_warn_undefined: [
      Account,
      AccountAnyPrecond,
      AccountCustomErrors,
      AccountCustomizedMessages,
      Airplane,
      Airplane.Seat,
      Article,
      Arena,
      Customer,
      EctoPassenger,
      Game,
      Library,
      Library.Book,
      Library.Book.Author,
      Library.Shelve,
      Money,
      PostFieldAndNestedPrecond,
      PostFieldPrecond,
      PostFieldPrecond.CommentNoTPrecond,
      PostNestedPecond,
      PostNestedPecond.CommentTPrecond,
      Receiver,
      ReceiverUserTypeAfterT,
      WebService
    ]
  )

  setup do
    Code.compiler_options(ignore_module_conflict: true)
    File.mkdir_p!(src_path())

    on_exit(fn ->
      File.rm_rf(tmp_path())
      Code.compiler_options(ignore_module_conflict: false)
    end)

    on_exit(fn ->
      ResolverTestHelper.stop_project_palnner()
    end)

    config = Mix.Project.config()
    config = Keyword.put(config, :elixirc_paths, [src_path() | config[:elixirc_paths]])
    allow Mix.Project.config(), meck_options: [:passthrough], return: config

    :ok
  end

  describe "Domo library" do
    test "adds the constructor and verification functions to a struct" do
      compile_receiver_struct()

      _ = DomoMixTask.run([])

      assert Kernel.function_exported?(Receiver, :new!, 1)
      assert Kernel.function_exported?(Receiver, :new_ok, 1)
      assert Kernel.function_exported?(Receiver, :ensure_type!, 1)
      assert Kernel.function_exported?(Receiver, :ensure_type_ok, 1)
    end

    test "generates TypeEnsurer modules for Elixir structs from standard library" do
      _ = DomoMixTask.run([])

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

    test "returns error for MapSet due to unsupport of t(value) types" do
      compile_mapset_holder_struct()

      assert {:error, [%{message: message}]} = DomoMixTask.run([])
      assert message =~ "MapSet.t"
    end

    test "tells whether struct module has TypeEnsurer" do
      compile_receiver_struct()

      _ = DomoMixTask.run([])

      assert Domo.has_type_ensurer?(Receiver) == true
      assert Domo.has_type_ensurer?(CustomStruct) == false
    end

    test "ensures data integrity of a struct by matching to it's type" do
      compile_receiver_struct()

      _ = DomoMixTask.run([])

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
      compile_receiver_user_type_after_t_struct()

      _ = DomoMixTask.run([])

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

    test "ensures data integrity of a struct with a sum type field" do
      compile_game_struct()

      _ = DomoMixTask.run([])

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

    test "ensures data integrity of a struct with a field referencing erlang type" do
      compile_web_service_struct()

      _ = DomoMixTask.run([])

      assert_raise ArgumentError, ~r/Invalid value nil for field :port/s, fn ->
        _ = WebService.new!(port: nil)
      end

      game = WebService.new!(port: 8080)
      assert %{__struct__: WebService} = game
    end

    test "ensures data integrity of nested structs" do
      compile_customer_structs()

      {:ok, []} = DomoMixTask.run([])

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

    test "ensures Ecto schema" do
      compile_ecto_passenger_struct()

      {:ok, []} = DomoMixTask.run([])

      assert %{__struct__: EctoPassenger, __meta__: _} = EctoPassenger.new!(first_name: "John", last_name: "Smith")

      assert_raise ArgumentError,
                   ~r/Invalid value.*for field :first_name/s,
                   fn ->
                     _ = EctoPassenger.new!(first_name: :john, last_name: "Smith")
                   end
    end

    test "ensures data integrity with struct field type's value preconditions" do
      compile_account_struct()

      {:ok, []} = DomoMixTask.run([])

      account = Account.new!(id: "adk-47896", name: "John Smith", money: 2578)
      assert %{__struct__: Account} = account

      message_regex = ~r/the following values should have types defined for fields of the Account struct:
 \* Invalid value "ak47896" for field :id of %Account\{\}. Expected the value matching the <<_::_\*8>> type. \
And a true value from the precondition function "\&\(String.match\?\(\&1, ~r\/\[a-z\]\{3\}-.*d\{5\}\/\)\)" defined for Account.id\(\) type./

      assert_raise ArgumentError, message_regex, fn ->
        _ = Account.new!(id: "ak47896", name: "John Smith", money: 2578)
      end

      assert_raise ArgumentError, ~r/Invalid value %Account{id: \"adk-47896\", money: 2, name: \"John Smith\"}.*\
a true value from the precondition.*defined for Account.t\(\) type./s, fn ->
        _ = Account.new!(id: "adk-47896", name: "John Smith", money: 2)
      end

      assert %{__struct__: Account} = %{account | money: 3500} |> Account.ensure_type!()

      assert_raise ArgumentError, ~r/Invalid value -1 for field :money/s, fn ->
        _ = %{account | money: -1} |> Account.ensure_type!()
      end

      assert_raise ArgumentError, ~r/Invalid value %Account{id: \"adk-47896\", money: 3, name: \"John Smith\"}.*\
a true value from the precondition.*defined for Account.t\(\) type./s, fn ->
        _ = %{account | money: 3} |> Account.ensure_type!()
      end
    end

    test "ensures data integrity with either field precondition or t() type precondition for field's struct value" do
      compile_post_comment_structs()

      {:ok, []} = DomoMixTask.run([])

      assert %{__struct__: PostFieldPrecond} = PostFieldPrecond.new!(comment: struct!(PostFieldPrecond.CommentNoTPrecond, id: 1))

      assert_raise ArgumentError, ~r/&1.id > 0/, fn ->
        _ = PostFieldPrecond.new!(comment: struct!(PostFieldPrecond.CommentNoTPrecond, id: 0))
      end

      assert %{__struct__: PostNestedPecond} = PostNestedPecond.new!(comment: struct!(PostNestedPecond.CommentTPrecond, id: 2))

      assert_raise ArgumentError, ~r/&1.id > 1/, fn ->
        _ = PostNestedPecond.new!(comment: struct!(PostNestedPecond.CommentTPrecond, id: 1))
      end

      [path] = compile_post_field_and_nested_precond_struct()

      me = self()

      msg =
        capture_io(fn ->
          assert {:error, [diagnostic]} = DomoMixTask.run([])
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
      compile_account_any_precond_struct()

      {:ok, []} = DomoMixTask.run([])

      account = AccountAnyPrecond.new!(id: 1)
      assert %{__struct__: AccountAnyPrecond} = account

      assert_raise ArgumentError, ~r/Expected the value matching the any\(\) type. And a true value from the precondition function/s, fn ->
        _ = AccountAnyPrecond.new!(id: "adk-47896")
      end
    end

    test "return custom error from preconditions" do
      compile_account_custom_errors_struct()

      {:ok, []} = DomoMixTask.run([])

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

      assert {:error, id: "Id should match format xxx-12345"} = AccountCustomErrors.new_ok(id: "ak47896", name: "John Smith", money: 2)

      assert_raise ArgumentError,
                   "the following values should have types defined for fields of the AccountCustomErrors struct:\n * :empty_name_string",
                   fn ->
                     _ = AccountCustomErrors.new!(id: "adk-47896", name: "", money: 2)
                   end

      assert {:error, name: :empty_name_string} = AccountCustomErrors.new_ok(id: "adk-47896", name: "", money: 2)
    end

    test "returns list of precondition errors or single string message for each field given maybe_filter_precond_errors: true option for *_ok functions" do
      compile_account_struct()

      _ = DomoMixTask.run([])

      assert {:error, messages} = Account.new_ok([id: "ak47896", name: :john_smith, money: 0], maybe_filter_precond_errors: true)

      [
        name: [
          "Invalid value :john_smith for field :name of %Account{}. Expected the value matching the <<_::_*8>> type."
        ],
        money: [
          """
          Expected the value matching the integer() type. And a true value from \
          the precondition function "&(&1 > 0 and &1 < 10000000)" defined for Account.money() type.\
          """
        ],
        id: [
          id_message
        ]
      ] = messages

      assert id_message =~ "String.match?"

      account = struct!(Account, id: "ak47896", name: :john_smith, money: 0)

      assert {:error, messages} = Account.ensure_type_ok(account, maybe_filter_precond_errors: true)

      [
        name: [
          "Invalid value :john_smith for field :name of %Account{}. Expected the value matching the <<_::_*8>> type."
        ],
        money: [
          """
          Expected the value matching the integer() type. And a true value from \
          the precondition function "&(&1 > 0 and &1 < 10000000)" defined for Account.money() type.\
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

      assert Account.new_ok([id: "akz-47896", name: "John Smith", money: 1], maybe_filter_precond_errors: true) == {:error, t: expected_messages}

      account = struct!(Account, id: "akz-47896", name: "John Smith", money: 1)

      assert Account.ensure_type_ok(account, maybe_filter_precond_errors: true) == {:error, t: expected_messages}

      compile_account_custom_errors_struct()

      _ = DomoMixTask.run([])

      expected_messages = ["Id should match format xxx-12345"]

      assert AccountCustomErrors.new_ok([id: "ak47896", name: "John Smith", money: 2], maybe_filter_precond_errors: true) ==
               {:error, id: expected_messages}

      account = struct!(AccountCustomErrors, id: "ak47896", name: "John Smith", money: 2)

      assert AccountCustomErrors.ensure_type_ok(account, maybe_filter_precond_errors: true) == {:error, id: expected_messages}

      compile_money_struct()

      _ = DomoMixTask.run([])

      expected_messages = [
        """
        Expected the value matching the float() type. And a true value from the \
        precondition function "&(&1 > 0.5)" defined for Money.float_amount() type.\
        """
      ]

      assert Money.new_ok([amount: 0.3], maybe_filter_precond_errors: true) == {:error, amount: expected_messages}

      money = struct!(Money, amount: 0.3)

      assert Money.ensure_type_ok(money, maybe_filter_precond_errors: true) == {:error, amount: expected_messages}
    end

    test "custom error messages are bypassed as in shape given in precond functions" do
      compile_account_customized_messages_struct()

      {:ok, []} = DomoMixTask.run([])

      assert {:error, messages} = AccountCustomizedMessages.new_ok(id: "ak47896", money: 0)

      assert messages == [
               money: """
               Invalid value 0 for field :money of %AccountCustomizedMessages{}. Expected the value matching \
               the integer() type. And a true value from the precondition function \"&(&1 > 0 and &1 < 10000000)\" defined for AccountCustomizedMessages.money() type.\
               """,
               id: {:format_mismatch, "xxx-yyyyy where x = a-z, y = 0-9"}
             ]

      assert {:error, messages} = AccountCustomizedMessages.new_ok([id: "ak47896", money: 0], maybe_filter_precond_errors: true)

      assert messages == [
               money: [
                 """
                 Expected the value matching the integer() type. And a true value \
                 from the precondition function \"&(&1 > 0 and &1 < 10000000)\" defined for AccountCustomizedMessages.money() type.\
                 """
               ],
               id: [{:format_mismatch, "xxx-yyyyy where x = a-z, y = 0-9"}]
             ]

      assert {:error, messages} = AccountCustomizedMessages.new_ok(id: "aky-47896", money: 1)

      assert messages == [t: {:overdraft, :overflow}]

      assert {:error, messages} = AccountCustomizedMessages.new_ok([id: "aky-47896", money: 1], maybe_filter_precond_errors: true)

      assert messages == [t: [{:overdraft, :overflow}]]
    end

    test "recompiles type ensurer of depending struct when the type of dependent struct Not using Domo changes" do
      compile_airplane_and_seat_structs()

      {:ok, []} = DomoMixTask.run([])

      seat = struct!(Airplane.Seat, id: "A2")
      assert _ = Airplane.new!(seats: [seat])

      :code.purge(Airplane.Seat)
      :code.delete(Airplane.Seat)

      compile_seat_with_atom_id()

      {:ok, []} = DomoMixTask.run([])

      assert_raise ArgumentError,
                   ~r/Invalid value.*for field :seats.*Value of field :id is invalid/s,
                   fn ->
                     seat = struct!(Airplane.Seat, id: "A2")
                     _ = Airplane.new!(seats: [seat])
                   end
    end

    for {fun, correct_fun_call, wrong_fun_call} <- [
          {"new!/1", "Foo.new!(title: \"hello\")", "Foo.new!(title: :hello)"},
          {"new_ok/1", "Foo.new_ok(title: \"hello\")", "Foo.new_ok(title: :hello)"},
          {"ensure_type!/1", "Foo.ensure_type!(%Foo{title: \"hello\"})", "Foo.ensure_type!(%Foo{title: :hello})"},
          {"ensure_type_ok/1", "Foo.ensure_type_ok(%Foo{title: \"hello\"})", "Foo.ensure_type_ok(%Foo{title: :hello})"}
        ] do
      test "ensures data integrity of a struct built at the compile time via #{fun} for being a default value" do
        compile_module_with_default_struct(unquote(correct_fun_call))

        assert {:ok, []} = DomoMixTask.run([])

        refute is_nil(struct!(FooHolder))

        :code.purge(Elixir.Foo.TypeEnsurer)
        :code.delete(Elixir.Foo.TypeEnsurer)
        File.rm(Path.join(Mix.Project.compile_path(), "Elixir.Foo.TypeEnsurer.beam"))

        [path] = compile_module_with_default_struct(unquote(wrong_fun_call))

        me = self()

        msg =
          capture_io(fn ->
            assert {:error, [diagnostic]} = DomoMixTask.run([])
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

        plan_file = DomoMixTask.manifest_path(MixProjectHelper.global_stub(), :plan)
        refute File.exists?(plan_file)

        types_file = DomoMixTask.manifest_path(MixProjectHelper.global_stub(), :types)
        refute File.exists?(types_file)
      end
    end

    test "ensures that struct default values conform to t() type" do
      compile_struct_with_defaults("id: 1, field: :hello", enforce_keys: nil, t: "id: integer(), field: atom()")

      assert {:ok, []} = DomoMixTask.run([])

      :code.purge(Elixir.Bar.TypeEnsurer)
      :code.delete(Elixir.Bar.TypeEnsurer)
      File.rm(Path.join(Mix.Project.compile_path(), "Elixir.Bar.TypeEnsurer.beam"))

      [path] = compile_struct_with_defaults(":id, field: :hello", enforce_keys: nil, t: "id: integer(), field: atom()")

      me = self()

      msg =
        capture_io(fn ->
          assert {:error, [diagnostic]} = DomoMixTask.run([])
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

      [path] =
        compile_struct_with_defaults(":id, field: :hello",
          enforce_keys: ":id",
          t: "id: integer(), field: integer()"
        )

      me = self()

      msg =
        capture_io(fn ->
          assert {:error, [diagnostic]} = DomoMixTask.run([])
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

      [path] =
        compile_struct_with_defaults("id: 1, field: :hello",
          enforce_keys: nil,
          t: "id: integer(), field: String.t() | nil"
        )

      me = self()

      msg =
        capture_io(fn ->
          assert {:error, [diagnostic]} = DomoMixTask.run([])
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

      [path] =
        compile_struct_with_defaults("id: 1, field: :hello",
          enforce_keys: nil,
          t: "id: integer(), field: atom()",
          precond_t: "precond t: &(&1.id > 10)"
        )

      me = self()

      msg =
        capture_io(fn ->
          assert {:error, [diagnostic]} = DomoMixTask.run([])
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

      plan_file = DomoMixTask.manifest_path(MixProjectHelper.global_stub(), :plan)
      refute File.exists?(plan_file)

      types_file = DomoMixTask.manifest_path(MixProjectHelper.global_stub(), :types)
      refute File.exists?(types_file)
    end

    test "skips enforced keys during the struct defaults values ensurance" do
      compile_struct_with_defaults(":id, field: :hello", enforce_keys: ":id", t: "id: integer(), field: atom()")

      assert {:ok, []} = DomoMixTask.run([])
    end

    test "skip keys that are not in t() type during defaults ensurance" do
      compile_struct_with_defaults(":id, :leaf, field: :hello", enforce_keys: nil, t: "field: atom()")

      assert {:ok, []} = DomoMixTask.run([])
    end

    test "skips ensurance of struct default values given ensure_struct_defaults: false option" do
      Application.put_env(:domo, :ensure_struct_defaults, false)

      compile_struct_with_defaults(":id, field: :hello", enforce_keys: nil, t: "id: integer(), field: atom()")

      assert {:ok, []} = DomoMixTask.run([])

      :code.purge(Elixir.Bar.TypeEnsurer)
      :code.delete(Elixir.Bar.TypeEnsurer)
      File.rm(Path.join(Mix.Project.compile_path(), "Elixir.Bar.TypeEnsurer.beam"))

      Application.put_env(:domo, :ensure_struct_defaults, true)

      compile_struct_with_defaults(":id, field: :hello",
        use_opts: "ensure_struct_defaults: false",
        enforce_keys: nil,
        t: "id: integer(), field: atom()"
      )

      assert {:ok, []} = DomoMixTask.run([])
    after
      Application.delete_env(:domo, :ensure_struct_defaults)
    end

    test "recompile module that builds struct using Domo at compile time when the struct's type changes" do
      :code.purge(Elixir.Game.TypeEnsurer)
      :code.delete(Elixir.Game.TypeEnsurer)
      File.rm(Path.join(Mix.Project.compile_path(), "Elixir.Game.TypeEnsurer.beam"))

      compile_game_struct()
      arena_paths = compile_arena_struct()

      _ = DomoMixTask.run([])

      assert %{__struct__: Arena, game: %{__struct__: Game, status: :not_started}} = struct!(Arena)

      :code.purge(Game)
      :code.delete(Game)

      compile_game_with_string_status()

      me = self()

      msg =
        capture_io(fn ->
          assert {:error, [diagnostic]} = DomoMixTask.run([])
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
  end

  describe "Domo library error messages should" do
    test "have no underlying errors printed giving | type with primitive type arguments" do
      compile_receiver_struct()

      _ = DomoMixTask.run([])

      assert_raise ArgumentError,
                   """
                   the following values should have types defined for fields of the Receiver struct:
                    * Invalid value nil for field :title of %Receiver{}. Expected the value \
                   matching the :mr | :ms | :dr type.\
                   """,
                   fn ->
                     _ = Receiver.new!(title: nil, name: "ok")
                   end
    end

    test "have only underlying error for matching argument type with failed precondition giving | with user type arguments" do
      compile_money_struct()

      _ = DomoMixTask.run([])

      assert_raise ArgumentError,
                   """
                   the following values should have types defined for fields of the Money struct:
                    * Invalid value 0.3 for field :amount of %Money{}. Expected the value \
                   matching the :none | float() | integer() type.
                   Underlying errors:
                      - Expected the value matching the float() type. And a true value from the \
                   precondition function "&(&1 > 0.5)" defined for Money.float_amount() type.\
                   """,
                   fn ->
                     _ = Money.new!(amount: 0.3)
                   end
    end

    test "returns error for | sum type with details about part that matches most deeply" do
      compile_article_struct()

      _ = DomoMixTask.run([])

      assert_raise ArgumentError,
                   """
                   the following values should have types defined for fields of the Article struct:
                    * Invalid value {:detail, %{author: "John Smith", published_updated: {~D[2021-06-20], nil}}} \
                   for field :metadata of %Article{}. Expected the value matching the \
                   :none \
                   | {:simple, %{author: <<_::_*8>>, published: <<_::_*8>>}} \
                   | {:detail, <<_::_*8>>} \
                   | {:detail, %{author: <<_::_*8>>, published_updated: :never}} \
                   | {:detail, %{author: <<_::_*8>>, published_updated: <<_::_*8>>}} type.
                   Underlying errors:
                      - The element at index 1 has value %{author: "John Smith", published_updated: {~D[2021-06-20], nil}} that is invalid.
                        - The field with key :published_updated has value {~D[2021-06-20], nil} that is invalid.
                        - Expected the value matching the :never type.
                      - The element at index 1 has value %{author: "John Smith", published_updated: {~D[2021-06-20], nil}} that is invalid.
                        - The field with key :published_updated has value {~D[2021-06-20], nil} that is invalid.
                        - Expected the value matching the <<_::_*8>> type.\
                   """,
                   fn ->
                     _ = Article.new!(metadata: {:detail, %{author: "John Smith", published_updated: {~D[2021-06-20], nil}}})
                   end
    end

    test "returns error for most deepest error for nested structs" do
      compile_library_struct()

      _ = DomoMixTask.run([])

      assert_raise ArgumentError,
                   """
                   the following values should have types defined for fields of the Library struct:
                    * Invalid value [%Library.Shelve{address: "A5", books: [%Library.Book{author: %Library.Book.Author{first_name: "Jack", second_name: "Kerouac"}, title: "On the Road"}]}, \
                   %Library.Shelve{address: "B1", books: [%Library.Book{author: %Library.Book.Author{first_name: "William S.", second_name: "Burroughs"}, title: "Naked Lunch"}, \
                   %Library.Book{author: %Library.Book.Author{first_name: "Allen", second_name: :ginsberg}, title: "Howl and Other Poems"}]}] for field :shelves of %Library{}. \
                   Expected the value matching the [%Library.Shelve{}] type.
                   Underlying errors:
                      - The element at index 1 has value %Library.Shelve{address: "B1", books: [%Library.Book{author: %Library.Book.Author{first_name: "William S.", second_name: "Burroughs"}, title: "Naked Lunch"}, \
                   %Library.Book{author: %Library.Book.Author{first_name: "Allen", second_name: :ginsberg}, title: "Howl and Other Poems"}]} that is invalid.
                      - Value of field :books is invalid due to the following:
                        - The element at index 1 has value %Library.Book{author: %Library.Book.Author{first_name: "Allen", second_name: :ginsberg}, title: "Howl and Other Poems"} that is invalid.
                        - Value of field :author is invalid due to Invalid value %Library.Book.Author{first_name: "Allen", second_name: :ginsberg} for field :author of %Library.Book{}. \
                   Value of field :second_name is invalid due to Invalid value :ginsberg for field :second_name of %Library.Book.Author{}. Expected the value matching the <<_::_*8>> type.
                    * Invalid value 1 for field :name of %Library{}. Expected the value matching the <<_::_*8>> type.\
                   """,
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
    path = src_path("/account_any_precond.ex")

    File.write!(path, """
    defmodule AccountAnyPrecond do
      use Domo, ensure_struct_defaults: false

      @enforce_keys [:id]
      defstruct @enforce_keys

      @type any_number :: term()
      precond any_number: &is_number(&1)

      @type t :: %__MODULE__{id: any_number()}
    end
    """)

    compile_with_elixir()
    [path]
  end

  defp compile_account_custom_errors_struct do
    path = src_path("/account_custom_errors.ex")

    File.write!(path, """
    defmodule AccountCustomErrors do
      use Domo, ensure_struct_defaults: false

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

    compile_with_elixir()
    [path]
  end

  defp compile_account_struct do
    path = src_path("/account.ex")

    File.write!(path, """
    defmodule Account do
      use Domo, ensure_struct_defaults: false

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

    compile_with_elixir()
    [path]
  end

  defp compile_post_comment_structs do
    path = src_path("/post_comment.ex")

    File.write!(path, """
    defmodule PostFieldPrecond.CommentNoTPrecond do
      use Domo, ensure_struct_defaults: false

      @enforce_keys [:id]
      defstruct @enforce_keys

      @type t :: %__MODULE__{id: integer()}
    end

    defmodule PostFieldPrecond do
      use Domo, ensure_struct_defaults: false

      alias PostFieldPrecond.CommentNoTPrecond

      @enforce_keys [:comment]
      defstruct @enforce_keys

      @type t :: %__MODULE__{comment: comment_positive_id()}

      @type comment_positive_id :: CommentNoTPrecond.t()
      precond comment_positive_id: &(&1.id > 0)
    end

    defmodule PostNestedPecond.CommentTPrecond do
      use Domo, ensure_struct_defaults: false

      @enforce_keys [:id]
      defstruct @enforce_keys

      @type t :: %__MODULE__{id: integer()}
      precond t: &(&1.id > 1)
    end

    defmodule PostNestedPecond do
      use Domo, ensure_struct_defaults: false

      alias PostNestedPecond.CommentTPrecond

      @enforce_keys [:comment]
      defstruct @enforce_keys

      @type t :: %__MODULE__{comment: CommentTPrecond.t()}
    end
    """)

    compile_with_elixir()
    [path]
  end

  defp compile_post_field_and_nested_precond_struct do
    path = src_path("/post_field_and_nested_precond.ex")

    File.write!(path, """
    defmodule PostFieldAndNestedPrecond do
      use Domo, ensure_struct_defaults: false

      alias PostNestedPecond.CommentTPrecond

      @enforce_keys [:comment]
      defstruct @enforce_keys

      @type t :: %__MODULE__{comment: comment_positive_id()}

      @type comment_positive_id :: CommentTPrecond.t()
      precond comment_positive_id: &(&1 > 2)
    end
    """)

    compile_with_elixir()
    [path]
  end

  defp compile_account_customized_messages_struct do
    path = src_path("/account_customized_messages.ex")

    File.write!(path, """
    defmodule AccountCustomizedMessages do
      use Domo, ensure_struct_defaults: false

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

    compile_with_elixir()
    [path]
  end

  defp compile_money_struct do
    path = src_path("/money.ex")

    File.write!(path, """
    defmodule Money do
      use Domo, ensure_struct_defaults: false

      @enforce_keys [:amount]
      defstruct @enforce_keys

      @type float_amount :: float()
      precond float_amount: &(&1 > 0.5)

      @type int_amount :: integer()
      precond int_amount: &(&1 >= 1)

      @type t :: %__MODULE__{amount: :none | float_amount() | int_amount()}
    end
    """)

    compile_with_elixir()
    [path]
  end

  defp compile_article_struct do
    path = src_path("/article.ex")

    File.write!(path, """
    defmodule Article do
      use Domo, ensure_struct_defaults: false

      @enforce_keys [:metadata]
      defstruct @enforce_keys

      @type t :: %__MODULE__{metadata: :none | simple_metadata() | detail_metadata()}

      @type simple_metadata :: {:simple, %{author: String.t(), published: String.t()}}
      @type detail_metadata :: {:detail, String.t() | %{author: String.t(), published_updated: :never | String.t()}}
    end
    """)

    compile_with_elixir()
    [path]
  end

  defp compile_library_struct do
    path = src_path("/library.ex")

    File.write!(path, """
    defmodule Library do
      use Domo, ensure_struct_defaults: false

      alias Library.Shelve

      @enforce_keys [:name, :shelves]
      defstruct @enforce_keys

      @type t :: %__MODULE__{name: String.t(), shelves: [Shelve.t()]}
    end

    defmodule Library.Shelve do
      use Domo, ensure_struct_defaults: false

      alias Library.Book

      @enforce_keys [:address, :books]
      defstruct @enforce_keys

      @type t :: %__MODULE__{address: String.t(), books: [Book.t()]}
    end

    defmodule Library.Book do
      use Domo, ensure_struct_defaults: false

      alias Library.Book.Author

      @enforce_keys [:title, :author]
      defstruct @enforce_keys

      @type t :: %__MODULE__{title: String.t(), author: Author.t()}
    end

    defmodule Library.Book.Author do
      use Domo, ensure_struct_defaults: false

      @enforce_keys [:first_name, :second_name]
      defstruct @enforce_keys

      @type t :: %__MODULE__{first_name: String.t(), second_name: String.t()}
    end
    """)

    compile_with_elixir()
    [path]
  end

  defp compile_receiver_struct do
    path = src_path("/receiver.ex")

    File.write!(path, """
    defmodule Receiver do
      use Domo, ensure_struct_defaults: false

      @enforce_keys [:title, :name]
      defstruct [:title, :name, age: 0, module: Atom]

      @type title :: :mr | :ms | :dr
      @type name :: String.t()
      @type age :: integer
      @type t :: %__MODULE__{title: title(), name: name(), age: age(), module: module()}
    end
    """)

    compile_with_elixir()
    [path]
  end

  defp compile_receiver_user_type_after_t_struct do
    path = src_path("/receiver_user_type_after_t.ex")

    File.write!(path, """
    defmodule ReceiverUserTypeAfterT do
      use Domo, ensure_struct_defaults: false

      @enforce_keys [:title, :name]
      defstruct [:title, :name, age: 0]

      @type t :: %__MODULE__{title: title(), name: name(), age: age()}
      @type title :: :mr | :ms | :dr
      @type name :: String.t()
      @type age :: integer
    end
    """)

    compile_with_elixir()
    [path]
  end

  defp compile_game_struct do
    path = src_path("/game.ex")

    File.write!(path, """
    defmodule Game do
      use Domo, ensure_struct_defaults: false

      @enforce_keys [:status]
      defstruct [:status]

      @type player :: String.t()
      @type t :: %__MODULE__{
            status: :not_started | {:in_progress, [player()]} | {:wining_player, player()}
          }
    end
    """)

    compile_with_elixir()
    [path]
  end

  defp compile_game_with_string_status do
    path = src_path("/game.ex")

    File.write!(path, """
    defmodule Game do
      use Domo, ensure_struct_defaults: false

      @enforce_keys [:status]
      defstruct [:status]

      @type t :: %__MODULE__{status: String.t()}
    end
    """)

    compile_with_elixir()
    [path]
  end

  defp compile_arena_struct do
    path = src_path("/arena.ex")

    File.write!(path, """
    defmodule Arena do
      defstruct [game: Game.new!(status: :not_started)]

      @type t :: %__MODULE__{game: Game.t()}
    end
    """)

    compile_with_elixir()
    [path]
  end

  defp compile_web_service_struct do
    path = src_path("/web_service.ex")

    File.write!(path, """
    defmodule WebService do
      use Domo, ensure_struct_defaults: false

      @enforce_keys [:port]
      defstruct @enforce_keys

      @type t :: %__MODULE__{port: :inet.port_number()}
    end
    """)

    compile_with_elixir()
    [path]
  end

  defp compile_mapset_holder_struct do
    path = src_path("/mapset_holder.ex")

    File.write!(path, """
    defmodule MapSetHolder do
      use Domo

      defstruct [:set]

      @type t :: %__MODULE__{set: MapSet.t() | nil}
    end
    """)

    compile_with_elixir()
    [path]
  end

  defp compile_ecto_passenger_struct do
    path = src_path("/ecto_passenger.ex")

    File.write!(path, """
    defmodule EctoPassenger do
      use Ecto.Schema
      use Domo, ensure_struct_defaults: false

      schema "passengers" do
        field :first_name, :string
        field :last_name, :string

        timestamps()
      end

      @type t :: %__MODULE__{
              first_name: String.t(),
              last_name: String.t(),
            }
    end
    """)

    compile_with_elixir()
    [path]
  end

  defp compile_customer_structs do
    address_path = src_path("/address.ex")

    File.write!(address_path, """
    defmodule Customer.Address do
      use Domo, ensure_struct_defaults: false

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

    delivery_path = src_path("/delivery.ex")

    File.write!(delivery_path, """
    defmodule Customer.DeliveryInfo do
      use Domo, ensure_struct_defaults: false

      alias Customer.Address

      @enforce_keys [:address]
      defstruct [:address]

      @type t :: %__MODULE__{address: Address.t()}
    end
    """)

    customer_path = src_path("/customer.ex")

    File.write!(customer_path, """
    defmodule Customer do
      use Domo, ensure_struct_defaults: false

      alias Customer.DeliveryInfo

      @enforce_keys [:delivery_info]
      defstruct [:delivery_info]

      @type t :: %__MODULE__{delivery_info: DeliveryInfo.t()}
    end
    """)

    compile_with_elixir()
    [address_path, delivery_path, customer_path]
  end

  defp compile_airplane_and_seat_structs do
    airplane_path = src_path("/airplane.ex")

    File.write!(airplane_path, """
    defmodule Airplane do
      use Domo, ensure_struct_defaults: false

      @enforce_keys [:seats]
      defstruct [:seats]

      @type t :: %__MODULE__{seats: [Airplane.Seat.t()]}
    end
    """)

    seat_path = src_path("/seat.ex")

    File.write!(seat_path, """
    defmodule Airplane.Seat do
      use Domo, ensure_struct_defaults: false

      @enforce_keys [:id]
      defstruct [:id]

      @type t :: %__MODULE__{id: String.t()}
    end
    """)

    compile_with_elixir()

    [airplane_path, seat_path]
  end

  defp compile_seat_with_atom_id do
    seat_path = src_path("/seat.ex")

    File.write!(seat_path, """
    defmodule Airplane.Seat do
      use Domo, ensure_struct_defaults: false

      @enforce_keys [:id]
      defstruct [:id]

      @type t :: %__MODULE__{id: atom()}
    end
    """)

    compile_with_elixir()

    [seat_path]
  end

  defp compile_module_with_default_struct(default_command) do
    path = src_path("/valid_foo_default.ex")

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

    compile_with_elixir()
    [path]
  end

  defp compile_struct_with_defaults(fields, opts) do
    path = src_path("/valid_bar_default.ex")

    File.write!(path, """
    defmodule Bar do
      use Domo#{if opts[:use_opts], do: ", #{opts[:use_opts]}", else: ""}

      #{if opts[:enforce_keys], do: "@enforce_keys [" <> opts[:enforce_keys] <> "]", else: ""}
      defstruct [#{fields}]
      @type t :: %__MODULE__{#{opts[:t]}}

      #{opts[:precond_t]}
    end
    """)

    compile_with_elixir()
    [path]
  end

  defp src_path do
    tmp_path("/src")
  end

  defp src_path(path) do
    Path.join([src_path(), path])
  end

  defp compile_with_elixir do
    command = Mix.Utils.module_name_to_command("Mix.Tasks.Compile.Elixir", 2)
    Mix.Task.rerun(command, [])
  end
end

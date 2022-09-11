locals_without_parens = [precond: 1, allow: :*, assert_called: :*]

[
  inputs: [
    "{mix,.iex,.formatter,.credo}.exs",
    "{config,lib}/**/*.{ex,exs}",
    "test/*.{ex,exs}",
    "test/{domo,support}/*.{ex,exs}",
    "test/struct_modules/lib/*.{ex,exs}"
  ],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: [precond: 1]
  ],
  line_length: 150
]

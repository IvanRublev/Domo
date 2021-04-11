locals_without_parens = [deftag: 2, field: :*, for_type: 1, allow: :*, assert_called: :*]

[
  inputs: [
    "{mix,.iex,.formatter,.credo}.exs",
    "{config,lib,test,benchmark}/**/*.{ex,exs}"
  ],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ]
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter],
  import_deps: [:ash, :spark],
  locals_without_parens: [
    context_attribute: 1
  ],
  export: [
    locals_without_parens: [
      context_attribute: 1
    ]
  ]
]

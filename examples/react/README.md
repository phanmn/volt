# Volt React Example

A minimal Phoenix app using Volt with React.

```sh
mix setup
mix phx.server
```

Open <http://localhost:4000>.

Before committing, check formatting and linting:

```sh
mix assets.check
# with tsgolint installed on PATH:
mix assets.check.type_aware
```

The lint config intentionally combines normal Oxlint category rules such as `"correctness"` with `typescript/*` rules that only run in the type-aware path.

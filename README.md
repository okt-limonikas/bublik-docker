> [!WARNING]
> This deployment method is intended for development and testing environments only. <br />
> For production deployments, please refer to the official installation guides.

## Documentation

The Bublik Docker setup documentation is available in two locations:

1. [Official Documentation](https://ts-factory.github.io/bublik-release/docker/setup) - Contains comprehensive setup guides and reference material
2. Instance-specific Documentation - Available at `<bublik_url>/<prefix>/docs` on your deployed instance

   For example: `https://ts-factory.io/bublik/docs/`

This documentation covers installation, configuration, usage guidelines and troubleshooting information.

## E2E workflow

Five commands cover the whole loop:

| Command | Does |
|---------|------|
| `task e2e:up` | Build the images, start the E2E stack, wait until it answers, and seed the fixture runs if the instance does not already have them. |
| `task e2e:test` | Run the Playwright suite against it. |
| `task e2e:test:ui` | The same suite in Playwright's interactive UI mode. |
| `task e2e:down` | Stop the stack, keeping its database and fixtures so the next `up` skips seeding. |
| `task e2e:reset` | Throw everything away — containers, volumes, generated fixtures, the manifest, and Playwright's reports, traces and cached auth state. |

A typical session:

```bash
task e2e:up      # first run seeds; later runs are a no-op if the data is there
task e2e:test
task e2e:down
```

`task e2e:up` rebuilds the images, so changes in `bublik-ui` reach the suite
only through it — the served UI is baked into the image.

`task --list-all` shows the helpers behind these: `e2e:seed`, `e2e:fixtures`,
`e2e:plan`, `e2e:logs`, `e2e:types`, `e2e:import:manifest`, `e2e:import:via-ui`
and `e2e:ci` (the whole pipeline on fresh volumes, for automation). They stay
runnable for debugging; `task e2e:reset` is the only one that prompts.

### The fixture campaign

The default campaign is versioned in `e2e/plan.yaml`. Validate it and see what
it expands to — without generating anything — with:

```bash
task e2e:plan                     # 39 runs, 5 dates with runs, 1 empty, ...
task e2e:plan -- --by conclusion  # or --by fixture
```

Each day lists one run group per line, `[fixture.]conclusion[@mix][+ui]=count`:

```yaml
days:
  2026-04-19: []                  # a planned empty day
  2026-04-20:
    - basic.ok@healthy=1
    - net-drv-ts.nok-warning@warn=1
    - basic.ok@healthy+ui=1       # imported through the UI form by Playwright
```

The plan's `runs:` total is asserted against what the days expand to, so an edit
that adds or drops a run fails loudly. Parsing, validation and seeding all live
in the `bublik-e2e` CLI (`bublik-e2e plan/generate/run --plan e2e/plan.yaml`);
`bublik-e2e schema --kind plan` prints the plan's JSON Schema. Run the local
helpers' tests with `python3 -m unittest tests/test_e2e.py`.

E2E uses a separate Compose project and defaults its bind-mounted data to
`data/e2e`. The production Compose files still bind fixed host ports, so stop
the normal stack before starting E2E; the two stacks cannot run concurrently
without overriding all conflicting ports.

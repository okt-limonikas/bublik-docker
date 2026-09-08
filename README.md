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

Four commands cover the whole loop:

| Command | Does |
|---------|------|
| `task e2e:up` | Build the images, start the E2E stack, and wait until the API, UI, logs and Celery all answer. |
| `task e2e:seed` | Generate the fixture runs and import them, skipping any the instance already has. |
| `task e2e:test` | Run the Playwright suite against it. |
| `task e2e:down` | Stop the stack, keeping its database and fixtures so the next `up` starts with the same data. |

A typical session:

```bash
task e2e:up
task e2e:seed    # first run seeds; later runs are a no-op if the data is there
task e2e:test
task e2e:down
```

`task e2e:up` rebuilds the images, so changes in `bublik-ui` reach the suite
only through it — the served UI is baked into the image.

Arguments after `--` go to Playwright, so `task e2e:test -- --grep @smoke`
narrows the run and `task e2e:test -- --ui --ui-host=127.0.0.1 --ui-port=0`
opens the interactive UI mode. `task --list-all` adds two more: `e2e:logs`
(`task e2e:logs -- -f celery`) and `e2e:types:check`.

To throw everything away rather than just stopping:

```bash
docker compose -f docker-compose.yml -f docker-compose.db.yml down --volumes
python3 scripts/e2e.py clean    # fixtures, manifest, reports, traces, auth state
```

Both need the E2E environment — `COMPOSE_PROJECT_NAME=bublik-e2e` and
`BUBLIK_DOCKER_DATA_DIR=./data/e2e` — or they will act on the production stack.

### The fixture campaign

The default campaign is versioned in `e2e/plan.yaml`. Validate it and see what
it expands to — without generating anything — with:

```bash
bublik-e2e plan --plan e2e/plan.yaml            # 39 runs, 5 dates with runs, 1 empty, ...
bublik-e2e plan --plan e2e/plan.yaml --by conclusion  # or --by fixture
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

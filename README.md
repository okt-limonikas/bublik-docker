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

The default fixture campaign is versioned in `e2e/plan.json`. Validate it and
its cleanup safety checks with `task e2e:plan:check` and `task e2e:plan:test`.

- `task e2e:run` and `task e2e:run:fresh` recreate dedicated E2E volumes and clean them up after the run.
- `task e2e:run:reuse` preserves the dedicated E2E volumes for local iteration.
- `task e2e:up` and `task e2e:down` preserve E2E volumes; `task e2e:clean` removes them and generated artifacts.

E2E uses a separate Compose project and defaults its bind-mounted data to
`data/e2e`. The production Compose files still bind fixed host ports, so stop
the normal stack before starting E2E; the two stacks cannot run concurrently
without overriding all conflicting ports.

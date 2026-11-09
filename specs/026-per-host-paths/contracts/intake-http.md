# Contract: Intake HTTP, project list

This contract changes one route from 025 `contracts/intake-http.md`. The other routes do not change.

## `GET /v1/projects` (changed)

| Status | Body |
|---|---|
| 200 | `{ "projects": [ { "name", "paths", "hosts", "default_host", "description" } ] }` |

- `paths` is an object with one key for each entry of `hosts`, in `hosts` order. Each value is the checkout path on that host after the `default` entry is applied. The `paths` field replaces the old `path` string. The answer uses this object also when the configuration gives one string.
- The list is in config order. `description` is `null` when the project has none.

Example:

```json
{ "projects": [ {
  "name": "app",
  "paths": { "local": "/Users/me/src/app", "v12dev": "/home/yufu/src/app" },
  "hosts": ["local", "v12dev"],
  "default_host": "local",
  "description": "My app"
} ] }
```

`cci projects` prints this answer unchanged.

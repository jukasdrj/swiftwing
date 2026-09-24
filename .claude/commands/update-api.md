---
description: Refresh the committed Talaria OpenAPI spec from the live API. Pass --force to skip the confirmation prompt.
argument-hint: "[--force]"
---

Update `swiftwing/OpenAPI/talaria-openapi.yaml` from the repo root.

```bash
./Scripts/update-api-spec.sh
```

Pass `--force` when the user asked to skip the confirmation prompt.

Show `git diff -- swiftwing/OpenAPI/` afterward. Do not commit unless the user asks.

# Local MX Space Core 10.5.3 development

This repository's `dev-10.5.3` branch starts at the official `v10.5.3` tag
(`f2ce6f63e3e2462c3ff81f76ca58e7a5afd538d1`). The image that originally
served the site on port 2333 advertises that same revision. Keep `master` and
the Shiro repository separate.

## Test stack

`compose.dev-10.5.3.yaml` uses port `127.0.0.1:2334`, its own Docker network,
MongoDB, Redis and three named volumes. It never joins the `shirocoretest`
network. The MongoDB database name is `mx-space-dev1053`. Startup runs Core's
automatic MongoDB migrations, so verify the Compose configuration before
starting after any edits. Use `localhost:2334` for the dashboard login; the
Compose file includes exact Better Auth trusted origins for both `localhost`
and `127.0.0.1` because `localhost:*` alone is not accepted by that auth layer.

Create the ignored `.env.dev-10.5.3` file in the repository root with a random
`JWT_SECRET`. Never commit this file or data exports. The test administrator
credentials are local test data and should also stay outside Git. On this
machine they are stored in `$env:LOCALAPPDATA\ShiroCoreDev1053\test-admin.json`.

From the repository root in PowerShell:

```powershell
$revision = git rev-parse HEAD
docker build --file dockerfile --tag cynthia174/mx-server:10.5.3-dev --build-arg SOURCE_COMMIT=$revision .
docker compose -f compose.dev-10.5.3.yaml config --quiet
docker compose -f compose.dev-10.5.3.yaml up -d --no-build
docker compose -f compose.dev-10.5.3.yaml ps
```

After changing Core source, rebuild with the same image tag and recreate only
the test Core container:

```powershell
$revision = git rev-parse HEAD
docker build --file dockerfile --tag cynthia174/mx-server:10.5.3-dev --build-arg SOURCE_COMMIT=$revision .
docker compose -f compose.dev-10.5.3.yaml up -d --no-deps --force-recreate --no-build core
docker inspect mxcore-dev1053-core --format '{{.Image}}'
docker image inspect cynthia174/mx-server:10.5.3-dev --format '{{.Id}}'
curl.exe http://127.0.0.1:2334/api/v2/health/source
docker compose -f compose.dev-10.5.3.yaml logs --tail 100 core
```

The source endpoint reports the Git commit passed at build time. If the
working tree has uncommitted edits, the commit alone does not identify those
edits; also compare the image ID and the endpoint behavior. The Dockerfile
downloads the dashboard release declared by `apps/core/package.json` rather
than the changing latest release. The 10.5.3 source declares mx-admin 6.4.0.

Test URLs:

- API: `http://127.0.0.1:2334/api/v2`
- Health: `http://127.0.0.1:2334/api/v2/health`
- Admin: `http://localhost:2334/proxy/qaqdmin`

## Testing the Shiro frontend against port 2334

Do not change the environment file or process serving the normal Shiro site on
port 2323. For compatibility work, use a disposable Shiro worktree or a
separate checkout and run it on another port (for example 2324). In that
checkout, set the frontend environment before starting its dev server:

```powershell
$env:NEXT_PUBLIC_API_URL = 'http://localhost:2334/api/v2'
$env:NEXT_PUBLIC_GATEWAY_URL = 'http://localhost:2334'
pnpm -C apps/web exec next dev -p 2324
```

Run that command from the Shiro repository root. Omitting `--turbo` uses
Next.js's Webpack dev mode, matching the current site's compiler mode.

The backend's gateway is served at `/web`; use the origin as
`NEXT_PUBLIC_GATEWAY_URL`. Confirm the resulting page's API requests target
port 2334, and that the original port 2323 still targets the official port
2333. The running 2323 site is the normal site; 2324 is only the disposable
compatibility frontend, 2333 is the existing service, and 2334 is the isolated
Core test service.

Stop and resume without deleting test data:

```powershell
docker compose -f compose.dev-10.5.3.yaml stop
docker compose -f compose.dev-10.5.3.yaml start
```

Use `docker compose -f compose.dev-10.5.3.yaml down` only when removing test
containers and network; omit `--volumes` to retain test data. For API errors,
inspect `docker compose -f compose.dev-10.5.3.yaml logs --tail 200 core` and
the MongoDB/Redis service logs. Keep the official port 2333 stack untouched.
Core 10.5.3 can log a nonfatal Redis Socket.IO adapter rejection during boot;
check health, restart count, later Redis readiness, and actual API/dashboard
behavior rather than treating that startup line alone as a failed deployment.
In the tested setup, the rejection occurred repeatedly during startup even
with Compose waiting for Redis health; Core then became healthy with both
Redis clients ready, stayed up without restarts, and API, admin login, and
dashboard loading worked. Source inspection locates the error at Socket.IO
adapter subscription setup using clients configured with
`enableOfflineQueue: false`. No explicit multi-client live-notification event
test was performed. A live Engine.IO websocket handshake and `/web` namespace
connection both succeeded; authenticated `/admin` events and cross-client
notification delivery remain items to verify before formal cutover.

## Production cutover preparation

The current official stack is in
`$env:LOCALAPPDATA\ShiroCoreTest\compose.yaml`. Its Core image is
`innei/mx-server:10.5.3`, with MongoDB and Redis on the `shirocoretest`
network. Before any approved cutover, verify a fresh recoverable MongoDB
archive and a copy of `/root/.mx-space`, compare API and admin behavior against
an isolated copy of current data, and retain the original Compose file and
image ID. Then change only the Core image reference in that Compose file,
recreate only Core, and keep its 2333 port, volumes, environment and network.
Rollback means restoring the original image reference and recreating Core;
if data changed incompatibly, stop Core and restore the verified pre-cutover
MongoDB and file backups before restarting the original image. Never run
either deployment or restoration without a separate approval and verified
backup for that specific cutover.

The initial read-only backup for this work is under
`$env:LOCALAPPDATA\ShiroCoreTest\backups\2026-09-24-before-own-core`:
`mx-space.archive.gz` is a MongoDB archive and `mx-space-persistent` contains
the mounted Core files. The archive was checked with `mongorestore --dryRun`
and restored successfully into an isolated temporary database for the
compatibility check. Take another fresh backup immediately before cutover.

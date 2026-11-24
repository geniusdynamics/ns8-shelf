# ns8-shelf

[Shelf](https://www.shelf.nu/) is an open-source asset management application:
track assets, organize them in kits and locations, assign custody, book
equipment and label everything with QR codes. This repository packages Shelf
as a [NethServer 8](https://github.com/NethServer/ns8-core) module.

## What runs

Shelf is not a standalone web application: it stores its data in PostgreSQL
and delegates sign-in and file storage to [Supabase](https://supabase.com/)
(Auth and Storage). The module runs the smallest set of components that
satisfies this, in a single rootless Podman pod:

| Container | Image | Role |
|---|---|---|
| `shelf-app` | `ghcr.io/shelf-nu/shelf.nu` | the Shelf web application; applies its database migrations at start |
| `postgres-app` | `docker.io/postgres` | one database, `shelf`, with the schemas `public` (Shelf), `auth` and `storage` |
| `gotrue-app` | `docker.io/supabase/gotrue` | Supabase Auth, e-mail one-time-password sign-in |
| `storage-app` | `docker.io/supabase/storage-api` | Supabase Storage, uploaded files kept in the `storage-data` volume |
| `gateway-app` | `docker.io/nginx` | serves Shelf, `/auth/v1` and `/storage/v1` under the single host name routed by Traefik |

Not needed, and not run: the Supabase API gateway, PostgREST, Realtime,
Studio and the image transformation proxy.

Shelf is published by Shelf Asset Management Inc. under the AGPL; its Docker
image is documented upstream as community-maintained. The module pins exact
versions of all the images (`org.nethserver.images` label in
`build-images.sh`) so that Renovate proposes upgrades.

## Install

Instantiate the module with:

    add-module ghcr.io/geniusdynamics/shelf:latest 1

The output of the command returns the instance name, for example:

    {"module_id": "shelf1", "image_name": "shelf", "image_url": "ghcr.io/geniusdynamics/shelf:latest"}

## Configure

Let's assume that the instance is named `shelf1`. Launch `configure-module`
with these parameters:

- `host`: a fully qualified domain name for the application (required)
- `lets_encrypt`: request a Let's Encrypt certificate (true/false)
- `disable_signup`: refuse self-service sign-up, users can only join by
  invitation (true/false, default false)
- `mail_from`: sender address of the e-mails, default `noreply@<host>`
- `maptiler_token`: optional [MapTiler](https://www.maptiler.com/) API key to
  draw maps. Not sent: keep the current one. Empty string: remove it.

Shelf is always served over HTTPS: it sets secure-only cookies, so there is no
HTTP to HTTPS toggle.

```
api-cli run configure-module --agent module/shelf1 --data - <<EOF
{
  "host": "shelf.domain.com",
  "lets_encrypt": true,
  "disable_signup": false
}
EOF
```

The action creates the Traefik route and starts the services. The first start
takes a few minutes: Shelf creates its database schema.

Read the configuration back with:

    api-cli run get-configuration --agent module/shelf1

It never returns secrets: it only tells whether a MapTiler key is set.

### Outgoing mail is required

Shelf confirms sign-up and sign-in with six-digit codes sent by e-mail, and
invitations are e-mails too. **Without a
working mail relay nobody can sign in.** The module sends mail through the
cluster [smarthost](https://nethserver.github.io/ns8-core/core/smarthost/):
configure and enable it in the cluster settings. The module reads it every time
it starts and restarts the Shelf and Auth services when the smarthost changes
(`events/smarthost-changed`). The Status page warns when it is not enabled.

Limits of the mail integration: the server certificate of the smarthost is
always verified, and encryption is chosen by port (implicit TLS on 465,
STARTTLS otherwise).

### The first user

There is no preset administrator. Open `https://<host>`, choose to sign up
with an e-mail address and enter the code you receive: you become the owner
of a new workspace and can invite others. When everybody who needs an account
has one, set `disable_signup` to true.

Stripe is not configured and `ENABLE_PREMIUM_FEATURES` is left unset, so
Shelf does not ask for a subscription to use its features.

## Credentials and secrets

All secrets are generated once, when the instance is created, and kept in
files readable by the module only, never in the module environment (which is
stored in Redis and visible to the other modules of the node):

- `state/passwords.env` (0600): database passwords, the JWT secret and the
  Supabase API keys derived from it, Shelf session and invitation secrets
- `state/settings.env` (0600): the MapTiler key, if set
- `state/{postgres,gotrue,storage,shelf}.env` (0600): env files of the
  containers, regenerated from the above at every start by `bin/render-env`

Nothing is passed on a command line or printed to the journal. The Supabase
API keys are signed for ten years; they would need to be regenerated after
that (a restore carries them along with `state/passwords.env`).

To reach the database for troubleshooting, as root on the node:

    runagent -m shelf1 podman exec -ti postgres-app psql -U postgres shelf

## Backup and restore

The module backup, configured from the NS8 Backup page, saves:

- a consistent dump of the whole `shelf` database (Shelf data plus the
  Supabase Auth and Storage metadata): `state/shelf.pg_dump`, created by
  `bin/module-dump-state` just before Restic runs and removed by
  `bin/module-cleanup-state`
- the uploaded files: the `storage-data` volume
- the secrets and settings: `state/passwords.env`, `state/settings.env`

The live `postgres-data` volume is deliberately not saved: a copy of a running
database is not consistent. The dump and the files are taken one after the
other, not atomically: a file uploaded during the backup can be missing from
the snapshot while its record is present, or the reverse.

Restore creates a new instance, loads the dump into an empty database
(`restore-module/40restore_database`), recreates the database roles from the
restored passwords and runs `configure-module` with the saved settings. Let's
Encrypt is never turned on by a restore or a clone, because the DNS may not
point to the new node yet: turn it on again from the Settings page. Sessions
and sign-in keep working, since the JWT secret is restored too.

## Update

To update the instance:

    api-cli run update-module --data '{"module_url":"ghcr.io/geniusdynamics/shelf:latest","instances":["shelf1"],"force":true}'

Services are restarted, the env files are regenerated and Shelf applies its
database migrations before it starts the server (it stops instead of starting
against an out-of-date schema). Hooks live in `imageroot/update-module.d/`.

## Uninstall

    remove-module --no-preserve shelf1

## Architecture notes

- One public host name serves everything. nginx forwards `/` to Shelf,
  `/auth/v1/` to Supabase Auth and `/storage/v1/` to Supabase Storage, as
  Supabase's own gateway does, so Shelf's `SUPABASE_URL` is the same
  `https://<host>`.
- Inside the pod the public host name resolves to `127.0.0.1`, where nginx
  answers on port 443 with a self-signed certificate that only the Shelf
  container trusts. The server side of Shelf reaches Auth and Storage without
  leaving the pod: it does not depend on DNS or on the Traefik certificate
  (for example before Let's Encrypt succeeds). Browsers use the public route.
- Service order: pod, then PostgreSQL (which creates the roles and schemas the
  Supabase services expect, idempotently, `bin/bootstrap-db`), then Auth and
  Storage, then Shelf. After Shelf starts, `bin/bootstrap-storage` creates the
  four storage buckets Shelf needs (`profile-pictures` and `files` public,
  `assets` and `kits` private).
- The Supabase API keys are the legacy HS256 JWT style (anon and
  `service_role`) generated by the module. Shelf accepts them in
  `SUPABASE_SECRET_KEY`.

## Troubleshooting

Become the module user to inspect it:

    runagent -m shelf1
    systemctl --user status shelf.service shelf-app.service
    podman ps
    podman logs shelf-app

Or read the journal as root: `journalctl -u user@$(id -u shelf1).service`.

- **Nobody can sign in, the code never arrives**: check that the smarthost is
  enabled (Status page) and read `podman logs gotrue-app` for SMTP errors.
- **The page does not load right after configuring**: Shelf is applying its
  database migrations, wait a few minutes and check `podman logs shelf-app`.
- **Uploads or profile pictures fail**: `podman logs storage-app`; the
  buckets are created at every start of `shelf-app.service`, see
  `journalctl` for `bootstrap-storage`.
- **Let's Encrypt fails**: the host name must resolve to the node and ports 80
  and 443 must be reachable. Configure again without `lets_encrypt` meanwhile.

## Testing

Test the module using the `test-module.sh` script:

    ./test-module.sh <NODE_ADDR> ghcr.io/geniusdynamics/shelf:latest

The tests are made using [Robot Framework](https://robotframework.org/). The
suite installs the module, configures it, checks the generated files and
their permissions, the health of Shelf, Supabase Auth and Storage through
Traefik, the storage buckets and the consistency of the backup dump, then
removes the instance. The GitHub workflow `Test module on QEMU` runs it on a
throwaway NS8 node.

## UI translation

Translated with [Weblate](https://hosted.weblate.org/projects/ns8/).

To setup the translation process:

- add [GitHub Weblate app](https://docs.weblate.org/en/latest/admin/continuous.html#github-setup) to your repository
- add your repository to [hosted.weblate.org](https://hosted.weblate.org) or ask a NethServer developer to add it to ns8 Weblate project

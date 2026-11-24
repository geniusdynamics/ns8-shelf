# Shelf for NethServer 8

Shelf 2.6.0 tracks equipment, assets, custody, and bookings. The NS8 module
runs the web app and a dedicated Supabase stack in a rootless Podman pod.
PostgreSQL, Auth, PostgREST, and Storage share that pod. Nginx serves Shelf
and the required Auth and Storage paths on one HTTPS hostname behind NS8
Traefik. PostgreSQL and PostgREST remain private to the pod.

## Install and configure

1. Install an available module build with
   `add-module ghcr.io/geniusdynamics/shelf:<tag> 1`.
2. Point a DNS name at the NS8 node and enter it in the module Settings.
   Use Let's Encrypt or install a certificate trusted by browsers and by
   the Shelf container. The NS8 node and pod must resolve and reach the
   same HTTPS hostname because Shelf uses it for server-side Supabase calls
   and browser-facing file URLs.
3. Configure the NS8 smarthost. In **Advanced**, set a sender address the
   relay accepts and enable self-registration to create the first account.
   Complete signup with the email code and create your workspace. Turn off
   self-registration if you want to restrict enrollment afterward.
   Enter a public MapTiler API key in Advanced if you use location maps.
4. Follow the [SAML guide](docs/saml.md) if you want directory-backed sign-in.

The module generates separate credentials for each installation. It creates
the four upstream storage buckets with their expected visibility. Shelf runs
its database migrations when its container starts. Supabase Studio, image
transformations, Realtime, and SCIM are outside this package.

For SMTP, use port 465 with implicit TLS or a relay that offers STARTTLS.
OTP delivery, invitations, and password recovery depend on the relay.

## Backup and restore

NS8 backup takes a cold snapshot of PostgreSQL, its extension configuration,
and Storage together. There is a brief outage while the volume archives are
taken. Restic stores the archives and the private module credentials. Restore
to empty volumes using the same module version first, then upgrade separately.
Preserve the HTTPS hostname during restore or update any SAML registration and
stored public file URLs that refer to it.

The package uses the upstream Shelf container. The companion mobile
application follows [Shelf's separate licensing terms](https://www.shelf.nu/).

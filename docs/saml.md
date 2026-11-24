# SAML sign-in for Shelf

Shelf delegates authentication to Supabase Auth. In this module, its SSO flow
uses SAML 2.0. NS8's OIDC provider picker and `register-client` action do not
create SAML clients. For Samba AD or OpenLDAP, use a SAML-capable IdP that
already federates your directory. A Keycloak realm in NS8 IdP can serve that
role if its administrator exposes SAML client management. Authentik or a
separately managed Keycloak installation can also supply the SAML client.

## Configure a pilot workspace

1. Verify email sign-in first. Keep an independent workspace owner who can
   sign in with email. Grant a trusted, existing local account access to the
   Shelf instance Admin Dashboard from **Settings → Shelf instance administration**.
   Enter the account email address and select **Grant Shelf instance administrator access**.
   The NS8 host command is also available.

   ```sh
   runagent -m shelf1 shelf-admin grant owner@example.net
   ```

   This role applies across the Shelf instance. Remove it when no longer
   needed with `shelf-admin revoke owner@example.net`.
2. Enable **SAML single sign-on** in NS8 Settings. Fetch the service provider
   metadata from `https://<shelf-host>/auth/v1/sso/saml/metadata`. Use the entity
   ID and assertion consumer service URL from that document as-is when
   registering the SAML client in your IdP. Configure the verified email
   attribute and the groups required by your Shelf workspace.
3. Export the IdP's XML metadata. Make the file readable by the module user
   and register it from the NS8 host. Replace the module ID and email domain.

   ```sh
   runagent -m shelf1 shelf-saml add /absolute/path/idp.xml example.org
   runagent -m shelf1 shelf-saml list
   ```

   For metadata rotation, use `shelf-saml update <provider-id> <metadata-file>
   <email-domain>`. Use `--attributes <mapping.json>` when GoTrue needs an
   explicit attribute mapping. Register only metadata from your own IdP.

4. In Shelf, sign in as the instance administrator and open **Admin
   Dashboard**, then the organization details page. Enable SSO for the
   workspace and configure its email domains and group-to-role mappings. Test a pilot account at
   `https://<shelf-host>/sso-login`. Verify that the account lands in the right
   workspace with the intended role before requiring SSO for anyone.

Disabling SAML in NS8 stops the login feature and preserves its provider
records. Remove any workspace requirement for SSO before turning it off.

- [Shelf SSO documentation](https://docs.shelf.nu/sso/)
- [Supabase SAML documentation](https://supabase.com/docs/guides/auth/enterprise-sso/auth-sso-saml)
- [NS8 user domains and provider discovery](https://nethserver.github.io/ns8-core/core/user_domains/#single-sign-on)

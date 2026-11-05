# Cloudflare Worker bouncer

## Cloudflare API token

Create a token for `CLOUDFLARE_API_TOKEN`, scoped to the intended account and
protected zones, with the permissions listed in the
[official documentation](https://docs.crowdsec.net/u/bouncers/cloudflare/):

| Scope   | Permission               |
| ------- | ------------------------ |
| Account | Workers KV Storage: Edit |
| Account | Workers Scripts: Edit    |
| Account | Account Settings: Read   |
| Account | Account Analytics: Read  |
| Account | Turnstile: Edit          |
| User    | User Details: Read       |
| Zone    | DNS: Read                |
| Zone    | Workers Routes: Edit     |
| Zone    | Zone: Read               |

This is the upstream permission baseline, not a verified minimum for ban-only
operation.

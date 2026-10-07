# CrowdSec operations

This deployment runs the central CrowdSec Local API (LAPI), Kubernetes log agents,
and the web UI in namespace `security`. The core configuration is in
[app/helmrelease.yaml](app/helmrelease.yaml); the UI is in [ui/](ui/), and the
Gateway bouncer is managed separately in [../envoy-proxy-bouncer/](../envoy-proxy-bouncer/).

## Roles and endpoints

- **Agent / machine:** parses logs and sends alerts to LAPI using a machine login
  and password. Each external agent needs its own machine registration.
- **Bouncer:** fetches decisions using an API key and enforces them, for example
  with firewall rules. A bouncer key is not a machine password.
- **Web UI user:** signs into the dashboard. These local users are separate from
  machine credentials and bouncer keys; the installed UI cannot provision those
  credentials. Use `cscli` for registration.

| Purpose                                           | Endpoint                                                  |
| ------------------------------------------------- | --------------------------------------------------------- |
| Internal clients: UI, bouncer, and cluster agents | `http://crowdsec-service.security.svc.cluster.local:8080` |
| External agents and bouncers over the tailnet     | `https://crowdsec-lapi.${SECRET_DOMAIN}/`                 |
| Web UI over the tailnet                           | `https://crowdsec.${SECRET_DOMAIN}/`                      |

Both hostnames use the existing `network/envoy-internal` Gateway's `https`
listener and wildcard TLS certificate. LAPI and the UI have no public-internet
ingress. The [LAPI HTTPRoute](app/httproute.yaml) forwards to `crowdsec-service:8080`
in `security`. Internal clients should keep using cluster DNS.

The separate Envoy bouncer protects only `envoy-external`. External authorization
is fail-closed: an unavailable authorization service produces HTTP 503. A LAPI
outage after initial synchronization is different: the bouncer can continue
enforcing cached decisions, which may become stale.

## Before you start

- On the **admin workstation**, select the correct Kubernetes context and ensure
  you can execute `cscli` in Deployment `security/crowdsec-lapi`.
- On the **external Linux server**, install the appropriate CrowdSec agent and/or
  firewall bouncer package. Agent instructions below use CrowdSec v1.8.1 `cscli`
  and systemd; package-specific service/configuration paths may differ.
- Ensure the server can reach the tailnet, resolve the LAPI hostname to the
  internal Gateway, and validate its TLS certificate. A route alone does not
  establish DNS or tailnet access.
- Choose unique names such as `server1` and `firewall-server1`. Keep passwords,
  API keys, and credential backups out of Git, tickets, and shared terminal logs.

On the external server, replace `example.com` with the actual `SECRET_DOMAIN`:

```sh
export LAPI_URL="https://crowdsec-lapi.example.com/"
```

`SECRET_DOMAIN` is a GitOps substitution variable, not an environment variable
automatically exported into your server's shell.

## Add an external firewall bouncer

On the **admin workstation**, create a dedicated key on the central LAPI:

```sh
kubectl -n security exec deploy/crowdsec-lapi -- cscli bouncers add firewall-server1
```

This command prints the API key **once**. Store it securely: the original key
cannot be recovered from the stored hash. Manual registrations persist in the
central PostgreSQL database; they do not need a `BOUNCER_KEY_*` environment variable.

On the **external server**, edit the existing
`/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml`. Merge these fields without
replacing its other settings, using the real hostname and newly issued key:

```yaml
api_url: https://crowdsec-lapi.example.com/
api_key: "<paste-the-issued-key-securely>"
```

```sh
sudo systemctl restart crowdsec-firewall-bouncer
```

On the **admin workstation**, check registration and subsequent polling:

```sh
kubectl -n security exec deploy/crowdsec-lapi -- cscli bouncers list
kubectl -n security exec deploy/crowdsec-lapi -- cscli bouncers inspect firewall-server1
```

Use a unique key for each independent server. Shared keys can create key-plus-IP
child identities, and clients behind the same LAPI-visible IP or proxy can share
a polling cursor. Do not assume a shared key provides independent delivery.

## Add an external CrowdSec agent

### 1. Register the remote machine

On the **external server**, securely back up any existing LAPI credential file
before registration. Registering generates machine credentials and overwrites
the configured credentials file, normally `/etc/crowdsec/local_api_credentials.yaml`.
Existing installations may already depend on its previous contents.

```sh
sudo cscli lapi register --url "$LAPI_URL" --machine server1
```

This flow deliberately supplies **no auto-registration token**. The new machine
remains pending until an administrator validates it. Do not distribute the
cluster registration token or broaden the configured registration ranges.

### 2. Validate centrally

On the **admin workstation**, review the pending name and address and confirm the
request belongs to the intended server before granting access:

```sh
kubectl -n security exec deploy/crowdsec-lapi -- cscli machines list
kubectl -n security exec deploy/crowdsec-lapi -- cscli machines validate server1
```

### 3. Configure agent-only operation and log sources

On the **external server**, merge the following into
`/etc/crowdsec/config.yaml.local`, preserving existing settings and avoiding
duplicate `api` keys. This disables the Linux package's local API server, not its
log-processing agent:

```yaml
api:
    server:
        enable: false
```

The credentials file written by registration points the agent to the central
LAPI. You do not need to configure the remote agent to access central PostgreSQL.
Do not substitute Docker-only environment settings for the Linux package config.

Install collections appropriate for services actually running on that server:

```sh
sudo cscli collections install crowdsecurity/sshd
sudo cscli collections install crowdsecurity/caddy
```

Registration and collection installation do **not** automatically establish the
correct log acquisition for every host. Configure and verify each remote agent's
sources: SSH may use journald or files, and Caddy needs suitable access logs such
as JSON. Collections and acquisitions belong on the server reading those logs,
not on the central LAPI, where `crowdsec_service` is disabled.

After central validation and local configuration:

```sh
sudo cscli lapi status
sudo systemctl restart crowdsec
sudo journalctl -u crowdsec --since "10 minutes ago"
```

Successful LAPI authentication does not by itself prove logs are being collected.
Check the agent's logs and acquisition configuration as well.

## Inspect the central deployment

Run these read-only commands on the **admin workstation**:

```sh
kubectl -n security get helmreleases crowdsec crowdsec-web-ui envoy-proxy-bouncer
kubectl -n security get pods
kubectl -n security logs deploy/crowdsec-lapi --since=10m
kubectl -n security get httproute crowdsec-lapi -o yaml
kubectl -n security exec deploy/crowdsec-lapi -- cscli machines list
kubectl -n security exec deploy/crowdsec-lapi -- cscli bouncers list
kubectl -n security exec deploy/crowdsec-lapi -- cscli alerts list
kubectl -n security exec deploy/crowdsec-lapi -- cscli decisions list
```

For the HTTPRoute, look for `Accepted` and `ResolvedRefs` conditions under its
internal Gateway parent. DNS, tailnet connectivity, and successful authentication
still need to work independently. The web UI provides another way to inspect
alerts and decisions; its login is not a LAPI machine login.

## Revoke access and handle managed keys

The following are **destructive administrative commands**, not health checks.
Run only when intentionally revoking the named external client's access:

```sh
kubectl -n security exec deploy/crowdsec-lapi -- cscli bouncers delete firewall-server1
kubectl -n security exec deploy/crowdsec-lapi -- cscli machines delete server1
```

Revocation does not guarantee immediate removal of already-installed firewall
rules or cached decisions. Retire or reconfigure the affected client as needed.

The existing Gateway bouncer is managed differently: the core HelmRelease uses
`BOUNCER_KEY_envoy_proxy_bouncer` to register identity `envoy_proxy_bouncer` from
the SOPS-managed Secret `envoy-proxy-bouncer`, key `api-key`. Underscores make the
registration name suitable for the environment-variable suffix.

This startup registration is **create-only**. Deleting that managed identity can
cause it to be recreated on the next LAPI restart. Changing only the Secret does
not rotate an existing identity's stored key. Coordinate a new key **and a new
registration name**, update the consuming bouncer, verify replacement readiness
and synchronization, then retire the old registration and its bootstrap entry.

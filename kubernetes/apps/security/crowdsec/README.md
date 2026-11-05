# Add external CrowdSec clients

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

# Authentik

Authentik is installed from its official pinned Helm chart with two servers,
two workers, disruption budgets, restricted pod security, metrics, public TLS,
and an external CloudNativePG database. The bundled PostgreSQL chart is disabled
and current Authentik releases do not require Redis/Valkey.

The included blueprint can create the frontend as a public OIDC Authorization
Code client, but it is not mounted until stable public URLs are configured. For
the current bootstrap phase, Authentik is reachable over NodePort `30900`.
Enable the blueprint and TLS ingress when the domain integration is ready.

Kubernetes outpost discovery is disabled because this deployment only provides
OIDC. Server and worker pods use an unprivileged ServiceAccount without a mounted
Kubernetes API token. Add narrowly scoped outpost RBAC later only if an outpost
is actually required.

Bootstrap credentials and the stable Authentik secret key come from OpenBao via
External Secrets. Change the initial administrator password after first login,
enable MFA, and never rotate `AUTHENTIK_SECRET_KEY` as a routine password change.

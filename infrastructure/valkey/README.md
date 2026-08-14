# Valkey (Redis protocol)

Valkey is the open-source, Redis-protocol-compatible service for reconstructable
backend state: short-lived caches, distributed gateway rate-limit counters, and
Pub/Sub notifications between backend replicas. It is not used by Authentik and
must never become the source of truth for customer resources, authorization, or
job completion.

The v1 footprint is deliberately one memory-bounded, non-persistent instance.
Loss or restart can drop keys and Pub/Sub messages, so consumers must refresh
authoritative state from PostgreSQL and make create/delete workflows idempotent.
If brief cache/event downtime becomes unacceptable, move to an operator-managed
Sentinel or clustered topology after load and failure testing rather than
assuming static replicas provide automatic failover.

Clients connect with TLS to:

```text
valkey.valkey.svc.cluster.local:6379
```

The ACL password is sourced from OpenBao. Backend deployments must mount that
password and the internal CA through External Secrets and cert-manager.

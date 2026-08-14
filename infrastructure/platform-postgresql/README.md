# Platform PostgreSQL

CloudNativePG manages a three-instance PostgreSQL cluster spread across three
nodes. The cluster contains separate `platform` and `authentik` databases with
non-superuser owners, TLS-only application connections, SCRAM passwords from
OpenBao, declarative role/database reconciliation, and Prometheus metrics.

Applications use the read/write endpoint:

```text
platform-postgresql-rw.platform-database.svc.cluster.local:5432
```

Do not grant backend service accounts write access to CloudNativePG `Cluster`,
`Database`, or `DatabaseRole` resources. Those resources are administrative and
can confer PostgreSQL superuser-equivalent control.

The `local-path` volumes and replicas provide node-level availability, not
disaster recovery. Off-cluster Barman Cloud backups and tested restores are a
launch requirement; see the infrastructure README.

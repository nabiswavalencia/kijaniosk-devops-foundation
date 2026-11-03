# Environment setup

Path: Multipass (primary). Backend: MinIO S3 at http://localhost:9000, bucket kijanikiosk-tfstate, locking via use_lockfile.

```
OS:        Ubuntu 24.04.5 LTS (7.0.0-34-generic)
Terraform: Terraform v1.16.5
Multipass: multipass   1.16.4
Ansible:   ansible [core 2.21.4]
Docker:    Docker version 29.8.1, build 4a63305
MinIO:     pgsty/minio:RELEASE.2026-08-04T00-00-00Z
jq:        jq-1.7
```

MinIO image: pgsty/minio:RELEASE.2026-08-04T00-00-00Z
Digest: sha256:b6bfe7239bfc83fb90d31612d9704d86039dd714f7904b3f1ad68f211e602372
Reason: minio/minio removed from Docker Hub (Sep 2026); quay.io/minio/minio returned 401 on anonymous pull.

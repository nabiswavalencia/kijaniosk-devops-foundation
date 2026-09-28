# IAM Least Privilege Design: KijaniKiosk

## Task sentence
The reports web service needs to read reconciliation files stored in one specific bucket, and nothing else.

Context: KijaniKiosk processes online orders and produces daily financial reconciliation reports. Staff review those reports through a web-facing service, and the files themselves sit in a backend storage bucket. Staff should reach only the files they need, and the storage should not be open to anything else.

## IAM reasoning: who can do what on which resource under which conditions

| Building block | Design |
|---|---|
| Principal | IAM role `reports-web-role`, assumed by the reports web service (a workload identity, not a shared user) |
| Permissions | `s3:ListBucket` and `s3:GetObject` only |
| Resource | The bucket `kijanikiosk-reconciliation-reports` and its objects, and no other bucket |
| Conditions | Requests must use TLS. Human access additionally requires MFA (see below) |

Bucket names are globally unique in S3, so the real bucket needs a unique suffix. The name above is used for readability.

## Policy for the workload role

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListReportsBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::kijanikiosk-reconciliation-reports"
    },
    {
      "Sid": "ReadReportFiles",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::kijanikiosk-reconciliation-reports/*"
    },
    {
      "Sid": "DenyWritesAndDeletes",
      "Effect": "Deny",
      "Action": ["s3:PutObject", "s3:DeleteObject", "s3:DeleteObjectVersion"],
      "Resource": "arn:aws:s3:::kijanikiosk-reconciliation-reports/*"
    },
    {
      "Sid": "RequireTLS",
      "Effect": "Deny",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::kijanikiosk-reconciliation-reports",
        "arn:aws:s3:::kijanikiosk-reconciliation-reports/*"
      ],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    }
  ]
}
```

Notes on the design:
- `s3:ListBucket` applies to the bucket itself and `s3:GetObject` to the objects inside it (`/*`), so they need separate resource lines.
- Anything not allowed is already denied by default. The explicit `Deny` on writes and deletes is a guardrail: an explicit deny always overrides an allow, so if someone later attaches a broader policy to this role by mistake, the report files still cannot be changed or removed.
- The TLS condition stops data from being requested over an unencrypted connection.

## Trust policy (who can assume the role)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Only the compute service running the reports web service can assume the role. If the service runs on a managed container platform instead, only the principal changes.

## Variant for a human user: MFA condition
If a person, such as a finance reviewer, needs direct read access, the same read permissions apply with an MFA condition:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadReportsWithMFA",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetObject"],
      "Resource": [
        "arn:aws:s3:::kijanikiosk-reconciliation-reports",
        "arn:aws:s3:::kijanikiosk-reconciliation-reports/*"
      ],
      "Condition": { "Bool": { "aws:MultiFactorAuthPresent": "true" } }
    }
  ]
}
```

MFA applies to people. A workload role cannot provide it, which is why the MFA condition is on the human policy and the TLS condition is on the workload policy.

## Credentials
- Workloads use the role's temporary credentials, which expire automatically. No access keys are stored in code, configuration, or the repository.
- Each person has their own identity. Credentials are never shared. This addresses a past KijaniKiosk incident where a shared password stayed active long after the temporary access it was created for.

## Permissions considered and rejected

| Permission | Why it was tempting | Why it is excluded |
|---|---|---|
| `s3:*` on the bucket | Avoids guessing which actions are needed | The service only reads |
| `s3:PutObject` | Might be useful for re-uploading a corrected report | Report generation is a different task with its own role |
| `s3:ListAllMyBuckets` | Lets the service find the bucket | The bucket name is configured, so discovery is not needed |
| Access to `Resource: "*"` | Works even if the bucket is renamed | It would expose every bucket in the account |

## Blast radius
If the reports service's credentials are compromised, an attacker can list and read reconciliation reports. They cannot change or delete them, cannot read any other bucket, cannot change IAM, and the credentials expire on their own. The remaining risk is confidentiality of the reports themselves, which is why access is limited to this one bucket and to TLS.

## Testing
Run these with the role's credentials (for example from the instance) and capture screenshots as evidence:

| Test | Expected result |
|---|---|
| `aws s3 ls s3://kijanikiosk-reconciliation-reports/` | Allowed |
| `aws s3 cp s3://kijanikiosk-reconciliation-reports/<report-file> .` | Allowed |
| `aws s3 cp test.txt s3://kijanikiosk-reconciliation-reports/` | AccessDenied |
| `aws s3 rm s3://kijanikiosk-reconciliation-reports/<report-file>` | AccessDenied |
| `aws s3 ls s3://<any-other-bucket>/` | AccessDenied |

The IAM policy simulator can be used to confirm the same results before running the commands.

## Change process
Policy changes go through a pull request like application code. The reviewer checks that every added action and resource is needed for the task sentence above. This applies the Feedback practice from `delivery-notes.md` to access control, and each access-related incident should add a rule or a check (Learning).

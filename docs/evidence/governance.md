# Governance evidence

This records what was checked on the TenantLoom AI governance controls, what was observed, and the limits of each result. The controls are described in [architecture section 7](../../architecture.md#7-governance), [ADR-001](../adr/ADR-001-model-access-boundary.md), and [ADR-004](../adr/ADR-004-state-and-ci-ownership.md).

## Summary

| Check | Lab check | Result |
|---|---|---|
| The organization policy baseline is managed by Terraform without changing it | | Verified |
| The access policy is managed by Terraform | | Verified from the apply only |
| Data Access audit logging covers Agent Platform, IAM, Cloud Storage, Secret Manager, and Cloud KMS | | Verified for configuration |
| `sa-terraform` sets project-level model allowlists | 1 | Verified |
| Allowlisted model calls succeed and others are denied, in each project | | Verified in sandbox and nonprod; prod pending |
| Unauthenticated Agent Platform calls are rejected | | Verified |
| A membership change to `ai-governance` or `auditors` raises an alert | 2 | Pending |
| Representative audit events reach the audit dataset | 7 | Verified for Agent Platform in sandbox and nonprod |
| Model Armor floor settings inspect in sandbox and block in nonprod and prod | | Failed: not applied to calls on the `us` endpoint |
| The `baseline` template flags a prompt injection through the sanitize API | | Pending |
| Prod log buckets use the CMEK key | | Pending |
| An unauthenticated call to the prod probe through the load balancer returns 403 | | Pending |
| Calls through the load balancer reach the probe | 4 | Pending, early signal from the dry run |
| Internet egress from prod fails; a model call through the restricted range succeeds | 5, 14 | Pending, early signal from the egress job |
| A `platform-prod-admin` grant gives access only while active | 16 | Pending |
| The dry-run perimeter logs violations for prohibited paths only | | Pending |

## Details

### Organization policy baseline

- **Checked:** import of the 11 organization policies and the folder's `vertexai.allowedModels` deny-all, with deletion protection, then a read of every policy after the apply.
- **Observed:** the plan imported all 12 and changed only Terraform's deletion protection setting; every rule matched the policies already in place. After the apply, each policy's etag and rules were identical to a copy taken before the import, so the apply did not rewrite any policy.
- **Significance:** the live baseline is now under review and approval like any other platform change, and Terraform refuses to delete it.

### Access policy

- **Checked:** import of the existing organization access policy into the perimeter module.
- **Observed:** the plan showed the policy's title and parent unchanged and only the deletion protection setting added, and the apply succeeded.
- **Limitation:** the break-glass account holds no Access Context Manager role, so the policy was not read back independently.

### Data Access audit logging

- **Checked:** the folder's IAM audit configuration after the apply.
- **Observed:** Agent Platform, IAM, Cloud Storage, Secret Manager, and Cloud KMS each log `ADMIN_READ`, `DATA_READ`, and `DATA_WRITE`, with no exempted members.
- **Limitation:** this shows the configuration only. Lab check 7 confirms that representative events arrive in the audit dataset.

### Model allowlists and model access (lab check 1)

- **Checked:** the effective `vertexai.allowedModels` policy on each project, then `generateContent` calls as `sa-model-test`, impersonated by a member of `ai-platform-admins`, on the `us` multi-region endpoint.
- **Observed:** the effective policies match the catalog: sandbox allows `gemini-3.8-flash` and `gemini-4-argon`, and nonprod and prod allow `gemini-3.8-flash`. Calls gave these results:

  | Call | Sandbox | Nonprod |
  |---|---|---|
  | `gemini-3.8-flash`, approved | 200 with a response | 200 with a response |
  | `gemini-4-argon`, sandbox candidate | Accepted; the client timed out before the response arrived | 400 `FAILED_PRECONDITION` naming `constraints/vertexai.allowedModels` |
  | `gemini-3.7-flash`, not in the catalog | 400 `FAILED_PRECONDITION` naming the constraint | 400 `FAILED_PRECONDITION` naming the constraint |
  | No credentials | 401 | |

- **Limitations:** the catalog models are not served on the `us-east4` regional endpoint, where every call returned 404, so models are called on the `us` endpoint. The sandbox `gemini-4-argon` result shows the policy allowed the call, from its audit entry, but no response was captured. Prod is tested separately.

### Audit events (lab check 7)

- **Checked:** the `cloudaudit_googleapis_com_data_access` table in the `audit_logs` dataset, queried as a member of `auditors`, for Agent Platform entries from the calls above.
- **Observed:** `GenerateContent` and `CountTokens` entries for `sa-model-test` from both sandbox and nonprod, with denied calls carrying status code 9 (`FAILED_PRECONDITION`).
- **Significance:** Data Access audit logs for model calls reach the one-year audit dataset from more than one project, including denials.

### Model Armor floor settings

- **Checked:** the live floor settings in sandbox and nonprod, then a prompt injection request in each project, then the restricted Model Armor bucket and each project's `_Default` bucket.
- **Observed:** the floor settings are as configured: prompt injection and jailbreak at medium confidence and above, sensitive data, and malicious URL detection, with inspect only in sandbox, inspect and block in nonprod, and logging on. Both requests returned 200 with the model declining on its own; nonprod did not block. No Model Armor log entry exists in the restricted bucket or in either `_Default` bucket.
- **Significance:** Agent Platform did not apply the floor settings to these calls, so they provide no screening on the `us` endpoint. The architecture now places screening in the application, through the sanitize API and each project's `baseline` template.
- **Limitation:** the documentation reviewed lists only European and Asian regions for template-based screening and does not state US support for floor settings, so the cause is inferred from the observed absence of screening.

### CI role lists for governance resources (lab check 9)

- **Observed:** pull request plans as `sa-terraform-plan` refreshed organization policies, the access policy, the organization data source, and the folder audit configuration without permission errors.

## Steps outside Terraform

| Step | Why it is outside Terraform |
|---|---|
| Organization custom role `terraformLogConfigReader` | `sa-terraform` cannot create organization roles |
| Organization log sink `identity-audit`, and Log Bucket Writer for its writer identity in nonprod | `sa-terraform` holds no organization logging role, so it cannot route organization-level logs |
| Sharing Cloud Identity data with Google Cloud | An Admin console setting |
| Organization-level Privileged Access Manager service agent | Created at the organization, where `sa-terraform` has no Service Usage role |
| Delegating the prod hostname to Cloud DNS | A registrar setting |

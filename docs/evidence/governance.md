# Governance evidence

This records what was checked on the TenantLoom AI governance controls, what was observed, and the limits of each result. The controls are described in [architecture section 7](../../architecture.md#7-governance), [ADR-001](../adr/ADR-001-model-access-boundary.md), and [ADR-004](../adr/ADR-004-state-and-ci-ownership.md).

## Summary

| Check | Lab check | Result |
|---|---|---|
| The organization policy baseline is managed by Terraform without changing it | | Verified |
| The access policy is managed by Terraform | | Verified from the apply only |
| Data Access audit logging covers Agent Platform, IAM, Cloud Storage, Secret Manager, and Cloud KMS | | Verified for configuration |
| `sa-terraform` sets project-level model allowlists | 1 | Verified |
| Allowlisted model calls succeed and others are denied, in each project | | Verified in sandbox and nonprod; prod deferred until the prod model path exists |
| Unauthenticated Agent Platform calls are rejected | | Verified |
| A membership change to `ai-governance` or `auditors` raises an alert | 2 | Verified: the alert opens an incident; email delivery not verified |
| Representative audit events reach the audit dataset | 7 | Verified for Agent Platform in sandbox and nonprod |
| Model Armor floor settings inspect in sandbox and block in nonprod and prod | | Failed: not applied to calls on the `us` endpoint |
| The `baseline` template flags a prompt injection through the sanitize API | | Verified in sandbox and nonprod |
| Model Armor logs reach the restricted bucket and stay out of `_Default` | | Verified |
| Prod log buckets use the CMEK key | | Verified |
| An unauthenticated call to the prod probe through the load balancer returns 403 | | Verified; the direct `run.app` URL is also refused |
| Calls through the load balancer reach the probe | 4 | Verified with the perimeter in dry run; enforced check pending |
| Internet egress from prod fails; a model call through the restricted range succeeds | 5, 14 | Internet egress fails; the model call is deferred until the prod model path exists |
| A `platform-prod-admin` grant gives access only while active | 16 | Verified with the perimeter in dry run; enforced check pending |
| The dry-run perimeter logs violations for prohibited paths only | | Verified for the outside write and the management identities; anonymous load balancer traffic is also logged, an open item |

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
  | `gemini-4-argon`, sandbox candidate | 200 with a response | 400 `FAILED_PRECONDITION` naming `constraints/vertexai.allowedModels` |
  | `gemini-3.7-flash`, not in the catalog | 400 `FAILED_PRECONDITION` naming the constraint | 400 `FAILED_PRECONDITION` naming the constraint |
  | No credentials | 401 | |

- **Limitations:** the catalog models are not served on the `us-east4` regional endpoint, where the publisher model lookup returns not found, so models are called on the `us` endpoint. Prod model calls wait on the prod model path, listed under open items.

### Audit events (lab check 7)

- **Checked:** the `cloudaudit_googleapis_com_data_access` table in the `audit_logs` dataset, queried as a member of `auditors`, for Agent Platform entries from the calls above.
- **Observed:** `GenerateContent` and `CountTokens` entries for `sa-model-test` from both sandbox and nonprod, with denied calls carrying status code 9 (`FAILED_PRECONDITION`).
- **Significance:** Data Access audit logs for model calls reach the one-year audit dataset from more than one project, including denials.

### Model Armor floor settings

- **Checked:** the live floor settings in sandbox and nonprod, then a prompt injection request in each project, then the restricted Model Armor bucket and each project's `_Default` bucket.
- **Observed:** the floor settings are as configured: prompt injection and jailbreak at medium confidence and above, sensitive data, and malicious URL detection, with inspect only in sandbox, inspect and block in nonprod, and logging on. Both requests returned 200 with the model declining on its own; nonprod did not block. No Model Armor log entry exists in the restricted bucket or in either `_Default` bucket.
- **Significance:** Agent Platform did not apply the floor settings to these calls, so they provide no screening on the `us` endpoint. The architecture now places screening in the application, through the sanitize API and each project's `baseline` template.
- **Limitation:** the documentation reviewed lists only European and Asian regions for template-based screening and does not state US support for floor settings, so the cause is inferred from the observed absence of screening.

### Model Armor template screening

- **Checked:** `sanitizeUserPrompt` calls as `sa-model-test` against each project's `baseline` template in the `us` location, then the restricted Model Armor bucket in nonprod and each project's `_Default` bucket.
- **Observed:** the prompt injection text returned `MATCH_FOUND` from the prompt injection and jailbreak filter at high confidence in both sandbox and nonprod, and a plain question returned `NO_MATCH_FOUND` from every filter. The sanitize operations from both projects appeared in the restricted bucket, and neither `_Default` bucket held a Model Armor entry.
- **Significance:** application-side screening works in the US, the sandbox sink delivers into nonprod across projects, and the exclusions keep prompt logs away from wider audiences.
- **Limitation:** no service calls the sanitize API yet; the starter template adds it.

### Group membership alert (lab check 2)

- **Checked:** a member was added to and then removed from `auditors` in the Admin console, then the log-based metric and the alert policy's incidents were read.
- **Observed:** the metric counted one change for each action, and an incident for "Approver or auditor group membership changed" opened on the `identity-audit` bucket, with the organization as its source.
- **Significance:** the chain works end to end: Cloud Identity data sharing, the organization `identity-audit` sink, the bucket-scoped metric, and the alert.
- **Limitation:** the notification channel sends to `ai-governance`, whose address has no mailbox, so email delivery was not observed. See open items.

### Prod log encryption

- **Checked:** the prod `app-logs` and `model-armor` bucket settings.
- **Observed:** both use the `platform/logs` key in `us-east4`, with 90-day and 30-day retention.

### Prod probe through the load balancer (lab check 4)

- **Checked:** requests to the prod hostname with no credentials, a request to the probe's `run.app` URL with no credentials, and a request to the hostname by a platform administrator with a user ID token, before and during an active `platform-prod-admin` grant.
- **Observed:** the managed certificate is active. The hostname returned 403 without credentials and the `run.app` URL returned 404, since ingress admits only the load balancer path. With an active grant the hostname returned the probe's page.
- **Limitation:** the perimeter is in dry run, so this does not show the path under enforcement.

### Prod egress and the dry-run perimeter (lab check 5)

- **Checked:** the output of `platform-egress-probe`, read from the CMEK `app-logs` bucket, and prod's policy audit logs for dry-run entries over the same hour, which also covered plan and apply builds reading prod.
- **Observed:**
  - The internet request timed out.
  - The write to a bucket in nonprod succeeded, and each of its storage calls by `sa-platform-probe` logged a dry-run violation, `NETWORK_NOT_IN_SAME_SERVICE_PERIMETER`.
  - No violations came from `sa-terraform`, `sa-terraform-plan`, `ai-platform-admins`, or the folder audit sink.
  - Unauthenticated requests through the load balancer logged a `run.googleapis.com/HttpIngress` violation, `NO_MATCHING_ACCESS_LEVEL`.
  - The model call returned 404, because the job calls the `us-east4` endpoint.
- **Significance:** enforcement would block the outside write without affecting management access. It would also block every load balancer caller not named in an ingress rule, before IAM is checked.

### Prod access through PAM (lab check 16)

- **Checked:** a `platform-prod-admin` grant requested by a platform administrator and approved by a member of `ai-governance`, with the load balancer request and a job run attempted before the grant took effect, while it was active, and after it ended.
- **Observed:** the approver saw the request and approved it. Shortly after approval, the load balancer returned 403 and a job status read was denied; once the grant was in effect, the probe page loaded and the job ran. After the grant ended, the load balancer returned 403 and starting the job was refused.
- **Limitations:** the perimeter is in dry run. The approver could not revoke the grant early, so it was left to end. See open items.

### Open items

| Item | Observation | Next step |
|---|---|---|
| Prod model path | The restricted range does not serve `*.rep.googleapis.com` endpoints, and the catalog models are not served on `us-east4` | Private Service Connect endpoints for the `us` Agent Platform and Model Armor endpoints, with the probe's model URL moved to `us`, tested once prod hosts a team service |
| Load balancer traffic under enforcement | Anonymous requests logged an `HttpIngress` dry-run violation | An ingress rule or access level for load balancer callers before the perimeter is enforced (ADR-007) |
| Early revocation of prod grants | `ai-governance` can approve but not revoke a grant, and no person holds the revoke permission | Grant a revoke-capable role to `ai-governance` on `jd-aip-prod` |
| Governance alert delivery | The notification channel's address has no mailbox | Point the channel at an address that receives mail |
| Model Armor floor settings | Not applied on the `us` endpoint | Kept in place; screening happens through the sanitize API |

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

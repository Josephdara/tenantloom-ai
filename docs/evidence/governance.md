# Governance evidence

This records what was checked on the TenantLoom AI governance controls, what was observed, and the limits of each result. The controls are described in [architecture section 7](../../architecture.md#7-governance), [ADR-001](../adr/ADR-001-model-access-boundary.md), and [ADR-004](../adr/ADR-004-state-and-ci-ownership.md).

## Summary

| Check | Lab check | Result |
|---|---|---|
| The organization policy baseline is managed by Terraform without changing it | | Verified |
| The access policy is managed by Terraform | | Verified from the apply only |
| Data Access audit logging covers Agent Platform, IAM, Cloud Storage, Secret Manager, and Cloud KMS | | Verified for configuration |
| `sa-terraform` sets project-level model allowlists | 1 | Pending |
| Allowlisted model calls succeed and others are denied, in each project | | Pending |
| A membership change to `ai-governance` or `auditors` raises an alert | 2 | Pending |
| Representative audit events reach the audit dataset | 7 | Pending |
| Model Armor floor settings inspect in sandbox and block in nonprod and prod | | Pending |

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

### CI role lists for governance resources (lab check 9)

- **Observed:** pull request plans as `sa-terraform-plan` refreshed organization policies, the access policy, the organization data source, and the folder audit configuration without permission errors.

## Steps outside Terraform

| Step | Why it is outside Terraform |
|---|---|
| Organization custom role `terraformLogConfigReader` | `sa-terraform` cannot create organization roles |
| Organization log sink `identity-audit`, and Log Bucket Writer for its writer identity in nonprod | `sa-terraform` holds no organization logging role, so it cannot route organization-level logs |
| Sharing Cloud Identity data with Google Cloud | An Admin console setting |

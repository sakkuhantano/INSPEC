# Lightning + Inspection Approval Deployment Runbook

## SQL deployment order

Run the scripts below in SQL Server Management Studio against the target INSPEC database. Do not deploy the application code before the required procedures and tables exist.

1. Existing prerequisites (only if not already applied):
   - `inspection_mode_migration.sql`
   - `inspection_batch_transaction_migration.sql`
   - `inspection_location_map_schema.sql` (only if the current Group Map / MapX / MapY schema is not already deployed)
2. `InspectionEmailApproval_Schema.sql`
3. `LightningInspection_Transaction_Migration.sql`
4. `LightningInspection_Approval_Workflow.sql`
5. `InspectionApproval_Workflow_Procedures.sql`
6. `LightningInspection_Sync_Procedure.sql`

The schema script creates the location-level Chief Engineering / Chief Security setup, section-level SPV setup, approval history, workflow state, and email outbox. It also adds `ChiefEngSectionID` and `ChiefSecSectionID` to existing installations.

## Application configuration

- Set `smtpFrom` in `Web.config` to a sender address authorized by the SMTP relay.
- Current relay defaults remain `smtp.varnion.net:25`, SSL disabled, and blank credentials. Confirm the relay policy and configure credentials if required.
- Pending/failed email notifications remain in `PIP_T_InspectionEmailOutbox`; dispatch is retried after inspection sync, approval actions, and approval queue loads.
- The setup page is available from Inspection Master. Configure two distinct Chief employees for the Company + Location, selecting each employee's actual section, then configure the SPV for every active inspection Section.

## Workflow behavior

- Standard / Batch: Technician submits -> configured Section SPV approves or voids.
- Lightning: one daily InspectionID contains every configured ScheduleTime -> Technician submits -> Chief Engineering (`CHECKED` -> `ACKNOWLEDGE 1`) -> Chief Security (`ACKNOWLEDGE`).
- A void requires a reason and returns the server record to the technician correction list. The authenticated correction email link opens that record.
- Approval email links open the authenticated approval review; approval itself is only performed by an explicit same-origin POST action.
- Lightning submission is locked while its approval workflow is active. Repeated submit requests return the existing server transaction instead of overwriting it.

## Deployment checks

Before enabling users, verify:

- Chief and SPV employee records have non-empty `M_HRD_Employee.emailaddress`.
- Chief and SPV employees have active Company + Location access.
- Every inspection Section has an active SPV mapping.
- Chief Engineering and Chief Security are different employees.
- The SQL scripts complete without errors and the procedures exist.
- The application compiles under the existing .NET Framework 4.5 / VS2013 project.
- A test Standard, Batch, and Lightning inspection can be submitted, approved, voided, corrected, and resubmitted.
- Inline map/photo attachments display in the received emails; SMTP delivery is confirmed from the outbox status.

## Important

The SQL scripts and C# changes are committed to the feature branch but have **not** been executed against the live database or compiled in the user's VS2013 environment. Run the deployment scripts in the order above and test in a non-production database before production rollout.

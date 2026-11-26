# Lightning + Inspection Approval Deployment Runbook

## SQL deployment order

Run the scripts below in SQL Server Management Studio against the target INSPEC database. Do not deploy the application code before the required procedures and tables exist.

1. Existing prerequisites (only if not already applied):
   - `InspectionWorkflow_ComVal_Migration.sql` (consolidates InspectionPointMode and renames schedule mode to INSPECT)
   - `InspectionEmailApproval_CommonValue_Migration.sql` (only when temporary routing tables still exist)
   - `InspectionApproval_ComValWorkflow_Migration.sql` (converts existing EMAIL mode flags into per-level workflow flags)
   - `InspectionApproval_ComVal_EmailHelper.sql` (creates the per-level ComVal email flag lookup function)
   - `inspection_mode_migration.sql`
   - `inspection_batch_transaction_migration.sql`
   - `InspectionMapGroup_Migration.sql`
   - `InspectionPoint_Coordinate_Consolidation.sql`
   - `InspectionPoint_RemoveCompanyLocation_Migration.sql`
     (only if the current Group Map / direct MapX+MapY schema and point scope are not already deployed)
2. `InspectionEmailApproval_Schema.sql`
3. `InspectionApproval_HeaderFields_Migration.sql`
4. `InspectionLegacyApproval_Procedure_ColumnRename.sql`
5. `LightningInspection_Transaction_Migration.sql`
6. `LightningInspection_Approval_Workflow.sql`
7. `InspectionApproval_Workflow_Procedures.sql`
8. `LightningInspection_Sync_Procedure.sql`

The schema script creates approval history and email outbox. Workflow state is stored on PIP_T_Inspection. Approval routing and email switches are stored in the existing `dbo.SysWebCommonValue` table under `AppID='INSPEC'`, `CommonGroup='EmailApproval'`.



## Application configuration

- Configure approval routing from Inspection Master -> Inspection Email & Approval Routing. Chief employee mappings, Section SPV mappings, and workflow email flags are stored in `dbo.SysWebCommonValue`.
- Approver mappings remain `<CompanyID><LocationID>;CHIEF_ENG` / `;CHIEF_SEC` with EmployeeID in Description; SPV uses `<CompanyID><LocationID>;SPV;<SectionID>`. Workflow flags use the three keys above and one `[LEVEL][TRUE/FALSE]` token per stage.
- Workflow email flags are stored per Company + Location: `<CompanyID><LocationID>;STANDARD`, `...;BATCH;PARAM`, and `...;BATCH;INSPECT`. Description tokens use `[LEVEL][TRUE/FALSE]`; a missing workflow ComVal or missing level token means email OFF for that level.
- If a development database already contains the temporary `PIP_M_InspectionEmailSetup*` tables from the earlier patch, run `InspectionEmailApproval_CommonValue_Migration.sql` once before removing those tables.
- Set `smtpFrom` in `Web.config` to a sender address authorized by the SMTP relay.
- Current relay defaults remain `smtp.varnion.net:25`, SSL disabled, and blank credentials. Confirm the relay policy and configure credentials if required.
- Pending/failed email notifications remain in `PIP_T_InspectionEmailOutbox`; dispatch is retried after inspection sync, approval actions, and approval queue loads.
- The dispatcher records `LastAttemptDate` and automatically recovers `SENDING` rows left stale for more than 30 minutes after an app-pool recycle or process interruption; the fifth failed attempt remains terminal for manual review.
- The setup page is available from Inspection Master. Configure two distinct Chief employees for the Company + Location, then configure the SPV for every active inspection Section.

## Workflow behavior

- STANDARD: Technician submits -> configured Section SPV verifies. BATCH / PARAM: Technician submits -> configured Section SPV verifies -> Chief Engineering acknowledges. BATCH / INSPECT: Technician submits -> SPV verifies -> Chief Security acknowledges -> Chief Engineering acknowledges. Each stage's email notification is independently controlled by its ComVal `[LEVEL][TRUE/FALSE]` token.
- Lightning: one daily InspectionID contains all 61 configured lamp points across the configured maps -> Technician submits -> SPV verifies (`CHECKED` -> `VERIFIED`) -> Chief Security acknowledges 1 -> Chief Engineering acknowledges 2 (`ACKNOWLEDGE 1` -> `ACKNOWLEDGE 2`).
- A void requires a reason and returns the server record to the technician correction list. The authenticated correction email link opens that record.
- Approval email links open the authenticated approval review; approval itself is only performed by an explicit same-origin POST action.
- Workflow state is held on PIP_T_Inspection (`IsSubmitted`, `IsApproved`, `IsApproved1`, `IsApproved2` and their actor/date fields). For Standard/Batch, `IsApproved` is SPV and `IsApproved1` is Chief Engineering; for Lightning, `IsApproved` is SPV, `IsApproved1` is Chief Security, and `IsApproved2` is Chief Engineering. Every approver VOID resets all three stages and returns the record to DRAFT; the approval history remains intact. Lightning schedule tabs are derived from PIP_M_InspectionTypeDetail.ScheduleTime and PIP_T_InspectionPoint.ScheduleTime.

## Deployment checks

Before enabling users, verify:

- Chief and SPV employee records have active Company + Location access.
- If email is enabled for a mode, the relevant recipients have non-empty `M_HRD_Employee.emailaddress`.
- Every inspection Section has an active SPV mapping in `SysWebCommonValue`.
- Chief Engineering and Chief Security are different employees.
- The SQL scripts complete without errors and the procedures exist.
- The application compiles under the existing .NET Framework 4.5 / VS2013 project.
- A test Standard, Batch, and Lightning inspection can be submitted, approved, voided, corrected, and resubmitted.
- Inline map/photo attachments display in the received emails; SMTP delivery is confirmed from the outbox status.

## Important

The SQL scripts and C# changes are committed to the feature branch but have **not** been executed against the live database or compiled in the user's VS2013 environment. Run the deployment scripts in the order above and test in a non-production database before production rollout.

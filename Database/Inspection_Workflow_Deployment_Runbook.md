# Inspection Approval Deployment Runbook

## SQL deployment order

Run these scripts in SQL Server Management Studio against a **non-production INSPEC database first**. Take a database backup before applying schema migrations. Confirm the existing base INSPEC schema, dbo.SysWebCommonValue, HR employee tables, login/access functions, and template/map master tables are present.

1. database/inspection_mode_migration.sql
   - Adds/normalizes the Inspection Type InspectionMode field.
2. database/inspection_presentation_config_migration.sql
   - Adds presentation, point-source, schedule-selection, and workflow-code master fields. Run after step 1.
3. Database/InspectionWorkflow_ComVal_Migration.sql
   - Consolidates point mode, normalizes AT_INSPECTION to INSPECT, converts legacy Lightning master types to BATCH / MAP / INSPECT, sets BATCH/PARAM to SPV_CHIEF_ENG and BATCH/INSPECT to LIGHTNING_4_STEP, and updates the related check constraints. Run after steps 1–2.
4. database/inspection_batch_transaction_migration.sql
5. Database/InspectionMapGroup_Migration.sql
6. Database/InspectionPoint_Coordinate_Consolidation.sql
7. Database/InspectionPoint_RemoveCompanyLocation_Migration.sql
   - Only when the deployed map-point schema still has the old Group Map / direct MapX+MapY point-scope fields.
8. Database/InspectionEmailApproval_CommonValue_Migration.sql
   - Run only when the old temporary PIP_M_InspectionEmailSetup* tables still exist. It moves their SPV/Chief/legacy email settings into dbo.SysWebCommonValue and drops the temporary tables.
9. Database/InspectionEmailApproval_Schema.sql
   - Creates/updates approval history and email outbox. It also permits the SKIPPED history action used when a Chief stage has no configured approver.
10. Database/InspectionApproval_HeaderFields_Migration.sql
    - Adds the three approval-stage actor/date fields. It retains legacy IsApprovedFinal columns for backward compatibility and does not drop historical approval data.
11. Database/LightningInspection_Transaction_Migration.sql
12. Database/InspectionLegacyApproval_Procedure_ColumnRename.sql
    - Recompiles the original Follow Up procedure after the IsApprove → IsApproved column rename.
13. Database/spUTL_PIP_T_Inspection_Approval.sql
    - Applies the updated Follow Up/approval authorization routine, including the final-stage behavior when optional Chief Engineering is not configured.
14. Database/InspectionApproval_ComValWorkflow_Migration.sql
    - Converts existing legacy ;EMAIL;STANDARD/BATCH/LIGHTNING switches into the new per-workflow/per-stage ComVal rows. Run after step 8 if the old temporary tables existed; it does not overwrite a workflow row that is already configured.
15. Database/InspectionApproval_ComVal_EmailHelper.sql
    - Creates dbo.fnINSPEC_ApprovalEmailEnabled. This must exist before compiling the workflow procedures below.
16. Database/LightningInspection_Approval_Workflow.sql
17. Database/InspectionApproval_Workflow_Procedures.sql
18. Database/LightningInspection_Sync_Procedure.sql

The active stored procedures are created by steps 16–18. The similarly named older standalone spUTL_PIP_T_Inspection_Lightning_* SQL files are not part of this runbook; do not apply those old copies over the active routines.

## Application configuration

Configure routing from Inspection Master → Inspection Email & Approval Routing. Routing remains in dbo.SysWebCommonValue, AppID='INSPEC', CommonGroup='EmailApproval':

- SPV: <CompanyID><LocationID>;SPV;<SectionID> → one or more SPV EmployeeIDs in Description. **SPV mapping is mandatory for every active Inspection Section**, independent of email settings.
- Chief Engineering: <CompanyID><LocationID>;CHIEF_ENG → EmployeeIDs in Description. Optional; an empty mapping causes the Batch/Param Chief stage to be skipped.
- Chief Security: <CompanyID><LocationID>;CHIEF_SEC → EmployeeIDs in Description. Optional; an empty mapping causes the Lightning Chief Security stage to be skipped.
- Workflow email flags are stored per Company + Location:
  - <CompanyID><LocationID>;STANDARD → [SPV][TRUE/FALSE]
  - <CompanyID><LocationID>;BATCH;PARAM → [SPV][TRUE/FALSE];[CHIEF][TRUE/FALSE]
  - <CompanyID><LocationID>;BATCH;INSPECT → [SPV][TRUE/FALSE];[CHIEF_SEC][TRUE/FALSE];[CHIEF_ENG][TRUE/FALSE]

Email flags control notification only. FALSE, a missing token, or a missing workflow ComVal means **no email for that stage**; it does not remove that approval stage. A missing Chief mapping, by contrast, means the Chief approval stage is skipped and its approval field is stamped with the NIK of the preceding person who actually approved. Skipped stages are recorded in PIP_T_InspectionApprovalHistory as ActionCode='SKIPPED'.

The CHIEF token for BATCH;PARAM controls email to Chief Engineering. The CHIEF_SEC and CHIEF_ENG tokens are separate Lightning notification switches. Chief Security and Chief Engineering mappings are independently optional and, when supplied, must contain valid active employees with the correct profit center and Company/Location access. The same NIK must not be assigned to both Chief roles or overlap the SPV mapping.

If a development database has the temporary setup tables from the earlier patch, run step 8 before step 14. Step 14 migrates old on/off switches only where a legacy setting exists; absent legacy settings remain OFF. New setups should be configured in the Inspection Email & Approval Routing page after the migrations.

Set smtpFrom in Web.config to a sender address authorized by the SMTP relay. Confirm relay policy and configure credentials if required; historical defaults were smtp.varnion.net:25, SSL disabled, and blank credentials, but do not assume those values match the current environment. Pending/failed notifications remain in PIP_T_InspectionEmailOutbox. The dispatcher retries eligible outbox rows after sync, approval actions, and approval queue loads.

## Workflow behavior

- **STANDARD:** Technician submits → configured Section SPV verifies. IsApproved / ApprovedBy records the actual SPV.
- **BATCH / PARAM (Car Park and Motor):** Technician submits → SPV verifies → Chief Engineering acknowledges. If no Chief Engineering mapping exists, SPV is the final approver; IsApproved1 / Approved1By is stamped with the SPV's NIK and the skipped Chief stage is audited.
- **BATCH / INSPECT (Lightning daily):** One daily InspectionID contains the daily map-point inspection. Normal flow is SPV → Chief Security → Chief Engineering. If Chief Security is absent, its field is stamped by SPV and the process continues to Chief Engineering if configured. If Chief Engineering is absent, its field is stamped by the preceding actual approver. If both are absent, SPV completes the workflow. The fields are IsApproved/ApprovedBy (SPV), IsApproved1/Approved1By (Chief Security stage), and IsApproved2/Approved2By (Chief Engineering stage).
- Email notification for each active stage is independently controlled by that stage's [LEVEL][TRUE/FALSE] token. Turning email OFF does not permit bypassing a configured approver.
- A VOID requires a reason, records the correct stage and returns the transaction to the technician correction list. Resubmission resets approval-stage flags but preserves approval history.
- Approval email links open the authenticated approval review; approval itself is performed only by an explicit same-origin POST action.

## Deployment and smoke checks

Before enabling users in the test environment:

1. Confirm all scripts complete without SQL errors and that the helper function and active procedures exist.
2. Confirm ScheduleSelectionMode values in PIP_M_InspectionType use PARAM or INSPECT; Lightning master records should be BATCH / MAP / INSPECT.
3. Configure one SPV for each tested Section. Test Chief Engineering blank while Chief Security is configured, and then the reverse; also test both Chief mappings blank.
4. Test all three workflows with email flags ON and OFF independently. With email OFF, check that approval is still required and no outbox message is queued for that stage.
5. Verify ApprovedBy, Approved1By, and Approved2By contain the NIK of the actual approving employee, including the auto-skipped cases. Verify SKIPPED history rows do not appear as actual Chief approvals in queues/dashboard counts.
6. Test APPROVE, VOID, correction, and resubmission for Standard, Batch/Param, and Batch/Inspect. For Batch/Inspect, exercise each missing-Chief combination.
7. Confirm SMTP delivery and inspect PIP_T_InspectionEmailOutbox status and errors.
8. Compile the existing WebForms project under .NET Framework 4.5 / VS2013 and test the approval pages in IIS.

## Test boundary

The feature branch has **not** been executed against the target SQL Server, compiled in the user's VS2013 environment, or exercised in IIS. Treat this as a test candidate, not a production-ready deployment, until the SQL deployment and smoke checks above pass in the non-production environment.
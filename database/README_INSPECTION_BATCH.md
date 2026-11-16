# INSPEC BATCH Inspection deployment order

The BATCH transaction code expects the existing Inspection Type / Template / Map masters to be installed first.

Run the SQL files in this order:

1. `inspection_transaction_schema.sql` — canonical Inspection header, result, result-value, and photo tables.
2. `master_template_inspection_schema.sql` — Inspection template/version master dependencies.
3. `Database/repeatable_inspection_schema.sql` — REPEAT child-field master and transaction values, including `ObjectIndex` for OBJECTS rows.
4. `Database/InspectionEmailApproval_Schema.sql`, then `Database/InspectionApproval_HeaderFields_Migration.sql` — create approval history/outbox before the header migration backfills workflow history and approval fields.
5. `Database/InspectionApproval_Workflow_Procedures.sql` — creates the Standard/Batch `spUTL_PIP_T_Inspection_SubmitWorkflow` and approval procedures. This is required before BATCH sync can submit its workflow.
6. `inspection_parameter_change_migration.sql` — canonical `spUTL_PIP_T_Inspection_Sync`, including version-level Follow Up enforcement and ObjectIndex persistence.
7. `inspection_mode_migration.sql` — adds/normalizes `dbo.PIP_M_InspectionType.InspectionMode` (`STANDARD` / `BATCH`).
8. The previously installed `PIP_M_InspectionMap` and `PIP_M_InspectionPoint` master schema.
9. `inspection_batch_transaction_migration.sql` — point transaction table, point references on result/photo tables, and BATCH sync procedure. No separate batch-number sequence table/procedure is used.
10. `Database/LightningInspection_Transaction_Migration.sql`, `Database/LightningInspection_Approval_Workflow.sql`, then `Database/LightningInspection_Sync_Procedure.sql` — Lightning schedule-point transaction, approval workflow, and daily sync procedure. The email schema from step 4 must be installed first.

The BATCH transaction design is:

- One `PIP_T_Inspection` row is the batch header; its `InspectionNo` uses the same existing `sp_GetGenerateAutoNumID` mechanism as STANDARD inspections.
- One `PIP_T_InspectionPoint` row is saved for each active master point in the batch.
- Checklist results and photos reference `InspectionPointTransactionID`, so repeated template item IDs across points do not collide.
- STANDARD inspections continue to use the existing header-level result/photo records (their point transaction ID remains NULL).
- Both STANDARD and BATCH use the selected template version's `IsFollowUpRequired`; when disabled, sync persists `No Follow Up` and clears Follow Up section/remark.
- Global Sync downloads `IsFollowUpRequired` with both Work Order and Inspection templates into their scoped IndexedDB stores; new Inspection records also retain the exact template snapshot for offline entry and later approval.

After the SQL migrations are installed, publish the updated WebForms and JavaScript files from this branch. Complete runtime verification still needs to be performed against the target SQL Server and the VS2013/.NET 4.5 application.

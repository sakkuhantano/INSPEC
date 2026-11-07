# INSPEC BATCH Inspection deployment order

The BATCH transaction code expects the existing Inspection Type / Template / Map masters to be installed first.

Run the SQL files in this order:

1. `inspection_transaction_schema.sql` — canonical Inspection header, result, result-value, and photo tables.
2. `master_template_inspection_schema.sql` — Inspection template/version master dependencies.
3. `inspection_parameter_change_migration.sql` — latest canonical `spUTL_PIP_T_Inspection_Sync` copied from the `sakkuhantano/test` repository branch `feature/inspec-template-assign-inspec`.
4. `inspection_mode_migration.sql` — adds/normalizes `dbo.PIP_M_InspectionType.InspectionMode` (`STANDARD` / `BATCH`).
5. The previously installed `PIP_M_InspectionMap` and `PIP_M_InspectionPoint` master schema.
6. `inspection_batch_transaction_migration.sql` — point transaction table, point references on result/photo tables, monthly batch-number sequence, and BATCH sync procedure.

The BATCH transaction design is:

- One `PIP_T_Inspection` row is the batch header; its number uses `yyyymmxxxx`.
- One `PIP_T_InspectionPoint` row is saved for each active master point in the batch.
- Checklist results and photos reference `InspectionPointTransactionID`, so repeated template item IDs across points do not collide.
- STANDARD inspections continue to use the existing header-level result/photo records (their point transaction ID remains NULL).

After the SQL migrations are installed, publish the updated WebForms and JavaScript files from this branch. Complete runtime verification still needs to be performed against the target SQL Server and the VS2013/.NET 4.5 application.

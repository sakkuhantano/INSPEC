# INSPEC integrated Inspection deployment runbook

Target: SQL Server 2008, ASP.NET WebForms / .NET Framework 4.5.

This is the deployment source of truth for the integrated REPEAT, map, BATCH (Car Park / Motor), Lightning daily Inspection, and COMVAL approval workflow branch. Back up the database and deploy to a non-production database first.

## Before running SQL

The existing INSPEC database is expected to contain the canonical base tables and types, including PIP_M_InspectionType, PIP_M_InspectionTypeDetail, PIP_M_Section, PIP_T_Inspection, PIP_T_InspectionResult, PIP_T_InspectionResultValue, PIP_T_InspectionPhoto, PIP_M_InspectionMap, PIP_M_InspectionPoint, Type_N_Tbl_C13, Type_N_Tbl_C5, SysWebCommonValue, M_HRD_Employee, SysWebUser, and the existing INSPEC/PIP authorization functions.

Do not rerun the initial-install scripts database/inspection_transaction_schema.sql or database/master_template_inspection_schema.sql when these base objects already exist. Resolve missing prerequisites separately before proceeding.

Before proceeding, confirm the populated map schema already has the map-owned type columns required by the current application:

```sql
SELECT
    COL_LENGTH('dbo.PIP_M_InspectionMap','InspectionTypeCode') AS MapInspectionTypeCodeLength,
    COL_LENGTH('dbo.PIP_M_InspectionMap','InspectionTypeDetailCode') AS MapInspectionTypeDetailCodeLength,
    COL_LENGTH('dbo.PIP_M_InspectionPoint','InspectionPointID') AS MasterPointIDLength;
```

If either map-owned type column is NULL while PIP_M_InspectionPoint already contains data, stop. Do not run SQL/ALTER_PIP_M_InspectionMap_MoveInspectionType.sql against the populated database; that script intentionally refuses populated points. A separate data-preserving migration is required before application deployment.

## Required SQL deployment order

Run each file in this order. Stop on the first SQL error.

1. Database/repeatable_inspection_schema.sql
   - Adds REPEAT master configuration tables and ObjectIndex/value-column changes.
2. Database/InspectionWorkflow_ComVal_Migration.sql
   - Consolidates InspectionMode to STANDARD or BATCH, InspectionPointMode to MAP or DYNAMIC, and ScheduleSelectionMode to PARAM or INSPECT.
   - Normalizes legacy LIGHTNING / AT_INSPECTION master values to BATCH / INSPECT, then drops deprecated PointSource and ApprovalWorkflowCode master columns after backfill.
3. Database/InspectionPoint_Coordinate_Consolidation.sql
   - Ensures MapX / MapY anchor coordinates exist on PIP_M_InspectionPoint.
4. Database/inspection_point_svg_shape_migration.sql
   - Adds SVG geometry columns and the supported CIRCLE / RECTANGLE / PATH shape constraint.
5. Database/InspectionMapGroup_Migration.sql
   - Adds Map Group master and the scoped MapGroupID relationship on PIP_M_InspectionMap.
6. SQL/ALTER_PIP_M_InspectionMap_RequireAllPoints.sql
   - Adds the map-level RequireAllPoints rule used by Car Park / Lightning coverage validation.
7. database/inspection_batch_transaction_migration.sql
   - Adds the canonical BATCH point transaction / result / photo structure. Requires existing base tables and TVPs.
8. Database/LightningInspection_Transaction_Migration.sql
   - Adds ScheduleTime per-point storage and normalizes old transaction header modes to BATCH.
9. Database/inspection_dynamic_point_migration.sql
   - Allows dynamic Motor point snapshots with NULL InspectionPointID, drops the deprecated PointSource transaction column, and creates schedule-scoped filtered indexes. Master points retain a non-NULL InspectionPointID.
10. database/inspection_point_abnormal_summary_migration.sql
    - Adds point abnormal / summary settings used by map point validation and REPEAT summary rules.
11. Database/Inspection_GPS_Transaction_Migration.sql
    - Adds technician GPS columns used by Inspection sync / geofence validation.
12. Database/Inspection_Tenant_Suite_Migration.sql
    - Adds tenant/suite inspection fields and duplicate-check index.
13. Database/InspectionApproval_HeaderFields_Migration.sql
    - Adds / normalizes approval actor, date, and stage fields on PIP_T_Inspection.
14. Database/InspectionEmailApproval_Schema.sql
    - Creates approval history and email outbox, including CHIEF_HK history support.
15. Database/InspectionApproval_ComVal_EmailHelper.sql
    - Creates fnINSPEC_ApprovalEmailEnabled and fnINSPEC_ChiefRoleForSection.
16. Database/spUTL_PIP_T_Inspection_Approval.sql
    - Deploys the Follow Up / final-approval gate used by the approval execute wrapper.
17. Database/InspectionApproval_Workflow_Procedures.sql
    - Deploys the active Standard / BATCH-PARAM submit, approval, and execute procedures.
18. Database/LightningInspection_Approval_Workflow.sql
    - Deploys the active Lightning submit and three-stage approval procedures.
19. database/inspection_parameter_change_migration.sql
    - Adds SyncDate / archive / cancellation fields and installs the parameter-change Standard sync foundation. This must run after the generic workflow procedures because it invokes the submit workflow.
20. Database/Patch_Inspection_DeleteArchive_ColumnLengths.sql
    - Fixes archive field lengths created by the parameter-change migration.
21. Database/spPIP_InsertUpdateDeleteInput_PIP_M_HD_InspectionType.sql
    - Deploys the Inspection Type master save procedure using InspectionMode / InspectionPointMode / ScheduleSelectionMode.
22. Database/spPIP_InsertUpdateDeleteInput_PIP_M_InspectionGeofence.sql
    - Creates / deploys the Geofence master save procedure.
23. Database/spUTL_PIP_T_WO_AssignmentEmployee.sql
    - Deploys the current Work Order assignment procedure.
24. Database/spUTL_PIP_M_CheckListWOPM.sql
    - Deploys REPEAT template configuration persistence.
25. Database/spUTL_WO_CheckList.sql
    - Deploys Work Order REPEAT value validation / persistence.
26. Database/spUTL_PIP_T_Inspection_Sync.sql
    - Deploys the final STANDARD Inspection sync, including REPEAT persistence, GPS / tenant fields, and generic submit workflow call. This replaces the interim procedure from step 19.
27. Database/spUTL_PIP_T_Inspection_Batch_Sync.sql
    - Deploys the final BATCH MAP / DYNAMIC sync, including abnormal summary validation and nullable InspectionPointID handling.
28. Database/LightningInspection_Sync_Procedure.sql
    - Deploys Lightning daily sync for BATCH / MAP / INSPECT.

The base schema scripts are initial-install prerequisites, not part of this upgrade sequence. If a base table or TVP is missing, resolve that separately; do not blindly run initial-install scripts over an existing database.

## Optional migrations — only when the condition applies

- Database/InspectionEmailApproval_CommonValue_Migration.sql: run only if the old temporary PIP_M_InspectionEmailSetup* tables still exist and must be migrated. It drops those temporary tables after migration.
- Database/InspectionApproval_ComValWorkflow_Migration.sql: run only if legacy Company/Location EMAIL switches exist and must be converted. Run after the previous optional migration when both apply. It never overwrites an already-configured workflow COMVAL.
- Database/InspectionPoint_RemoveCompanyLocation_Migration.sql: run only if PIP_M_InspectionPoint still has the old CompanyID / LocationID columns. Review its dependency report first; it stops if database modules still reference those columns.
- Database/inspection_point_circle_geometry_backfill.sql: run after the SVG shape migration only if existing CIRCLE points need ShapeAttributes backfilled from MapX / MapY.
- Database/THD_Tenant_Suite_Master_Reference.sql: run only if the THD tenant / agreement master tables are genuinely absent. These tables are owned by THD; do not create duplicate copies when they already exist.
- Database/InspectionPoint_Seed_MCDP.sql, Database/InspectionPoint_Seed_MCDP_Lighting_SplitMaps.sql, and Database/Import_INSPEC_Lighting_Parking_Maps_Points_FKFix.sql are data import / seed scripts only. Do not run if the required Map / Point master data is already present.

## Do NOT run these superseded scripts

These files are retained for reference or compatibility, but are not part of this deployment:

- database/inspection_mode_migration.sql
- database/inspection_presentation_config_migration.sql
- database/inspection_type_code_length_migration.sql (the final standard sync procedure already has the corrected parameter width)
- Database/spPIP_Inspection_Query.sql (not called by the current WebForms call sites in this branch)
- SQL/ALTER_PIP_M_InspectionMap_MoveInspectionType.sql (only for an empty initial database; it intentionally refuses to run when Inspection Points exist)
- Database/InspectionLegacyApproval_Procedure_ColumnRename.sql
- Database/InspectionPoint_ShapeGeometry_Migration.sql
- Database/InspectionPoint_RemoveShapeTypeCheckConstraint.sql
- database/inspection_location_map_schema.sql (initial map schema; do not rerun over existing map tables)
- database/inspection_transaction_schema.sql (initial transaction schema; do not rerun over existing transaction tables)
- database/master_template_inspection_schema.sql (initial template schema; do not rerun over existing template tables)
- Database/spUTL_PIP_T_Inspection_SubmitWorkflow.sql
- Database/spUTL_PIP_T_Inspection_ApprovalWorkflow.sql
- Database/spUTL_PIP_T_Inspection_Approval_Execute.sql
- Database/spUTL_PIP_T_Inspection_Lightning_Approval.sql
- Database/spUTL_PIP_T_Inspection_Lightning_SubmitWorkflow.sql
- Database/spUTL_PIP_T_Inspection_Lightning_Sync.sql

Use the consolidated / canonical scripts in the required order above. Do not run the obsolete inspection_presentation_config_migration.sql; it adds deprecated PointSource / ApprovalWorkflowCode master fields.

## Per-company COMVAL configuration

All routing is stored in dbo.SysWebCommonValue, AppID='INSPEC', CommonGroup='EmailApproval'. The key scope is CompanyID + LocationID (without a separator).

Approver mappings:

- SPV: <CompanyID><LocationID>;SPV;<SectionID> → semicolon-separated EmployeeIDs in Description. Mandatory for every active Inspection Section.
- Chief Engineering: <CompanyID><LocationID>;CHIEF_ENG → semicolon-separated EmployeeIDs.
- Chief Security: <CompanyID><LocationID>;CHIEF_SEC → semicolon-separated EmployeeIDs.
- Chief Housekeeping: <CompanyID><LocationID>;CHIEF_HK → semicolon-separated EmployeeIDs.

Chief role for BATCH / PARAM is resolved from PIP_M_Section.ProfitCenterNo:

| ProfitCenterNo | COMVAL mapping key |
|---|---|
| PENG | CHIEF_ENG |
| PSEC | CHIEF_SEC |
| PHKP | CHIEF_HK |

The Chief Description can contain multiple NIKs separated by semicolons, so an alternate / assistant can also receive approval. Every listed NIK must be an active employee in the matching Company and ProfitCenter.

Workflow email switches are scoped per Company + Location; Description contains stage tokens:

| COMVAL ID suffix | Description |
|---|---|
| ;STANDARD | [SPV][TRUE/FALSE] |
| ;BATCH;PARAM | [SPV][TRUE/FALSE];[CHIEF][TRUE/FALSE] |
| ;BATCH;INSPECT | [SPV][TRUE/FALSE];[CHIEF_SEC][TRUE/FALSE];[CHIEF_ENG][TRUE/FALSE] |

Example: ID I00024012R02;BATCH;INSPECT, Description [SPV][TRUE];[CHIEF_SEC][TRUE];[CHIEF_ENG][TRUE].

Email switches control notification only; they never bypass an approval stage. Missing token / malformed token / FALSE means no email for that stage. A missing Chief approver mapping skips that Chief stage and records SKIPPED in PIP_T_InspectionApprovalHistory, with the approval actor field stamped using the previous actual approver.

## Canonical workflow behavior

- STANDARD: Technician → Section SPV.
- BATCH / MAP / PARAM (Car Park): Technician → Section SPV → one Chief selected from the Section ProfitCenter.
- BATCH / DYNAMIC / PARAM (Motor): Technician → Section SPV → one Chief selected from the Section ProfitCenter.
- BATCH / MAP / INSPECT (Lightning daily): Technician → SPV → Chief Security → Chief Engineering.

InspectionMode is only STANDARD or BATCH. ScheduleSelectionMode is PARAM or INSPECT. InspectionPointMode is MAP or DYNAMIC for BATCH types and NULL for STANDARD. There is no active master workflow-code field.

Approval flags on PIP_T_Inspection:

- STANDARD / BATCH-PARAM: IsApproved = SPV; IsApproved1 = Section Chief stage.
- BATCH-INSPECT: IsApproved = SPV; IsApproved1 = Chief Security; IsApproved2 = Chief Engineering.

A missing optional Chief mapping skips that stage and records the skip. Email OFF does not skip an approver. VOID requires a reason and returns the transaction for technician correction; resubmission resets active approval flags but retains approval history.

## Application files

Publish the whole feature/repeatable-inspection-integrated-ux branch with the SQL package. Do not cherry-pick only a subset into an older WebForms build. The following files are changed in this branch relative to main.

**JavaScript**

- JSCus/GFC_FO.js
- JSCus/Login.js
- JSCus/Site1.Master.js
- JSCus/dashboard.js
- JSCus/inspection.js
- JSCus/inspectionApprovalOffline.js
- JSCus/inspectionApprovalSync.js
- JSCus/inspectionGeofence.js
- JSCus/inspectionMapWorkspace.js
- JSCus/inspectionmaster.js
- JSCus/pdf.min.js
- JSCus/pdf.worker.min.js
- JSCus/template.js
- JSCus/workorder.js

**CSS**

- CSSCus/Site1.Master.css
- CSSCus/inspectionGeofence.css
- CSSCus/inspectionmaster.css
- CSSCus/template.css

**ASPX code-behind (.aspx.cs)**

- Login.aspx.cs
- SearchList_2.aspx.cs
- Secure/M_InspectionGeofence.aspx.cs
- Secure/M_InspectionType.aspx.cs
- Secure/M_LightingMapEditor.aspx.cs
- Secure/R_Report.aspx.cs
- Secure/R_Reports.aspx.cs
- Secure/T_LightingInspection.aspx.cs
- Secure/T_ParkingInspection.aspx.cs
- Secure/assignwoemployee.aspx.cs
- Secure/dashboard.aspx.cs
- Secure/inspection.aspx.cs
- Secure/inspectionemailsetup.aspx.cs
- Secure/inspectionmaster.aspx.cs
- Secure/template.aspx.cs
- Secure/workorder.aspx.cs

**Other C# files**

- BRC/PIP_T_WO.cs
- BusinessRules/Components/CF.cs
- GFC.cs
- MasterPages/Site1.Master.cs

**ASPX markup**

- Login.aspx
- Secure/M_InspectionGeofence.aspx
- Secure/M_InspectionType.aspx
- Secure/M_LightingMapEditor.aspx
- Secure/R_Reports.aspx
- Secure/T_LightingInspection.aspx
- Secure/T_ParkingInspection.aspx
- Secure/inspection.aspx
- Secure/inspectionemailsetup.aspx
- Secure/inspectionmaster.aspx
- Secure/template.aspx
- Secure/workorder.aspx

**Designer files**

- SearchList_2.aspx.designer.cs
- Secure/M_InspectionGeofence.aspx.designer.cs
- Secure/M_InspectionType.aspx.designer.cs
- Secure/M_LightingMapEditor.aspx.designer.cs
- Secure/T_LightingInspection.aspx.designer.cs
- Secure/T_ParkingInspection.aspx.designer.cs
- Secure/inspectionemailsetup.aspx.designer.cs
- Secure/inspectionmaster.aspx.designer.cs

The current workflow finalization adds no new CSS files beyond the four CSS files already changed in this integrated branch. Keep the INSPEC.csproj inclusion of JSCus/inspectionMapWorkspace.js for build / publish.

## Non-production smoke test

1. Confirm all required scripts finish without errors; confirm both helper functions and all active submit / approval / sync procedures exist.
2. Confirm Inspection Type values: STANDARD has no point mode and PARAM schedule; Car Park is BATCH / MAP / PARAM; Motor is BATCH / DYNAMIC / PARAM; Lightning is BATCH / MAP / INSPECT.
3. Configure one SPV per test Section and the appropriate Chief mapping for its ProfitCenter. Test semicolon-separated alternate NIKs.
4. Test STANDARD, Car Park, Motor, and Lightning sync. Confirm the saved Inspection header uses only STANDARD or BATCH.
5. Test SPV approval, Chief approval, missing-Chief skip, VOID, correction, and resubmission for each applicable workflow.
6. Test email flags ON and OFF independently. OFF must suppress notification only; it must not bypass approval.
7. Confirm history StageCode values, actor NIKs, ApprovedBy / Approved1By / Approved2By, and outbox status.
8. Test REPEAT items in template, STANDARD/BATCH Inspection entry, offline save/sync, approval read-only view, and Work Order if in scope.
9. Build with VS2013 / .NET Framework 4.5 and test in IIS. Repository edits alone do not certify runtime behavior.

Release status: this branch remains a test candidate until SQL deployment, VS2013 build, and non-production smoke tests pass.

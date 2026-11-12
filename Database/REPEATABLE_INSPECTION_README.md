# Native REPEAT inspection schema and deployment

This branch adds native `ItemType='REPEAT'` support without converting or deleting legacy `GROUP` records.

## Deployment order

1. Run `Database/repeatable_inspection_schema.sql` on the INSPEC database. It creates the REPEAT master tables and TVPs, adds `ObjectIndex` to Work Order and Inspection child values, widens Work Order child values to text, and updates the Inspection child-value primary key.
2. Deploy the updated definitions of these procedures from `Database/stored proedures.txt`:
   - `spUTL_PIP_M_CheckListWOPM`
   - `spUTL_WO_CheckList`
   - `spUTL_PIP_T_Inspection_Sync`
   - `spUTL_PIP_T_Inspection_Batch_Sync`
3. Deploy the corresponding WebForms and JavaScript changes from this branch.

`Database/tvp.txt` is the TVP reference listing. The schema migration creates the new TVP types required by the application.

## Data model

- `PIP_M_CheckListWOPM_ItemRepeat`: one REPEAT configuration per checklist item.
- `PIP_M_CheckListWOPM_ItemRepeatField`: child field definitions keyed by stable `FieldKey`.
- Child field types: `NUMBER`, `RANGE`, `OPTION`, `TEXT`. Nested REPEAT is not supported.
- `FIELDS`: one logical record, stored as `ObjectIndex=0`; `ColumnCount` controls the UI grid (default 3).
- `OBJECTS`: repeated objects with the same child field definitions; object indices are zero-based and sequential.
- Child values use `FieldKey`, never the visible field label. Renaming a label therefore does not change the data key.
- Child fields can be required, constrained by min/max, assigned a unit, option list, display order, and optional group heading.

## Transaction storage

- Work Order child values use `PIP_T_WO_CheckList_SubValue.ObjectIndex` plus `FieldName=FieldKey`.
- Inspection child values use `PIP_T_InspectionResultValue.ObjectIndex` plus `FieldName=FieldKey`.
- STANDARD and BATCH Inspection sync reuse spare columns in the existing `Type_N_Tbl_C5` TVP for ObjectIndex, so the existing C# procedure signature remains compatible.
- Legacy GROUP values remain at ObjectIndex 0 and are not migrated.

The application validates required child fields and object counts on both client and server paths. The SQL migration and procedure definitions must be deployed together before enabling REPEAT templates.

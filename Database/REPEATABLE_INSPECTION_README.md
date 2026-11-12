# Native REPEAT inspection schema and deployment

This branch adds native `ItemType='REPEAT'` support without converting or deleting legacy `GROUP` records.

## Deployment order

1. Run `Database/repeatable_inspection_schema.sql` on the INSPEC database. It creates the REPEAT master tables and TVPs (including `Type_Tbl_RepeatFieldV2`), adds `ObjectIndex` to Work Order and Inspection child values, widens Work Order child values to text, adds inclusive/exclusive range flags, and updates the Inspection child-value primary key.
2. Deploy the updated definitions of these procedures from `Database/stored proedures.txt`:
   - `spUTL_PIP_M_CheckListWOPM`
   - `spUTL_WO_CheckList`
   - `spUTL_PIP_T_Inspection_Sync`
   - `spUTL_PIP_T_Inspection_Batch_Sync`
3. Run `Database/inspection_point_svg_shape_migration.sql` after `PIP_M_InspectionPoint` exists. This adds shape columns directly to the existing point table; it does not create or reference `PIP_M_InspectionMapElement`.
4. Deploy the corresponding WebForms and JavaScript changes from this branch.

`Database/tvp.txt` is the TVP reference listing. The schema migration creates the new TVP types required by the application. The template save procedure now accepts `Type_Tbl_RepeatFieldV2`; the original `Type_Tbl_RepeatField` is retained so other existing consumers are not broken.

## Data model

- `PIP_M_CheckListWOPM_ItemRepeat`: one REPEAT configuration per checklist item.
- `PIP_M_CheckListWOPM_ItemRepeatField`: child field definitions keyed by stable `FieldKey`.
- Child field types: `NUMBER`, `RANGE`, `OPTION`, `TEXT`. Nested REPEAT is not supported.
- `FIELDS`: one logical record, stored as `ObjectIndex=0`; `ColumnCount` controls the UI grid (default 3).
- `OBJECTS`: repeated objects with the same child field definitions; object indices are zero-based and sequential.
- Child values use `FieldKey`, never the visible field label. Renaming a label therefore does not change the data key.
- Child fields can be required, constrained by min/max, assigned an optional unit, option list, display order, and optional group heading. Unit is presentation metadata only; blank units are valid. `ShowUnitInRange` on a parent RANGE item controls whether its unit appears beside the reference range choices/hint. `MinInclusive` and `MaxInclusive` independently define whether a configured boundary is accepted; legacy fields default to inclusive. For example, `MinValue=26, MinInclusive=0` means `>26`, while `MaxValue=47, MaxInclusive=0` means `<47`. An open boundary is represented by NULL.

## Transaction storage

- Work Order child values use `PIP_T_WO_CheckList_SubValue.ObjectIndex` plus `FieldName=FieldKey`.
- Inspection child values use `PIP_T_InspectionResultValue.ObjectIndex` plus `FieldName=FieldKey`.
- STANDARD and BATCH Inspection sync reuse spare columns in the existing `Type_N_Tbl_C5` TVP for ObjectIndex, so the existing C# procedure signature remains compatible.
- Legacy GROUP values remain at ObjectIndex 0 and are not migrated.

The application validates required child fields and object counts on both client and server paths. The SQL migration and procedure definitions must be deployed together before enabling REPEAT templates.

## Integrated Inspection UX patch

The integrated branch also includes these Inspection Entry fixes:

- STANDARD `Start Checklist` opens the Checklist pane immediately after the parameters are accepted.
- On screens up to 767.98px, the desktop Point List is fully hidden; it does not collapse below the map.
- Tapping a map marker on mobile opens that point's Checklist Entry directly. Desktop retains the Point List workflow.
- The Batch map workspace uses a viewport-height layout, a narrower desktop Point List, and a map stage fitted to both available width and height. PDF/JPEG maps preserve their original aspect ratios in Inspection Entry and Inspection Master preview.
- `JSCus/inspectionMapWorkspace.js` is explicitly included in `INSPEC.csproj`, so it is part of the Web Application project build/publish output.

The map workspace is a separate JavaScript module referenced by `Secure/inspection.aspx`; keep both the page reference and project inclusion when moving the patch into another solution.

## Map geometry

- Circle points continue to use `PIP_M_InspectionPoint.MapX/MapY`.
- A point can now use `ShapeType='PATH'`; its SVG `d` data is stored in `PIP_M_InspectionPoint.SvgPathData`, with `ShapeAttributes` and `StrokeWidth` stored on the same point row.
- SVG coordinates use the normalized `0..100` map coordinate plane. `MapX/MapY` remain the anchor/centroid used for the point identity and navigation.
- `Secure/inspectionmaster.aspx` includes a freehand Draw SVG Path tool; the Inspection map renders the path as a clickable area whose visual state follows the point's checklist status.
- This design deliberately extends `PIP_M_InspectionPoint` and does not revive the dropped `PIP_M_InspectionMapElement` table.

## REPEAT coverage audit

The branch contains code paths for Template Builder/master persistence, dashboard template payloads, Work Order entry and IndexedDB serialization, Work Order sync through `SyncWO`/`PIP_T_WO.UpdateWO`/`spUTL_WO_CheckList`, STANDARD and BATCH Inspection entry, IndexedDB record persistence, server validation and both Inspection sync procedures, returned/approval read-only snapshots, and the Excel `REPEAT DETAIL` worksheet. REPEAT values remain nested in the existing offline records; no separate IndexedDB object store is required.

The dashboard overview cards remain Work Order/Inspection summary cards; they do not expand every child field as card content. The template payload used by Work Order and Inspection does include the REPEAT configuration. Runtime verification still requires a VS2013 build and SQL Server 2008 deployment/test run; repository inspection alone cannot certify those.

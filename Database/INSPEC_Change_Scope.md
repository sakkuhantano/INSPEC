# INSPEC database change scope

This document lists **only database objects added or structurally changed** for the current REPEAT, SVG inspection-point, and Inspection Map Group work. Unchanged objects are intentionally omitted.

SQL Server target: SQL Server 2008.

## 1. New tables

| New table | Purpose |
|---|---|
| `dbo.PIP_M_CheckListWOPM_ItemRepeat` | REPEAT configuration for a checklist item: FIELDS/OBJECTS mode, column layout, and object-count rules. |
| `dbo.PIP_M_CheckListWOPM_ItemRepeatField` | Child-field definitions for a REPEAT item, including type, options, unit, range boundaries, required flag, grouping, and display order. |
| `dbo.PIP_M_InspectionMapGroup` | Inspection Map Group master scoped by Company and Location. |

## 2. Existing tables changed

| Existing table | Change |
|---|---|
| `dbo.PIP_T_WO_CheckList_SubValue` | Add `ObjectIndex`; widen `FieldName` to `VARCHAR(100)` and `Value` to `NVARCHAR(500)`; add index `IX_PIP_T_WO_SubValue_Result_Object_Field`. |
| `dbo.PIP_T_InspectionResultValue` | Widen `Value` to `NVARCHAR(500)`; add `ObjectIndex`; change primary key to `(InspectionResultID, ObjectIndex, FieldName)`. |
| `dbo.PIP_M_InspectionPoint` | Add `ShapeType`, `SvgPathData`, `ShapeAttributes`, and `StrokeWidth` for CIRCLE/PATH geometry. `MapX` and `MapY` remain the point anchor coordinates. |
| `dbo.PIP_M_InspectionMap` | Add nullable `MapGroupID`, composite FK to `PIP_M_InspectionMapGroup`, and group lookup index `IX_PIP_M_InspectionMap_Group`. |

## 3. Stored procedures changed

Only these four procedures have REPEAT persistence/validation changes:

1. `dbo.spUTL_PIP_M_CheckListWOPM` — saves REPEAT configuration and child-field definitions from the master template.
2. `dbo.spUTL_WO_CheckList` — validates and stores REPEAT values entered for a Work Order.
3. `dbo.spUTL_PIP_T_Inspection_Sync` — validates and stores REPEAT values for standard inspections.
4. `dbo.spUTL_PIP_T_Inspection_Batch_Sync` — validates and stores REPEAT values for batch inspections.

No additional stored procedure is listed as changed for the Map Group or SVG geometry work.

## 4. Existing TVPs reused — no new TVP types

**No User Defined Table Type is created or required by this change.** The existing definitions in `Database/tvp.txt` remain the source of truth.

| Procedure parameter / payload | Existing TVP | Columns used |
|---|---|---|
| `@p_dt_RepeatConfig` in `spUTL_PIP_M_CheckListWOPM` | `dbo.Type_N_Tbl_C13` | C1–C9 |
| `@p_dt_RepeatField` in `spUTL_PIP_M_CheckListWOPM` | `dbo.Type_N_Tbl_C13` | C1–C13 |
| `@p_DtRepeat` in `spUTL_WO_CheckList` | `dbo.Type_N_Tbl_C5` | C1–C5 |
| `@p_ItemValues` in standard and batch inspection sync | `dbo.Type_N_Tbl_C5` | C1–C5 |

The existing `Type_N_Tbl_C13` and `Type_N_Tbl_C5` definitions use `NVARCHAR(MAX)` columns, so the payloads support Unicode text. The legacy GROUP parameters keep their existing TVP contracts; they are not repurposed.

The Repeat-specific type declarations previously appended to `tvp.txt` and `repeatable_inspection_schema.sql` have been removed. Do not run or create `Type_Tbl_RepeatConfig`, `Type_Tbl_RepeatField`, `Type_Tbl_RepeatFieldV2`, or `Type_Tbl_WORepeatValue`.

## 5. Deployment scripts

Run the applicable scripts in this order:

1. `Database/repeatable_inspection_schema.sql` — creates the two REPEAT master tables and alters the two existing value tables.
2. `Database/inspection_point_svg_shape_migration.sql` — adds SVG geometry columns and constraints to `PIP_M_InspectionPoint`.
3. `Database/InspectionMapGroup_Migration.sql` — creates the Map Group table and alters `PIP_M_InspectionMap`.
4. Deploy the four updated stored procedure definitions listed in section 3 from `Database/stored proedures.txt`.

The existing TVP types must already be present in the database. **There is no TVP deployment step for this feature.**

## 6. Explicitly unchanged / out of scope

- `dbo.PIP_M_CheckListWOPM_Item` receives no structural change; `ItemType='REPEAT'` identifies a REPEAT item.
- Existing legacy GROUP data and its TVP contract remain unchanged.
- No legacy GROUP/REPEAT data migration is required for this rollout; the new REPEAT template is empty and no Work Orders have been initialized from it.
- Work Order schema/workflow is not changed for Map Group support.
- `dbo.PIP_M_InspectionMapElement` is obsolete and is not created, queried, or referenced. Map coordinates remain on `PIP_M_InspectionPoint.MapX` and `MapY`.

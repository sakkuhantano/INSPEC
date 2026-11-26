/* LEGACY DUPLICATE — DO NOT RUN. Use Database/inspection_point_svg_shape_migration.sql for the current geometry schema. */
/*
    INSPEC - Inspection Point shape geometry columns
    Target: SQL Server 2008
    Run this migration ONCE before running:
      InspectionPoint_Seed_MCDP_Lighting_SplitMaps.sql

    The earlier coordinate migration only added MapX / MapY. The map editor
    also reads and writes these shape columns, so they must exist on the master.
*/
IF COL_LENGTH('dbo.PIP_M_InspectionPoint','ShapeType') IS NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint ADD ShapeType VARCHAR(20) NULL;
GO

IF COL_LENGTH('dbo.PIP_M_InspectionPoint','SvgPathData') IS NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint ADD SvgPathData NVARCHAR(8000) NULL;
GO

IF COL_LENGTH('dbo.PIP_M_InspectionPoint','ShapeAttributes') IS NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint ADD ShapeAttributes NVARCHAR(2000) NULL;
GO

IF COL_LENGTH('dbo.PIP_M_InspectionPoint','StrokeWidth') IS NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint ADD StrokeWidth DECIMAL(6,2) NULL;
GO

/* Backfill safe defaults for existing records without changing coordinates. */
UPDATE dbo.PIP_M_InspectionPoint
SET ShapeType=ISNULL(NULLIF(ShapeType,''),'CIRCLE'),
    ShapeAttributes=ISNULL(NULLIF(ShapeAttributes,''),'{}'),
    StrokeWidth=ISNULL(StrokeWidth,1.50)
WHERE ShapeType IS NULL OR ShapeType='' OR ShapeAttributes IS NULL
   OR ShapeAttributes='' OR StrokeWidth IS NULL;
GO

/* Confirm the required geometry columns are present. */
SELECT C.name AS ColumnName, TYPE_NAME(C.user_type_id) AS DataType,
       C.max_length AS MaxLength, C.precision, C.scale, C.is_nullable
FROM sys.columns C
WHERE C.object_id=OBJECT_ID('dbo.PIP_M_InspectionPoint')
  AND C.name IN ('MapX','MapY','ShapeType','SvgPathData','ShapeAttributes','StrokeWidth')
ORDER BY C.column_id;
GO

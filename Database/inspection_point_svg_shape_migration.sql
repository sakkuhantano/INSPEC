/*
    INSPEC inspection-point SVG geometry.
    Geometry is stored on PIP_M_InspectionPoint itself; this migration does NOT
    create or reference the obsolete PIP_M_InspectionMapElement table.

    SVG coordinates use a normalized 0..100 x/y coordinate space that matches
    MapX/MapY and the map image's aspect-ratio-preserving display stage.

    CIRCLE geometry is stored in ShapeAttributes JSON as {cx,cy,r}; cx/cy
    use the normalized 0..100 plane and r is the circle radius in that plane.
    MapX/MapY remain compatibility anchors. PATH geometry stays in SvgPathData.
*/
SET NOCOUNT ON;
GO

IF COL_LENGTH('dbo.PIP_M_InspectionPoint','ShapeType') IS NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint
        ADD ShapeType VARCHAR(10) NOT NULL
            CONSTRAINT DF_PIP_M_InspectionPoint_ShapeType DEFAULT ('CIRCLE');
GO

IF COL_LENGTH('dbo.PIP_M_InspectionPoint','SvgPathData') IS NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint
        ADD SvgPathData NVARCHAR(MAX) NULL;
GO

IF COL_LENGTH('dbo.PIP_M_InspectionPoint','ShapeAttributes') IS NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint
        ADD ShapeAttributes NVARCHAR(1000) NOT NULL
            CONSTRAINT DF_PIP_M_InspectionPoint_ShapeAttributes DEFAULT (N'{}');
GO

IF COL_LENGTH('dbo.PIP_M_InspectionPoint','StrokeWidth') IS NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint
        ADD StrokeWidth DECIMAL(10,2) NOT NULL
            CONSTRAINT DF_PIP_M_InspectionPoint_StrokeWidth DEFAULT (1.50);
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_M_InspectionPoint')
      AND name='CK_PIP_M_InspectionPoint_ShapeType'
)
    ALTER TABLE dbo.PIP_M_InspectionPoint
        ADD CONSTRAINT CK_PIP_M_InspectionPoint_ShapeType
        CHECK (ShapeType IN ('CIRCLE','PATH'));
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_M_InspectionPoint')
      AND name='CK_PIP_M_InspectionPoint_StrokeWidth'
)
    ALTER TABLE dbo.PIP_M_InspectionPoint
        ADD CONSTRAINT CK_PIP_M_InspectionPoint_StrokeWidth
        CHECK (StrokeWidth > 0 AND StrokeWidth <= 20);
GO

/* Existing points remain CIRCLE. A PATH point keeps MapX/MapY as its anchor
   and stores its actual clickable outline in SvgPathData. */
PRINT 'InspectionPoint SVG geometry columns are ready.';
GO

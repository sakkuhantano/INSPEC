/*
    Backfill normalized SVG circle geometry for existing Inspection Points.

    New CIRCLE records are saved as ShapeAttributes JSON:
      {"cx":35.00,"cy":45.30,"r":0.45}

    MapX/MapY remain as compatibility anchors for existing queries, validation,
    and point-position swapping. CIRCLE center is normalized from MapX/MapY.
    SQL Server 2008 compatible; safe to execute more than once.
*/
SET NOCOUNT ON;
GO

UPDATE P
SET ShapeAttributes =
    N'{"cx":' + CONVERT(VARCHAR(30), CONVERT(DECIMAL(9,4), P.MapX)) +
    N',"cy":' + CONVERT(VARCHAR(30), CONVERT(DECIMAL(9,4), P.MapY)) +
    N',"r":0.45}'
FROM dbo.PIP_M_InspectionPoint P
WHERE ISNULL(P.ShapeType, 'CIRCLE') = 'CIRCLE'
  AND P.MapX IS NOT NULL
  AND P.MapY IS NOT NULL
;

PRINT 'Existing Inspection Point circle geometry JSON normalized to compact dots.';
GO

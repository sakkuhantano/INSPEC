/*
    Backfill normalized SVG circle geometry for existing Inspection Points.

    New CIRCLE records are saved as ShapeAttributes JSON:
      {"cx":35.00,"cy":45.30,"r":2.0}

    MapX/MapY remain as compatibility anchors for existing queries, validation,
    and point-position swapping. Existing valid cx/cy geometry is preserved.
    SQL Server 2008 compatible; safe to execute more than once.
*/
SET NOCOUNT ON;
GO

UPDATE P
SET ShapeAttributes =
    N'{"cx":' + CONVERT(VARCHAR(30), CONVERT(DECIMAL(9,4), P.MapX)) +
    N',"cy":' + CONVERT(VARCHAR(30), CONVERT(DECIMAL(9,4), P.MapY)) +
    N',"r":2.0}'
FROM dbo.PIP_M_InspectionPoint P
WHERE ISNULL(P.ShapeType, 'CIRCLE') = 'CIRCLE'
  AND P.MapX IS NOT NULL
  AND P.MapY IS NOT NULL
  AND (
      P.ShapeAttributes IS NULL
      OR P.ShapeAttributes NOT LIKE N'%"cx"%'
      OR P.ShapeAttributes NOT LIKE N'%"cy"%'
  );

PRINT 'Existing Inspection Point circle geometry JSON backfill completed.';
GO

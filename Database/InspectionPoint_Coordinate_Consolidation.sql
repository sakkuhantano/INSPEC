/*
    Inspection Point coordinate columns
    Target: SQL Server 2008

    MapX and MapY are percentages (0..100) relative to the PDF page.
    Coordinates are stored directly on PIP_M_InspectionPoint.
    This script deliberately has no dependency on any legacy map-element table.
*/
IF COL_LENGTH('dbo.PIP_M_InspectionPoint', 'MapX') IS NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint ADD MapX DECIMAL(9,4) NULL;
GO

IF COL_LENGTH('dbo.PIP_M_InspectionPoint', 'MapY') IS NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint ADD MapY DECIMAL(9,4) NULL;
GO

/* Record that the coordinate-column setup has been applied.
   This does not populate or overwrite point coordinates. */
IF NOT EXISTS
(
    SELECT 1
    FROM sys.extended_properties
    WHERE name='PIP_InspectionPointCoordinateMigration'
      AND major_id=OBJECT_ID('dbo.PIP_M_InspectionPoint')
)
BEGIN
    EXEC sys.sp_addextendedproperty
         @name=N'PIP_InspectionPointCoordinateMigration',
         @value=N'Coordinate columns initialized; coordinates are maintained on PIP_M_InspectionPoint.',
         @level0type=N'SCHEMA', @level0name=N'dbo',
         @level1type=N'TABLE', @level1name=N'PIP_M_InspectionPoint';
END;
GO

/* Support map marker loading and nearby-coordinate checks. */
IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name='IX_PIP_M_InspectionPoint_MapCoordinate'
      AND object_id=OBJECT_ID('dbo.PIP_M_InspectionPoint')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_M_InspectionPoint_MapCoordinate
    ON dbo.PIP_M_InspectionPoint (MapID,MapX,MapY);
END;
GO

/* Review the current coordinates. This script does not alter existing values. */
SELECT InspectionPointID, MapID, PointCode, PointName, MapX, MapY
FROM dbo.PIP_M_InspectionPoint
ORDER BY MapID, DisplayOrder, PointCode;
GO

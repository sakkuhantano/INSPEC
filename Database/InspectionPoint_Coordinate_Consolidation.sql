/*
    Inspection Point coordinate consolidation
    Target: SQL Server 2008
    Run once before deploying the updated inspectionmaster.aspx page.

    Coordinates are percentages (0..100) relative to the PDF page.
    Legacy marker data is copied once. The old table is retained temporarily
    as a rollback copy; the updated application no longer reads or writes it.
*/
IF COL_LENGTH('dbo.PIP_M_InspectionPoint', 'MapX') IS NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint ADD MapX DECIMAL(9,4) NULL;
GO
IF COL_LENGTH('dbo.PIP_M_InspectionPoint', 'MapY') IS NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint ADD MapY DECIMAL(9,4) NULL;
GO

/* Extended property prevents a rerun from restoring coordinates that users
   have intentionally cleared or subsequently corrected. */
IF NOT EXISTS
(
    SELECT 1
    FROM sys.extended_properties
    WHERE name='PIP_InspectionPointCoordinateMigration'
      AND major_id=OBJECT_ID('dbo.PIP_M_InspectionPoint')
)
BEGIN
    IF OBJECT_ID('dbo.PIP_M_InspectionMapElement', 'U') IS NOT NULL
    BEGIN
        ;WITH MarkerSource AS
        (
            SELECT E.InspectionPointID, E.MapID, E.ShapeAttributes,
                   ROW_NUMBER() OVER
                   (PARTITION BY E.InspectionPointID, E.MapID ORDER BY E.UpdateDate DESC, E.MapElementID DESC) AS RowNo
            FROM dbo.PIP_M_InspectionMapElement E
            WHERE E.IsActive=1 AND E.IsDeleted=0
        ),
        Parsed AS
        (
            SELECT InspectionPointID, MapID,
                CASE WHEN CHARINDEX('x=', ShapeAttributes)>0
                     THEN SUBSTRING(ShapeAttributes, CHARINDEX('x=', ShapeAttributes)+2,
                          CHARINDEX(';', ShapeAttributes+';', CHARINDEX('x=', ShapeAttributes)+2)
                          - (CHARINDEX('x=', ShapeAttributes)+2))
                     ELSE '' END AS XText,
                CASE WHEN CHARINDEX('y=', ShapeAttributes)>0
                     THEN SUBSTRING(ShapeAttributes, CHARINDEX('y=', ShapeAttributes)+2,
                          CHARINDEX(';', ShapeAttributes+';', CHARINDEX('y=', ShapeAttributes)+2)
                          - (CHARINDEX('y=', ShapeAttributes)+2))
                     ELSE '' END AS YText
            FROM MarkerSource
            WHERE RowNo=1
        )
        UPDATE P
           SET P.MapX=CASE WHEN ISNUMERIC(Parsed.XText)=1
                           THEN CASE WHEN CONVERT(FLOAT, Parsed.XText)<0 THEN 0
                                     WHEN CONVERT(FLOAT, Parsed.XText)>100 THEN 100
                                     ELSE CONVERT(DECIMAL(9,4), Parsed.XText) END
                           ELSE NULL END,
               P.MapY=CASE WHEN ISNUMERIC(Parsed.YText)=1
                           THEN CASE WHEN CONVERT(FLOAT, Parsed.YText)<0 THEN 0
                                     WHEN CONVERT(FLOAT, Parsed.YText)>100 THEN 100
                                     ELSE CONVERT(DECIMAL(9,4), Parsed.YText) END
                           ELSE NULL END
        FROM dbo.PIP_M_InspectionPoint P
        INNER JOIN Parsed ON Parsed.InspectionPointID=P.InspectionPointID
                         AND Parsed.MapID=P.MapID;
    END;

    EXEC sys.sp_addextendedproperty
         @name=N'PIP_InspectionPointCoordinateMigration',
         @value=N'Completed',
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

/* Review migrated values before optionally dropping the legacy table. */
SELECT InspectionPointID, MapID, PointCode, PointName, MapX, MapY
FROM dbo.PIP_M_InspectionPoint
ORDER BY MapID, DisplayOrder, PointCode;
GO

/* After verifying the migrated data and application behavior, the legacy table
   may be dropped manually:
   DROP TABLE dbo.PIP_M_InspectionMapElement;
*/

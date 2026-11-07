/*
    Inspection Point coordinate consolidation
    Target: SQL Server 2008
    Run once before deploying the updated inspectionmaster.aspx page.

    Coordinates are stored as percentages (0..100) relative to the PDF page.
    The legacy map-element table is retained as a rollback copy; the updated
    application no longer reads from or writes to it.
*/
IF COL_LENGTH('dbo.PIP_M_InspectionPoint', 'MapX') IS NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint ADD MapX DECIMAL(9,4) NULL;
GO

IF COL_LENGTH('dbo.PIP_M_InspectionPoint', 'MapY') IS NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint ADD MapY DECIMAL(9,4) NULL;
GO

/* Migrate the latest active marker for each Inspection Point. */
IF OBJECT_ID('dbo.PIP_M_InspectionMapElement', 'U') IS NOT NULL
BEGIN
    ;WITH MarkerSource AS
    (
        SELECT E.InspectionPointID, E.MapID, E.ShapeAttributes,
               ROW_NUMBER() OVER
               (PARTITION BY E.InspectionPointID ORDER BY E.UpdateDate DESC, E.MapElementID DESC) AS RowNo
        FROM dbo.PIP_M_InspectionMapElement E
        WHERE E.IsActive=1 AND E.IsDeleted=0
    ),
    Parsed AS
    (
        SELECT InspectionPointID, MapID,
            CASE WHEN CHARINDEX('x=', ShapeAttributes)>0
                 THEN SUBSTRING(ShapeAttributes, CHARINDEX('x=', ShapeAttributes)+2,
                      CASE WHEN CHARINDEX(';', ShapeAttributes+';', CHARINDEX('x=', ShapeAttributes)+2)>0
                           THEN CHARINDEX(';', ShapeAttributes+';', CHARINDEX('x=', ShapeAttributes)+2)
                                - (CHARINDEX('x=', ShapeAttributes)+2)
                           ELSE 0 END)
                 ELSE '' END AS XText,
            CASE WHEN CHARINDEX('y=', ShapeAttributes)>0
                 THEN SUBSTRING(ShapeAttributes, CHARINDEX('y=', ShapeAttributes)+2,
                      CASE WHEN CHARINDEX(';', ShapeAttributes+';', CHARINDEX('y=', ShapeAttributes)+2)>0
                           THEN CHARINDEX(';', ShapeAttributes+';', CHARINDEX('y=', ShapeAttributes)+2)
                                - (CHARINDEX('y=', ShapeAttributes)+2)
                           ELSE 0 END)
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
GO

/* Review migrated values before optionally dropping the legacy table. */
SELECT InspectionPointID, MapID, PointCode, PointName, MapX, MapY
FROM dbo.PIP_M_InspectionPoint
ORDER BY MapID, DisplayOrder, PointCode;
GO

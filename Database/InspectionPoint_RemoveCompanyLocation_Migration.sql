/*
    Migration: remove CompanyID and LocationID from PIP_M_InspectionPoint
    Scope is inherited through PIP_M_InspectionPoint.MapID
      -> PIP_M_InspectionMap.CompanyID / LocationID.

    Review the dependency report first. Stored procedures using dynamic SQL may
    not appear in sys.sql_expression_dependencies and must be inspected separately.
    Run during a maintenance window after deploying the matching application code.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('dbo.PIP_M_InspectionPoint', 'U') IS NULL
BEGIN
    RAISERROR('dbo.PIP_M_InspectionPoint does not exist.', 16, 1);
    RETURN;
END;
GO

/* Report database modules with recorded dependencies on the two legacy columns. */
SELECT
    OBJECT_SCHEMA_NAME(SED.referencing_id) AS ReferencingSchema,
    OBJECT_NAME(SED.referencing_id) AS ReferencingObject,
    O.type_desc AS ReferencingType,
    COL_NAME(SED.referenced_id, SED.referenced_minor_id) AS ReferencedColumn
FROM sys.sql_expression_dependencies SED
INNER JOIN sys.objects O ON O.object_id = SED.referencing_id
WHERE SED.referenced_id = OBJECT_ID('dbo.PIP_M_InspectionPoint')
  AND SED.referenced_minor_id IN
      (
          SELECT column_id
          FROM sys.columns
          WHERE object_id = OBJECT_ID('dbo.PIP_M_InspectionPoint')
            AND name IN ('CompanyID', 'LocationID')
      )
ORDER BY ReferencingSchema, ReferencingObject, ReferencedColumn;
GO

BEGIN TRANSACTION;

/* Stop rather than break a stored procedure, view, function, or trigger. */
IF EXISTS
(
    SELECT 1
    FROM sys.sql_expression_dependencies SED
    INNER JOIN sys.objects O ON O.object_id = SED.referencing_id
    WHERE SED.referenced_id = OBJECT_ID('dbo.PIP_M_InspectionPoint')
      AND SED.referenced_minor_id IN
          (
              SELECT column_id
              FROM sys.columns
              WHERE object_id = OBJECT_ID('dbo.PIP_M_InspectionPoint')
                AND name IN ('CompanyID', 'LocationID')
          )
)
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Migration cancelled: database modules still reference PIP_M_InspectionPoint.CompanyID/LocationID. Update those modules first.', 16, 1);
    RETURN;
END;

/* Check that the new map-scoped unique key can be created. */
IF EXISTS
(
    SELECT MapID, PointCode
    FROM dbo.PIP_M_InspectionPoint
    WHERE MapID IS NOT NULL
    GROUP BY MapID, PointCode
    HAVING COUNT(1) > 1
)
BEGIN
    SELECT MapID, PointCode, COUNT(1) AS DuplicateCount
    FROM dbo.PIP_M_InspectionPoint
    WHERE MapID IS NOT NULL
    GROUP BY MapID, PointCode
    HAVING COUNT(1) > 1;

    ROLLBACK TRANSACTION;
    RAISERROR('Migration cancelled: duplicate PointCode values exist inside the same MapID.', 16, 1);
    RETURN;
END;

/* Drop legacy constraints/indexes that include the columns being removed. */
IF EXISTS
(
    SELECT 1 FROM sys.key_constraints
    WHERE parent_object_id = OBJECT_ID('dbo.PIP_M_InspectionPoint')
      AND name = 'UQ_PIP_M_InspectionPoint_Code'
)
    ALTER TABLE dbo.PIP_M_InspectionPoint
        DROP CONSTRAINT UQ_PIP_M_InspectionPoint_Code;

IF EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_M_InspectionPoint')
      AND name = 'IX_PIP_M_InspectionPoint_Scope'
)
    DROP INDEX IX_PIP_M_InspectionPoint_Scope
        ON dbo.PIP_M_InspectionPoint;

IF EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_M_InspectionPoint')
      AND name = 'IX_PIP_M_InspectionPoint_MapCoordinate'
)
    DROP INDEX IX_PIP_M_InspectionPoint_MapCoordinate
        ON dbo.PIP_M_InspectionPoint;

/* Remove the redundant tenant scope from the point master. */
IF COL_LENGTH('dbo.PIP_M_InspectionPoint', 'CompanyID') IS NOT NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint DROP COLUMN CompanyID;

IF COL_LENGTH('dbo.PIP_M_InspectionPoint', 'LocationID') IS NOT NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint DROP COLUMN LocationID;

/* A point code is unique per map; NULL MapID rows remain outside this key. */
IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_M_InspectionPoint')
      AND name = 'UX_PIP_M_InspectionPoint_Map_PointCode'
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_PIP_M_InspectionPoint_Map_PointCode
        ON dbo.PIP_M_InspectionPoint (MapID, PointCode)
        WHERE MapID IS NOT NULL;
END;

/* Coordinate lookup is scoped by MapID, not CompanyID/LocationID. */
IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_M_InspectionPoint')
      AND name = 'IX_PIP_M_InspectionPoint_MapCoordinate'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_M_InspectionPoint_MapCoordinate
        ON dbo.PIP_M_InspectionPoint (MapID, MapX, MapY);
END;

COMMIT TRANSACTION;
GO

/* Final verification */
SELECT c.name AS RemainingLegacyColumn
FROM sys.columns c
WHERE c.object_id = OBJECT_ID('dbo.PIP_M_InspectionPoint')
  AND c.name IN ('CompanyID', 'LocationID');

SELECT name, type_desc
FROM sys.indexes
WHERE object_id = OBJECT_ID('dbo.PIP_M_InspectionPoint')
ORDER BY name;
GO

/*
    Dynamic Motor point schema migration.
    Point mode is defined once on PIP_M_InspectionType.InspectionPointMode.
    On the transaction point table:
      InspectionPointID IS NOT NULL => snapshot of a master MAP point.
      InspectionPointID IS NULL     => dynamic point (e.g. Motor / Nopol).
    No PointSource column is stored.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF COL_LENGTH('dbo.PIP_T_InspectionPoint','PointCode') IS NULL
    ALTER TABLE dbo.PIP_T_InspectionPoint ADD PointCode VARCHAR(100) NULL;

IF COL_LENGTH('dbo.PIP_T_InspectionPoint','PointName') IS NULL
    ALTER TABLE dbo.PIP_T_InspectionPoint ADD PointName VARCHAR(200) NULL;

UPDATE T
SET T.PointCode=ISNULL(NULLIF(T.PointCode,''),M.PointCode),
    T.PointName=ISNULL(NULLIF(T.PointName,''),M.PointName)
FROM dbo.PIP_T_InspectionPoint T
LEFT JOIN dbo.PIP_M_InspectionPoint M ON M.InspectionPointID=T.InspectionPointID;

IF EXISTS
(
    SELECT 1 FROM dbo.PIP_T_InspectionPoint
    WHERE PointCode IS NULL OR LTRIM(RTRIM(PointCode))=''
       OR PointName IS NULL OR LTRIM(RTRIM(PointName))=''
)
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Cannot backfill PointCode/PointName for every inspection point snapshot. Resolve missing point data before rerunning.',16,1);
    RETURN;
END;

IF EXISTS
(
    SELECT 1 FROM dbo.PIP_T_InspectionPoint
    GROUP BY InspectionID,PointCode
    HAVING COUNT(1)>1
)
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Duplicate PointCode exists within an Inspection. Resolve duplicates before creating the unique point-code index.',16,1);
    RETURN;
END;

/* Dynamic points have no master ID. Remove the old PointSource-based
   constraints, default, and filtered index before dropping that column. */
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='FK_PIP_T_InspectionPoint_Master')
    ALTER TABLE dbo.PIP_T_InspectionPoint DROP CONSTRAINT FK_PIP_T_InspectionPoint_Master;

IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name='UQ_PIP_T_InspectionPoint_Master')
    ALTER TABLE dbo.PIP_T_InspectionPoint DROP CONSTRAINT UQ_PIP_T_InspectionPoint_Master;

IF EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_T_InspectionPoint')
      AND name='CK_PIP_T_InspectionPoint_Source'
)
    ALTER TABLE dbo.PIP_T_InspectionPoint DROP CONSTRAINT CK_PIP_T_InspectionPoint_Source;

IF EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id=OBJECT_ID('dbo.PIP_T_InspectionPoint')
      AND name='UX_PIP_T_InspectionPoint_Master'
)
    DROP INDEX UX_PIP_T_InspectionPoint_Master ON dbo.PIP_T_InspectionPoint;

/* Drop any additional legacy checks / indexes that include PointSource. */
DECLARE @PointSourceCheck SYSNAME, @DropPointSourceCheckSql NVARCHAR(1000);
DECLARE PointSourceChecks CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_T_InspectionPoint')
      AND definition LIKE '%PointSource%';
OPEN PointSourceChecks;
FETCH NEXT FROM PointSourceChecks INTO @PointSourceCheck;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @DropPointSourceCheckSql=N'ALTER TABLE dbo.PIP_T_InspectionPoint DROP CONSTRAINT '+QUOTENAME(@PointSourceCheck)+N';';
    EXEC sp_executesql @DropPointSourceCheckSql;
    FETCH NEXT FROM PointSourceChecks INTO @PointSourceCheck;
END;
CLOSE PointSourceChecks;
DEALLOCATE PointSourceChecks;

DECLARE @PointSourceIndex SYSNAME, @DropPointSourceIndexSql NVARCHAR(1000);
DECLARE PointSourceIndexes CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT I.name
    FROM sys.indexes I
    JOIN sys.index_columns IC ON IC.object_id=I.object_id AND IC.index_id=I.index_id
    JOIN sys.columns C ON C.object_id=IC.object_id AND C.column_id=IC.column_id
    WHERE I.object_id=OBJECT_ID('dbo.PIP_T_InspectionPoint')
      AND I.is_primary_key=0 AND I.is_unique_constraint=0
      AND C.name='PointSource';
OPEN PointSourceIndexes;
FETCH NEXT FROM PointSourceIndexes INTO @PointSourceIndex;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @DropPointSourceIndexSql=N'DROP INDEX '+QUOTENAME(@PointSourceIndex)+N' ON dbo.PIP_T_InspectionPoint;';
    EXEC sp_executesql @DropPointSourceIndexSql;
    FETCH NEXT FROM PointSourceIndexes INTO @PointSourceIndex;
END;
CLOSE PointSourceIndexes;
DEALLOCATE PointSourceIndexes;

DECLARE @PointSourceDefault SYSNAME, @DropDefaultSql NVARCHAR(1000);
SELECT @PointSourceDefault=DC.name
FROM sys.default_constraints DC
JOIN sys.columns C ON C.object_id=DC.parent_object_id AND C.column_id=DC.parent_column_id
WHERE DC.parent_object_id=OBJECT_ID('dbo.PIP_T_InspectionPoint')
  AND C.name='PointSource';

IF @PointSourceDefault IS NOT NULL
BEGIN
    SET @DropDefaultSql=N'ALTER TABLE dbo.PIP_T_InspectionPoint DROP CONSTRAINT '+QUOTENAME(@PointSourceDefault)+N';';
    EXEC sp_executesql @DropDefaultSql;
END;

IF COL_LENGTH('dbo.PIP_T_InspectionPoint','PointSource') IS NOT NULL
    ALTER TABLE dbo.PIP_T_InspectionPoint DROP COLUMN PointSource;

ALTER TABLE dbo.PIP_T_InspectionPoint ALTER COLUMN InspectionPointID BIGINT NULL;
ALTER TABLE dbo.PIP_T_InspectionPoint ALTER COLUMN PointCode VARCHAR(100) NOT NULL;
ALTER TABLE dbo.PIP_T_InspectionPoint ALTER COLUMN PointName VARCHAR(200) NOT NULL;

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_T_InspectionPoint')
      AND name='CK_PIP_T_InspectionPoint_Code'
)
    ALTER TABLE dbo.PIP_T_InspectionPoint WITH CHECK
        ADD CONSTRAINT CK_PIP_T_InspectionPoint_Code
        CHECK (LEN(LTRIM(RTRIM(PointCode)))>0 AND LEN(LTRIM(RTRIM(PointName)))>0);

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id=OBJECT_ID('dbo.PIP_T_InspectionPoint')
      AND name='UX_PIP_T_InspectionPoint_Master'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_PIP_T_InspectionPoint_Master
        ON dbo.PIP_T_InspectionPoint(InspectionID,InspectionPointID)
        WHERE InspectionPointID IS NOT NULL;

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id=OBJECT_ID('dbo.PIP_T_InspectionPoint')
      AND name='UX_PIP_T_InspectionPoint_Code'
)
    CREATE UNIQUE NONCLUSTERED INDEX UX_PIP_T_InspectionPoint_Code
        ON dbo.PIP_T_InspectionPoint(InspectionID,PointCode);

COMMIT TRANSACTION;
GO

/*
    Move Inspection Type ownership from Inspection Point to Inspection Map.
    Target: SQL Server 2008.
    The INSPEC database is still empty, so this migration intentionally refuses
    to run if Inspection Points already exist.
*/
SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF EXISTS (SELECT 1 FROM dbo.PIP_M_InspectionPoint)
BEGIN
    RAISERROR('Migration dibatalkan: PIP_M_InspectionPoint masih berisi data.',16,1);
    ROLLBACK TRANSACTION;
    RETURN;
END;

DECLARE @TypeColumnType NVARCHAR(300);
DECLARE @DetailColumnType NVARCHAR(300);
DECLARE @sql NVARCHAR(MAX);

SELECT @TypeColumnType =
    CASE WHEN T.name IN ('varchar','char','varbinary','binary')
         THEN T.name + '(' + CASE WHEN C.max_length=-1 THEN 'MAX' ELSE CONVERT(VARCHAR(10),C.max_length) END + ')'
         WHEN T.name IN ('nvarchar','nchar')
         THEN T.name + '(' + CASE WHEN C.max_length=-1 THEN 'MAX' ELSE CONVERT(VARCHAR(10),C.max_length/2) END + ')'
         WHEN T.name IN ('decimal','numeric')
         THEN T.name + '(' + CONVERT(VARCHAR(10),C.precision) + ',' + CONVERT(VARCHAR(10),C.scale) + ')'
         ELSE T.name END
FROM sys.columns C
INNER JOIN sys.types T ON T.user_type_id=C.user_type_id
WHERE C.object_id=OBJECT_ID('dbo.PIP_M_InspectionPoint')
  AND C.name='InspectionTypeCode';

SELECT @DetailColumnType =
    CASE WHEN T.name IN ('varchar','char','varbinary','binary')
         THEN T.name + '(' + CASE WHEN C.max_length=-1 THEN 'MAX' ELSE CONVERT(VARCHAR(10),C.max_length) END + ')'
         WHEN T.name IN ('nvarchar','nchar')
         THEN T.name + '(' + CASE WHEN C.max_length=-1 THEN 'MAX' ELSE CONVERT(VARCHAR(10),C.max_length/2) END + ')'
         WHEN T.name IN ('decimal','numeric')
         THEN T.name + '(' + CONVERT(VARCHAR(10),C.precision) + ',' + CONVERT(VARCHAR(10),C.scale) + ')'
         ELSE T.name END
FROM sys.columns C
INNER JOIN sys.types T ON T.user_type_id=C.user_type_id
WHERE C.object_id=OBJECT_ID('dbo.PIP_M_InspectionPoint')
  AND C.name='InspectionTypeDetailCode';

IF @TypeColumnType IS NULL OR @DetailColumnType IS NULL
BEGIN
    RAISERROR('Kolom sumber InspectionTypeCode/InspectionTypeDetailCode tidak ditemukan pada PIP_M_InspectionPoint.',16,1);
    ROLLBACK TRANSACTION;
    RETURN;
END;

IF COL_LENGTH('dbo.PIP_M_InspectionMap','InspectionTypeCode') IS NULL
BEGIN
    SET @sql='ALTER TABLE dbo.PIP_M_InspectionMap ADD InspectionTypeCode ' + @TypeColumnType + ' NULL;';
    EXEC sp_executesql @sql;
END;

IF COL_LENGTH('dbo.PIP_M_InspectionMap','InspectionTypeDetailCode') IS NULL
BEGIN
    SET @sql='ALTER TABLE dbo.PIP_M_InspectionMap ADD InspectionTypeDetailCode ' + @DetailColumnType + ' NULL;';
    EXEC sp_executesql @sql;
END;

/* Remove defaults attached to the two point-level columns, if any. */
DECLARE @DropDefaults NVARCHAR(MAX);
SET @DropDefaults=N'';
SELECT @DropDefaults=@DropDefaults +
    N'ALTER TABLE dbo.PIP_M_InspectionPoint DROP CONSTRAINT ' + QUOTENAME(DC.name) + N';'
FROM sys.default_constraints DC
INNER JOIN sys.columns C ON C.object_id=DC.parent_object_id AND C.column_id=DC.parent_column_id
WHERE DC.parent_object_id=OBJECT_ID('dbo.PIP_M_InspectionPoint')
  AND C.name IN ('InspectionTypeCode','InspectionTypeDetailCode');
IF @DropDefaults<>N'' EXEC sp_executesql @DropDefaults;

/* Remove foreign keys that depend on either point-level column. */
DECLARE @DropForeignKeys NVARCHAR(MAX);
SET @DropForeignKeys=N'';
SELECT @DropForeignKeys=@DropForeignKeys +
    N'ALTER TABLE dbo.PIP_M_InspectionPoint DROP CONSTRAINT ' + QUOTENAME(FK.name) + N';'
FROM sys.foreign_keys FK
INNER JOIN sys.foreign_key_columns FKC ON FKC.constraint_object_id=FK.object_id
INNER JOIN sys.columns C ON C.object_id=FKC.parent_object_id AND C.column_id=FKC.parent_column_id
WHERE FKC.parent_object_id=OBJECT_ID('dbo.PIP_M_InspectionPoint')
  AND C.name IN ('InspectionTypeCode','InspectionTypeDetailCode');
IF @DropForeignKeys<>N'' EXEC sp_executesql @DropForeignKeys;

/* Remove unique constraints that depend on either point-level column. */
DECLARE @DropUniqueConstraints NVARCHAR(MAX);
SET @DropUniqueConstraints=N'';
SELECT @DropUniqueConstraints=@DropUniqueConstraints +
    N'ALTER TABLE dbo.PIP_M_InspectionPoint DROP CONSTRAINT ' + QUOTENAME(IX.name) + N';'
FROM sys.indexes IX
WHERE IX.object_id=OBJECT_ID('dbo.PIP_M_InspectionPoint')
  AND IX.is_unique_constraint=1
  AND EXISTS
  (
      SELECT 1 FROM sys.index_columns IC
      INNER JOIN sys.columns C ON C.object_id=IC.object_id AND C.column_id=IC.column_id
      WHERE IC.object_id=IX.object_id AND IC.index_id=IX.index_id
        AND C.name IN ('InspectionTypeCode','InspectionTypeDetailCode')
  );
IF @DropUniqueConstraints<>N'' EXEC sp_executesql @DropUniqueConstraints;

/* Remove ordinary indexes once each, even if both columns occur in one index. */
DECLARE @IndexName SYSNAME;
DECLARE IndexCursor CURSOR LOCAL FAST_FORWARD FOR
SELECT DISTINCT IX.name
FROM sys.indexes IX
WHERE IX.object_id=OBJECT_ID('dbo.PIP_M_InspectionPoint')
  AND IX.type>0 AND IX.is_primary_key=0 AND IX.is_unique_constraint=0
  AND EXISTS
  (
      SELECT 1 FROM sys.index_columns IC
      INNER JOIN sys.columns C ON C.object_id=IC.object_id AND C.column_id=IC.column_id
      WHERE IC.object_id=IX.object_id AND IC.index_id=IX.index_id
        AND C.name IN ('InspectionTypeCode','InspectionTypeDetailCode')
  );
OPEN IndexCursor;
FETCH NEXT FROM IndexCursor INTO @IndexName;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @sql=N'DROP INDEX ' + QUOTENAME(@IndexName) + N' ON dbo.PIP_M_InspectionPoint;';
    EXEC sp_executesql @sql;
    FETCH NEXT FROM IndexCursor INTO @IndexName;
END;
CLOSE IndexCursor;
DEALLOCATE IndexCursor;

/* The point table no longer owns Type and Detail. */
IF COL_LENGTH('dbo.PIP_M_InspectionPoint','InspectionTypeCode') IS NOT NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint DROP COLUMN InspectionTypeCode;
IF COL_LENGTH('dbo.PIP_M_InspectionPoint','InspectionTypeDetailCode') IS NOT NULL
    ALTER TABLE dbo.PIP_M_InspectionPoint DROP COLUMN InspectionTypeDetailCode;

COMMIT TRANSACTION;
GO

/* New maps must be configured with a valid Type + Detail in the application.
   Once every existing map has been configured, these two columns can be made NOT NULL. */

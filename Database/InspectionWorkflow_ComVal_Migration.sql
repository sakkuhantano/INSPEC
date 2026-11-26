/*
    INSPEC consolidated Inspection mode migration.
    SQL Server 2008 compatible and restartable.

    Active master fields:
      InspectionMode       : STANDARD / BATCH
      InspectionPointMode  : NULL (STANDARD) / MAP / DYNAMIC (BATCH)
      ScheduleSelectionMode: PARAM / INSPECT

    Workflow routing is NOT stored on PIP_M_InspectionType.
    Approval stages are resolved from SysWebCommonValue (Company + Location)
    and the Section ProfitCenter. Legacy PointSource / ApprovalWorkflowCode
    columns are intentionally not read by the application; this migration
    retains them temporarily for compatibility with any un-audited external
    database objects, but removes constraints that depend on them.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID('dbo.PIP_M_InspectionType','U') IS NULL
BEGIN
    RAISERROR('dbo.PIP_M_InspectionType is required before this migration.',16,1);
    RETURN;
END;
GO

IF COL_LENGTH('dbo.PIP_M_InspectionType','InspectionPointMode') IS NULL
    ALTER TABLE dbo.PIP_M_InspectionType ADD InspectionPointMode VARCHAR(10) NULL;
GO

/* Remove obsolete presentation/workflow CHECK constraints before normalizing. */
DECLARE @ConstraintName SYSNAME, @DropSql NVARCHAR(4000);
DECLARE ObsoleteInspectionTypeChecks CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_M_InspectionType')
      AND
      (
          definition LIKE '%PointSource%'
          OR definition LIKE '%ApprovalWorkflowCode%'
          OR name IN
             ('CK_PIP_M_InspectionType_ScheduleSelectionMode',
              'CK_PIP_M_InspectionType_PresentationCombination')
      );
OPEN ObsoleteInspectionTypeChecks;
FETCH NEXT FROM ObsoleteInspectionTypeChecks INTO @ConstraintName;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @DropSql=N'ALTER TABLE dbo.PIP_M_InspectionType DROP CONSTRAINT '+QUOTENAME(@ConstraintName)+N';';
    EXEC sp_executesql @DropSql;
    FETCH NEXT FROM ObsoleteInspectionTypeChecks INTO @ConstraintName;
END;
CLOSE ObsoleteInspectionTypeChecks;
DEALLOCATE ObsoleteInspectionTypeChecks;
GO

/* The old LIGHTNING mode is consolidated into BATCH + INSPECT. */
UPDATE dbo.PIP_M_InspectionType
SET InspectionMode='BATCH'
WHERE UPPER(LTRIM(RTRIM(ISNULL(InspectionMode,''))))='LIGHTNING';
GO

/* Normalize the former schedule selector value. */
UPDATE dbo.PIP_M_InspectionType
SET ScheduleSelectionMode='INSPECT'
WHERE UPPER(LTRIM(RTRIM(ISNULL(ScheduleSelectionMode,''))))='AT_INSPECTION';
GO

/* Backfill the single point-mode field from legacy fields when present.
   Existing valid InspectionPointMode values are preserved. */
DECLARE @PointModeSql NVARCHAR(MAX);
DECLARE @LegacyPointSource BIT, @LegacyLayout BIT;
SET @LegacyPointSource=CASE WHEN COL_LENGTH('dbo.PIP_M_InspectionType','PointSource') IS NULL THEN 0 ELSE 1 END;
SET @LegacyLayout=CASE WHEN COL_LENGTH('dbo.PIP_M_InspectionType','InspectionLayoutCode') IS NULL THEN 0 ELSE 1 END;

SET @PointModeSql=N'
UPDATE dbo.PIP_M_InspectionType
SET InspectionPointMode=
    CASE
      WHEN UPPER(LTRIM(RTRIM(ISNULL(InspectionMode,''STANDARD''))))=''STANDARD'' THEN NULL
      WHEN UPPER(LTRIM(RTRIM(ISNULL(InspectionPointMode,'''')))) IN (''MAP'',''DYNAMIC'')
        THEN UPPER(LTRIM(RTRIM(InspectionPointMode)))'
    + CASE WHEN @LegacyPointSource=1
           THEN N'
      WHEN UPPER(LTRIM(RTRIM(ISNULL(PointSource,''MASTER''))))=''DYNAMIC'' THEN ''DYNAMIC'''
           ELSE N'' END
    + CASE WHEN @LegacyLayout=1
           THEN N'
      WHEN UPPER(LTRIM(RTRIM(ISNULL(InspectionLayoutCode,'''')))) IN (''DYNAMIC'',''DYNAMIC_LIST'') THEN ''DYNAMIC'''
           ELSE N'' END
    + N'
      ELSE ''MAP''
    END;';
EXEC sp_executesql @PointModeSql;
GO

/* Standard inspections have no point mode. BATCH/INSPECT is always map-based;
   BATCH/PARAM may use MAP (Car Park) or DYNAMIC (Motor). */
UPDATE dbo.PIP_M_InspectionType
SET InspectionPointMode=NULL
WHERE UPPER(LTRIM(RTRIM(ISNULL(InspectionMode,'STANDARD'))))='STANDARD';

UPDATE dbo.PIP_M_InspectionType
SET InspectionPointMode='MAP'
WHERE UPPER(LTRIM(RTRIM(ISNULL(InspectionMode,''))))='BATCH'
  AND UPPER(LTRIM(RTRIM(ISNULL(ScheduleSelectionMode,'PARAM'))))='INSPECT'
  AND ISNULL(InspectionPointMode,'')<>'MAP';
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_M_InspectionType')
      AND name='CK_PIP_M_InspectionType_InspectionPointMode'
)
    ALTER TABLE dbo.PIP_M_InspectionType WITH CHECK
        ADD CONSTRAINT CK_PIP_M_InspectionType_InspectionPointMode
        CHECK (InspectionPointMode IS NULL OR InspectionPointMode IN ('MAP','DYNAMIC'));
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_M_InspectionType')
      AND name='CK_PIP_M_InspectionType_ScheduleSelectionMode'
)
    ALTER TABLE dbo.PIP_M_InspectionType WITH CHECK
        ADD CONSTRAINT CK_PIP_M_InspectionType_ScheduleSelectionMode
        CHECK (ScheduleSelectionMode IN ('PARAM','INSPECT'));
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_M_InspectionType')
      AND name='CK_PIP_M_InspectionType_ModePointSchedule'
)
    ALTER TABLE dbo.PIP_M_InspectionType WITH CHECK
        ADD CONSTRAINT CK_PIP_M_InspectionType_ModePointSchedule
        CHECK
        (
            (InspectionMode='STANDARD'
             AND InspectionPointMode IS NULL
             AND ScheduleSelectionMode='PARAM')
            OR
            (InspectionMode='BATCH'
             AND InspectionPointMode='MAP'
             AND ScheduleSelectionMode IN ('PARAM','INSPECT'))
            OR
            (InspectionMode='BATCH'
             AND InspectionPointMode='DYNAMIC'
             AND ScheduleSelectionMode='PARAM')
        );
GO

/* No ApprovalWorkflowCode / PointSource values are written or seeded here.
   Per-company workflow COMVALs are configured in Inspection Email & Approval
   Routing and are never overwritten by this schema migration. */

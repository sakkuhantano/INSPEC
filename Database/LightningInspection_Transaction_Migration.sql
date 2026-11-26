/*
    INSPEC - Lightning daily inspection transaction foundation
    SQL Server 2008 compatible; additive and safe to re-run.

    One PIP_T_Inspection header represents ONE daily Lightning submission.
    ScheduleTime values come from PIP_M_InspectionTypeDetail and are assigned
    directly to each PIP_T_InspectionPoint transaction row. No schedule child
    table is required.

    Existing STANDARD and BATCH rows keep ScheduleTime=''. Their existing
    one-point-per-inspection uniqueness is preserved by the composite unique
    key because the empty schedule remains one shared partition.

    IMPORTANT:
    - This script does not alter the legacy T_LightingInspection tables/pages.
    - It does not implement the sync/approval endpoints by itself.
    - Run only after inspection_batch_transaction_migration.sql.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/*
    Normalize Lightning to the canonical BATCH + INSPECT mode in both the inspection
    type master and transaction header. Lightning remains a workflow/entity type,
    not a separate InspectionMode value.
*/
IF COL_LENGTH('dbo.PIP_M_InspectionType','InspectionMode') IS NULL
    ALTER TABLE dbo.PIP_M_InspectionType ADD InspectionMode VARCHAR(10) NOT NULL
        CONSTRAINT DF_PIP_M_InspectionType_InspectionMode DEFAULT ('STANDARD');
GO
IF EXISTS (SELECT 1 FROM sys.check_constraints
           WHERE parent_object_id=OBJECT_ID('dbo.PIP_M_InspectionType')
             AND name='CK_PIP_M_InspectionType_InspectionMode')
    ALTER TABLE dbo.PIP_M_InspectionType DROP CONSTRAINT CK_PIP_M_InspectionType_InspectionMode;
GO
ALTER TABLE dbo.PIP_M_InspectionType
    ADD CONSTRAINT CK_PIP_M_InspectionType_InspectionMode
    CHECK (InspectionMode IN ('STANDARD','BATCH'));
GO

IF COL_LENGTH('dbo.PIP_T_Inspection','InspectionMode') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD InspectionMode VARCHAR(10) NOT NULL
        CONSTRAINT DF_PIP_T_Inspection_InspectionMode DEFAULT ('STANDARD');
GO
IF EXISTS (SELECT 1 FROM sys.check_constraints
           WHERE parent_object_id=OBJECT_ID('dbo.PIP_T_Inspection')
             AND name='CK_PIP_T_Inspection_InspectionMode')
    ALTER TABLE dbo.PIP_T_Inspection DROP CONSTRAINT CK_PIP_T_Inspection_InspectionMode;
GO
/* Old daily Lightning / MAP header values are normalized to BATCH. */
UPDATE dbo.PIP_T_Inspection
SET InspectionMode='BATCH'
WHERE UPPER(LTRIM(RTRIM(ISNULL(InspectionMode,'')))) IN ('LIGHTNING','MAP');
GO
ALTER TABLE dbo.PIP_T_Inspection
    ADD CONSTRAINT CK_PIP_T_Inspection_InspectionMode
    CHECK (InspectionMode IN ('STANDARD','BATCH'));
GO

IF COL_LENGTH('dbo.PIP_T_InspectionPoint','ScheduleTime') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_T_InspectionPoint
        ADD ScheduleTime VARCHAR(5) NOT NULL
            CONSTRAINT DF_PIP_T_InspectionPoint_ScheduleTime DEFAULT ('');
END;
GO

/*
    A physical master point may be inspected once in EACH schedule during the
    same Lightning day. For STANDARD/BATCH, ScheduleTime remains empty, so the
    old uniqueness rule is retained for those transactions.
*/
IF EXISTS
(
    SELECT 1 FROM sys.key_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_T_InspectionPoint')
      AND name='UQ_PIP_T_InspectionPoint_Master'
)
    ALTER TABLE dbo.PIP_T_InspectionPoint
        DROP CONSTRAINT UQ_PIP_T_InspectionPoint_Master;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.key_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_T_InspectionPoint')
      AND name='UQ_PIP_T_InspectionPoint_Schedule_Master'
)
BEGIN
    ALTER TABLE dbo.PIP_T_InspectionPoint
        ADD CONSTRAINT UQ_PIP_T_InspectionPoint_Schedule_Master
        UNIQUE (InspectionID, ScheduleTime, InspectionPointID);
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id=OBJECT_ID('dbo.PIP_T_InspectionPoint')
      AND name='IX_PIP_T_InspectionPoint_Schedule'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_T_InspectionPoint_Schedule
        ON dbo.PIP_T_InspectionPoint(InspectionID,ScheduleTime,Status,InspectionPointID);
END;
GO

/* Separate VOID reasons for the three Lightning approval stages.
   ReasonVoid remains the SPV reason; the new fields are additive and do not
   change STANDARD/BATCH workflow consumers. */
IF COL_LENGTH('dbo.PIP_T_Inspection','ReasonVoid1') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD ReasonVoid1 VARCHAR(500) NULL;
GO
IF COL_LENGTH('dbo.PIP_T_Inspection','ReasonVoid2') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD ReasonVoid2 VARCHAR(500) NULL;
GO

/* The daily header and point ScheduleTime values are the only transaction schedule storage. */
IF OBJECT_ID('dbo.PIP_T_InspectionLightningSchedule','U') IS NOT NULL
    DROP TABLE dbo.PIP_T_InspectionLightningSchedule;
GO

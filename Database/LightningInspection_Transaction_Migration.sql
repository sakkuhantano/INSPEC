/*
    INSPEC - Lightning daily inspection transaction foundation
    SQL Server 2008 compatible; additive and safe to re-run.

    One PIP_T_Inspection header represents ONE daily Lightning submission.
    PIP_T_InspectionLightningSchedule stores every ScheduleTime belonging to
    the selected InspectionTypeDetailCode. PIP_T_InspectionPoint.ScheduleTime
    assigns each point transaction to exactly one schedule.

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
    Enable LIGHTNING as a first-class mode in both the inspection type master
    and the canonical transaction header. Preserve existing STANDARD/BATCH/MAP
    values; do not normalize existing data.
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
    CHECK (InspectionMode IN ('STANDARD','BATCH','LIGHTNING'));
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
ALTER TABLE dbo.PIP_T_Inspection
    ADD CONSTRAINT CK_PIP_T_Inspection_InspectionMode
    CHECK (InspectionMode IN ('STANDARD','BATCH','LIGHTNING','MAP'));
GO

IF OBJECT_ID('dbo.PIP_T_InspectionLightningSchedule','U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_T_InspectionLightningSchedule
    (
        InspectionID BIGINT NOT NULL,
        ScheduleTime VARCHAR(5) NOT NULL,
        ScheduleStatus VARCHAR(12) NOT NULL
            CONSTRAINT DF_PIP_T_InspectionLightningSchedule_Status DEFAULT ('DRAFT'),
        SubmittedDate DATETIME NULL,
        EntryUser VARCHAR(50) NOT NULL,
        EntryDate DATETIME NOT NULL
            CONSTRAINT DF_PIP_T_InspectionLightningSchedule_EntryDate DEFAULT (GETDATE()),
        UpdateUser VARCHAR(50) NOT NULL,
        UpdateDate DATETIME NOT NULL
            CONSTRAINT DF_PIP_T_InspectionLightningSchedule_UpdateDate DEFAULT (GETDATE()),
        CONSTRAINT PK_PIP_T_InspectionLightningSchedule
            PRIMARY KEY CLUSTERED (InspectionID, ScheduleTime),
        CONSTRAINT FK_PIP_T_InspectionLightningSchedule_Header
            FOREIGN KEY (InspectionID) REFERENCES dbo.PIP_T_Inspection(InspectionID),
        CONSTRAINT CK_PIP_T_InspectionLightningSchedule_Time CHECK
        (
            LEN(ScheduleTime)=5
            AND ScheduleTime LIKE '[0-2][0-9]:[0-5][0-9]'
            AND LEFT(ScheduleTime,2)<='23'
        ),
        CONSTRAINT CK_PIP_T_InspectionLightningSchedule_Status
            CHECK (ScheduleStatus IN ('DRAFT','SUBMITTED'))
    );
END;
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

/* One row per selected ScheduleTime is required before a Lightning submit. */
IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id=OBJECT_ID('dbo.PIP_T_InspectionLightningSchedule')
      AND name='IX_PIP_T_InspectionLightningSchedule_Status'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_T_InspectionLightningSchedule_Status
        ON dbo.PIP_T_InspectionLightningSchedule(InspectionID,ScheduleStatus,ScheduleTime);
END;
GO

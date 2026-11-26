/*
    Inspection presentation / point-source configuration.
    SQL Server 2008 compatible and safe to run more than once.

    InspectionMode remains the transaction behavior:
      STANDARD / BATCH / LIGHTNING

    These columns describe independent configuration dimensions:
      InspectionLayoutCode  = STANDARD / MAP / DYNAMIC_LIST
      PointSource           = MASTER / DYNAMIC
      ScheduleSelectionMode = PARAM / INSPECT
      ApprovalWorkflowCode  = STANDARD / SPV_CHIEF_ENG / LIGHTNING_4_STEP

    Defaults preserve existing inspections. Existing BATCH remains MAP + MASTER
    until an administrator explicitly configures a dynamic-list inspection.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;
DECLARE @PresentationConfigAdded BIT;
SET @PresentationConfigAdded = 0;

IF COL_LENGTH('dbo.PIP_M_InspectionType', 'InspectionLayoutCode') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_M_InspectionType
        ADD InspectionLayoutCode VARCHAR(20) NOT NULL
            CONSTRAINT DF_PIP_M_InspectionType_InspectionLayoutCode DEFAULT ('STANDARD');
    SET @PresentationConfigAdded = 1;
END;

IF COL_LENGTH('dbo.PIP_M_InspectionType', 'PointSource') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_M_InspectionType
        ADD PointSource VARCHAR(10) NOT NULL
            CONSTRAINT DF_PIP_M_InspectionType_PointSource DEFAULT ('MASTER');
    SET @PresentationConfigAdded = 1;
END;

IF COL_LENGTH('dbo.PIP_M_InspectionType', 'ScheduleSelectionMode') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_M_InspectionType
        ADD ScheduleSelectionMode VARCHAR(20) NOT NULL
            CONSTRAINT DF_PIP_M_InspectionType_ScheduleSelectionMode DEFAULT ('PARAM');
    SET @PresentationConfigAdded = 1;
END;

IF COL_LENGTH('dbo.PIP_M_InspectionType', 'ApprovalWorkflowCode') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_M_InspectionType
        ADD ApprovalWorkflowCode VARCHAR(30) NOT NULL
            CONSTRAINT DF_PIP_M_InspectionType_ApprovalWorkflowCode DEFAULT ('STANDARD');
    SET @PresentationConfigAdded = 1;
END;

/* Backfill existing behavior without changing any existing InspectionMode. */
IF @PresentationConfigAdded = 1
BEGIN
UPDATE dbo.PIP_M_InspectionType
SET
    InspectionLayoutCode = CASE
        WHEN UPPER(LTRIM(RTRIM(ISNULL(InspectionMode, 'STANDARD')))) = 'BATCH' THEN 'MAP'
        WHEN UPPER(LTRIM(RTRIM(ISNULL(InspectionMode, 'STANDARD')))) = 'LIGHTNING' THEN 'MAP'
        ELSE 'STANDARD'
    END,
    PointSource = 'MASTER',
    ScheduleSelectionMode = CASE
        WHEN UPPER(LTRIM(RTRIM(ISNULL(InspectionMode, 'STANDARD')))) = 'LIGHTNING' THEN 'INSPECT'
        ELSE 'PARAM'
    END,
    ApprovalWorkflowCode = CASE
        WHEN UPPER(LTRIM(RTRIM(ISNULL(InspectionMode, 'STANDARD')))) = 'LIGHTNING' THEN 'LIGHTNING_4_STEP'
        WHEN UPPER(LTRIM(RTRIM(ISNULL(InspectionMode, 'STANDARD')))) = 'BATCH' THEN 'SPV_CHIEF_ENG'
        ELSE 'STANDARD'
    END;
END;

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID('dbo.PIP_M_InspectionType')
      AND name = 'CK_PIP_M_InspectionType_InspectionLayoutCode'
)
    ALTER TABLE dbo.PIP_M_InspectionType WITH CHECK
        ADD CONSTRAINT CK_PIP_M_InspectionType_InspectionLayoutCode
        CHECK (InspectionLayoutCode IN ('STANDARD', 'MAP', 'DYNAMIC_LIST'));

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID('dbo.PIP_M_InspectionType')
      AND name = 'CK_PIP_M_InspectionType_PointSource'
)
    ALTER TABLE dbo.PIP_M_InspectionType WITH CHECK
        ADD CONSTRAINT CK_PIP_M_InspectionType_PointSource
        CHECK (PointSource IN ('MASTER', 'DYNAMIC'));

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID('dbo.PIP_M_InspectionType')
      AND name = 'CK_PIP_M_InspectionType_ScheduleSelectionMode'
)
    ALTER TABLE dbo.PIP_M_InspectionType WITH CHECK
        ADD CONSTRAINT CK_PIP_M_InspectionType_ScheduleSelectionMode
        CHECK (ScheduleSelectionMode IN ('PARAM', 'INSPECT'));

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID('dbo.PIP_M_InspectionType')
      AND name = 'CK_PIP_M_InspectionType_ApprovalWorkflowCode'
)
    ALTER TABLE dbo.PIP_M_InspectionType WITH CHECK
        ADD CONSTRAINT CK_PIP_M_InspectionType_ApprovalWorkflowCode
        CHECK (ApprovalWorkflowCode IN ('STANDARD', 'SPV_CHIEF_ENG', 'LIGHTNING_4_STEP'));

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID('dbo.PIP_M_InspectionType')
      AND name = 'CK_PIP_M_InspectionType_PresentationCombination'
)
    ALTER TABLE dbo.PIP_M_InspectionType WITH CHECK
        ADD CONSTRAINT CK_PIP_M_InspectionType_PresentationCombination
        CHECK (
            (InspectionMode = 'LIGHTNING'
             AND InspectionLayoutCode = 'MAP'
             AND PointSource = 'MASTER'
             AND ScheduleSelectionMode = 'INSPECT'
             AND ApprovalWorkflowCode = 'LIGHTNING_4_STEP')
            OR
            (InspectionMode = 'BATCH'
             AND InspectionLayoutCode = 'MAP'
             AND PointSource = 'MASTER'
             AND ScheduleSelectionMode = 'PARAM'
             AND ApprovalWorkflowCode IN ('STANDARD', 'SPV_CHIEF_ENG'))
            OR
            (InspectionMode = 'BATCH'
             AND InspectionLayoutCode = 'DYNAMIC_LIST'
             AND PointSource = 'DYNAMIC'
             AND ScheduleSelectionMode = 'PARAM'
             AND ApprovalWorkflowCode IN ('STANDARD', 'SPV_CHIEF_ENG'))
            OR
            (InspectionMode = 'STANDARD'
             AND InspectionLayoutCode = 'STANDARD'
             AND PointSource = 'MASTER'
             AND ScheduleSelectionMode = 'PARAM'
             AND ApprovalWorkflowCode = 'STANDARD')
        );

COMMIT TRANSACTION;

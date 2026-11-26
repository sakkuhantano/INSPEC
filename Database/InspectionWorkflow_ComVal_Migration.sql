/*
    INSPEC inspection point mode and approval workflow configuration.
    SQL Server 2008 compatible; safe to execute repeatedly.

    InspectionMode: STANDARD / BATCH
    InspectionPointMode: NULL (STANDARD) / MAP / DYNAMIC (BATCH)
    ScheduleSelectionMode: PARAM / AT_INSPECTION

    Approval route is read from SysWebCommonValue:
      ID=BATCH;AT_INSPECTION, Description=SPV;CHIEF_SEC;CHIEF_ENG
      ID=BATCH;PARAM,          Description=SPV;CHIEF

    Missing workflow ComVal deliberately falls back to SPV only.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

IF COL_LENGTH('dbo.PIP_M_InspectionType','InspectionPointMode') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_M_InspectionType
        ADD InspectionPointMode VARCHAR(10) NULL;
END;

/* Backfill the consolidated point mode from the former independent fields. */
UPDATE dbo.PIP_M_InspectionType
SET InspectionPointMode =
    CASE
        WHEN UPPER(LTRIM(RTRIM(ISNULL(InspectionMode,'STANDARD'))))='STANDARD' THEN NULL
        WHEN UPPER(LTRIM(RTRIM(ISNULL(PointSource,'MASTER'))))='DYNAMIC' THEN 'DYNAMIC'
        WHEN UPPER(LTRIM(RTRIM(ISNULL(InspectionLayoutCode,'MAP'))))='MAP' THEN 'MAP'
        ELSE 'MAP'
    END;

/* Lightning is a BATCH inspection; AT_INSPECTION distinguishes its daily scope. */
UPDATE dbo.PIP_M_InspectionType
SET InspectionMode='BATCH',
    InspectionPointMode='MAP',
    ScheduleSelectionMode='AT_INSPECTION'
WHERE UPPER(LTRIM(RTRIM(ISNULL(InspectionMode,''))))='LIGHTNING';

/* A Standard inspection has no point-mode setting. */
UPDATE dbo.PIP_M_InspectionType
SET InspectionPointMode=NULL
WHERE UPPER(LTRIM(RTRIM(ISNULL(InspectionMode,'STANDARD'))))='STANDARD';

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_M_InspectionType')
      AND name='CK_PIP_M_InspectionType_InspectionPointMode'
)
    ALTER TABLE dbo.PIP_M_InspectionType WITH CHECK
        ADD CONSTRAINT CK_PIP_M_InspectionType_InspectionPointMode
        CHECK (InspectionPointMode IS NULL OR InspectionPointMode IN ('MAP','DYNAMIC'));

IF OBJECT_ID('dbo.SysWebCommonValue','U') IS NULL
BEGIN
    RAISERROR('dbo.SysWebCommonValue is required to configure inspection approval workflows.',16,1);
    ROLLBACK TRANSACTION;
    RETURN;
END;

/* The workflow definition is global by InspectionMode + ScheduleSelectionMode.
   Preserve existing rows if already configured by an administrator. */
IF NOT EXISTS
(
    SELECT 1 FROM dbo.SysWebCommonValue
    WHERE AppID='INSPEC' AND CommonGroup='EmailApproval' AND ID='BATCH;AT_INSPECTION'
)
    INSERT dbo.SysWebCommonValue
        (AppID,ID,Description,CommonGroup,GroupDescription,IsDelete,IsSystem,EntryUser,EntryDate,UpdateUser,UpdateDate)
    VALUES
        ('INSPEC','BATCH;AT_INSPECTION','SPV;CHIEF_SEC;CHIEF_ENG','EmailApproval',
         'INSPEC Inspection Approval Workflow',0,1,'SYSTEM',GETDATE(),'SYSTEM',GETDATE());

IF NOT EXISTS
(
    SELECT 1 FROM dbo.SysWebCommonValue
    WHERE AppID='INSPEC' AND CommonGroup='EmailApproval' AND ID='BATCH;PARAM'
)
    INSERT dbo.SysWebCommonValue
        (AppID,ID,Description,CommonGroup,GroupDescription,IsDelete,IsSystem,EntryUser,EntryDate,UpdateUser,UpdateDate)
    VALUES
        ('INSPEC','BATCH;PARAM','SPV;CHIEF','EmailApproval',
         'INSPEC Inspection Approval Workflow',0,1,'SYSTEM',GETDATE(),'SYSTEM',GETDATE());

COMMIT TRANSACTION;
GO

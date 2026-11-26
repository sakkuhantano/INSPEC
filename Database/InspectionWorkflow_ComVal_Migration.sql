/*
    INSPEC inspection point mode and approval workflow configuration.
    SQL Server 2008 compatible; safe to execute repeatedly.

    InspectionMode: STANDARD / BATCH
    InspectionPointMode: NULL (STANDARD) / MAP / DYNAMIC (BATCH)
    ScheduleSelectionMode: PARAM / INSPECT

    Company + Location scoped workflow email ComVal:
      ID=<CompanyLocation>;STANDARD
      ID=<CompanyLocation>;BATCH;PARAM
      ID=<CompanyLocation>;BATCH;INSPECT

    Description format: [LEVEL][TRUE/FALSE], one token per approval stage.
    Missing workflow ComVal or token means email OFF; approval stages still
    follow InspectionMode and ScheduleSelectionMode.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

/* Drop legacy presentation checks before converting LIGHTNING / AT_INSPECTION
   records to the consolidated BATCH / INSPECT profile. */
IF EXISTS (SELECT 1 FROM sys.check_constraints
           WHERE parent_object_id=OBJECT_ID('dbo.PIP_M_InspectionType')
             AND name='CK_PIP_M_InspectionType_ScheduleSelectionMode')
    ALTER TABLE dbo.PIP_M_InspectionType DROP CONSTRAINT CK_PIP_M_InspectionType_ScheduleSelectionMode;

IF EXISTS (SELECT 1 FROM sys.check_constraints
           WHERE parent_object_id=OBJECT_ID('dbo.PIP_M_InspectionType')
             AND name='CK_PIP_M_InspectionType_PresentationCombination')
    ALTER TABLE dbo.PIP_M_InspectionType DROP CONSTRAINT CK_PIP_M_InspectionType_PresentationCombination;

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

/* Lightning is a BATCH inspection; INSPECT distinguishes its daily scope. */
UPDATE dbo.PIP_M_InspectionType
SET InspectionMode='BATCH',
    InspectionLayoutCode='MAP',
    PointSource='MASTER',
    InspectionPointMode='MAP',
    ScheduleSelectionMode='INSPECT'
WHERE UPPER(LTRIM(RTRIM(ISNULL(InspectionMode,''))))='LIGHTNING';

/* A previous partial migration may already have changed InspectionMode to
   BATCH while leaving its old selector value. Normalize the whole inspect
   profile so the new presentation-combination CHECK can be trusted. */
UPDATE dbo.PIP_M_InspectionType
SET InspectionLayoutCode='MAP',
    PointSource='MASTER',
    InspectionPointMode='MAP'
WHERE UPPER(LTRIM(RTRIM(ISNULL(InspectionMode,''))))='BATCH'
  AND UPPER(LTRIM(RTRIM(ISNULL(ScheduleSelectionMode,''))))='INSPECT';

/* Normalize any remaining legacy schedule selector values, including records
   already stored as BATCH but still carrying AT_INSPECTION. */
UPDATE dbo.PIP_M_InspectionType
SET ScheduleSelectionMode='INSPECT'
WHERE UPPER(LTRIM(RTRIM(ISNULL(ScheduleSelectionMode,''))))='AT_INSPECTION';

/* Approval workflow codes are normalized with the new master modes:
   BATCH/PARAM always routes SPV -> optional Chief Engineering;
   BATCH/INSPECT routes SPV -> Chief Security -> Chief Engineering. */
UPDATE dbo.PIP_M_InspectionType
SET ApprovalWorkflowCode='SPV_CHIEF_ENG'
WHERE InspectionMode='BATCH' AND ScheduleSelectionMode='PARAM'
  AND ISNULL(ApprovalWorkflowCode,'')<>'SPV_CHIEF_ENG';

UPDATE dbo.PIP_M_InspectionType
SET ApprovalWorkflowCode='LIGHTNING_4_STEP'
WHERE InspectionMode='BATCH' AND ScheduleSelectionMode='INSPECT'
  AND ISNULL(ApprovalWorkflowCode,'')<>'LIGHTNING_4_STEP';

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

/* Workflow email flags are configured per Company + Location in the
   existing INSPEC EmailApproval CommonGroup:
      <CompanyLocation>;STANDARD
      <CompanyLocation>;BATCH;PARAM
      <CompanyLocation>;BATCH;INSPECT
   Description contains tokens [LEVEL][TRUE/FALSE]. Missing rows mean
   all email flags are OFF. No unscoped/global workflow rows are created here.
   Legacy EMAIL;STANDARD/BATCH/LIGHTNING values are migrated by the
   dedicated ComVal migration script after review of the current settings.
*/
IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_M_InspectionType')
      AND name='CK_PIP_M_InspectionType_ScheduleSelectionMode'
)
    ALTER TABLE dbo.PIP_M_InspectionType WITH CHECK
        ADD CONSTRAINT CK_PIP_M_InspectionType_ScheduleSelectionMode
        CHECK (ScheduleSelectionMode IN ('PARAM','INSPECT'));

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_M_InspectionType')
      AND name='CK_PIP_M_InspectionType_PresentationCombination'
)
    ALTER TABLE dbo.PIP_M_InspectionType WITH CHECK
        ADD CONSTRAINT CK_PIP_M_InspectionType_PresentationCombination
        CHECK
        (
            (InspectionMode='STANDARD'
             AND InspectionLayoutCode='STANDARD'
             AND PointSource='MASTER'
             AND ScheduleSelectionMode='PARAM'
             AND ApprovalWorkflowCode='STANDARD')
            OR
            (InspectionMode='BATCH'
             AND InspectionLayoutCode='MAP'
             AND PointSource='MASTER'
             AND ScheduleSelectionMode='PARAM'
             AND ApprovalWorkflowCode IN ('STANDARD','SPV_CHIEF_ENG'))
            OR
            (InspectionMode='BATCH'
             AND InspectionLayoutCode='MAP'
             AND PointSource='MASTER'
             AND ScheduleSelectionMode='INSPECT'
             AND ApprovalWorkflowCode IN ('STANDARD','LIGHTNING_4_STEP'))
            OR
            (InspectionMode='BATCH'
             AND InspectionLayoutCode='DYNAMIC_LIST'
             AND PointSource='DYNAMIC'
             AND ScheduleSelectionMode='PARAM'
             AND ApprovalWorkflowCode IN ('STANDARD','SPV_CHIEF_ENG'))
        );

COMMIT TRANSACTION;
GO

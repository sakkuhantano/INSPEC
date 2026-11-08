/*
    Inspection point condition + checklist summary migration.
    SQL Server 2008 compatible.
    Run after inspection_location_map_schema.sql and inspection_batch_transaction_migration.sql.
    Re-run the updated inspection_batch_transaction_migration.sql afterward to install
    the batch sync procedure that validates C6 and persists C5 as AbnormalRemark.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* Summary is a Version-level setting. Existing item-level values are folded
   into one Version value before the obsolete Item column is removed. */
IF OBJECT_ID('dbo.PIP_M_CheckListWOPM_Version','U') IS NOT NULL
   AND COL_LENGTH('dbo.PIP_M_CheckListWOPM_Version','IsSummaryRequired') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_M_CheckListWOPM_Version
    ADD IsSummaryRequired BIT NOT NULL
        CONSTRAINT DF_PIP_M_CheckListWOPM_Version_IsSummaryRequired DEFAULT (1);
END;
GO

IF OBJECT_ID('dbo.PIP_M_CheckListWOPM_Item','U') IS NOT NULL
   AND COL_LENGTH('dbo.PIP_M_CheckListWOPM_Item','IsSummaryRequired') IS NOT NULL
BEGIN
    UPDATE V
       SET V.IsSummaryRequired = CASE
       WHEN NOT EXISTS
       (
           SELECT 1 FROM dbo.PIP_M_CheckListWOPM_Section S
           JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDSection=S.IDSection
           WHERE S.IDVersion=V.IDVersion
       ) THEN 1
       WHEN EXISTS
       (
           SELECT 1
           FROM dbo.PIP_M_CheckListWOPM_Section S
           JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDSection=S.IDSection
           WHERE S.IDVersion=V.IDVersion
             AND ISNULL(I.IsSummaryRequired,1)=1
       ) THEN 1 ELSE 0 END
    FROM dbo.PIP_M_CheckListWOPM_Version V;

    DECLARE @SummaryDefaultConstraint SYSNAME;
    SELECT @SummaryDefaultConstraint=DC.name
    FROM sys.default_constraints DC
    JOIN sys.columns C ON C.object_id=DC.parent_object_id AND C.column_id=DC.parent_column_id
    WHERE DC.parent_object_id=OBJECT_ID('dbo.PIP_M_CheckListWOPM_Item')
      AND C.name='IsSummaryRequired';
    IF @SummaryDefaultConstraint IS NOT NULL
        EXEC('ALTER TABLE dbo.PIP_M_CheckListWOPM_Item DROP CONSTRAINT [' + @SummaryDefaultConstraint + ']');

    ALTER TABLE dbo.PIP_M_CheckListWOPM_Item DROP COLUMN IsSummaryRequired;
END;
GO

IF OBJECT_ID('dbo.PIP_M_InspectionPoint','U') IS NOT NULL
   AND COL_LENGTH('dbo.PIP_M_InspectionPoint','IsNormalAbnormalRequired') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_M_InspectionPoint
    ADD IsNormalAbnormalRequired BIT NOT NULL
        CONSTRAINT DF_PIP_M_InspectionPoint_IsNormalAbnormalRequired DEFAULT (0);
END;
GO

IF OBJECT_ID('dbo.PIP_T_InspectionPoint','U') IS NOT NULL
   AND COL_LENGTH('dbo.PIP_T_InspectionPoint','AbnormalRemark') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_T_InspectionPoint
    ADD AbnormalRemark VARCHAR(500) NULL;
END;
GO

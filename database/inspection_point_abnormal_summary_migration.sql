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

IF OBJECT_ID('dbo.PIP_M_CheckListWOPM_Item','U') IS NOT NULL
   AND COL_LENGTH('dbo.PIP_M_CheckListWOPM_Item','IsSummaryRequired') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_M_CheckListWOPM_Item
    ADD IsSummaryRequired BIT NOT NULL
        CONSTRAINT DF_PIP_M_CheckListWOPM_Item_IsSummaryRequired DEFAULT (1);
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

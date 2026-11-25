/* Dynamic inspection point schema migration. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;
IF COL_LENGTH('dbo.PIP_T_InspectionPoint','PointSource') IS NULL
 ALTER TABLE dbo.PIP_T_InspectionPoint ADD PointSource VARCHAR(10) NOT NULL CONSTRAINT DF_PIP_T_InspectionPoint_PointSource DEFAULT ('MASTER') WITH VALUES;
IF COL_LENGTH('dbo.PIP_T_InspectionPoint','PointCode') IS NULL
 ALTER TABLE dbo.PIP_T_InspectionPoint ADD PointCode VARCHAR(100) NULL;
IF COL_LENGTH('dbo.PIP_T_InspectionPoint','PointName') IS NULL
 ALTER TABLE dbo.PIP_T_InspectionPoint ADD PointName VARCHAR(200) NULL;
UPDATE T SET T.PointSource='MASTER', T.PointCode=ISNULL(NULLIF(T.PointCode,''),M.PointCode), T.PointName=ISNULL(NULLIF(T.PointName,''),M.PointName)
FROM dbo.PIP_T_InspectionPoint T LEFT JOIN dbo.PIP_M_InspectionPoint M ON M.InspectionPointID=T.InspectionPointID;
IF EXISTS (SELECT 1 FROM dbo.PIP_T_InspectionPoint WHERE PointCode IS NULL OR LTRIM(RTRIM(PointCode))='' OR PointName IS NULL OR LTRIM(RTRIM(PointName))='')
BEGIN
 ROLLBACK TRANSACTION;
 RAISERROR('Cannot backfill PointCode/PointName for all existing points. Resolve master point data before rerunning.',16,1);
 RETURN;
END;
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name='FK_PIP_T_InspectionPoint_Master')
 ALTER TABLE dbo.PIP_T_InspectionPoint DROP CONSTRAINT FK_PIP_T_InspectionPoint_Master;
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name='UQ_PIP_T_InspectionPoint_Master')
 ALTER TABLE dbo.PIP_T_InspectionPoint DROP CONSTRAINT UQ_PIP_T_InspectionPoint_Master;
ALTER TABLE dbo.PIP_T_InspectionPoint ALTER COLUMN InspectionPointID BIGINT NULL;
ALTER TABLE dbo.PIP_T_InspectionPoint ALTER COLUMN PointCode VARCHAR(100) NOT NULL;
ALTER TABLE dbo.PIP_T_InspectionPoint ALTER COLUMN PointName VARCHAR(200) NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name='CK_PIP_T_InspectionPoint_Source')
 ALTER TABLE dbo.PIP_T_InspectionPoint WITH CHECK ADD CONSTRAINT CK_PIP_T_InspectionPoint_Source CHECK ((PointSource='MASTER' AND InspectionPointID IS NOT NULL) OR (PointSource='DYNAMIC' AND InspectionPointID IS NULL));
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name='CK_PIP_T_InspectionPoint_Code')
 ALTER TABLE dbo.PIP_T_InspectionPoint WITH CHECK ADD CONSTRAINT CK_PIP_T_InspectionPoint_Code CHECK (LEN(LTRIM(RTRIM(PointCode)))>0 AND LEN(LTRIM(RTRIM(PointName)))>0);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.PIP_T_InspectionPoint') AND name='UX_PIP_T_InspectionPoint_Master')
 CREATE UNIQUE NONCLUSTERED INDEX UX_PIP_T_InspectionPoint_Master ON dbo.PIP_T_InspectionPoint(InspectionID,InspectionPointID) WHERE PointSource='MASTER';
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.PIP_T_InspectionPoint') AND name='UX_PIP_T_InspectionPoint_Code')
 CREATE UNIQUE NONCLUSTERED INDEX UX_PIP_T_InspectionPoint_Code ON dbo.PIP_T_InspectionPoint(InspectionID,PointCode);
COMMIT TRANSACTION;
GO

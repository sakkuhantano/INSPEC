/*
  INSPEC approval header fields - clean deployment.
  SQL Server 2008 compatible.
  Additive for existing installations; does not drop legacy approval columns.
  Approval flags:
    IsApproved  = SPV (Standard/Batch and Lightning stage 1)
    IsApproved1 = the section ProfitCenter-derived Chief for BATCH/PARAM; Chief Security for Lightning stage 2
    IsApproved2 = Chief Engineering for Lightning stage 3
  Legacy IsApprovedFinal columns are retained for backward compatibility.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF COL_LENGTH('dbo.PIP_T_Inspection','IsApprove') IS NOT NULL
   AND COL_LENGTH('dbo.PIP_T_Inspection','IsApproved') IS NULL
BEGIN
    DECLARE @OldDefault SYSNAME;
    SELECT @OldDefault=dc.name
    FROM sys.default_constraints dc
    JOIN sys.columns c ON c.object_id=dc.parent_object_id AND c.column_id=dc.parent_column_id
    WHERE dc.parent_object_id=OBJECT_ID('dbo.PIP_T_Inspection') AND c.name='IsApprove';
    IF @OldDefault IS NOT NULL EXEC('ALTER TABLE dbo.PIP_T_Inspection DROP CONSTRAINT '+QUOTENAME(@OldDefault));
    EXEC sp_rename 'dbo.PIP_T_Inspection.IsApprove','IsApproved','COLUMN';
END;
GO

IF COL_LENGTH('dbo.PIP_T_Inspection','IsApproved') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD IsApproved BIT NOT NULL CONSTRAINT DF_PIP_T_Inspection_IsApproved DEFAULT (0);
IF COL_LENGTH('dbo.PIP_T_Inspection','ApprovedBy') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD ApprovedBy VARCHAR(50) NOT NULL CONSTRAINT DF_PIP_T_Inspection_ApprovedBy DEFAULT ('');
IF COL_LENGTH('dbo.PIP_T_Inspection','ApprovedDate') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD ApprovedDate DATETIME NOT NULL CONSTRAINT DF_PIP_T_Inspection_ApprovedDate DEFAULT ('19000101');

IF COL_LENGTH('dbo.PIP_T_Inspection','IsApproved1') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD IsApproved1 BIT NOT NULL CONSTRAINT DF_PIP_T_Inspection_IsApproved1 DEFAULT (0);
IF COL_LENGTH('dbo.PIP_T_Inspection','Approved1By') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD Approved1By VARCHAR(50) NOT NULL CONSTRAINT DF_PIP_T_Inspection_Approved1By DEFAULT ('');
IF COL_LENGTH('dbo.PIP_T_Inspection','Approved1Date') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD Approved1Date DATETIME NOT NULL CONSTRAINT DF_PIP_T_Inspection_Approved1Date DEFAULT ('19000101');

IF COL_LENGTH('dbo.PIP_T_Inspection','IsApproved2') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD IsApproved2 BIT NOT NULL CONSTRAINT DF_PIP_T_Inspection_IsApproved2 DEFAULT (0);
IF COL_LENGTH('dbo.PIP_T_Inspection','Approved2By') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD Approved2By VARCHAR(50) NOT NULL CONSTRAINT DF_PIP_T_Inspection_Approved2By DEFAULT ('');
IF COL_LENGTH('dbo.PIP_T_Inspection','Approved2Date') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD Approved2Date DATETIME NOT NULL CONSTRAINT DF_PIP_T_Inspection_Approved2Date DEFAULT ('19000101');
GO

/*
  Keep legacy IsApprovedFinal / ApprovedFinalBy / ApprovedFinalDate columns
  during the transition. They are no longer read or written by the new
  workflow, but dropping them could destroy historical data and can break
  older reports or stored procedures. Remove them only in a separate,
  explicitly reviewed cleanup migration after all legacy dependencies have
  been audited.
*/
GO

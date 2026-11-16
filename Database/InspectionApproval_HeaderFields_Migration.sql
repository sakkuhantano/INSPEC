/*
  INSPEC approval header fields - clean deployment.
  SQL Server 2008 compatible.
  Assumes PIP_T_Inspection contains no production data.
  Approval flags:
    IsApproved  = SPV (Standard/Batch and Lightning stage 1)
    IsApproved1 = Chief Engineering (Lightning stage 2)
    IsApproved2 = Chief Security (Lightning stage 3)
  The obsolete IsApprovedFinal family is removed.
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

/* Remove the obsolete final-stage fields; Standard/Batch now stop at IsApproved. */
DECLARE @Constraint SYSNAME;
DECLARE cFinal CURSOR LOCAL FAST_FORWARD FOR
    SELECT dc.name
    FROM sys.default_constraints dc
    JOIN sys.columns c ON c.object_id=dc.parent_object_id AND c.column_id=dc.parent_column_id
    WHERE dc.parent_object_id=OBJECT_ID('dbo.PIP_T_Inspection')
      AND c.name IN ('IsApprovedFinal','ApprovedFinalBy','ApprovedFinalDate');
OPEN cFinal;
FETCH NEXT FROM cFinal INTO @Constraint;
WHILE @@FETCH_STATUS=0
BEGIN
    EXEC('ALTER TABLE dbo.PIP_T_Inspection DROP CONSTRAINT '+QUOTENAME(@Constraint));
    FETCH NEXT FROM cFinal INTO @Constraint;
END;
CLOSE cFinal;
DEALLOCATE cFinal;

IF COL_LENGTH('dbo.PIP_T_Inspection','IsApprovedFinal') IS NOT NULL
    ALTER TABLE dbo.PIP_T_Inspection DROP COLUMN IsApprovedFinal;
IF COL_LENGTH('dbo.PIP_T_Inspection','ApprovedFinalBy') IS NOT NULL
    ALTER TABLE dbo.PIP_T_Inspection DROP COLUMN ApprovedFinalBy;
IF COL_LENGTH('dbo.PIP_T_Inspection','ApprovedFinalDate') IS NOT NULL
    ALTER TABLE dbo.PIP_T_Inspection DROP COLUMN ApprovedFinalDate;
GO

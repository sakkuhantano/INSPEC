/*
  INSPEC approval header migration.
  SQL Server 2008 compatible and safe to re-run.
  Run after InspectionEmailApproval_Schema.sql and before workflow procedures.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* Rename the legacy approval flag; never keep two sources of truth. */
IF COL_LENGTH('dbo.PIP_T_Inspection','IsApprove') IS NOT NULL
   AND COL_LENGTH('dbo.PIP_T_Inspection','IsApproved') IS NULL
BEGIN
    DECLARE @OldDefault SYSNAME;
    SELECT @OldDefault=dc.name
    FROM sys.default_constraints dc
    JOIN sys.columns c ON c.object_id=dc.parent_object_id AND c.column_id=dc.parent_column_id
    WHERE dc.parent_object_id=OBJECT_ID('dbo.PIP_T_Inspection') AND c.name='IsApprove';
    IF @OldDefault IS NOT NULL
        EXEC('ALTER TABLE dbo.PIP_T_Inspection DROP CONSTRAINT '+QUOTENAME(@OldDefault));
    EXEC sp_rename 'dbo.PIP_T_Inspection.IsApprove','IsApproved','COLUMN';
END;
GO
IF COL_LENGTH('dbo.PIP_T_Inspection','IsApproved') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD IsApproved BIT NOT NULL CONSTRAINT DF_PIP_T_Inspection_IsApproved DEFAULT (0);
GO
IF COL_LENGTH('dbo.PIP_T_Inspection','IsApprove') IS NOT NULL
BEGIN
    UPDATE dbo.PIP_T_Inspection SET IsApproved=ISNULL(IsApprove,0);
    DECLARE @OldDefault2 SYSNAME;
    SELECT @OldDefault2=dc.name
    FROM sys.default_constraints dc
    JOIN sys.columns c ON c.object_id=dc.parent_object_id AND c.column_id=dc.parent_column_id
    WHERE dc.parent_object_id=OBJECT_ID('dbo.PIP_T_Inspection') AND c.name='IsApprove';
    IF @OldDefault2 IS NOT NULL
        EXEC('ALTER TABLE dbo.PIP_T_Inspection DROP CONSTRAINT '+QUOTENAME(@OldDefault2));
    ALTER TABLE dbo.PIP_T_Inspection DROP COLUMN IsApprove;
END;
GO

IF COL_LENGTH('dbo.PIP_T_Inspection','IsSubmitted') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD IsSubmitted BIT NOT NULL CONSTRAINT DF_PIP_T_Inspection_IsSubmitted DEFAULT (0);
IF COL_LENGTH('dbo.PIP_T_Inspection','SubmittedBy') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD SubmittedBy VARCHAR(50) NOT NULL CONSTRAINT DF_PIP_T_Inspection_SubmittedBy DEFAULT ('');
IF COL_LENGTH('dbo.PIP_T_Inspection','SubmittedDate') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD SubmittedDate DATETIME NOT NULL CONSTRAINT DF_PIP_T_Inspection_SubmittedDate DEFAULT ('19000101');
IF COL_LENGTH('dbo.PIP_T_Inspection','IsApprovedFinal') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD IsApprovedFinal BIT NOT NULL CONSTRAINT DF_PIP_T_Inspection_IsApprovedFinal DEFAULT (0);
IF COL_LENGTH('dbo.PIP_T_Inspection','ApprovedFinalBy') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD ApprovedFinalBy VARCHAR(50) NOT NULL CONSTRAINT DF_PIP_T_Inspection_ApprovedFinalBy DEFAULT ('');
IF COL_LENGTH('dbo.PIP_T_Inspection','ApprovedFinalDate') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection ADD ApprovedFinalDate DATETIME NOT NULL CONSTRAINT DF_PIP_T_Inspection_ApprovedFinalDate DEFAULT ('19000101');
GO

/* Backfill the legacy one-step approval convention. */
UPDATE dbo.PIP_T_Inspection
SET IsSubmitted=CASE WHEN Status='DONE' OR IsApproved=1 OR ISNULL(ReasonVoid,'')<>'' THEN 1 ELSE IsSubmitted END,
    SubmittedBy=CASE WHEN IsApproved=1 THEN ISNULL(NULLIF(ApprovedBy,''),SubmittedBy) ELSE SubmittedBy END,
    SubmittedDate=CASE WHEN IsApproved=1 AND ApprovedDate>CONVERT(DATETIME,'19000101',112) THEN ApprovedDate ELSE SubmittedDate END,
    IsApprovedFinal=CASE WHEN IsApproved=1 THEN 1 ELSE IsApprovedFinal END,
    ApprovedFinalBy=CASE WHEN IsApproved=1 THEN ISNULL(NULLIF(ApprovedBy,''),ApprovedFinalBy) ELSE ApprovedFinalBy END,
    ApprovedFinalDate=CASE WHEN IsApproved=1 AND ApprovedDate>CONVERT(DATETIME,'19000101',112) THEN ApprovedDate ELSE ApprovedFinalDate END;
GO

/* Preserve workflow state/history before removing the redundant state table. */
IF OBJECT_ID('dbo.PIP_T_InspectionWorkflow','U') IS NOT NULL
BEGIN
    UPDATE I
    SET IsSubmitted=CASE WHEN W.WorkflowStatus IN ('SUBMITTED','CHECKED','ACKNOWLEDGE 1','ACKNOWLEDGE','APPROVED') THEN 1 ELSE 0 END,
        SubmittedBy=CASE WHEN W.WorkflowStatus IN ('SUBMITTED','CHECKED','ACKNOWLEDGE 1','ACKNOWLEDGE','APPROVED') THEN ISNULL(W.SubmittedBy,'') ELSE '' END,
        SubmittedDate=CASE WHEN W.WorkflowStatus IN ('SUBMITTED','CHECKED','ACKNOWLEDGE 1','ACKNOWLEDGE','APPROVED') THEN ISNULL(W.SubmittedDate,CONVERT(DATETIME,'19000101',112)) ELSE CONVERT(DATETIME,'19000101',112) END,
        IsApproved=CASE WHEN W.WorkflowStatus IN ('APPROVED','ACKNOWLEDGE 1','ACKNOWLEDGE') THEN 1 ELSE 0 END,
        IsApprovedFinal=CASE WHEN W.WorkflowStatus IN ('APPROVED','ACKNOWLEDGE') THEN 1 ELSE 0 END,
        ApprovedBy=CASE WHEN W.WorkflowStatus IN ('APPROVED','ACKNOWLEDGE 1','ACKNOWLEDGE') THEN ISNULL(NULLIF((SELECT TOP 1 H.ActorEmployeeID FROM dbo.PIP_T_InspectionApprovalHistory H WHERE H.EntityID=I.InspectionID AND H.StageCode IN ('SPV','CHIEF_ENG') AND H.ActionCode='APPROVED' ORDER BY H.ApprovalEventID DESC),''),ISNULL(W.LastActorEmployeeID,'')) ELSE '' END,
        ApprovedDate=CASE WHEN W.WorkflowStatus IN ('APPROVED','ACKNOWLEDGE 1','ACKNOWLEDGE') THEN ISNULL((SELECT TOP 1 H.ActionDate FROM dbo.PIP_T_InspectionApprovalHistory H WHERE H.EntityID=I.InspectionID AND H.StageCode IN ('SPV','CHIEF_ENG') AND H.ActionCode='APPROVED' ORDER BY H.ApprovalEventID DESC),W.LastActionDate) ELSE CONVERT(DATETIME,'19000101',112) END,
        ApprovedFinalBy=CASE WHEN W.WorkflowStatus IN ('APPROVED','ACKNOWLEDGE') THEN ISNULL(W.LastActorEmployeeID,'') ELSE '' END,
        ApprovedFinalDate=CASE WHEN W.WorkflowStatus IN ('APPROVED','ACKNOWLEDGE') THEN W.LastActionDate ELSE CONVERT(DATETIME,'19000101',112) END,
        Status=CASE WHEN W.WorkflowStatus='VOID' THEN 'DRAFT' ELSE I.Status END,
        ReasonVoid=CASE WHEN W.WorkflowStatus='VOID' THEN ISNULL(NULLIF(CONVERT(VARCHAR(500),W.LastRemark),''),I.ReasonVoid) ELSE I.ReasonVoid END
    FROM dbo.PIP_T_Inspection I
    JOIN dbo.PIP_T_InspectionWorkflow W ON W.EntityID=I.InspectionID
    WHERE W.EntityType IN ('INSPECTION','LIGHTNING');

    DROP TABLE dbo.PIP_T_InspectionWorkflow;
END;
GO

/* VOID always returns the whole approval cycle to the technician. */
UPDATE dbo.PIP_T_Inspection
SET IsSubmitted=0,SubmittedBy='',SubmittedDate=CONVERT(DATETIME,'19000101',112),
    IsApproved=0,ApprovedBy='',ApprovedDate=CONVERT(DATETIME,'19000101',112),
    IsApprovedFinal=0,ApprovedFinalBy='',ApprovedFinalDate=CONVERT(DATETIME,'19000101',112),
    ApprovalRemark=''
WHERE Status='DRAFT' AND ISNULL(ReasonVoid,'')<>'';
GO

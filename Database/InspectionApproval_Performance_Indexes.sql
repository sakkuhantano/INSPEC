/*
    INSPEC approval queue performance indexes
    SQL Server 2008 compatible and safe to re-run.

    Supports the queue's repeated latest-VOID / latest-SUBMISSION checks:
      EntityType + EntityID + StageCode + ActionCode + ActionDate

    This is additive only. It does not alter workflow data, constraints, or existing indexes.
*/
SET NOCOUNT ON;
GO

IF OBJECT_ID('dbo.PIP_T_InspectionApprovalHistory','U') IS NOT NULL
AND NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id=OBJECT_ID('dbo.PIP_T_InspectionApprovalHistory')
      AND name='IX_PIP_T_InspectionApprovalHistory_QueueHistory'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_T_InspectionApprovalHistory_QueueHistory
        ON dbo.PIP_T_InspectionApprovalHistory
        (
            EntityType,
            EntityID,
            StageCode,
            ActionCode,
            ActionDate
        )
        INCLUDE (ApprovalEventID);
END;
GO

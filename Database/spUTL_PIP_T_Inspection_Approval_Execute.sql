CREATE PROCEDURE [dbo].[spUTL_PIP_T_Inspection_Approval_Execute]
(
    @p_InspectionID BIGINT,
    @p_Action VARCHAR(10),
    @p_EmployeeID VARCHAR(50),
    @p_CompanyID VARCHAR(10),
    @p_LocationID VARCHAR(3),
    @p_Remark NVARCHAR(1000),
    @p_CorrectionUrl NVARCHAR(1000)
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    /*
      The transaction is opened by CF.EQueryP(..., true, true).
      This procedure and its child procedures must not BEGIN, COMMIT,
      or ROLLBACK that caller-owned transaction.
    */
    BEGIN TRY
        IF EXISTS
        (
            SELECT 1
            FROM dbo.PIP_T_Inspection I
            JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
            WHERE I.InspectionID=@p_InspectionID
              AND (ISNULL(IT.ApprovalWorkflowCode,'')<>'SPV_CHIEF_ENG'
                   OR (ISNULL(I.IsApproved,0)=1 AND ISNULL(I.IsApprovedFinal,0)=0))
        )
        BEGIN
            EXEC dbo.spUTL_PIP_T_Inspection_Approval
                @p_InspectionID = @p_InspectionID,
                @p_Action = @p_Action,
                @p_EmployeeID = @p_EmployeeID,
                @p_CompanyID = @p_CompanyID,
                @p_LocationID = @p_LocationID,
                @p_Remark = @p_Remark;
        END;

        EXEC dbo.spUTL_PIP_T_Inspection_ApprovalWorkflow
            @p_InspectionID = @p_InspectionID,
            @p_ActorEmployeeID = @p_EmployeeID,
            @p_Action = @p_Action,
            @p_Remark = @p_Remark,
            @p_CorrectionUrl = @p_CorrectionUrl;
    END TRY
    BEGIN CATCH
        DECLARE @V_ExecuteError NVARCHAR(4000);
        DECLARE @V_ExecuteSeverity INT;
        DECLARE @V_ExecuteState INT;

        SELECT
            @V_ExecuteError = ERROR_MESSAGE(),
            @V_ExecuteSeverity = ERROR_SEVERITY(),
            @V_ExecuteState = ERROR_STATE();

        RAISERROR(@V_ExecuteError, @V_ExecuteSeverity, @V_ExecuteState);
        RETURN;
    END CATCH;
END;

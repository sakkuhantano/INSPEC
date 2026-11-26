/* LEGACY RECOMPILE SCRIPT — DO NOT DEPLOY. The active follow-up authorization routine is Database/spUTL_PIP_T_Inspection_Approval.sql, and the active submit/approval procedures are deployed from Database/InspectionApproval_Workflow_Procedures.sql. */
/*
  Recompile the existing Follow Up work-order approval routine after
  dbo.PIP_T_Inspection.IsApprove is renamed to IsApproved.
  The routine retains its existing Follow Up WO creation behavior.
  The subsequent spUTL_PIP_T_Inspection_ApprovalWorkflow call completes
  the common two-stage header-field workflow and records approval history.
*/
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
ALTER PROCEDURE [dbo].[spUTL_PIP_T_Inspection_Approval]
(
    @p_InspectionID BIGINT,
    @p_Action VARCHAR(10),
    @p_EmployeeID VARCHAR(50),
    @p_CompanyID VARCHAR(10),
    @p_LocationID VARCHAR(3),
    @p_Remark VARCHAR(500) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;


    SET @p_Action = UPPER(LTRIM(RTRIM(ISNULL(@p_Action, ''))));
    IF @p_Action NOT IN ('APPROVE', 'VOID')
    BEGIN
        RAISERROR('Invalid inspection approval action.', 16, 1);
        RETURN;
    END;
    IF @p_Action = 'VOID' AND LEN(LTRIM(RTRIM(ISNULL(@p_Remark, '')))) = 0
    BEGIN
        RAISERROR('Reason for void is required.', 16, 1);
        RETURN;
    END;
    IF ISNULL(@p_EmployeeID, '') = ''
    BEGIN
        RAISERROR('Supervisor identity is required.', 16, 1);
        RETURN;
    END;

    BEGIN TRY
        DECLARE @V_SectionID VARCHAR(10);
        DECLARE @V_Status VARCHAR(10);
        DECLARE @V_IsApprove BIT;
        DECLARE @V_ApprovedBy VARCHAR(50);
        DECLARE @V_ApprovedDate DATETIME;
        DECLARE @V_ApprovalRemark VARCHAR(500);
        DECLARE @V_ReasonVoid VARCHAR(500);
        DECLARE @V_FollowUp VARCHAR(30);
        DECLARE @V_FollowUpSection VARCHAR(10);
        DECLARE @V_FollowUpRemark VARCHAR(300);
        DECLARE @V_FollowUpWONo VARCHAR(10);
        DECLARE @V_InspectionNo VARCHAR(10);
        DECLARE @V_OwnerEmployeeID VARCHAR(50);
        DECLARE @V_IDTemplate INT;

        SELECT @V_IDTemplate=IDTemplate, @V_SectionID=SectionID, @V_Status=Status, @V_IsApprove=IsApproved,
               @V_ApprovedBy=ApprovedBy, @V_ApprovedDate=ApprovedDate,
               @V_ApprovalRemark=ApprovalRemark, @V_ReasonVoid=ReasonVoid,
               @V_FollowUp=ISNULL(FollowUp,'No Follow Up'),
               @V_FollowUpSection=ISNULL(FollowUpSection,''),
               @V_FollowUpRemark=ISNULL(FollowUpRemark,''),
               @V_FollowUpWONo=ISNULL(FollowUpWONo,''),
               @V_InspectionNo=ISNULL(InspectionNo,''),
               @V_OwnerEmployeeID=OwnerEmployeeID
        FROM dbo.PIP_T_Inspection WITH (UPDLOCK, HOLDLOCK)
        WHERE InspectionID=@p_InspectionID
          AND CompanyID=@p_CompanyID AND LocationID=@p_LocationID;

        IF @V_SectionID IS NULL
            RAISERROR('Inspection was not found for this company/location.', 16, 1);

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.SysWebUser SU
            WHERE SU.EmployeeID=@p_EmployeeID
              AND SU.IsActive=1
              AND
              (
                  EXISTS
                  (
                      SELECT 1
                      FROM dbo.SysWebUserUserGroup UG
                      WHERE UG.UserID=SU.UserID
                        AND UG.UserGroupID='administrator'
                  )
                  OR
                  (
                      EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM
                              WHERE AM.MenuID='20022')
                      AND EXISTS
                      (
                          SELECT 1 FROM dbo.SysWebCommonValue C
                          WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                            AND C.ID=CONVERT(VARCHAR(30),@p_CompanyID)+CONVERT(VARCHAR(30),@p_LocationID)+';SPV;'+@V_SectionID
                            AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X
                                        WHERE LTRIM(RTRIM(X.val))=@p_EmployeeID)
                      )
                  )
              )
              AND
              (
                  EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                          WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                            AND C.CompanyID=@p_CompanyID AND C.LocationID=@p_LocationID)
                  OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                             WHERE L.CompanyID=@p_CompanyID AND L.LocationID=@p_LocationID)
              )
        )
        OR NOT EXISTS
        (
            SELECT 1
            FROM dbo.PIP_M_CheckListWOPM T
            WHERE T.IDTemplate=@V_IDTemplate
              AND T.SectionID=@V_SectionID
              AND ISNULL(T.TemplateType,'W')='I'
              AND (ISNULL(T.CompanyScope,'S')='A'
                   OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + @p_CompanyID + @p_LocationID + ';%'))
              AND (ISNULL(T.EmployeeList,'')=''
                   OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + @V_OwnerEmployeeID + ';%'))
        )
            RAISERROR('Supervisor is not authorized for this inspection template, technician, or company/location.', 16, 1);

        IF @V_Status <> 'DONE' OR ISNULL(@V_IsApprove,0) <> 0
           OR ISNULL(@V_ApprovedBy,'') <> '' OR ISNULL(@V_ApprovedDate,CONVERT(DATETIME,'19000101',112)) > CONVERT(DATETIME,'19000101',112)
           OR ISNULL(@V_ApprovalRemark,'') <> '' OR ISNULL(@V_ReasonVoid,'') <> ''
            RAISERROR('Only inspections awaiting approval can be processed.', 16, 1);

        IF @p_Action = 'APPROVE'
        BEGIN
            IF @V_FollowUp NOT IN ('No Follow Up','Recommend Follow Up')
                RAISERROR('Inspection Follow Up selection is invalid.', 16, 1);

            IF @V_FollowUp='Recommend Follow Up'
            BEGIN
                IF @V_FollowUpSection NOT IN ('ACON','COMM','MECH','ELEC','CIVIL','PFIT','PHKP','PSEC')
                    RAISERROR('A valid Follow Up Responsible Section is required.', 16, 1);
                IF LEN(LTRIM(RTRIM(@V_FollowUpRemark)))=0
                    RAISERROR('Follow Up Work Order Description is required.', 16, 1);
            END;

            /*
              Do not update IsApproved here. ApprovalWorkflow owns the final
              header transition and requires IsSubmitted=1, IsApproved=0.
              This procedure only validates scope and creates the Follow Up WO.
            */
            IF @V_FollowUp='Recommend Follow Up' AND ISNULL(@V_FollowUpWONo,'')=''
            BEGIN
                DECLARE @V_KeyHDWO INT;
                DECLARE @V_WONo VARCHAR(10);
                DECLARE @V_AutoNum VARCHAR(30);
                DECLARE @V_RequestedBy VARCHAR(50);
                DECLARE @V_DescriptionWO VARCHAR(255);
                DECLARE @V_AutoNumResult TABLE (ID VARCHAR(10), SeqNo INT);

                SELECT @V_KeyHDWO=ISNULL(MAX(KeyHD),0)+1
                FROM dbo.PIP_T_WO WITH (TABLOCKX, HOLDLOCK);

                SET @V_AutoNum='PIPWO'+@p_CompanyID+@p_LocationID;
                INSERT INTO @V_AutoNumResult
                EXECUTE dbo.sp_GetGenerateAutoNumID 'pip', @V_AutoNum, 1;
                SELECT @V_WONo=ID FROM @V_AutoNumResult;

                IF ISNULL(@V_WONo,'')=''
                    RAISERROR('Failed to generate internal Follow Up WO number.', 16, 1);

                SELECT @V_RequestedBy=LEFT(ISNULL(
                    (SELECT TOP 1 SWU.UserID FROM dbo.SysWebUser SWU WHERE SWU.EmployeeID=@V_OwnerEmployeeID),
                    @V_OwnerEmployeeID),50);

                SET @V_DescriptionWO=LEFT(
                    CASE WHEN @V_InspectionNo='' THEN '' ELSE 'Inspection '+@V_InspectionNo+': ' END+
                    @V_FollowUpRemark,255);

                INSERT INTO dbo.PIP_T_WO
                (
                    KeyHD, CompanyID, LocationID, WONo, WODate, WOType, StartDate, JONo,
                    PMType, Description, LocationNo, SectionID, RequestedBy, CompletedBy, CompletedDate,
                    CancelReason, SIIAmount, IsDelete, IsJO, IsApproved, ApprovedUser, ApprovedDate,
                    EntryUser, EntryDate, UpdateUser, UpdateDate, IsPrint, [RePrint],
                    Feedback1, Feedback2, Feedback3, Feedback4, Feedback5, EquipmentCode, SectionIDUser,
                    isApprovedDH, ApprovedDHUser, ApprovedDHDate, ReasonDH,
                    isApprovedHelpDesk, ApprovedHelpDeskUser, ApprovedHelpDeskDate, ReasonHelpDesk,
                    isCompleteDC, ReasonDC, LastStatusTransaction, ProfitCenterNo,
                    isRespondDC, ApprovedRespondDCUser, ApprovedRespondDCDate, ReasonRespondDC,
                    isCompletedUser, CompletedUser, CompletedDateUser, ReasonUser
                )
                VALUES
                (
                    @V_KeyHDWO, @p_CompanyID, @p_LocationID, @V_WONo,
                    CONVERT(VARCHAR(8),GETDATE(),112), 'I', CONVERT(VARCHAR(8),GETDATE(),112), '',
                    '', @V_DescriptionWO, '', @V_FollowUpSection, @V_RequestedBy, '', '',
                    '', 0, 0, 1, 0, '', '',
                    @p_EmployeeID, GETDATE(), @p_EmployeeID, GETDATE(), 0, 0,
                    0, 0, 0, 0, 0, '', @V_SectionID,
                    1, @p_EmployeeID, GETDATE(), '',
                    1, @p_EmployeeID, GETDATE(), '',
                    0, '', '', '',
                    0, '', '', '',
                    0, '', '', ''
                );

                UPDATE dbo.PIP_T_Inspection
                SET FollowUpWONo=@V_WONo, UpdateUser=@p_EmployeeID, UpdateDate=GETDATE()
                WHERE InspectionID=@p_InspectionID;
            END;
        END;

        /* VOID header reset is performed by ApprovalWorkflow. */

        SELECT @p_InspectionID AS InspectionID, @p_Action AS Action,
               (SELECT FollowUpWONo FROM dbo.PIP_T_Inspection WHERE InspectionID=@p_InspectionID) AS FollowUpWONo;
    END TRY
    BEGIN CATCH
        /* Transaction ownership belongs to the calling BRC/EQueryP layer. */
        DECLARE @V_ErrorMessage NVARCHAR(4000);
        DECLARE @V_ErrorSeverity INT;
        DECLARE @V_ErrorState INT;
        SELECT @V_ErrorMessage=ERROR_MESSAGE(), @V_ErrorSeverity=ERROR_SEVERITY(), @V_ErrorState=ERROR_STATE();
        RAISERROR(@V_ErrorMessage, @V_ErrorSeverity, @V_ErrorState);
    END CATCH;
END;
GO

/*
  Keep the approval executor transaction-safe when called through CF.EQueryP,
  which may already own a SqlTransaction. Never roll back a caller-owned
  transaction from this procedure.
*/
GO
ALTER PROCEDURE [dbo].[spUTL_PIP_T_Inspection_Approval_Execute]
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
        EXEC dbo.spUTL_PIP_T_Inspection_Approval
            @p_InspectionID = @p_InspectionID,
            @p_Action = @p_Action,
            @p_EmployeeID = @p_EmployeeID,
            @p_CompanyID = @p_CompanyID,
            @p_LocationID = @p_LocationID,
            @p_Remark = @p_Remark;

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
GO

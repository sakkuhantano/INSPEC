/*
    INSPEC - Lightning approval workflow and email outbox.
    SQL Server 2008 compatible.
    Requires Database/InspectionEmailApproval_Schema.sql and
    Database/LightningInspection_Transaction_Migration.sql.

    Lightning stages:
      TECHNICIAN SUBMITTED -> CHECKED / CHIEF_ENG
      CHIEF_ENG APPROVED   -> ACKNOWLEDGE 1 / CHIEF_SEC
      CHIEF_SEC APPROVED   -> ACKNOWLEDGE / COMPLETED
      CHIEF_ENG or CHIEF_SEC VOID -> VOID / TECHNICIAN correction

    This procedure only queues email in the outbox. SMTP is dispatched after
    the caller's SQL transaction commits.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_Lightning_SubmitWorkflow','P') IS NOT NULL
    DROP PROCEDURE dbo.spUTL_PIP_T_Inspection_Lightning_SubmitWorkflow;
GO
IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_Lightning_SubmitWorkflow','P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spUTL_PIP_T_Inspection_Lightning_SubmitWorkflow AS RETURN 0;');
GO

ALTER PROCEDURE dbo.spUTL_PIP_T_Inspection_Lightning_SubmitWorkflow
    @p_InspectionID BIGINT,
    @p_ActorEmployeeID VARCHAR(50),
    @p_ApprovalUrl NVARCHAR(1000)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @V_CompanyID VARCHAR(10), @V_LocationID VARCHAR(3), @V_SectionID VARCHAR(10);
    DECLARE @V_OwnerEmployeeID VARCHAR(50), @V_InspectionNo VARCHAR(10);
    DECLARE @V_InspectionTypeName VARCHAR(100), @V_InspectionDetailName VARCHAR(100);
    DECLARE @V_ChiefEngID VARCHAR(50), @V_ChiefSecID VARCHAR(50);
    DECLARE @V_ChiefEngSectionID VARCHAR(10),@V_ChiefSecSectionID VARCHAR(10);
    DECLARE @V_EmailEnabled BIT,@V_ConfigScope VARCHAR(30);
    DECLARE @V_TechnicianEmail VARCHAR(320), @V_TechnicianName VARCHAR(200);
    DECLARE @V_ChiefEngEmail VARCHAR(320), @V_ChiefEngName VARCHAR(200);
    DECLARE @V_ChiefSecEmail VARCHAR(320), @V_ChiefSecName VARCHAR(200);
    DECLARE @V_ExistingStatus VARCHAR(30), @V_Action VARCHAR(20);
    DECLARE @V_EventID BIGINT, @V_TranCount INT, @V_LastActionCode VARCHAR(20);

    SELECT @V_CompanyID=I.CompanyID,@V_LocationID=I.LocationID,@V_SectionID=I.SectionID,
           @V_OwnerEmployeeID=I.OwnerEmployeeID,@V_InspectionNo=I.InspectionNo,
           @V_InspectionTypeName=I.InspectionTypeName,@V_InspectionDetailName=I.InspectionTypeDetailName
    FROM dbo.PIP_T_Inspection I
    JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
    WHERE I.InspectionID=@p_InspectionID
      AND ISNULL(IT.InspectionMode,'STANDARD')='LIGHTNING'
      AND I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=0 AND ISNULL(I.IsApprovedFinal,0)=0;

    IF @V_CompanyID IS NULL
    BEGIN RAISERROR('Submitted Lightning inspection header was not found or is not eligible for workflow.',16,1); RETURN; END;

    IF @V_OwnerEmployeeID<>@p_ActorEmployeeID
    BEGIN RAISERROR('Only the inspection owner can submit a Lightning daily inspection.',16,1); RETURN; END;

    SET @V_ConfigScope=CONVERT(VARCHAR(30),@V_CompanyID)+CONVERT(VARCHAR(30),@V_LocationID);

    SELECT @V_ChiefEngID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';CHIEF_ENG';

    SELECT @V_ChiefSecID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';CHIEF_SEC';

    SELECT @V_ChiefEngSectionID=E.SectionID
    FROM dbo.M_HRD_Employee E
    WHERE E.EmployeeID=@V_ChiefEngID AND E.CompanyID=@V_CompanyID;

    SELECT @V_ChiefSecSectionID=E.SectionID
    FROM dbo.M_HRD_Employee E
    WHERE E.EmployeeID=@V_ChiefSecID AND E.CompanyID=@V_CompanyID;

    IF ISNULL(@V_ChiefEngID,'')='' OR ISNULL(@V_ChiefSecID,'')='' OR
       ISNULL(@V_ChiefEngSectionID,'')='' OR ISNULL(@V_ChiefSecSectionID,'')=''
    BEGIN RAISERROR('Chief Engineering / Chief Security routing is not configured for this Company and Location.',16,1); RETURN; END;

    SELECT @V_EmailEnabled=CASE WHEN ISNULL(C.Description,'0')='1' THEN 1 ELSE 0 END
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';EMAIL;LIGHTNING';
    SET @V_EmailEnabled=ISNULL(@V_EmailEnabled,1);

    IF @V_ChiefEngID=@V_ChiefSecID
    BEGIN RAISERROR('Chief Engineering and Chief Security must be different employees.',16,1); RETURN; END;

    IF NOT EXISTS
    (
        SELECT 1 FROM dbo.M_HRD_Employee E
        WHERE E.EmployeeID=@V_ChiefEngID AND E.CompanyID=@V_CompanyID
          AND E.SectionID=@V_ChiefEngSectionID AND ISNULL(E.TerminationDate,'')=''
          AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
              AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
          AND EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL
              WHERE CL.UserID=E.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@V_CompanyID AND CL.LocationID=@V_LocationID)
    )
    BEGIN RAISERROR('Configured Chief Engineering employee is not active, not in the selected section, or lacks approval access for this location.',16,1); RETURN; END;

    IF NOT EXISTS
    (
        SELECT 1 FROM dbo.M_HRD_Employee E
        WHERE E.EmployeeID=@V_ChiefSecID AND E.CompanyID=@V_CompanyID
          AND E.SectionID=@V_ChiefSecSectionID AND ISNULL(E.TerminationDate,'')=''
          AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
              AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
          AND EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL
              WHERE CL.UserID=E.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@V_CompanyID AND CL.LocationID=@V_LocationID)
    )
    BEGIN RAISERROR('Configured Chief Security employee is not active, not in the selected section, or lacks approval access for this location.',16,1); RETURN; END;

    SELECT @V_TechnicianEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))),@V_TechnicianName=ISNULL(Name,@V_OwnerEmployeeID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@V_OwnerEmployeeID;
    SELECT @V_ChiefEngEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))),@V_ChiefEngName=ISNULL(Name,@V_ChiefEngID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@V_ChiefEngID;
    SELECT @V_ChiefSecEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))),@V_ChiefSecName=ISNULL(Name,@V_ChiefSecID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@V_ChiefSecID;

    IF @V_EmailEnabled=1
       AND (ISNULL(@V_TechnicianEmail,'')='' OR ISNULL(@V_ChiefEngEmail,'')='' OR ISNULL(@V_ChiefSecEmail,'')='')
    BEGIN RAISERROR('Email address is missing for Technician, Chief Engineering, or Chief Security. Complete M_HRD_Employee.emailaddress before submitting.',16,1); RETURN; END;

    SELECT @V_ExistingStatus=CASE
        WHEN ISNULL(IsSubmitted,0)=1 THEN CASE WHEN ISNULL(IsApprovedFinal,0)=1 THEN 'ACKNOWLEDGE' WHEN ISNULL(IsApproved,0)=1 THEN 'ACKNOWLEDGE 1' ELSE 'CHECKED' END
        WHEN Status='DRAFT' AND ISNULL(ReasonVoid,'')<>'' THEN 'VOID' ELSE ''
    END
    FROM dbo.PIP_T_Inspection WITH (UPDLOCK,HOLDLOCK)
    WHERE InspectionID=@p_InspectionID;

    IF @V_ExistingStatus IN ('CHECKED','ACKNOWLEDGE 1','ACKNOWLEDGE','APPROVED')
    BEGIN RAISERROR('Lightning daily inspection is already in the approval workflow and cannot be resubmitted.',16,1); RETURN; END;

    SELECT TOP 1 @V_LastActionCode=ActionCode
    FROM dbo.PIP_T_InspectionApprovalHistory
    WHERE EntityType='LIGHTNING' AND EntityID=@p_InspectionID
    ORDER BY ApprovalEventID DESC;
    SET @V_Action=CASE WHEN @V_LastActionCode='VOIDED' THEN 'RESUBMITTED' ELSE 'SUBMITTED' END;
    SET @V_TranCount=@@TRANCOUNT;
    BEGIN TRY
        IF @V_TranCount=0 BEGIN TRANSACTION;
        ELSE SAVE TRANSACTION LightningWorkflowSubmitSave;

        UPDATE dbo.PIP_T_Inspection
        SET Status='DONE',IsSubmitted=1,SubmittedBy=@p_ActorEmployeeID,SubmittedDate=GETDATE(),
            IsApproved=0,ApprovedBy='',ApprovedDate=CONVERT(DATETIME,'19000101',112),
            IsApprovedFinal=0,ApprovedFinalBy='',ApprovedFinalDate=CONVERT(DATETIME,'19000101',112),
            ApprovalRemark='',ReasonVoid='',UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
        WHERE InspectionID=@p_InspectionID;

        INSERT dbo.PIP_T_InspectionApprovalHistory
        (EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
        VALUES ('LIGHTNING',@p_InspectionID,@V_CompanyID,@V_LocationID,@V_SectionID,
                'TECHNICIAN',@V_Action,@p_ActorEmployeeID,GETDATE(),NULL);
        SET @V_EventID=CONVERT(BIGINT,SCOPE_IDENTITY());

        IF @V_EmailEnabled=1
        BEGIN
            INSERT dbo.PIP_T_InspectionEmailOutbox
            (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
             EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
            VALUES
            ('LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':CHIEF_ENG',
             @V_EventID,'LIGHTNING',@p_InspectionID,'APPROVER',@V_ChiefEngID,@V_ChiefEngEmail,
             N'Lightning Inspection menunggu approval Chief Engineering - '+ISNULL(@V_InspectionNo,''),
             N'<p>Daily Lightning Inspection menunggu review Chief Engineering.</p><p>Inspection: '+ISNULL(@V_InspectionNo,'')+
             N'<br/>Type: '+ISNULL(@V_InspectionTypeName,'')+N'<br/>Detail: '+ISNULL(@V_InspectionDetailName,'')+
             N'</p><p><a href="'+ISNULL(@p_ApprovalUrl,N'')+N'&inspectionId='+CONVERT(NVARCHAR(20),@p_InspectionID)+N'">Buka halaman approval INSPEC</a></p>',
             N'Daily Lightning Inspection menunggu approval Chief Engineering. '+ISNULL(@p_ApprovalUrl,N'')+N'&inspectionId='+CONVERT(NVARCHAR(20),@p_InspectionID),'PENDING',0,GETDATE()),
            ('LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':TECHNICIAN',
             @V_EventID,'LIGHTNING',@p_InspectionID,'TECHNICIAN',@V_OwnerEmployeeID,@V_TechnicianEmail,
             N'Lightning Inspection telah dikirim - '+ISNULL(@V_InspectionNo,''),
             N'<p>Daily Lightning Inspection Anda telah dikirim dan berstatus CHECKED.</p><p>Menunggu review Chief Engineering.</p>',
             N'Daily Lightning Inspection Anda telah dikirim. Status: CHECKED.','PENDING',0,GETDATE());
        END;

        IF @V_TranCount=0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()=1
        BEGIN
            IF @V_TranCount=0 ROLLBACK TRANSACTION;
            ELSE ROLLBACK TRANSACTION LightningWorkflowSubmitSave;
        END
        ELSE IF XACT_STATE()=-1 AND @V_TranCount=0 ROLLBACK TRANSACTION;
        DECLARE @V_Error NVARCHAR(4000),@V_Severity INT,@V_State INT;
        SELECT @V_Error=ERROR_MESSAGE(),@V_Severity=ERROR_SEVERITY(),@V_State=ERROR_STATE();
        RAISERROR(@V_Error,@V_Severity,@V_State);
    END CATCH;
END;
GO

IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_Lightning_Approval','P') IS NOT NULL
    DROP PROCEDURE dbo.spUTL_PIP_T_Inspection_Lightning_Approval;
GO
IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_Lightning_Approval','P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spUTL_PIP_T_Inspection_Lightning_Approval AS RETURN 0;');
GO

ALTER PROCEDURE dbo.spUTL_PIP_T_Inspection_Lightning_Approval
    @p_InspectionID BIGINT,
    @p_ActorEmployeeID VARCHAR(50),
    @p_Action VARCHAR(10),
    @p_Remark NVARCHAR(1000),
    @p_ApprovalUrl NVARCHAR(1000),
    @p_CorrectionUrl NVARCHAR(1000)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @p_Action=UPPER(LTRIM(RTRIM(ISNULL(@p_Action,''))));
    SET @p_Remark=LTRIM(RTRIM(ISNULL(@p_Remark,N'')));
    IF @p_Action NOT IN ('APPROVE','VOID')
    BEGIN RAISERROR('Invalid Lightning approval action.',16,1); RETURN; END;
    IF @p_Action='VOID' AND @p_Remark=''
    BEGIN RAISERROR('Void reason is required.',16,1); RETURN; END;

    DECLARE @V_CompanyID VARCHAR(10),@V_LocationID VARCHAR(3),@V_SectionID VARCHAR(10);
    DECLARE @V_OwnerEmployeeID VARCHAR(50),@V_InspectionNo VARCHAR(10),@V_Stage VARCHAR(20);
    DECLARE @V_ChiefEngID VARCHAR(50),@V_ChiefSecID VARCHAR(50);
    DECLARE @V_TechnicianEmail VARCHAR(320),@V_TechnicianName VARCHAR(200);
    DECLARE @V_EmailEnabled BIT,@V_ConfigScope VARCHAR(30);
    DECLARE @V_NextEmployeeID VARCHAR(50),@V_NextEmail VARCHAR(320),@V_NextName VARCHAR(200);
    DECLARE @V_EventID BIGINT,@V_TranCount INT,@V_NewStatus VARCHAR(30),@V_NextStage VARCHAR(20);

    SELECT @V_CompanyID=I.CompanyID,@V_LocationID=I.LocationID,@V_SectionID=I.SectionID,
           @V_Stage=CASE WHEN ISNULL(I.IsApproved,0)=0 THEN 'CHIEF_ENG' ELSE 'CHIEF_SEC' END,
           @V_OwnerEmployeeID=I.OwnerEmployeeID,@V_InspectionNo=I.InspectionNo
    FROM dbo.PIP_T_Inspection I WITH (UPDLOCK,HOLDLOCK)
    JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
    WHERE I.InspectionID=@p_InspectionID AND ISNULL(IT.InspectionMode,'STANDARD')='LIGHTNING'
      AND ISNULL(I.IsSubmitted,0)=1 AND ISNULL(I.IsApprovedFinal,0)=0
      AND ISNULL(I.Status,'')='DONE';

    IF @V_CompanyID IS NULL
    BEGIN RAISERROR('Lightning inspection is not waiting for approval.',16,1); RETURN; END;

    SET @V_ConfigScope=CONVERT(VARCHAR(30),@V_CompanyID)+CONVERT(VARCHAR(30),@V_LocationID);

    SELECT @V_EmailEnabled=CASE WHEN ISNULL(C.Description,'0')='1' THEN 1 ELSE 0 END
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';EMAIL;LIGHTNING';
    SET @V_EmailEnabled=ISNULL(@V_EmailEnabled,1);

    SELECT @V_ChiefEngID=NULLIF(LTRIM(RTRIM(C.Description)),''),
           @V_ChiefSecID=NULL
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';CHIEF_ENG';

    SELECT @V_ChiefSecID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';CHIEF_SEC';

    IF (@V_Stage='CHIEF_ENG' AND @p_ActorEmployeeID<>@V_ChiefEngID)
       OR (@V_Stage='CHIEF_SEC' AND @p_ActorEmployeeID<>@V_ChiefSecID)
    BEGIN RAISERROR('You are not the configured approver for the current Lightning stage.',16,1); RETURN; END;

    SELECT @V_TechnicianEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))),@V_TechnicianName=ISNULL(Name,@V_OwnerEmployeeID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@V_OwnerEmployeeID;
    IF @V_EmailEnabled=1 AND ISNULL(@V_TechnicianEmail,'')=''
    BEGIN RAISERROR('Technician email is missing from M_HRD_Employee.emailaddress.',16,1); RETURN; END;

    IF @p_Action='APPROVE' AND @V_Stage='CHIEF_ENG'
    BEGIN
        SELECT @V_NextEmployeeID=@V_ChiefSecID;
        SELECT @V_NextEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))),@V_NextName=ISNULL(Name,@V_NextEmployeeID)
        FROM dbo.M_HRD_Employee WHERE EmployeeID=@V_NextEmployeeID;
        IF @V_EmailEnabled=1 AND ISNULL(@V_NextEmail,'')=''
        BEGIN RAISERROR('Chief Security email is missing from M_HRD_Employee.emailaddress.',16,1); RETURN; END;
        SET @V_NewStatus='ACKNOWLEDGE 1'; SET @V_NextStage='CHIEF_SEC';
    END
    ELSE IF @p_Action='APPROVE'
    BEGIN
        SET @V_NewStatus='ACKNOWLEDGE'; SET @V_NextStage='COMPLETED';
    END
    ELSE
    BEGIN
        SET @V_NewStatus='VOID'; SET @V_NextStage='TECHNICIAN';
    END;

    SET @V_TranCount=@@TRANCOUNT;
    BEGIN TRY
        IF @V_TranCount=0 BEGIN TRANSACTION;
        ELSE SAVE TRANSACTION LightningApprovalSave;

        INSERT dbo.PIP_T_InspectionApprovalHistory
        (EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
        VALUES ('LIGHTNING',@p_InspectionID,@V_CompanyID,@V_LocationID,@V_SectionID,
                @V_Stage,CASE WHEN @p_Action='APPROVE' THEN 'APPROVED' ELSE 'VOIDED' END,
                @p_ActorEmployeeID,GETDATE(),NULLIF(@p_Remark,N''));
        SET @V_EventID=CONVERT(BIGINT,SCOPE_IDENTITY());


        IF @p_Action='VOID'
        BEGIN
            UPDATE dbo.PIP_T_Inspection
            SET Status='DRAFT',
                IsSubmitted=0,SubmittedBy='',SubmittedDate=CONVERT(DATETIME,'19000101',112),
                IsApproved=0,ApprovedBy='',ApprovedDate=CONVERT(DATETIME,'19000101',112),
                IsApprovedFinal=0,ApprovedFinalBy='',ApprovedFinalDate=CONVERT(DATETIME,'19000101',112),
                ApprovalRemark='',ReasonVoid=CONVERT(VARCHAR(500),@p_Remark),
                UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
            WHERE InspectionID=@p_InspectionID;

            IF @V_EmailEnabled=1
            BEGIN
                INSERT dbo.PIP_T_InspectionEmailOutbox
                (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
                 EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                VALUES
                ('LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':TECHNICIAN',
                 @V_EventID,'LIGHTNING',@p_InspectionID,'TECHNICIAN',@V_OwnerEmployeeID,@V_TechnicianEmail,
                 N'Lightning Inspection perlu diperbaiki - '+ISNULL(@V_InspectionNo,''),
                 N'<p>Daily Lightning Inspection dikembalikan untuk koreksi.</p><p>Alasan: '+REPLACE(REPLACE(REPLACE(@p_Remark,N'&',N'&amp;'),N'<',N'&lt;'),N'>',N'&gt;')+
                 N'</p><p><a href="'+ISNULL(@p_CorrectionUrl,N'')+N'">Buka INSPEC untuk memperbaiki dan submit ulang</a></p>',
                 N'Daily Lightning Inspection dikembalikan. Alasan: '+@p_Remark+N' '+ISNULL(@p_CorrectionUrl,N''),'PENDING',0,GETDATE());
            END;
        END
        ELSE
        BEGIN
            IF @V_Stage='CHIEF_ENG'
                UPDATE dbo.PIP_T_Inspection
                SET IsApproved=1,ApprovedBy=@p_ActorEmployeeID,ApprovedDate=GETDATE(),
                    ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),ReasonVoid='',
                    UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
                WHERE InspectionID=@p_InspectionID;
            ELSE
                UPDATE dbo.PIP_T_Inspection
                SET IsApprovedFinal=1,ApprovedFinalBy=@p_ActorEmployeeID,ApprovedFinalDate=GETDATE(),
                    ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),ReasonVoid='',
                    UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
                WHERE InspectionID=@p_InspectionID;

            IF @V_EmailEnabled=1
            BEGIN
                INSERT dbo.PIP_T_InspectionEmailOutbox
                (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
                 EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                VALUES
                ('LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':TECHNICIAN',
                 @V_EventID,'LIGHTNING',@p_InspectionID,'TECHNICIAN',@V_OwnerEmployeeID,@V_TechnicianEmail,
                 N'Lightning Inspection approval update - '+ISNULL(@V_InspectionNo,''),
                 N'<p>Daily Lightning Inspection Anda telah diproses.</p><p>Status: '+@V_NewStatus+
                 N'</p><p>Stage berikutnya: '+@V_NextStage+N'</p>',
                 N'Daily Lightning Inspection status: '+@V_NewStatus+N'. Stage: '+@V_NextStage,'PENDING',0,GETDATE());

                IF @V_Stage='CHIEF_ENG'
                    INSERT dbo.PIP_T_InspectionEmailOutbox
                    (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
                     EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                    VALUES
                    ('LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':CHIEF_SEC',
                     @V_EventID,'LIGHTNING',@p_InspectionID,'APPROVER',@V_NextEmployeeID,@V_NextEmail,
                     N'Lightning Inspection menunggu approval Chief Security - '+ISNULL(@V_InspectionNo,''),
                     N'<p>Chief Engineering telah approve. Daily Lightning Inspection menunggu review Chief Security.</p><p><a href="'+ISNULL(@p_ApprovalUrl,N'')+N'&inspectionId='+CONVERT(NVARCHAR(20),@p_InspectionID)+N'">Buka halaman approval INSPEC</a></p>',
                     N'Daily Lightning Inspection menunggu approval Chief Security. '+ISNULL(@p_ApprovalUrl,N'')+N'&inspectionId='+CONVERT(NVARCHAR(20),@p_InspectionID),'PENDING',0,GETDATE());
            END;
        END;

        IF @V_TranCount=0 COMMIT TRANSACTION;
        SELECT @V_NewStatus WorkflowStatus,@V_NextStage CurrentStageCode,@V_EventID ApprovalEventID;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()=1
        BEGIN
            IF @V_TranCount=0 ROLLBACK TRANSACTION;
            ELSE ROLLBACK TRANSACTION LightningApprovalSave;
        END
        ELSE IF XACT_STATE()=-1 AND @V_TranCount=0 ROLLBACK TRANSACTION;
        DECLARE @V_Error NVARCHAR(4000),@V_Severity INT,@V_State INT;
        SELECT @V_Error=ERROR_MESSAGE(),@V_Severity=ERROR_SEVERITY(),@V_State=ERROR_STATE();
        RAISERROR(@V_Error,@V_Severity,@V_State);
    END CATCH;
END;
GO

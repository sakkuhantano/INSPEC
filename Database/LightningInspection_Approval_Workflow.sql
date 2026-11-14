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
    DECLARE @V_TechnicianEmail VARCHAR(320), @V_TechnicianName VARCHAR(200);
    DECLARE @V_ChiefEngEmail VARCHAR(320), @V_ChiefEngName VARCHAR(200);
    DECLARE @V_ChiefSecEmail VARCHAR(320), @V_ChiefSecName VARCHAR(200);
    DECLARE @V_ExistingStatus VARCHAR(30), @V_Action VARCHAR(20);
    DECLARE @V_EventID BIGINT, @V_TranCount INT;

    SELECT @V_CompanyID=I.CompanyID,@V_LocationID=I.LocationID,@V_SectionID=I.SectionID,
           @V_OwnerEmployeeID=I.OwnerEmployeeID,@V_InspectionNo=I.InspectionNo,
           @V_InspectionTypeName=I.InspectionTypeName,@V_InspectionDetailName=I.InspectionTypeDetailName
    FROM dbo.PIP_T_Inspection I
    JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
    WHERE I.InspectionID=@p_InspectionID
      AND ISNULL(IT.InspectionMode,'STANDARD')='LIGHTNING'
      AND I.Status='DONE' AND ISNULL(I.IsApprove,0)=0;

    IF @V_CompanyID IS NULL
    BEGIN RAISERROR('Submitted Lightning inspection header was not found or is not eligible for workflow.',16,1); RETURN; END;

    IF @V_OwnerEmployeeID<>@p_ActorEmployeeID
    BEGIN RAISERROR('Only the inspection owner can submit a Lightning daily inspection.',16,1); RETURN; END;

    SELECT @V_ChiefEngID=ChiefEngEmployeeID,@V_ChiefSecID=ChiefSecEmployeeID
    FROM dbo.PIP_M_InspectionEmailSetup
    WHERE CompanyID=@V_CompanyID AND LocationID=@V_LocationID AND IsActive=1;

    IF ISNULL(@V_ChiefEngID,'')='' OR ISNULL(@V_ChiefSecID,'')=''
    BEGIN RAISERROR('Chief Engineering / Chief Security routing is not configured for this Company and Location.',16,1); RETURN; END;

    SELECT @V_TechnicianEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))),@V_TechnicianName=ISNULL(Name,@V_OwnerEmployeeID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@V_OwnerEmployeeID;
    SELECT @V_ChiefEngEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))),@V_ChiefEngName=ISNULL(Name,@V_ChiefEngID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@V_ChiefEngID;
    SELECT @V_ChiefSecEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))),@V_ChiefSecName=ISNULL(Name,@V_ChiefSecID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@V_ChiefSecID;

    IF ISNULL(@V_TechnicianEmail,'')='' OR ISNULL(@V_ChiefEngEmail,'')='' OR ISNULL(@V_ChiefSecEmail,'')=''
    BEGIN RAISERROR('Email address is missing for Technician, Chief Engineering, or Chief Security. Complete M_HRD_Employee.emailaddress before submitting.',16,1); RETURN; END;

    SELECT @V_ExistingStatus=WorkflowStatus
    FROM dbo.PIP_T_InspectionWorkflow WITH (UPDLOCK,HOLDLOCK)
    WHERE EntityType='LIGHTNING' AND EntityID=@p_InspectionID;

    IF @V_ExistingStatus IN ('CHECKED','ACKNOWLEDGE 1','ACKNOWLEDGE','APPROVED')
    BEGIN RAISERROR('Lightning daily inspection is already in the approval workflow and cannot be resubmitted.',16,1); RETURN; END;

    SET @V_Action=CASE WHEN @V_ExistingStatus='VOID' THEN 'RESUBMITTED' ELSE 'SUBMITTED' END;
    SET @V_TranCount=@@TRANCOUNT;
    BEGIN TRY
        IF @V_TranCount=0 BEGIN TRANSACTION;
        ELSE SAVE TRANSACTION LightningWorkflowSubmitSave;

        IF EXISTS (SELECT 1 FROM dbo.PIP_T_InspectionWorkflow WHERE EntityType='LIGHTNING' AND EntityID=@p_InspectionID)
            UPDATE dbo.PIP_T_InspectionWorkflow
            SET CompanyID=@V_CompanyID,LocationID=@V_LocationID,SectionID=@V_SectionID,
                WorkflowStatus='CHECKED',CurrentStageCode='CHIEF_ENG',
                SubmittedBy=@p_ActorEmployeeID,SubmittedDate=GETDATE(),
                LastActorEmployeeID=@p_ActorEmployeeID,LastActionDate=GETDATE(),LastRemark=NULL
            WHERE EntityType='LIGHTNING' AND EntityID=@p_InspectionID;
        ELSE
            INSERT dbo.PIP_T_InspectionWorkflow
            (EntityType,EntityID,CompanyID,LocationID,SectionID,WorkflowStatus,CurrentStageCode,
             SubmittedBy,SubmittedDate,LastActorEmployeeID,LastActionDate,LastRemark)
            VALUES
            ('LIGHTNING',@p_InspectionID,@V_CompanyID,@V_LocationID,@V_SectionID,'CHECKED','CHIEF_ENG',
             @p_ActorEmployeeID,GETDATE(),@p_ActorEmployeeID,GETDATE(),NULL);

        INSERT dbo.PIP_T_InspectionApprovalHistory
        (EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
        VALUES ('LIGHTNING',@p_InspectionID,@V_CompanyID,@V_LocationID,@V_SectionID,
                'TECHNICIAN',@V_Action,@p_ActorEmployeeID,GETDATE(),NULL);
        SET @V_EventID=CONVERT(BIGINT,SCOPE_IDENTITY());

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
    DECLARE @V_NextEmployeeID VARCHAR(50),@V_NextEmail VARCHAR(320),@V_NextName VARCHAR(200);
    DECLARE @V_EventID BIGINT,@V_TranCount INT,@V_NewStatus VARCHAR(30),@V_NextStage VARCHAR(20);

    SELECT @V_CompanyID=W.CompanyID,@V_LocationID=W.LocationID,@V_SectionID=W.SectionID,
           @V_Stage=W.CurrentStageCode,@V_OwnerEmployeeID=I.OwnerEmployeeID,@V_InspectionNo=I.InspectionNo
    FROM dbo.PIP_T_InspectionWorkflow W WITH (UPDLOCK,HOLDLOCK)
    JOIN dbo.PIP_T_Inspection I ON I.InspectionID=W.EntityID
    JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
    WHERE W.EntityType='LIGHTNING' AND W.EntityID=@p_InspectionID
      AND W.WorkflowStatus IN ('CHECKED','ACKNOWLEDGE 1')
      AND ISNULL(IT.InspectionMode,'STANDARD')='LIGHTNING';

    IF @V_CompanyID IS NULL
    BEGIN RAISERROR('Lightning inspection is not waiting for approval.',16,1); RETURN; END;

    SELECT @V_ChiefEngID=ChiefEngEmployeeID,@V_ChiefSecID=ChiefSecEmployeeID
    FROM dbo.PIP_M_InspectionEmailSetup
    WHERE CompanyID=@V_CompanyID AND LocationID=@V_LocationID AND IsActive=1;

    IF (@V_Stage='CHIEF_ENG' AND @p_ActorEmployeeID<>@V_ChiefEngID)
       OR (@V_Stage='CHIEF_SEC' AND @p_ActorEmployeeID<>@V_ChiefSecID)
    BEGIN RAISERROR('You are not the configured approver for the current Lightning stage.',16,1); RETURN; END;

    SELECT @V_TechnicianEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))),@V_TechnicianName=ISNULL(Name,@V_OwnerEmployeeID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@V_OwnerEmployeeID;
    IF ISNULL(@V_TechnicianEmail,'')=''
    BEGIN RAISERROR('Technician email is missing from M_HRD_Employee.emailaddress.',16,1); RETURN; END;

    IF @p_Action='APPROVE' AND @V_Stage='CHIEF_ENG'
    BEGIN
        SELECT @V_NextEmployeeID=@V_ChiefSecID;
        SELECT @V_NextEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))),@V_NextName=ISNULL(Name,@V_NextEmployeeID)
        FROM dbo.M_HRD_Employee WHERE EmployeeID=@V_NextEmployeeID;
        IF ISNULL(@V_NextEmail,'')=''
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

        UPDATE dbo.PIP_T_InspectionWorkflow
        SET WorkflowStatus=@V_NewStatus,CurrentStageCode=@V_NextStage,
            LastActorEmployeeID=@p_ActorEmployeeID,LastActionDate=GETDATE(),LastRemark=NULLIF(@p_Remark,N'')
        WHERE EntityType='LIGHTNING' AND EntityID=@p_InspectionID;

        IF @p_Action='VOID'
        BEGIN
            UPDATE dbo.PIP_T_Inspection
            SET Status='DRAFT',IsApprove=0,ApprovedBy='',
                ApprovedDate=CONVERT(DATETIME,'19000101',112),ApprovalRemark='',
                ReasonVoid=CONVERT(VARCHAR(500),@p_Remark),
                UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
            WHERE InspectionID=@p_InspectionID;

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
        END
        ELSE
        BEGIN
            IF @V_Stage='CHIEF_SEC'
                UPDATE dbo.PIP_T_Inspection
                SET IsApprove=1,ApprovedBy=@p_ActorEmployeeID,ApprovedDate=GETDATE(),
                    ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),ReasonVoid='',
                    UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
                WHERE InspectionID=@p_InspectionID;

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

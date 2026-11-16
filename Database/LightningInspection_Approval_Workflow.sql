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
    DECLARE @V_SPVID VARCHAR(4000),@V_SPVEmail VARCHAR(4000),@V_SPVName VARCHAR(4000);
    DECLARE @V_ChiefEngID VARCHAR(4000), @V_ChiefSecID VARCHAR(4000);
    DECLARE @V_ChiefEngSectionID VARCHAR(10),@V_ChiefSecSectionID VARCHAR(10);
    DECLARE @V_EmailEnabled BIT,@V_ConfigScope VARCHAR(30);
    DECLARE @V_TechnicianEmail VARCHAR(320), @V_TechnicianName VARCHAR(200);
    DECLARE @V_ChiefEngEmail VARCHAR(4000), @V_ChiefEngName VARCHAR(4000);
    DECLARE @V_ChiefSecEmail VARCHAR(4000), @V_ChiefSecName VARCHAR(4000);
    DECLARE @V_ExistingStatus VARCHAR(30), @V_Action VARCHAR(20);
    DECLARE @V_EventID BIGINT, @V_TranCount INT, @V_LastActionCode VARCHAR(20);

    SELECT @V_CompanyID=I.CompanyID,@V_LocationID=I.LocationID,@V_SectionID=I.SectionID,
           @V_OwnerEmployeeID=I.OwnerEmployeeID,@V_InspectionNo=I.InspectionNo,
           @V_InspectionTypeName=I.InspectionTypeName,@V_InspectionDetailName=I.InspectionTypeDetailName
    FROM dbo.PIP_T_Inspection I
    JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
    WHERE I.InspectionID=@p_InspectionID
      AND ISNULL(IT.InspectionMode,'STANDARD')='LIGHTNING'
      AND I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=0;

    IF @V_CompanyID IS NULL
    BEGIN RAISERROR('Submitted Lightning inspection header was not found or is not eligible for workflow.',16,1); RETURN; END;

    IF @V_OwnerEmployeeID<>@p_ActorEmployeeID
    BEGIN RAISERROR('Only the inspection owner can submit a Lightning daily inspection.',16,1); RETURN; END;

    SET @V_ConfigScope=CONVERT(VARCHAR(30),@V_CompanyID)+CONVERT(VARCHAR(30),@V_LocationID);

    SELECT @V_SPVID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=@V_ConfigScope+';SPV;'+@V_SectionID;

    SELECT @V_SPVID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=@V_ConfigScope+';SPV;'+@V_SectionID;

    SELECT @V_ChiefEngID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';CHIEF_ENG';

    SELECT @V_ChiefSecID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';CHIEF_SEC';

    IF ISNULL(@V_SPVID,'')='' OR ISNULL(@V_SPVID,'')='' OR ISNULL(@V_ChiefSecID,'')=''
    BEGIN RAISERROR('SPV, Chief Engineering, and Chief Security routing must be configured for this Company, Location, and Section.',16,1); RETURN; END;

    SELECT @V_EmailEnabled=CASE WHEN ISNULL(C.Description,'0')='1' THEN 1 ELSE 0 END
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';EMAIL;LIGHTNING';
    SET @V_EmailEnabled=ISNULL(@V_EmailEnabled,1);

    IF EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_SPVID,';') S JOIN dbo.SplitStringConvertToTable(@V_ChiefEngID,';') E ON LTRIM(RTRIM(S.val))=LTRIM(RTRIM(E.val)))
       OR EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_SPVID,';') S JOIN dbo.SplitStringConvertToTable(@V_ChiefSecID,';') C ON LTRIM(RTRIM(S.val))=LTRIM(RTRIM(C.val)))
    BEGIN RAISERROR('SPV, Chief Engineering, and Chief Security must not contain overlapping employees.',16,1); RETURN; END;

    IF EXISTS (
        SELECT 1
        FROM dbo.SplitStringConvertToTable(@V_ChiefEngID,';') E
        JOIN dbo.SplitStringConvertToTable(@V_ChiefSecID,';') S
          ON LTRIM(RTRIM(E.val))=LTRIM(RTRIM(S.val))
    )
    BEGIN RAISERROR('Chief Engineering and Chief Security must not contain the same employee.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1 FROM dbo.SplitStringConvertToTable(@V_SPVID,';') X
        WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee E WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND E.CompanyID=@V_CompanyID AND E.SectionID=@V_SectionID AND ISNULL(E.TerminationDate,'')=''
          AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1 AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
          AND EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL WHERE CL.UserID=E.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@V_CompanyID AND CL.LocationID=@V_LocationID))
    )
    BEGIN RAISERROR('One or more configured SPV employees are not active or lack approval access for this Section and location.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1 FROM dbo.SplitStringConvertToTable(@V_ChiefEngID,';') X
        WHERE NOT EXISTS
        (
            SELECT 1 FROM dbo.M_HRD_Employee E
            WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND E.CompanyID=@V_CompanyID AND ISNULL(E.TerminationDate,'')=''
              AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
                  AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
              AND EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL
                  WHERE CL.UserID=E.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@V_CompanyID AND CL.LocationID=@V_LocationID)
        )
    )
    BEGIN RAISERROR('One or more configured Chief Engineering employees are not active or lack approval access for this location.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1 FROM dbo.SplitStringConvertToTable(@V_ChiefSecID,';') X
        WHERE NOT EXISTS
        (
            SELECT 1 FROM dbo.M_HRD_Employee E
            WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND E.CompanyID=@V_CompanyID AND ISNULL(E.TerminationDate,'')=''
              AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
                  AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
              AND EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL
                  WHERE CL.UserID=E.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@V_CompanyID AND CL.LocationID=@V_LocationID)
        )
    )
    BEGIN RAISERROR('One or more configured Chief Security employees are not active or lack approval access for this location.',16,1); RETURN; END;

    SELECT @V_TechnicianEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))),@V_TechnicianName=ISNULL(Name,@V_OwnerEmployeeID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@V_OwnerEmployeeID;
    SELECT @V_ActorName=ISNULL(NULLIF(LTRIM(RTRIM(Name)),''),@p_ActorEmployeeID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@p_ActorEmployeeID;
    SELECT @V_SPVName=ISNULL(STUFF((SELECT '; '+ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(X.val)) FROM dbo.SplitStringConvertToTable(@V_SPVID,';') X LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val)) ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,2,''),@V_SPVID),
           @V_SPVEmail=ISNULL(STUFF((SELECT ';'+LTRIM(RTRIM(E.emailaddress)) FROM dbo.SplitStringConvertToTable(@V_SPVID,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val)) WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'' ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,''),'');
    SELECT @V_ChiefEngName=ISNULL(STUFF((SELECT '; '+ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(X.val)) FROM dbo.SplitStringConvertToTable(@V_ChiefEngID,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val)) ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,2,''),@V_ChiefEngID),
           @V_ChiefEngEmail=ISNULL(STUFF((SELECT ';'+LTRIM(RTRIM(E.emailaddress)) FROM dbo.SplitStringConvertToTable(@V_ChiefEngID,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val)) WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'' ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,''),'');
    SELECT @V_ChiefSecName=ISNULL(STUFF((SELECT '; '+ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(X.val)) FROM dbo.SplitStringConvertToTable(@V_ChiefSecID,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val)) ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,2,''),@V_ChiefSecID),
           @V_ChiefSecEmail=ISNULL(STUFF((SELECT ';'+LTRIM(RTRIM(E.emailaddress)) FROM dbo.SplitStringConvertToTable(@V_ChiefSecID,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val)) WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'' ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,''),'');

    IF @V_EmailEnabled=1
       AND (
            ISNULL(@V_TechnicianEmail,'')=''
            OR EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_SPVID,';') X WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee E WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''))
            OR EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_ChiefEngID,';') X WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee E WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''))
            OR EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_ChiefSecID,';') X WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee E WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''))
       )
    BEGIN RAISERROR('Email address is missing for Technician, Chief Engineering, or Chief Security. Complete M_HRD_Employee.emailaddress before submitting.',16,1); RETURN; END;

    SELECT @V_ExistingStatus=CASE
        WHEN ISNULL(IsSubmitted,0)=1 THEN CASE WHEN ISNULL(IsApproved2,0)=1 THEN 'ACKNOWLEDGE 2' WHEN ISNULL(IsApproved1,0)=1 THEN 'ACKNOWLEDGE 1' WHEN ISNULL(IsApproved,0)=1 THEN 'VERIFIED' ELSE 'CHECKED' END
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
            IsApproved1=0,Approved1By='',Approved1Date=CONVERT(DATETIME,'19000101',112),
            IsApproved2=0,Approved2By='',Approved2Date=CONVERT(DATETIME,'19000101',112),
            ApprovalRemark='',ReasonVoid='',ReasonVoid1='',ReasonVoid2='',UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
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
            ('LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':SPV',
             @V_EventID,'LIGHTNING',@p_InspectionID,'APPROVER',@V_SPVID,@V_SPVEmail,
             N'Lightning Inspection menunggu verifikasi SPV - '+ISNULL(@V_InspectionNo,'),
             N'<p>Daily Lightning Inspection menunggu verifikasi SPV.</p><p>Teknisi: '+ISNULL(@V_TechnicianName,@V_OwnerEmployeeID)+N' ('+ISNULL(@V_OwnerEmployeeID,'')+N')</p><p>Approver berikutnya: '+ISNULL(@V_SPVName,@V_SPVID)+N' ('+ISNULL(@V_ChiefEngID,'')+N')</p><p>Inspection: '+ISNULL(@V_InspectionNo,'')+
             N'<br/>Type: '+ISNULL(@V_InspectionTypeName,'')+N'<br/>Detail: '+ISNULL(@V_InspectionDetailName,'')+
             N'</p><p><a href="'+ISNULL(@p_ApprovalUrl,N'')+N'&inspectionId='+CONVERT(NVARCHAR(20),@p_InspectionID)+N'">Buka halaman approval INSPEC</a></p>',
             N'Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' milik '+ISNULL(@V_TechnicianName,@V_OwnerEmployeeID)+N' ('+ISNULL(@V_OwnerEmployeeID,'')+N') menunggu approval Chief Engineering '+ISNULL(@V_ChiefEngName,@V_ChiefEngID)+N' ('+ISNULL(@V_ChiefEngID,'')+N'). '+ISNULL(@p_ApprovalUrl,N'')+N'&inspectionId='+CONVERT(NVARCHAR(20),@p_InspectionID),'PENDING',0,GETDATE()),
            ('LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':TECHNICIAN',
             @V_EventID,'LIGHTNING',@p_InspectionID,'TECHNICIAN',@V_OwnerEmployeeID,@V_TechnicianEmail,
             N'Lightning Inspection telah dikirim - '+ISNULL(@V_InspectionNo,''),
             N'<p>Halo '+ISNULL(@V_TechnicianName,@V_OwnerEmployeeID)+N' ('+ISNULL(@V_OwnerEmployeeID,'')+N'), Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' telah dikirim dan berstatus CHECKED. Menunggu review Chief Engineering '+ISNULL(@V_ChiefEngName,@V_ChiefEngID)+N' ('+ISNULL(@V_ChiefEngID,'')+N').</p>',
             N'Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' milik '+ISNULL(@V_TechnicianName,@V_OwnerEmployeeID)+N' ('+ISNULL(@V_OwnerEmployeeID,'')+N') telah dikirim. Menunggu review Chief Engineering '+ISNULL(@V_ChiefEngName,@V_ChiefEngID)+N' ('+ISNULL(@V_ChiefEngID,'')+N'). Status: CHECKED.','PENDING',0,GETDATE());
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
    DECLARE @V_SPVID VARCHAR(4000),@V_ChiefEngID VARCHAR(4000),@V_ChiefSecID VARCHAR(4000);
    DECLARE @V_TechnicianEmail VARCHAR(320),@V_TechnicianName VARCHAR(200),@V_ActorName VARCHAR(200);
    DECLARE @V_EmailEnabled BIT,@V_ConfigScope VARCHAR(30);
    DECLARE @V_NextEmployeeID VARCHAR(4000),@V_NextEmail VARCHAR(4000),@V_NextName VARCHAR(4000);
    DECLARE @V_EventID BIGINT,@V_TranCount INT,@V_NewStatus VARCHAR(30),@V_NextStage VARCHAR(20);

    SELECT @V_CompanyID=I.CompanyID,@V_LocationID=I.LocationID,@V_SectionID=I.SectionID,
           @V_Stage=CASE WHEN ISNULL(I.IsApproved,0)=0 THEN 'SPV' WHEN ISNULL(I.IsApproved1,0)=0 THEN 'CHIEF_ENG' ELSE 'CHIEF_SEC' END,
           @V_OwnerEmployeeID=I.OwnerEmployeeID,@V_InspectionNo=I.InspectionNo
    FROM dbo.PIP_T_Inspection I WITH (UPDLOCK,HOLDLOCK)
    JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
    WHERE I.InspectionID=@p_InspectionID AND ISNULL(IT.InspectionMode,'STANDARD')='LIGHTNING'
      AND ISNULL(I.IsSubmitted,0)=1 AND ISNULL(I.IsApproved2,0)=0
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

    IF (@V_Stage='SPV' AND NOT EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_SPVID,';') X WHERE LTRIM(RTRIM(X.val))=@p_ActorEmployeeID))
       OR (@V_Stage='CHIEF_ENG' AND NOT EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_ChiefEngID,';') X WHERE LTRIM(RTRIM(X.val))=@p_ActorEmployeeID))
       OR (@V_Stage='CHIEF_SEC' AND NOT EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_ChiefSecID,';') X WHERE LTRIM(RTRIM(X.val))=@p_ActorEmployeeID))
    BEGIN RAISERROR('You are not the configured approver for the current Lightning stage.',16,1); RETURN; END;

    SELECT @V_TechnicianEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))),@V_TechnicianName=ISNULL(Name,@V_OwnerEmployeeID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@V_OwnerEmployeeID;
    IF @V_EmailEnabled=1 AND ISNULL(@V_TechnicianEmail,'')=''
    BEGIN RAISERROR('Technician email is missing from M_HRD_Employee.emailaddress.',16,1); RETURN; END;

    IF @p_Action='APPROVE' AND @V_Stage IN ('SPV','CHIEF_ENG')
    BEGIN
        SELECT @V_NextEmployeeID=CASE WHEN @V_Stage='SPV' THEN @V_ChiefEngID ELSE @V_ChiefSecID END;
        SELECT @V_NextEmail=ISNULL(STUFF((SELECT ';'+LTRIM(RTRIM(E.emailaddress)) FROM dbo.SplitStringConvertToTable(@V_NextEmployeeID,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val)) WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'' ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,''),''),
               @V_NextName=ISNULL(STUFF((SELECT '; '+ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(X.val))) FROM dbo.SplitStringConvertToTable(@V_NextEmployeeID,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val)) ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,2,''),@V_NextEmployeeID);
        IF @V_EmailEnabled=1 AND ISNULL(@V_NextEmail,'')=''
        BEGIN RAISERROR('Chief Security email is missing from M_HRD_Employee.emailaddress.',16,1); RETURN; END;
        SET @V_NewStatus=CASE WHEN @V_Stage='SPV' THEN 'VERIFIED' ELSE 'ACKNOWLEDGE 1' END; SET @V_NextStage=CASE WHEN @V_Stage='SPV' THEN 'CHIEF_ENG' ELSE 'CHIEF_SEC' END;
    END
    ELSE IF @p_Action='APPROVE'
    BEGIN
        SET @V_NewStatus='ACKNOWLEDGE 2'; SET @V_NextStage='COMPLETED';
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
                IsApproved1=0,Approved1By='',Approved1Date=CONVERT(DATETIME,'19000101',112),
                IsApproved2=0,Approved2By='',Approved2Date=CONVERT(DATETIME,'19000101',112),
                ApprovalRemark='',
                ReasonVoid=CASE WHEN @V_Stage='SPV' THEN CONVERT(VARCHAR(500),@p_Remark) ELSE ReasonVoid END,
                ReasonVoid1=CASE WHEN @V_Stage='CHIEF_ENG' THEN CONVERT(VARCHAR(500),@p_Remark) ELSE ReasonVoid1 END,
                ReasonVoid2=CASE WHEN @V_Stage='CHIEF_SEC' THEN CONVERT(VARCHAR(500),@p_Remark) ELSE ReasonVoid2 END,
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
                 N'<p>Halo '+ISNULL(@V_TechnicianName,@V_OwnerEmployeeID)+N' ('+ISNULL(@V_OwnerEmployeeID,'')+N'), Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' dikembalikan oleh '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N') untuk koreksi.</p><p>Alasan: '+REPLACE(REPLACE(REPLACE(@p_Remark,N'&',N'&amp;'),N'<',N'&lt;'),N'>',N'&gt;')+
                 N'</p><p><a href="'+ISNULL(@p_CorrectionUrl,N'')+N'">Buka INSPEC untuk memperbaiki dan submit ulang</a></p>',
                 N'Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' dikembalikan oleh '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N'). Alasan: '+@p_Remark+N' '+ISNULL(@p_CorrectionUrl,N''),'PENDING',0,GETDATE());
            END;
        END
        ELSE
        BEGIN
            IF @V_Stage='SPV'
                UPDATE dbo.PIP_T_Inspection
                SET IsApproved=1,ApprovedBy=@p_ActorEmployeeID,ApprovedDate=GETDATE(),
                    ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),
                    UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
                WHERE InspectionID=@p_InspectionID;
            ELSE IF @V_Stage='CHIEF_ENG'
                UPDATE dbo.PIP_T_Inspection SET IsApproved1=1,Approved1By=@p_ActorEmployeeID,Approved1Date=GETDATE(),ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE() WHERE InspectionID=@p_InspectionID;
            ELSE
                UPDATE dbo.PIP_T_Inspection SET IsApproved2=1,Approved2By=@p_ActorEmployeeID,Approved2Date=GETDATE(),ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE() WHERE InspectionID=@p_InspectionID;

            IF @V_EmailEnabled=1
            BEGIN
                INSERT dbo.PIP_T_InspectionEmailOutbox
                (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
                 EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                VALUES
                ('LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':TECHNICIAN',
                 @V_EventID,'LIGHTNING',@p_InspectionID,'TECHNICIAN',@V_OwnerEmployeeID,@V_TechnicianEmail,
                 N'Lightning Inspection approval update - '+ISNULL(@V_InspectionNo,''),
                 N'<p>Halo '+ISNULL(@V_TechnicianName,@V_OwnerEmployeeID)+N' ('+ISNULL(@V_OwnerEmployeeID,'')+N'), Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' telah diproses oleh '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N').</p><p>Status: '+@V_NewStatus+
                 N'</p><p>Stage berikutnya: '+@V_NextStage+N'</p>',
                 N'Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' telah diproses oleh '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N'). Status: '+@V_NewStatus+N'. Stage: '+@V_NextStage,'PENDING',0,GETDATE());

                IF @V_Stage IN ('SPV','CHIEF_ENG')
                    INSERT dbo.PIP_T_InspectionEmailOutbox
                    (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
                     EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                    SELECT
                    'LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+'+CASE WHEN @V_Stage='SPV' THEN ':CHIEF_ENG:' ELSE ':CHIEF_SEC:' END+X.EmployeeID,
                     @V_EventID,'LIGHTNING',@p_InspectionID,'APPROVER',X.EmployeeID,X.EmailAddress,
                     N'Lightning Inspection menunggu approval Chief Security - '+ISNULL(@V_InspectionNo,''),
                     N'<p>Chief Engineering '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N') telah approve. Daily Lightning Inspection menunggu review Chief Security '+ISNULL(X.EmployeeName,X.EmployeeID)+N' ('+ISNULL(X.EmployeeID,'')+N').</p><p><a href="'+ISNULL(@p_ApprovalUrl,N'')+N'&inspectionId='+CONVERT(NVARCHAR(20),@p_InspectionID)+N'">Buka halaman approval INSPEC</a></p>',
                     N'Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' menunggu approval Chief Security '+ISNULL(X.EmployeeName,X.EmployeeID)+N' ('+ISNULL(X.EmployeeID,'')+N') setelah di-approve Chief Engineering '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N'). '+ISNULL(@p_ApprovalUrl,N'')+N'&inspectionId='+CONVERT(NVARCHAR(20),@p_InspectionID),'PENDING',0,GETDATE()
                    FROM
                    (
                      SELECT LTRIM(RTRIM(S.val)) EmployeeID,E.emailaddress EmailAddress,ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(S.val))) EmployeeName
                      FROM dbo.SplitStringConvertToTable(@V_NextEmployeeID,';') S
                      JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(S.val))
                      WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''
                    ) X;
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

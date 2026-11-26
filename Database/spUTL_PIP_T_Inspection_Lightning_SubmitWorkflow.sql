/* LEGACY COPY — DO NOT DEPLOY. The active Lightning submit procedure is deployed from Database/LightningInspection_Approval_Workflow.sql. */

CREATE PROCEDURE dbo.spUTL_PIP_T_Inspection_Lightning_SubmitWorkflow
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
    DECLARE @V_ChiefSecID VARCHAR(4000), @V_ChiefEngID VARCHAR(4000);
    DECLARE @V_ChiefSecSectionID VARCHAR(10),@V_ChiefEngSectionID VARCHAR(10);
    DECLARE @V_EmailEnabled BIT,@V_ConfigScope VARCHAR(30);
    DECLARE @V_TechnicianEmail VARCHAR(320), @V_TechnicianName VARCHAR(200), @V_ActorName VARCHAR(200);
    DECLARE @V_ChiefSecEmail VARCHAR(4000), @V_ChiefSecName VARCHAR(4000);
    DECLARE @V_ChiefEngEmail VARCHAR(4000), @V_ChiefEngName VARCHAR(4000);
    DECLARE @V_ExistingStatus VARCHAR(30), @V_Action VARCHAR(20);
    DECLARE @V_EventID BIGINT, @V_LastActionCode VARCHAR(20), @V_IsActorSPV BIT=0;

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

    SELECT @V_ChiefSecID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';CHIEF_SEC';

    SELECT @V_ChiefEngID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';CHIEF_ENG';

    IF EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_SPVID,';') X WHERE LTRIM(RTRIM(X.val))=@p_ActorEmployeeID)
        SET @V_IsActorSPV=1;

    IF ISNULL(@V_SPVID,'')='' OR ISNULL(@V_ChiefSecID,'')='' OR ISNULL(@V_ChiefEngID,'')=''
    BEGIN RAISERROR('SPV, Chief Security, and Chief Engineering routing must be configured for this Company, Location, and Section.',16,1); RETURN; END;

    SELECT @V_EmailEnabled=CASE WHEN ISNULL(C.Description,'0')='1' THEN 1 ELSE 0 END
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';EMAIL;LIGHTNING';
    SET @V_EmailEnabled=ISNULL(@V_EmailEnabled,0);

    IF EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_SPVID,';') S JOIN dbo.SplitStringConvertToTable(@V_ChiefSecID,';') E ON LTRIM(RTRIM(S.val))=LTRIM(RTRIM(E.val)))
       OR EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_SPVID,';') S JOIN dbo.SplitStringConvertToTable(@V_ChiefEngID,';') C ON LTRIM(RTRIM(S.val))=LTRIM(RTRIM(C.val)))
    BEGIN RAISERROR('SPV, Chief Security, and Chief Engineering must not contain overlapping employees.',16,1); RETURN; END;

    IF EXISTS (
        SELECT 1
        FROM dbo.SplitStringConvertToTable(@V_ChiefSecID,';') E
        JOIN dbo.SplitStringConvertToTable(@V_ChiefEngID,';') S
          ON LTRIM(RTRIM(E.val))=LTRIM(RTRIM(S.val))
    )
    BEGIN RAISERROR('Chief Security and Chief Engineering must not contain the same employee.',16,1); RETURN; END;

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

    SELECT @V_TechnicianEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))),@V_TechnicianName=ISNULL(Name,@V_OwnerEmployeeID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@V_OwnerEmployeeID;
    SELECT @V_ActorName=ISNULL(NULLIF(LTRIM(RTRIM(Name)),''),@p_ActorEmployeeID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@p_ActorEmployeeID;
    SELECT @V_SPVName=ISNULL(STUFF((SELECT '; '+ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(X.val))) FROM dbo.SplitStringConvertToTable(@V_SPVID,';') X LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val)) ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,2,''),@V_SPVID),
           @V_SPVEmail=ISNULL(STUFF((SELECT ';'+LTRIM(RTRIM(E.emailaddress)) FROM dbo.SplitStringConvertToTable(@V_SPVID,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val)) WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'' ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,''),'');
    SELECT @V_ChiefSecName=ISNULL(STUFF((SELECT '; '+ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(X.val))) FROM dbo.SplitStringConvertToTable(@V_ChiefSecID,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val)) ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,2,''),@V_ChiefSecID),
           @V_ChiefSecEmail=ISNULL(STUFF((SELECT ';'+LTRIM(RTRIM(E.emailaddress)) FROM dbo.SplitStringConvertToTable(@V_ChiefSecID,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val)) WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'' ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,''),'');
    SELECT @V_ChiefEngName=ISNULL(STUFF((SELECT '; '+ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(X.val))) FROM dbo.SplitStringConvertToTable(@V_ChiefEngID,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val)) ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,2,''),@V_ChiefEngID),
           @V_ChiefEngEmail=ISNULL(STUFF((SELECT ';'+LTRIM(RTRIM(E.emailaddress)) FROM dbo.SplitStringConvertToTable(@V_ChiefEngID,';') X JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val)) WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'' ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,''),'');

    IF @V_EmailEnabled=1
       AND (
            ISNULL(@V_TechnicianEmail,'')=''
            OR EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_SPVID,';') X WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee E WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''))
            OR EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_ChiefSecID,';') X WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee E WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''))
            OR EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_ChiefEngID,';') X WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee E WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''))
       )
    BEGIN RAISERROR('Email address is missing for Technician, Chief Security, or Chief Engineering. Complete M_HRD_Employee.emailaddress before submitting.',16,1); RETURN; END;

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
    BEGIN TRY
        -- Transaction lifecycle is owned by BRC.PIP_T_WO.SyncInspection().
        UPDATE dbo.PIP_T_Inspection
        SET Status='DONE',IsSubmitted=1,SubmittedBy=@p_ActorEmployeeID,SubmittedDate=GETDATE(),
            IsApproved=CASE WHEN @V_IsActorSPV=1 THEN 1 ELSE 0 END,
            ApprovedBy=CASE WHEN @V_IsActorSPV=1 THEN @p_ActorEmployeeID ELSE '' END,
            ApprovedDate=CASE WHEN @V_IsActorSPV=1 THEN GETDATE() ELSE CONVERT(DATETIME,'19000101',112) END,
            IsApproved1=0,Approved1By='',Approved1Date=CONVERT(DATETIME,'19000101',112),
            IsApproved2=0,Approved2By='',Approved2Date=CONVERT(DATETIME,'19000101',112),
            ApprovalRemark='',ReasonVoid='',ReasonVoid1='',ReasonVoid2='',UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
        WHERE InspectionID=@p_InspectionID;

        INSERT dbo.PIP_T_InspectionApprovalHistory
        (EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
        VALUES ('LIGHTNING',@p_InspectionID,@V_CompanyID,@V_LocationID,@V_SectionID,
                'TECHNICIAN',@V_Action,@p_ActorEmployeeID,GETDATE(),NULL);
        SET @V_EventID=CONVERT(BIGINT,SCOPE_IDENTITY());

        IF @V_IsActorSPV=1
        BEGIN
            INSERT dbo.PIP_T_InspectionApprovalHistory
            (EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
            VALUES ('LIGHTNING',@p_InspectionID,@V_CompanyID,@V_LocationID,@V_SectionID,
                    'SPV','APPROVED',@p_ActorEmployeeID,GETDATE(),N'Auto-approved: inspection owner is a configured SPV.');
            SET @V_EventID=CONVERT(BIGINT,SCOPE_IDENTITY());
        END;

        IF @V_EmailEnabled=1
        BEGIN
            /* One outbox row per configured SPV; RecipientEmployeeID is a single NIK. */
            IF @V_IsActorSPV=0
            INSERT dbo.PIP_T_InspectionEmailOutbox
            (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,ApprovalToken,
             EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
            SELECT
             'LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':SPV:'+X.EmployeeID,
             @V_EventID,'LIGHTNING',@p_InspectionID,'APPROVER',X.EmployeeID,X.EmailAddress,T.ApprovalToken,
             N'Lightning Inspection menunggu verifikasi SPV - '+ISNULL(@V_InspectionNo,''),
             N'<p>Daily Lightning Inspection menunggu verifikasi SPV.</p><p>Teknisi: '+ISNULL(@V_TechnicianName,@V_OwnerEmployeeID)+N' ('+ISNULL(@V_OwnerEmployeeID,'')+N')</p><p>Approver: '+X.EmployeeName+N' ('+X.EmployeeID+N')</p><p>Inspection: '+ISNULL(@V_InspectionNo,'')+
             N'<br/>Type: '+ISNULL(@V_InspectionTypeName,'')+N'<br/>Detail: '+ISNULL(@V_InspectionDetailName,'')+
             N'</p><p><a href="'+ISNULL(@p_ApprovalUrl,N'')+N'&inspectionId='+CONVERT(NVARCHAR(20),@p_InspectionID)+N'&approvalToken='+CONVERT(NVARCHAR(36),T.ApprovalToken)+N'">Buka halaman approval INSPEC</a></p>',
             N'Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' milik '+ISNULL(@V_TechnicianName,@V_OwnerEmployeeID)+N' ('+ISNULL(@V_OwnerEmployeeID,'')+N') menunggu verifikasi SPV '+X.EmployeeName+N' ('+X.EmployeeID+N'). '+ISNULL(@p_ApprovalUrl,N'')+N'&inspectionId='+CONVERT(NVARCHAR(20),@p_InspectionID),
             'PENDING',0,GETDATE()
            FROM
            (
                SELECT LTRIM(RTRIM(S.val)) EmployeeID,
                       LTRIM(RTRIM(E.emailaddress)) EmailAddress,
                       ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(S.val))) EmployeeName
                FROM dbo.SplitStringConvertToTable(@V_SPVID,';') S
                JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(S.val))
                WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''
            ) X
            CROSS APPLY (SELECT NEWID() ApprovalToken) T;

            IF @V_IsActorSPV=1
                INSERT dbo.PIP_T_InspectionEmailOutbox
                (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,ApprovalToken,
                 EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                SELECT 'LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':CHIEF_SEC:'+X.EmployeeID,
                       @V_EventID,'LIGHTNING',@p_InspectionID,'APPROVER',X.EmployeeID,X.EmailAddress,T.ApprovalToken,
                       N'Lightning Inspection menunggu approval Chief Security - '+ISNULL(@V_InspectionNo,''),
                       N'<p>SPV '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N' ('+ISNULL(@p_ActorEmployeeID,'')+N') telah auto-approve inspeksi miliknya. Daily Lightning Inspection menunggu review Chief Security '+X.EmployeeName+N' ('+X.EmployeeID+N').</p><p><a href="'+ISNULL(@p_ApprovalUrl,N'')+N'&inspectionId='+CONVERT(NVARCHAR(20),@p_InspectionID)+N'&approvalToken='+CONVERT(NVARCHAR(36),T.ApprovalToken)+N'">Buka halaman approval INSPEC</a></p>',
                       N'Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' menunggu approval Chief Security '+X.EmployeeName+N' ('+X.EmployeeID+N') setelah auto-approval SPV.',
                       'PENDING',0,GETDATE()
                FROM (SELECT LTRIM(RTRIM(S.val)) EmployeeID,LTRIM(RTRIM(E.emailaddress)) EmailAddress,
                             ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(S.val))) EmployeeName
                      FROM dbo.SplitStringConvertToTable(@V_ChiefSecID,';') S
                      JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(S.val))
                      WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'') X
                CROSS APPLY (SELECT NEWID() ApprovalToken) T;

            INSERT dbo.PIP_T_InspectionEmailOutbox
            (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
             EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
            VALUES
            ('LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':TECHNICIAN',
             @V_EventID,'LIGHTNING',@p_InspectionID,'TECHNICIAN',@V_OwnerEmployeeID,@V_TechnicianEmail,
             CASE WHEN @V_IsActorSPV=1 THEN N'Lightning Inspection SPV verified - ' ELSE N'Lightning Inspection telah dikirim - ' END+ISNULL(@V_InspectionNo,''),
             CASE WHEN @V_IsActorSPV=1 THEN N'<p>Halo '+ISNULL(@V_TechnicianName,@V_OwnerEmployeeID)+N' ('+ISNULL(@V_OwnerEmployeeID,'')+N'), Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' telah diverifikasi otomatis oleh Anda sebagai SPV dan menunggu Chief Security.</p>' ELSE N'<p>Halo '+ISNULL(@V_TechnicianName,@V_OwnerEmployeeID)+N' ('+ISNULL(@V_OwnerEmployeeID,'')+N'), Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' telah dikirim dan berstatus CHECKED. Menunggu verifikasi SPV '+ISNULL(@V_SPVName,@V_SPVID)+N'.</p>' END,
             CASE WHEN @V_IsActorSPV=1 THEN N'Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' telah diverifikasi otomatis oleh SPV dan menunggu Chief Security.' ELSE N'Daily Lightning Inspection '+ISNULL(@V_InspectionNo,'')+N' milik '+ISNULL(@V_TechnicianName,@V_OwnerEmployeeID)+N' ('+ISNULL(@V_OwnerEmployeeID,'')+N') telah dikirim. Menunggu verifikasi SPV '+ISNULL(@V_SPVName,@V_SPVID)+N'. Status: CHECKED.' END,'PENDING',0,GETDATE());
        END;

    END TRY
    BEGIN CATCH
        DECLARE @V_Error NVARCHAR(4000),@V_Severity INT,@V_State INT;
        SELECT @V_Error=ERROR_MESSAGE(),@V_Severity=ERROR_SEVERITY(),@V_State=ERROR_STATE();
        RAISERROR(@V_Error,@V_Severity,@V_State);
    END CATCH;
END;

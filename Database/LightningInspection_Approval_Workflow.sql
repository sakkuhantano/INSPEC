/*
    INSPEC - Lightning approval workflow and email outbox.
    SQL Server 2008 compatible.
    Requires Database/InspectionEmailApproval_Schema.sql and
    Database/LightningInspection_Transaction_Migration.sql.

    Lightning stages:
      TECHNICIAN SUBMITTED -> CHECKED / SPV
      SPV APPROVED         -> VERIFIED / CHIEF_SEC
      CHIEF_SEC APPROVED   -> ACKNOWLEDGE 1 / CHIEF_ENG
      CHIEF_ENG APPROVED   -> ACKNOWLEDGE 2 / COMPLETED
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

    DECLARE @V_CompanyID VARCHAR(10),@V_LocationID VARCHAR(3),@V_SectionID VARCHAR(10);
    DECLARE @V_OwnerEmployeeID VARCHAR(50),@V_InspectionNo VARCHAR(10);
    DECLARE @V_InspectionTypeName VARCHAR(100),@V_InspectionDetailName VARCHAR(100);
    DECLARE @V_SPVID VARCHAR(4000),@V_ChiefSecID VARCHAR(4000),@V_ChiefEngID VARCHAR(4000);
    DECLARE @V_EmailSPV BIT,@V_EmailChiefSec BIT,@V_EmailChiefEng BIT,@V_ConfigScope VARCHAR(30);
    DECLARE @V_TechnicianEmail VARCHAR(320),@V_TechnicianName VARCHAR(200);
    DECLARE @V_SPVEmail VARCHAR(4000),@V_SPVName VARCHAR(4000),@V_ActorName VARCHAR(200);
    DECLARE @V_LastActionCode VARCHAR(20),@V_Action VARCHAR(20),@V_EventID BIGINT;

    SELECT @V_CompanyID=I.CompanyID,@V_LocationID=I.LocationID,@V_SectionID=I.SectionID,
           @V_OwnerEmployeeID=I.OwnerEmployeeID,@V_InspectionNo=I.InspectionNo,
           @V_InspectionTypeName=I.InspectionTypeName,@V_InspectionDetailName=I.InspectionTypeDetailName
    FROM dbo.PIP_T_Inspection I
    JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
    WHERE I.InspectionID=@p_InspectionID
      AND (ISNULL(IT.InspectionMode,'STANDARD')='LIGHTNING'
           OR (ISNULL(IT.InspectionMode,'STANDARD')='BATCH' AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='INSPECT'))
      AND I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=0 AND ISNULL(I.IsApproved,0)=0;

    IF @V_CompanyID IS NULL
    BEGIN RAISERROR('Daily Inspection record was not found or is not eligible for submission.',16,1); RETURN; END;
    IF @V_OwnerEmployeeID<>@p_ActorEmployeeID
    BEGIN RAISERROR('Only the inspection owner can submit this daily inspection.',16,1); RETURN; END;

    SET @V_ConfigScope=CONVERT(VARCHAR(30),@V_CompanyID)+CONVERT(VARCHAR(30),@V_LocationID);
    SET @V_EmailSPV=dbo.fnINSPEC_ApprovalEmailEnabled(@V_CompanyID,@V_LocationID,'BATCH;INSPECT','SPV');
    SET @V_EmailChiefSec=dbo.fnINSPEC_ApprovalEmailEnabled(@V_CompanyID,@V_LocationID,'BATCH;INSPECT','CHIEF_SEC');
    SET @V_EmailChiefEng=dbo.fnINSPEC_ApprovalEmailEnabled(@V_CompanyID,@V_LocationID,'BATCH;INSPECT','CHIEF_ENG');

    SELECT @V_SPVID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';SPV;'+@V_SectionID;
    SELECT @V_ChiefSecID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';CHIEF_SEC';
    SELECT @V_ChiefEngID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';CHIEF_ENG';

    IF ISNULL(@V_SPVID,'')=''
    BEGIN RAISERROR('SPV mapping is required for this Company, Location, and Section. Email flags do not disable approval.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1 FROM dbo.SplitStringConvertToTable(@V_SPVID,';') X
        WHERE NOT EXISTS
        (
            SELECT 1 FROM dbo.M_HRD_Employee E
            WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND E.CompanyID=@V_CompanyID
              AND E.SectionID=@V_SectionID AND ISNULL(E.TerminationDate,'')=''
              AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
                AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
              AND (EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL WHERE CL.UserID=E.EmployeeID
                    AND CL.AppID='pip' AND CL.CompanyID=@V_CompanyID AND CL.LocationID=@V_LocationID)
                   OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip',E.EmployeeID,'') L
                    WHERE L.CompanyID=@V_CompanyID AND L.LocationID=@V_LocationID))
        )
    )
    BEGIN RAISERROR('One or more SPV approvers are inactive or lack Inspection approval access for this Section and location.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1 FROM dbo.SplitStringConvertToTable(ISNULL(@V_ChiefSecID,''),';') X
        WHERE NOT EXISTS
        (
            SELECT 1 FROM dbo.M_HRD_Employee E
            WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND E.CompanyID=@V_CompanyID
              AND ISNULL(E.TerminationDate,'')='' AND E.ProfitCenterNo='PSEC'
              AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
                AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
              AND (EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL WHERE CL.UserID=E.EmployeeID
                    AND CL.AppID='pip' AND CL.CompanyID=@V_CompanyID AND CL.LocationID=@V_LocationID)
                   OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip',E.EmployeeID,'') L
                    WHERE L.CompanyID=@V_CompanyID AND L.LocationID=@V_LocationID))
        )
    )
    BEGIN RAISERROR('One or more configured Chief Security approvers are inactive or lack PSEC approval access for this location.',16,1); RETURN; END;

    IF EXISTS
    (
        SELECT 1 FROM dbo.SplitStringConvertToTable(ISNULL(@V_ChiefEngID,''),';') X
        WHERE NOT EXISTS
        (
            SELECT 1 FROM dbo.M_HRD_Employee E
            WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND E.CompanyID=@V_CompanyID
              AND ISNULL(E.TerminationDate,'')='' AND E.ProfitCenterNo='PENG'
              AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU WHERE SU.EmployeeID=E.EmployeeID AND SU.IsActive=1
                AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') AM WHERE AM.MenuID='20022'))
              AND (EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation CL WHERE CL.UserID=E.EmployeeID
                    AND CL.AppID='pip' AND CL.CompanyID=@V_CompanyID AND CL.LocationID=@V_LocationID)
                   OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip',E.EmployeeID,'') L
                    WHERE L.CompanyID=@V_CompanyID AND L.LocationID=@V_LocationID))
        )
    )
    BEGIN RAISERROR('One or more configured Chief Engineering approvers are inactive or lack PENG approval access for this location.',16,1); RETURN; END;

    IF EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(ISNULL(@V_ChiefSecID,''),';') A
               JOIN dbo.SplitStringConvertToTable(ISNULL(@V_ChiefEngID,''),';') B
                 ON LTRIM(RTRIM(A.val))=LTRIM(RTRIM(B.val)))
    BEGIN RAISERROR('An employee cannot be configured as both Chief Security and Chief Engineering.',16,1); RETURN; END;
    IF EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_SPVID,';') A
               JOIN dbo.SplitStringConvertToTable(ISNULL(@V_ChiefSecID,''),';') B
                 ON LTRIM(RTRIM(A.val))=LTRIM(RTRIM(B.val)))
       OR EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_SPVID,';') A
               JOIN dbo.SplitStringConvertToTable(ISNULL(@V_ChiefEngID,''),';') B
                 ON LTRIM(RTRIM(A.val))=LTRIM(RTRIM(B.val)))
    BEGIN RAISERROR('SPV and Chief approver mappings must not contain overlapping employees.',16,1); RETURN; END;

    SELECT @V_TechnicianEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))),
           @V_TechnicianName=ISNULL(NULLIF(LTRIM(RTRIM(Name)),''),@V_OwnerEmployeeID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@V_OwnerEmployeeID;
    SELECT @V_ActorName=ISNULL(NULLIF(LTRIM(RTRIM(Name)),''),@p_ActorEmployeeID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@p_ActorEmployeeID;
    SELECT @V_SPVName=ISNULL(STUFF((SELECT '; '+ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(X.val))
         FROM dbo.SplitStringConvertToTable(@V_SPVID,';') X
         LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val))
         ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,2,''),@V_SPVID),
           @V_SPVEmail=ISNULL(STUFF((SELECT ';'+LTRIM(RTRIM(E.emailaddress))
         FROM dbo.SplitStringConvertToTable(@V_SPVID,';') X
         JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val))
         WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''
         ORDER BY X.id FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,1,''),'');

    IF @V_EmailSPV=1 AND
       (ISNULL(@V_TechnicianEmail,'')='' OR EXISTS
        (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_SPVID,';') X
         WHERE NOT EXISTS (SELECT 1 FROM dbo.M_HRD_Employee E
                           WHERE E.EmployeeID=LTRIM(RTRIM(X.val)) AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>'')))
    BEGIN RAISERROR('Technician and configured SPV recipients need email addresses while SPV email is enabled.',16,1); RETURN; END;

    SELECT TOP 1 @V_LastActionCode=ActionCode
    FROM dbo.PIP_T_InspectionApprovalHistory
    WHERE EntityType='LIGHTNING' AND EntityID=@p_InspectionID
    ORDER BY ApprovalEventID DESC;
    SET @V_Action=CASE WHEN @V_LastActionCode='VOIDED' THEN 'RESUBMITTED' ELSE 'SUBMITTED' END;

    BEGIN TRY
        UPDATE dbo.PIP_T_Inspection
        SET Status='DONE',IsSubmitted=1,SubmittedBy=@p_ActorEmployeeID,SubmittedDate=GETDATE(),
            IsApproved=0,ApprovedBy='',ApprovedDate=CONVERT(DATETIME,'19000101',112),
            IsApproved1=0,Approved1By='',Approved1Date=CONVERT(DATETIME,'19000101',112),
            IsApproved2=0,Approved2By='',Approved2Date=CONVERT(DATETIME,'19000101',112),
            ApprovalRemark='',ReasonVoid='',ReasonVoid1='',ReasonVoid2='',
            UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
        WHERE InspectionID=@p_InspectionID;

        INSERT dbo.PIP_T_InspectionApprovalHistory
        (EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
        VALUES('LIGHTNING',@p_InspectionID,@V_CompanyID,@V_LocationID,@V_SectionID,
               'TECHNICIAN',@V_Action,@p_ActorEmployeeID,GETDATE(),NULL);
        SET @V_EventID=CONVERT(BIGINT,SCOPE_IDENTITY());

        IF @V_EmailSPV=1
        BEGIN
            INSERT dbo.PIP_T_InspectionEmailOutbox
            (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,ApprovalToken,
             EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
            SELECT 'LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':SPV:'+X.EmployeeID,
                   @V_EventID,'LIGHTNING',@p_InspectionID,'APPROVER',X.EmployeeID,X.EmailAddress,T.ApprovalToken,
                   N'Daily Inspection menunggu verifikasi SPV - '+ISNULL(@V_InspectionNo,''),
                   N'<p>Daily Inspection '+ISNULL(@V_InspectionNo,'')+N' menunggu verifikasi SPV '+X.EmployeeName+N'.</p><p>Teknisi: '+ISNULL(@V_TechnicianName,@V_OwnerEmployeeID)+N' ('+@V_OwnerEmployeeID+N')</p><p><a href="'+ISNULL(@p_ApprovalUrl,N'')+N'&inspectionId='+CONVERT(NVARCHAR(20),@p_InspectionID)+N'&approvalToken='+CONVERT(NVARCHAR(36),T.ApprovalToken)+N'">Buka halaman approval INSPEC</a></p>',
                   N'Daily Inspection '+ISNULL(@V_InspectionNo,'')+N' menunggu verifikasi SPV '+X.EmployeeName+N'. '+ISNULL(@p_ApprovalUrl,N''),
                   'PENDING',0,GETDATE()
            FROM
            (
                SELECT LTRIM(RTRIM(S.val)) EmployeeID,LTRIM(RTRIM(E.emailaddress)) EmailAddress,
                       ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(S.val))) EmployeeName
                FROM dbo.SplitStringConvertToTable(@V_SPVID,';') S
                JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(S.val))
                WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''
            ) X
            CROSS APPLY (SELECT NEWID() ApprovalToken) T;

            INSERT dbo.PIP_T_InspectionEmailOutbox
            (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
             EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
            VALUES('LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':TECHNICIAN',
                   @V_EventID,'LIGHTNING',@p_InspectionID,'TECHNICIAN',@V_OwnerEmployeeID,@V_TechnicianEmail,
                   N'Daily Inspection telah dikirim - '+ISNULL(@V_InspectionNo,''),
                   N'Halo '+ISNULL(@V_TechnicianName,@V_OwnerEmployeeID)+N', Daily Inspection telah dikirim dan menunggu verifikasi SPV.',
                   N'Daily Inspection '+ISNULL(@V_InspectionNo,'')+N' telah dikirim dan menunggu verifikasi SPV.','PENDING',0,GETDATE());
        END;

        SELECT @p_InspectionID InspectionID,'SPV' CurrentStageCode,@V_EventID ApprovalEventID;
    END TRY
    BEGIN CATCH
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
    @p_CorrectionUrl NVARCHAR(1000),
    @p_ApprovalToken UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @p_Action=UPPER(LTRIM(RTRIM(ISNULL(@p_Action,''))));
    SET @p_Remark=LTRIM(RTRIM(ISNULL(@p_Remark,N'')));
    IF @p_Action NOT IN ('APPROVE','VOID')
    BEGIN RAISERROR('Invalid daily Inspection approval action.',16,1); RETURN; END;
    IF @p_Action='VOID' AND @p_Remark=''
    BEGIN RAISERROR('Void reason is required.',16,1); RETURN; END;

    DECLARE @V_CompanyID VARCHAR(10),@V_LocationID VARCHAR(3),@V_SectionID VARCHAR(10);
    DECLARE @V_OwnerEmployeeID VARCHAR(50),@V_InspectionNo VARCHAR(10),@V_Stage VARCHAR(20);
    DECLARE @V_SPVID VARCHAR(4000),@V_ChiefSecID VARCHAR(4000),@V_ChiefEngID VARCHAR(4000);
    DECLARE @V_TechnicianEmail VARCHAR(320),@V_TechnicianName VARCHAR(200),@V_ActorName VARCHAR(200);
    DECLARE @V_EmailSPV BIT,@V_EmailChiefSec BIT,@V_EmailChiefEng BIT,@V_EmailStage BIT,@V_EmailNext BIT;
    DECLARE @V_ConfigScope VARCHAR(30),@V_PreviousActor VARCHAR(50);
    DECLARE @V_NextEmployeeID VARCHAR(4000),@V_NextStage VARCHAR(20),@V_NextEventID BIGINT;
    DECLARE @V_EventID BIGINT,@V_NewStatus VARCHAR(30),@V_CurrentHistoryStage VARCHAR(20);

    SELECT @V_CompanyID=I.CompanyID,@V_LocationID=I.LocationID,@V_SectionID=I.SectionID,
           @V_Stage=CASE WHEN ISNULL(I.IsApproved,0)=0 THEN 'SPV'
                         WHEN ISNULL(I.IsApproved1,0)=0 THEN 'CHIEF_SEC'
                         ELSE 'CHIEF_ENG' END,
           @V_OwnerEmployeeID=I.OwnerEmployeeID,@V_InspectionNo=I.InspectionNo,
           @V_PreviousActor=CASE WHEN ISNULL(I.IsApproved,0)=0 THEN ''
                                 WHEN ISNULL(I.IsApproved1,0)=0 THEN I.ApprovedBy
                                 ELSE ISNULL(NULLIF(I.Approved1By,''),I.ApprovedBy) END
    FROM dbo.PIP_T_Inspection I WITH (UPDLOCK,HOLDLOCK)
    JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
    WHERE I.InspectionID=@p_InspectionID
      AND (ISNULL(IT.InspectionMode,'STANDARD')='LIGHTNING'
           OR (ISNULL(IT.InspectionMode,'STANDARD')='BATCH' AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='INSPECT'))
      AND ISNULL(I.IsSubmitted,0)=1 AND ISNULL(I.IsApproved2,0)=0
      AND ISNULL(I.Status,'')='DONE';

    IF @V_CompanyID IS NULL
    BEGIN RAISERROR('Daily Inspection is not waiting for approval.',16,1); RETURN; END;

    SET @V_ConfigScope=CONVERT(VARCHAR(30),@V_CompanyID)+CONVERT(VARCHAR(30),@V_LocationID);
    SET @V_EmailSPV=dbo.fnINSPEC_ApprovalEmailEnabled(@V_CompanyID,@V_LocationID,'BATCH;INSPECT','SPV');
    SET @V_EmailChiefSec=dbo.fnINSPEC_ApprovalEmailEnabled(@V_CompanyID,@V_LocationID,'BATCH;INSPECT','CHIEF_SEC');
    SET @V_EmailChiefEng=dbo.fnINSPEC_ApprovalEmailEnabled(@V_CompanyID,@V_LocationID,'BATCH;INSPECT','CHIEF_ENG');
    SET @V_EmailStage=CASE @V_Stage WHEN 'SPV' THEN @V_EmailSPV
                                    WHEN 'CHIEF_SEC' THEN @V_EmailChiefSec ELSE @V_EmailChiefEng END;

    SELECT @V_SPVID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';SPV;'+@V_SectionID;
    SELECT @V_ChiefSecID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';CHIEF_SEC';
    SELECT @V_ChiefEngID=NULLIF(LTRIM(RTRIM(C.Description)),'')
    FROM dbo.SysWebCommonValue C
    WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
      AND C.ID=@V_ConfigScope+';CHIEF_ENG';

    IF ISNULL(@V_SPVID,'')=''
    BEGIN RAISERROR('SPV mapping is missing. The SPV approval stage cannot be disabled by email settings.',16,1); RETURN; END;
    IF @V_Stage='CHIEF_SEC' AND ISNULL(@V_ChiefSecID,'')=''
    BEGIN RAISERROR('Chief Security mapping is missing during an active Chief Security stage. Reconcile the inspection approval state before continuing.',16,1); RETURN; END;
    IF @V_Stage='CHIEF_ENG' AND ISNULL(@V_ChiefEngID,'')=''
    BEGIN RAISERROR('Chief Engineering mapping is missing during an active Chief Engineering stage. Reconcile the inspection approval state before continuing.',16,1); RETURN; END;

    IF (@V_Stage='SPV' AND NOT EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_SPVID,';') X WHERE LTRIM(RTRIM(X.val))=@p_ActorEmployeeID))
       OR (@V_Stage='CHIEF_SEC' AND NOT EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_ChiefSecID,';') X WHERE LTRIM(RTRIM(X.val))=@p_ActorEmployeeID))
       OR (@V_Stage='CHIEF_ENG' AND NOT EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@V_ChiefEngID,';') X WHERE LTRIM(RTRIM(X.val))=@p_ActorEmployeeID))
    BEGIN
        IF NOT EXISTS
        (
            SELECT 1 FROM dbo.SysWebUser SU
            JOIN dbo.SysWebUserUserGroup UG ON UG.UserID=SU.UserID
            WHERE SU.EmployeeID=@p_ActorEmployeeID AND SU.IsActive=1
              AND UG.UserGroupID='administrator'
        )
        BEGIN RAISERROR('You are not configured as an approver for the current daily Inspection stage.',16,1); RETURN; END;
    END;

    IF @p_ApprovalToken IS NOT NULL
       AND NOT EXISTS
       (
           SELECT 1
           FROM dbo.PIP_T_InspectionEmailOutbox O
           JOIN dbo.PIP_T_InspectionApprovalHistory H ON H.ApprovalEventID=O.ApprovalEventID
           WHERE O.ApprovalToken=@p_ApprovalToken
             AND O.EntityType='LIGHTNING' AND O.EntityID=@p_InspectionID
             AND O.RecipientType='APPROVER' AND O.RecipientEmployeeID=@p_ActorEmployeeID
             AND O.ApprovalEventID=(SELECT MAX(H2.ApprovalEventID)
                                    FROM dbo.PIP_T_InspectionApprovalHistory H2
                                    WHERE H2.EntityType='LIGHTNING' AND H2.EntityID=@p_InspectionID)
             AND H.StageCode=CASE WHEN @V_Stage='SPV' THEN 'TECHNICIAN'
                                  WHEN @V_Stage='CHIEF_SEC' THEN 'SPV' ELSE 'CHIEF_SEC' END
             AND H.ActionCode IN ('SUBMITTED','RESUBMITTED','APPROVED','SKIPPED')
       )
    BEGIN RAISERROR('This approval email link is invalid, expired, or belongs to another approver.',16,1); RETURN; END;

    SELECT @V_TechnicianEmail=LTRIM(RTRIM(ISNULL(emailaddress,''))),
           @V_TechnicianName=ISNULL(NULLIF(LTRIM(RTRIM(Name)),''),@V_OwnerEmployeeID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@V_OwnerEmployeeID;
    SELECT @V_ActorName=ISNULL(NULLIF(LTRIM(RTRIM(Name)),''),@p_ActorEmployeeID)
    FROM dbo.M_HRD_Employee WHERE EmployeeID=@p_ActorEmployeeID;
    IF @V_EmailStage=1 AND ISNULL(@V_TechnicianEmail,'')=''
    BEGIN RAISERROR('Technician email is missing from M_HRD_Employee.emailaddress while this approval stage email is enabled.',16,1); RETURN; END;

    SET @V_NextEmployeeID='';
    SET @V_NextStage='COMPLETED';
    SET @V_EmailNext=0;
    IF @p_Action='APPROVE'
    BEGIN
        IF @V_Stage='SPV' AND ISNULL(@V_ChiefSecID,'')<>''
        BEGIN
            SET @V_NextEmployeeID=@V_ChiefSecID;
            SET @V_NextStage='CHIEF_SEC';
            SET @V_EmailNext=@V_EmailChiefSec;
        END
        ELSE IF (@V_Stage='SPV' OR @V_Stage='CHIEF_SEC') AND ISNULL(@V_ChiefEngID,'')<>''
        BEGIN
            SET @V_NextEmployeeID=@V_ChiefEngID;
            SET @V_NextStage='CHIEF_ENG';
            SET @V_EmailNext=@V_EmailChiefEng;
        END;

        IF @V_EmailNext=1 AND ISNULL(@V_NextEmployeeID,'')<>''
           AND EXISTS
           (
               SELECT 1 FROM dbo.SplitStringConvertToTable(@V_NextEmployeeID,';') X
               WHERE NOT EXISTS
               (
                   SELECT 1 FROM dbo.M_HRD_Employee E
                   WHERE E.EmployeeID=LTRIM(RTRIM(X.val))
                     AND ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''
               )
           )
        BEGIN RAISERROR('Email address is missing for one or more configured next-stage approvers.',16,1); RETURN; END;
    END;

    BEGIN TRY
        INSERT dbo.PIP_T_InspectionApprovalHistory
        (EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
        VALUES('LIGHTNING',@p_InspectionID,@V_CompanyID,@V_LocationID,@V_SectionID,
               @V_Stage,CASE WHEN @p_Action='APPROVE' THEN 'APPROVED' ELSE 'VOIDED' END,
               @p_ActorEmployeeID,GETDATE(),NULLIF(@p_Remark,N''));
        SET @V_EventID=CONVERT(BIGINT,SCOPE_IDENTITY());
        SET @V_NextEventID=@V_EventID;

        IF @p_ApprovalToken IS NOT NULL
        BEGIN
            UPDATE dbo.PIP_T_InspectionEmailOutbox
            SET ApprovalToken=NULL
            WHERE ApprovalToken=@p_ApprovalToken AND EntityType='LIGHTNING'
              AND EntityID=@p_InspectionID AND RecipientType='APPROVER'
              AND RecipientEmployeeID=@p_ActorEmployeeID;
        END;

        IF @p_Action='VOID'
        BEGIN
            UPDATE dbo.PIP_T_Inspection
            SET Status='DRAFT',IsSubmitted=0,SubmittedBy='',SubmittedDate=CONVERT(DATETIME,'19000101',112),
                IsApproved=0,ApprovedBy='',ApprovedDate=CASE WHEN @V_Stage='SPV' THEN GETDATE() ELSE CONVERT(DATETIME,'19000101',112) END,
                IsApproved1=0,Approved1By='',Approved1Date=CASE WHEN @V_Stage='CHIEF_SEC' THEN GETDATE() ELSE CONVERT(DATETIME,'19000101',112) END,
                IsApproved2=0,Approved2By='',Approved2Date=CASE WHEN @V_Stage='CHIEF_ENG' THEN GETDATE() ELSE CONVERT(DATETIME,'19000101',112) END,
                ApprovalRemark='',
                ReasonVoid=CASE WHEN @V_Stage='SPV' THEN CONVERT(VARCHAR(500),@p_Remark) ELSE ReasonVoid END,
                ReasonVoid1=CASE WHEN @V_Stage='CHIEF_SEC' THEN CONVERT(VARCHAR(500),@p_Remark) ELSE ReasonVoid1 END,
                ReasonVoid2=CASE WHEN @V_Stage='CHIEF_ENG' THEN CONVERT(VARCHAR(500),@p_Remark) ELSE ReasonVoid2 END,
                UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
            WHERE InspectionID=@p_InspectionID;

            IF @V_EmailStage=1
            BEGIN
                INSERT dbo.PIP_T_InspectionEmailOutbox
                (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
                 EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                VALUES('LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':TECHNICIAN',
                       @V_EventID,'LIGHTNING',@p_InspectionID,'TECHNICIAN',@V_OwnerEmployeeID,@V_TechnicianEmail,
                       N'Daily Inspection perlu diperbaiki - '+ISNULL(@V_InspectionNo,''),
                       N'Halo '+ISNULL(@V_TechnicianName,@V_OwnerEmployeeID)+N', Daily Inspection dikembalikan oleh '+@V_Stage+N'. Alasan: '+REPLACE(REPLACE(REPLACE(@p_Remark,N'&',N'&amp;'),N'<',N'&lt;'),N'>',N'&gt;')+N'. <a href="'+ISNULL(@p_CorrectionUrl,N'')+N'">Buka INSPEC untuk koreksi</a>',
                       N'Daily Inspection '+ISNULL(@V_InspectionNo,'')+N' dikembalikan oleh '+@V_Stage+N'. Alasan: '+@p_Remark+N' '+ISNULL(@p_CorrectionUrl,N''),
                       'PENDING',0,GETDATE());
            END;
            SET @V_NewStatus='VOID';
            SET @V_NextStage='TECHNICIAN';
        END
        ELSE
        BEGIN
            IF @V_Stage='SPV'
            BEGIN
                UPDATE dbo.PIP_T_Inspection
                SET IsApproved=1,ApprovedBy=@p_ActorEmployeeID,ApprovedDate=GETDATE(),
                    IsApproved1=CASE WHEN ISNULL(@V_ChiefSecID,'')='' THEN 1 ELSE 0 END,
                    Approved1By=CASE WHEN ISNULL(@V_ChiefSecID,'')='' THEN @p_ActorEmployeeID ELSE '' END,
                    Approved1Date=CASE WHEN ISNULL(@V_ChiefSecID,'')='' THEN GETDATE() ELSE CONVERT(DATETIME,'19000101',112) END,
                    IsApproved2=CASE WHEN ISNULL(@V_ChiefSecID,'')='' AND ISNULL(@V_ChiefEngID,'')='' THEN 1 ELSE 0 END,
                    Approved2By=CASE WHEN ISNULL(@V_ChiefSecID,'')='' AND ISNULL(@V_ChiefEngID,'')='' THEN @p_ActorEmployeeID ELSE '' END,
                    Approved2Date=CASE WHEN ISNULL(@V_ChiefSecID,'')='' AND ISNULL(@V_ChiefEngID,'')='' THEN GETDATE() ELSE CONVERT(DATETIME,'19000101',112) END,
                    ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),ReasonVoid='',ReasonVoid1='',ReasonVoid2='',
                    UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
                WHERE InspectionID=@p_InspectionID;

                IF ISNULL(@V_ChiefSecID,'')=''
                BEGIN
                    INSERT dbo.PIP_T_InspectionApprovalHistory
                    (EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
                    VALUES('LIGHTNING',@p_InspectionID,@V_CompanyID,@V_LocationID,@V_SectionID,'CHIEF_SEC','SKIPPED',
                           @p_ActorEmployeeID,GETDATE(),N'No Chief Security mapping; Approved1By stamped with preceding actual approver.');
                    SET @V_NextEventID=CONVERT(BIGINT,SCOPE_IDENTITY());
                END;
                IF ISNULL(@V_ChiefSecID,'')='' AND ISNULL(@V_ChiefEngID,'')=''
                BEGIN
                    INSERT dbo.PIP_T_InspectionApprovalHistory
                    (EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
                    VALUES('LIGHTNING',@p_InspectionID,@V_CompanyID,@V_LocationID,@V_SectionID,'CHIEF_ENG','SKIPPED',
                           @p_ActorEmployeeID,GETDATE(),N'No Chief Engineering mapping; Approved2By stamped with preceding actual approver.');
                    SET @V_NextEventID=CONVERT(BIGINT,SCOPE_IDENTITY());
                END;
            END
            ELSE IF @V_Stage='CHIEF_SEC'
            BEGIN
                UPDATE dbo.PIP_T_Inspection
                SET IsApproved1=1,Approved1By=@p_ActorEmployeeID,Approved1Date=GETDATE(),
                    IsApproved2=CASE WHEN ISNULL(@V_ChiefEngID,'')='' THEN 1 ELSE 0 END,
                    Approved2By=CASE WHEN ISNULL(@V_ChiefEngID,'')='' THEN @p_ActorEmployeeID ELSE '' END,
                    Approved2Date=CASE WHEN ISNULL(@V_ChiefEngID,'')='' THEN GETDATE() ELSE CONVERT(DATETIME,'19000101',112) END,
                    ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),ReasonVoid1='',ReasonVoid2='',
                    UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
                WHERE InspectionID=@p_InspectionID;
                IF ISNULL(@V_ChiefEngID,'')=''
                BEGIN
                    INSERT dbo.PIP_T_InspectionApprovalHistory
                    (EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
                    VALUES('LIGHTNING',@p_InspectionID,@V_CompanyID,@V_LocationID,@V_SectionID,'CHIEF_ENG','SKIPPED',
                           @p_ActorEmployeeID,GETDATE(),N'No Chief Engineering mapping; Approved2By stamped with preceding actual approver.');
                    SET @V_NextEventID=CONVERT(BIGINT,SCOPE_IDENTITY());
                END;
            END
            ELSE
            BEGIN
                UPDATE dbo.PIP_T_Inspection
                SET IsApproved2=1,Approved2By=@p_ActorEmployeeID,Approved2Date=GETDATE(),
                    ApprovalRemark=CONVERT(VARCHAR(500),@p_Remark),ReasonVoid2='',
                    UpdateUser=@p_ActorEmployeeID,UpdateDate=GETDATE()
                WHERE InspectionID=@p_InspectionID;
            END;

            IF @V_EmailStage=1
            BEGIN
                INSERT dbo.PIP_T_InspectionEmailOutbox
                (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,
                 EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                VALUES('LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_EventID)+':TECHNICIAN',
                       @V_EventID,'LIGHTNING',@p_InspectionID,'TECHNICIAN',@V_OwnerEmployeeID,@V_TechnicianEmail,
                       N'Daily Inspection approval update - '+ISNULL(@V_InspectionNo,''),
                       N'Daily Inspection '+ISNULL(@V_InspectionNo,'')+N' telah diproses oleh '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N'. Status: '+CASE WHEN @V_NextStage='COMPLETED' THEN N'APPROVED' ELSE N'MENUNGGU '+@V_NextStage END+N'.',
                       N'Daily Inspection '+ISNULL(@V_InspectionNo,'')+N' diproses oleh '+ISNULL(@V_ActorName,@p_ActorEmployeeID)+N'.',
                       'PENDING',0,GETDATE());
            END;

            IF @V_EmailNext=1 AND ISNULL(@V_NextEmployeeID,'')<>''
            BEGIN
                INSERT dbo.PIP_T_InspectionEmailOutbox
                (NotificationKey,ApprovalEventID,EntityType,EntityID,RecipientType,RecipientEmployeeID,RecipientEmail,ApprovalToken,
                 EmailSubject,HtmlBody,PlainBody,DeliveryStatus,AttemptCount,NextAttemptDate)
                SELECT 'LIGHTNING:'+CONVERT(VARCHAR(20),@p_InspectionID)+':'+CONVERT(VARCHAR(20),@V_NextEventID)+':'+@V_NextStage+':'+X.EmployeeID,
                       @V_NextEventID,'LIGHTNING',@p_InspectionID,'APPROVER',X.EmployeeID,X.EmailAddress,T.ApprovalToken,
                       N'Daily Inspection menunggu approval '+CASE WHEN @V_NextStage='CHIEF_SEC' THEN N'Chief Security - ' ELSE N'Chief Engineering - ' END+ISNULL(@V_InspectionNo,''),
                       N'Daily Inspection '+ISNULL(@V_InspectionNo,'')+N' telah di-approve oleh '+@V_Stage+N' dan menunggu approval '+@V_NextStage+N' '+X.EmployeeName+N'. <a href="'+ISNULL(@p_ApprovalUrl,N'')+N'&inspectionId='+CONVERT(NVARCHAR(20),@p_InspectionID)+N'&approvalToken='+CONVERT(NVARCHAR(36),T.ApprovalToken)+N'">Buka approval INSPEC</a>',
                       N'Daily Inspection '+ISNULL(@V_InspectionNo,'')+N' menunggu '+@V_NextStage+N' '+X.EmployeeName+N'.',
                       'PENDING',0,GETDATE()
                FROM
                (
                    SELECT LTRIM(RTRIM(S.val)) EmployeeID,LTRIM(RTRIM(E.emailaddress)) EmailAddress,
                           ISNULL(NULLIF(LTRIM(RTRIM(E.Name)),''),LTRIM(RTRIM(S.val))) EmployeeName
                    FROM dbo.SplitStringConvertToTable(@V_NextEmployeeID,';') S
                    JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(S.val))
                    WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''
                ) X
                CROSS APPLY (SELECT NEWID() ApprovalToken) T;
            END;

            SET @V_NewStatus=CASE WHEN @V_NextStage='COMPLETED' THEN 'ACKNOWLEDGE 2' ELSE @V_NextStage END;
        END;

        SELECT @V_NewStatus WorkflowStatus,@V_NextStage CurrentStageCode,
               @V_EventID ApprovalEventID,@V_NextEventID NextStageEventID;
    END TRY
    BEGIN CATCH
        DECLARE @V_Error NVARCHAR(4000),@V_Severity INT,@V_State INT;
        SELECT @V_Error=ERROR_MESSAGE(),@V_Severity=ERROR_SEVERITY(),@V_State=ERROR_STATE();
        RAISERROR(@V_Error,@V_Severity,@V_State);
    END CATCH;
END;
GO

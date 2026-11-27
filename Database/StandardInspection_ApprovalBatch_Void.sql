/*
  Chief STANDARD batch Void. SQL Server 2008 compatible.
  Empty @p_InspectionIDs means Void all remaining members.
  Voided inspections return through GetReturnedInspections as server-backed DRAFT records.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO
IF COL_LENGTH('dbo.PIP_T_Inspection_ApprovalBatch','VoidedBy') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection_ApprovalBatch ADD VoidedBy VARCHAR(50) NOT NULL CONSTRAINT DF_PIP_T_Inspection_ApprovalBatch_VoidedBy DEFAULT ('');
GO
IF COL_LENGTH('dbo.PIP_T_Inspection_ApprovalBatch','VoidedDate') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection_ApprovalBatch ADD VoidedDate DATETIME NULL;
GO
IF COL_LENGTH('dbo.PIP_T_Inspection_ApprovalBatch','VoidRemark') IS NULL
    ALTER TABLE dbo.PIP_T_Inspection_ApprovalBatch ADD VoidRemark NVARCHAR(500) NOT NULL CONSTRAINT DF_PIP_T_Inspection_ApprovalBatch_VoidRemark DEFAULT (N'');
GO
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name='CK_PIP_T_Inspection_ApprovalBatch_BatchStatus' AND parent_object_id=OBJECT_ID('dbo.PIP_T_Inspection_ApprovalBatch'))
    ALTER TABLE dbo.PIP_T_Inspection_ApprovalBatch DROP CONSTRAINT CK_PIP_T_Inspection_ApprovalBatch_BatchStatus;
GO
ALTER TABLE dbo.PIP_T_Inspection_ApprovalBatch WITH CHECK ADD CONSTRAINT CK_PIP_T_Inspection_ApprovalBatch_BatchStatus CHECK (BatchStatus IN ('PENDING','APPROVED','VOID'));
GO
IF OBJECT_ID('dbo.spUTL_PIP_T_Inspection_ApprovalBatch_Void','P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spUTL_PIP_T_Inspection_ApprovalBatch_Void AS RETURN 0;');
GO
ALTER PROCEDURE dbo.spUTL_PIP_T_Inspection_ApprovalBatch_Void
    @p_ApprovalBatchID BIGINT,
    @p_InspectionIDs VARCHAR(4000),
    @p_EmployeeID VARCHAR(50),
    @p_CompanyID VARCHAR(10),
    @p_LocationID VARCHAR(3),
    @p_Remark NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    SET @p_Remark=LTRIM(RTRIM(ISNULL(@p_Remark,N'')));
    IF @p_Remark=N'' BEGIN RAISERROR('Reason Void is required.',16,1); RETURN; END;

    DECLARE @Ids TABLE (InspectionID BIGINT NOT NULL PRIMARY KEY);
    DECLARE @Raw TABLE (Value VARCHAR(50) NOT NULL);
    DECLARE @C VARCHAR(10),@L VARCHAR(3),@S VARCHAR(10),@PC VARCHAR(20),
            @Role VARCHAR(20),@Chief VARCHAR(4000),@Status VARCHAR(20),
            @VoidCount INT,@Remaining INT;

    IF LTRIM(RTRIM(ISNULL(@p_InspectionIDs,'')))<>''
    BEGIN
        INSERT @Raw(Value) SELECT LTRIM(RTRIM(val)) FROM dbo.SplitStringConvertToTable(@p_InspectionIDs,',') WHERE LTRIM(RTRIM(val))<>'';
        IF EXISTS(SELECT 1 FROM @Raw WHERE Value LIKE '%[^0-9]%') OR (SELECT COUNT(*) FROM @Raw)=0 OR (SELECT COUNT(*) FROM @Raw)>200
        BEGIN RAISERROR('Selected InspectionID list is invalid.',16,1); RETURN; END;
        INSERT @Ids SELECT CONVERT(BIGINT,Value) FROM @Raw;
        IF (SELECT COUNT(*) FROM @Ids)<>(SELECT COUNT(*) FROM @Raw)
        BEGIN RAISERROR('Duplicate InspectionID values are not allowed.',16,1); RETURN; END;
    END;

    BEGIN TRY
      BEGIN TRANSACTION;
      SELECT @C=CompanyID,@L=LocationID,@S=SectionID,@PC=ProfitCenterNo,@Status=BatchStatus
      FROM dbo.PIP_T_Inspection_ApprovalBatch WITH (UPDLOCK,HOLDLOCK)
      WHERE ApprovalBatchID=@p_ApprovalBatchID;
      IF @C IS NULL OR @Status<>'PENDING'
          RAISERROR('Void is allowed only while the approval batch is Pending. Approved batches cannot be voided.',16,1);
      IF @C<>@p_CompanyID OR @L<>@p_LocationID
          RAISERROR('Approval batch is outside the logged-in Company/Location.',16,1);

      SET @Role=CASE UPPER(LTRIM(RTRIM(ISNULL(@PC,'')))) WHEN 'PENG' THEN 'CHIEF_ENG' WHEN 'PSEC' THEN 'CHIEF_SEC' WHEN 'PHKP' THEN 'CHIEF_HK' ELSE '' END;
      SELECT @Chief=NULLIF(LTRIM(RTRIM(C.Description)),'')
      FROM dbo.SysWebCommonValue C
      WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=@C+@L+';'+@Role;
      IF ISNULL(@Role,'')='' OR ISNULL(@Chief,'')=''
          RAISERROR('Current CHIEF approver configuration is missing.',16,1);

      IF NOT EXISTS
      (
        SELECT 1 FROM dbo.SysWebUser SU
        WHERE SU.EmployeeID=@p_EmployeeID AND SU.IsActive=1
          AND EXISTS(SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',SU.EmployeeID,'') M WHERE M.MenuID='20022')
          AND EXISTS(SELECT 1 FROM dbo.SplitStringConvertToTable(@Chief,';') X WHERE LTRIM(RTRIM(X.val))=@p_EmployeeID)
          AND EXISTS(SELECT 1 FROM dbo.M_HRD_Employee E WHERE E.EmployeeID=@p_EmployeeID AND E.CompanyID=@C AND ISNULL(E.TerminationDate,'')='')
          AND (EXISTS(SELECT 1 FROM dbo.SysWebUserCompanyLocation CL WHERE CL.UserID=SU.EmployeeID AND CL.AppID='pip' AND CL.CompanyID=@C AND CL.LocationID=@L)
               OR EXISTS(SELECT 1 FROM dbo.F_SelectOneLogin('pip',SU.EmployeeID,'') L WHERE L.CompanyID=@C AND L.LocationID=@L))
      )
          RAISERROR('Employee is not an authorized CHIEF approver for this batch.',16,1);

      IF NOT EXISTS(SELECT 1 FROM dbo.PIP_T_Inspection WHERE ApprovalBatchID=@p_ApprovalBatchID)
          RAISERROR('This batch has no remaining inspections.',16,1);
      IF EXISTS
      (
        SELECT 1 FROM dbo.PIP_T_Inspection I
        LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
        WHERE I.ApprovalBatchID=@p_ApprovalBatchID
          AND (I.CompanyID<>@C OR I.LocationID<>@L OR I.SectionID<>@S OR ISNULL(I.IsActive,1)<>1
               OR I.Status<>'DONE' OR ISNULL(I.IsSubmitted,0)<>1 OR ISNULL(I.IsApproved,0)<>1
               OR ISNULL(I.IsApproved1,0)=1 OR ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')<>'STANDARD')
      )
          RAISERROR('Batch contains an inspection that is not in the expected SPV-approved Pending state.',16,1);

      IF NOT EXISTS(SELECT 1 FROM @Ids)
          INSERT @Ids SELECT InspectionID FROM dbo.PIP_T_Inspection WITH (UPDLOCK,HOLDLOCK) WHERE ApprovalBatchID=@p_ApprovalBatchID;
      ELSE IF EXISTS
      (
        SELECT 1 FROM @Ids X
        WHERE NOT EXISTS(SELECT 1 FROM dbo.PIP_T_Inspection I WITH (UPDLOCK,HOLDLOCK)
                         WHERE I.InspectionID=X.InspectionID AND I.ApprovalBatchID=@p_ApprovalBatchID
                           AND I.CompanyID=@C AND I.LocationID=@L AND I.SectionID=@S
                           AND I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=1 AND ISNULL(I.IsApproved,0)=1 AND ISNULL(I.IsApproved1,0)=0)
      )
          RAISERROR('One or more selected inspections are not active members of this Pending batch.',16,1);

      SELECT @VoidCount=COUNT(*) FROM @Ids;
      IF ISNULL(@VoidCount,0)=0 RAISERROR('No inspections were selected for Void.',16,1);

      INSERT dbo.PIP_T_InspectionApprovalHistory
        (EntityType,EntityID,CompanyID,LocationID,SectionID,StageCode,ActionCode,ActorEmployeeID,ActionDate,Remark)
      SELECT 'INSPECTION',I.InspectionID,@C,@L,@S,@Role,'VOIDED',@p_EmployeeID,GETDATE(),@p_Remark
      FROM dbo.PIP_T_Inspection I JOIN @Ids X ON X.InspectionID=I.InspectionID;

      UPDATE I
      SET Status='DRAFT',IsSubmitted=0,SubmittedBy='',SubmittedDate=CONVERT(DATETIME,'19000101',112),
          IsApproved=0,ApprovedBy='',ApprovedDate=CONVERT(DATETIME,'19000101',112),
          IsApproved1=0,Approved1By='',Approved1Date=CONVERT(DATETIME,'19000101',112),
          IsApproved2=0,Approved2By='',Approved2Date=CONVERT(DATETIME,'19000101',112),
          ApprovalRemark='',ReasonVoid=@p_Remark,ReasonVoid1=@p_Remark,ReasonVoid2='',
          ApprovalBatchID=NULL,UpdateUser=@p_EmployeeID,UpdateDate=GETDATE()
      FROM dbo.PIP_T_Inspection I JOIN @Ids X ON X.InspectionID=I.InspectionID
      WHERE I.ApprovalBatchID=@p_ApprovalBatchID;
      IF @@ROWCOUNT<>@VoidCount RAISERROR('Some inspections could not be returned to the technician. No Void was committed.',16,1);

      SELECT @Remaining=COUNT(*) FROM dbo.PIP_T_Inspection WHERE ApprovalBatchID=@p_ApprovalBatchID;
      UPDATE dbo.PIP_T_Inspection_ApprovalBatch
      SET BatchStatus=CASE WHEN @Remaining=0 THEN 'VOID' ELSE 'PENDING' END,
          VoidedBy=@p_EmployeeID,VoidedDate=GETDATE(),VoidRemark=@p_Remark
      WHERE ApprovalBatchID=@p_ApprovalBatchID AND BatchStatus='PENDING';
      IF @@ROWCOUNT<>1 RAISERROR('Batch status changed during Void. Refresh and try again.',16,1);

      COMMIT TRANSACTION;
      SELECT @p_ApprovalBatchID ApprovalBatchID,@VoidCount VoidCount,@Remaining RemainingCount,
             CASE WHEN @Remaining=0 THEN 'VOID' ELSE 'PENDING' END BatchStatus;
    END TRY
    BEGIN CATCH
      IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
      DECLARE @Err NVARCHAR(4000),@Sev INT,@State INT;
      SELECT @Err=ERROR_MESSAGE(),@Sev=ERROR_SEVERITY(),@State=ERROR_STATE();
      RAISERROR(@Err,@Sev,@State); RETURN;
    END CATCH;
END;
GO

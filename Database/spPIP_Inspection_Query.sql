IF OBJECT_ID('dbo.spPIP_Inspection_Query', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spPIP_Inspection_Query AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spPIP_Inspection_Query
    @p_Tipe VARCHAR(3),
    @p_IDTemplate INT = NULL,
    @p_IDVersion INT = NULL,
    @p_CompanyID VARCHAR(50) = NULL,
    @p_LocationID VARCHAR(50) = NULL,
    @p_UserID VARCHAR(50) = NULL,
    @p_EmployeeID VARCHAR(50) = NULL,
    @p_SectionID VARCHAR(50) = NULL,
    @p_InspectionTypeCode VARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    /*
      Central read/query dispatcher for INSPEC.
      001 = Template access / return SectionID
      002 = Version access / return IDTemplate
      003 = Template Versions
      004 = Version Structure (7 result sets)
    */

    IF @p_Tipe = '001'
    BEGIN
        SELECT TOP 1 SectionID
        FROM dbo.PIP_M_CheckListWOPM
        WHERE IDTemplate = @p_IDTemplate
          AND (
              ISNULL(CompanyScope, 'S') = 'A'
              OR (';' + ISNULL(CompanyLocationList, '') + ';'
                  LIKE '%;' + ISNULL(@p_CompanyID, '') + ISNULL(@p_LocationID, '') + ';%')
          );
        RETURN;
    END;

    IF @p_Tipe = '002'
    BEGIN
        SELECT TOP 1 IDTemplate
        FROM dbo.PIP_M_CheckListWOPM_Version
        WHERE IDVersion = @p_IDVersion;
        RETURN;
    END;

    IF @p_Tipe = '003'
    BEGIN
        SELECT
            a.IDVersion,
            a.Version,
            a.[Status],
            a.EffectiveDate,
            a.StatusOption,
            a.Remark,
            RuntimeVersionID = a.IDVersion,
            a.GroupEquipment,
            a.RemarkRequiredOptions,
            a.SummarySampleText,
            a.IsRemark1Required,
            a.Remark1Text,
            a.IsRemark2Required,
            a.Remark2Text,
            ISNULL(a.PhotoRequirement,'NONE') PhotoRequirement,
            ISNULL(a.IsSummaryRequired,1) IsSummaryRequired,
            ISNULL(a.IsFollowUpRequired,1) IsFollowUpRequired
        FROM dbo.PIP_M_CheckListWOPM_Version a
        WHERE a.IDTemplate = @p_IDTemplate;
        RETURN;
    END;

    IF @p_Tipe = '005'
    BEGIN
        SELECT
            aa.val SectionID,
            TotalTemplate = ISNULL((
                SELECT COUNT(*)
                FROM dbo.PIP_M_CheckListWOPM bb
                WHERE bb.SectionID = aa.val
                  AND (
                      ISNULL(bb.CompanyScope, 'S') = 'A'
                      OR (';' + ISNULL(bb.CompanyLocationList, '') + ';'
                          LIKE '%;' + ISNULL(@p_CompanyID, '') + ISNULL(@p_LocationID, '') + ';%')
                  )
            ), 0)
        FROM dbo.SplitStringConvertToTable(@p_SectionID, ';') aa
        WHERE (
            EXISTS (
                SELECT 1
                FROM dbo.SysWebUserCompanyLocation perm
                WHERE perm.AppID = 'INSPEC'
                  AND perm.UserID = @p_UserID
                  AND perm.CompanyID = @p_CompanyID
                  AND perm.LocationID = @p_LocationID
            )
            OR EXISTS (
                SELECT 1
                FROM dbo.F_SelectOneLogin('INSPEC', @p_EmployeeID, '') loginCompany
                WHERE loginCompany.CompanyID = @p_CompanyID
                  AND loginCompany.LocationID = @p_LocationID
            )
        );
        RETURN;
    END;

    IF @p_Tipe = '006'
    BEGIN
        SELECT InspectionTypeCode, InspectionTypeName, SectionID, IsActive
        FROM dbo.PIP_M_InspectionType
        WHERE SectionID=@p_SectionID AND IsActive=1
        ORDER BY InspectionTypeName;
        RETURN;
    END;

    IF @p_Tipe = '007'
    BEGIN
        SELECT
            T.SectionID,
            D.InspectionTypeDetailCode,
            D.InspectionTypeDetailName
        FROM dbo.PIP_M_InspectionType T
        JOIN dbo.PIP_M_InspectionTypeDetail D
          ON D.InspectionTypeCode=T.InspectionTypeCode
         AND D.IsActive=1
        WHERE T.InspectionTypeCode=@p_InspectionTypeCode
          AND T.IsActive=1
        ORDER BY D.InspectionTypeDetailName, D.InspectionTypeDetailCode;
        RETURN;
    END;

    IF @p_Tipe = '008'
    BEGIN
        SELECT
            a.IDTemplate,
            a.TemplateNo,
            a.TemplateName,
            a.IsActive,
            a.SectionID,
            a.TemplateType,
            a.InspectionTypeCode,
            ISNULL(a.InspectionTypeDetailCode,'') InspectionTypeDetailCode,
            a.CompanyScope,
            HasActiveVersion = CAST(CASE WHEN EXISTS (
                SELECT 1 FROM dbo.PIP_M_CheckListWOPM_Version aa
                WHERE aa.IDTemplate=a.IDTemplate AND aa.Status='Active'
            ) THEN 1 ELSE 0 END AS BIT),
            CanDeleted = CAST(CASE WHEN NOT EXISTS (
                SELECT 1 FROM dbo.PIP_M_CheckListWOPM_Version aa
                WHERE aa.IDTemplate=a.IDTemplate AND aa.Status='Active'
            ) THEN 1 ELSE 0 END AS BIT),
            RuntimeTemplateID=a.IDTemplate
        FROM dbo.PIP_M_CheckListWOPM a
        WHERE a.SectionID=@p_SectionID
          AND (
              EXISTS (
                  SELECT 1 FROM dbo.SysWebUserCompanyLocation perm
                  WHERE perm.AppID='INSPEC' AND perm.UserID=@p_UserID
                    AND perm.CompanyID=@p_CompanyID AND perm.LocationID=@p_LocationID
              )
              OR EXISTS (
                  SELECT 1 FROM dbo.F_SelectOneLogin('INSPEC', @p_EmployeeID, '') loginCompany
                  WHERE loginCompany.CompanyID=@p_CompanyID AND loginCompany.LocationID=@p_LocationID
              )
          )
          AND (
              ISNULL(a.CompanyScope,'S')='A'
              OR (';' + ISNULL(a.CompanyLocationList,'') + ';'
                  LIKE '%;' + @p_CompanyID + @p_LocationID + ';%')
          );
        RETURN;
    END;

    IF @p_Tipe = '009'
    BEGIN
        SELECT
            L.CompanyID, L.LocationID, L.CompanyName, L.LocationName,
            IsAssigned=CAST(CASE
                WHEN T.IDTemplate IS NOT NULL
                 AND (';' + ISNULL(T.CompanyLocationList,'') + ';'
                      LIKE '%;' + L.CompanyID + L.LocationID + ';%') THEN 1
                WHEN @p_IDTemplate<=0
                 AND L.CompanyID=@p_CompanyID AND L.LocationID=@p_LocationID THEN 1
                ELSE 0 END AS BIT)
        FROM (
            SELECT swc.CompanyID, swl.LocationID, swc.CompanyName, swl.LocationName
            FROM dbo.SysWebLocation swl
            JOIN dbo.SysWebCompany swc ON swc.CompanyID=swl.CompanyID
            WHERE swc.IsActive=1 AND swl.IsActive=1
              AND (
                  EXISTS (
                      SELECT 1 FROM dbo.SysWebUserCompanyLocation perm
                      WHERE perm.CompanyID=swl.CompanyID AND perm.LocationID=swl.LocationID
                        AND perm.UserID=@p_UserID AND perm.AppID='INSPEC'
                  )
                  OR EXISTS (
                      SELECT 1 FROM dbo.F_SelectOneLogin('INSPEC', @p_EmployeeID, '') LoginCompany
                      WHERE LoginCompany.CompanyID=swl.CompanyID
                        AND LoginCompany.LocationID=swl.LocationID
                  )
              )
        ) L
        LEFT JOIN dbo.PIP_M_CheckListWOPM T ON T.IDTemplate=@p_IDTemplate
        WHERE (
            EXISTS (
                SELECT 1 FROM dbo.SysWebUserCompanyLocation CurrentPermission
                WHERE CurrentPermission.AppID='INSPEC' AND CurrentPermission.UserID=@p_UserID
                  AND CurrentPermission.CompanyID=@p_CompanyID
                  AND CurrentPermission.LocationID=@p_LocationID
            )
            OR EXISTS (
                SELECT 1 FROM dbo.F_SelectOneLogin('INSPEC', @p_EmployeeID, '') LoginCompany
                WHERE LoginCompany.CompanyID=@p_CompanyID AND LoginCompany.LocationID=@p_LocationID
            )
        )
        AND (
            @p_IDTemplate<=0
            OR EXISTS (
                SELECT 1 FROM dbo.PIP_M_CheckListWOPM T
                WHERE T.IDTemplate=@p_IDTemplate
                  AND (ISNULL(T.CompanyScope,'S')='A'
                       OR (';' + ISNULL(T.CompanyLocationList,'') + ';'
                           LIKE '%;' + @p_CompanyID + @p_LocationID + ';%'))
            )
        )
        ORDER BY L.CompanyID, L.LocationID;
        RETURN;
    END;

    IF @p_Tipe = '010'
    BEGIN
        SELECT SectionID
        FROM dbo.PIP_M_CheckListWOPM
        WHERE IDTemplate=@p_IDTemplate;
        RETURN;
    END;

    IF @p_Tipe = '011'
    BEGIN
        SELECT
            E.EmployeeID, E.Name, E.CompanyID, E.LocationID,
            IsAssigned=CAST(CASE
                WHEN ISNULL(T.EmployeeList,'')=''
                  OR (';' + REPLACE(ISNULL(T.EmployeeList,''),':',';') + ';'
                      LIKE '%;' + E.EmployeeID + ';%')
                THEN 1 ELSE 0 END AS BIT),
            swc.BuildingName
        FROM dbo.M_HRD_Employee E
        JOIN dbo.SysWebCompany swc ON swc.CompanyID=E.CompanyID
        JOIN dbo.PIP_M_CheckListWOPM T ON T.IDTemplate=@p_IDTemplate
        WHERE E.SectionID=T.SectionID
          AND E.SectionID=@p_SectionID
          AND T.TemplateType='I'
          AND ISNULL(E.TerminationDate,'')=''
          AND (
              EXISTS (
                  SELECT 1 FROM dbo.SysWebUserCompanyLocation CurrentPermission
                  WHERE CurrentPermission.AppID='INSPEC'
                    AND CurrentPermission.UserID=(SELECT TOP 1 SU.UserID FROM dbo.SysWebUser SU WHERE SU.employeeid=E.EmployeeID)
                    AND CurrentPermission.CompanyID=@p_CompanyID
                    AND CurrentPermission.LocationID=@p_LocationID
              )
              OR EXISTS (
                  SELECT 1 FROM dbo.F_SelectOneLogin('INSPEC', E.EmployeeID, '') LoginCompany
                  WHERE LoginCompany.CompanyID=@p_CompanyID
                    AND LoginCompany.LocationID=@p_LocationID
              )
          )
          AND (
              ISNULL(T.CompanyScope,'S')='A'
              OR (';' + ISNULL(T.CompanyLocationList,'') + ';'
                  LIKE '%;' + @p_CompanyID + @p_LocationID + ';%')
          )
        ORDER BY E.CompanyID, E.LocationID, E.EmployeeID;
        RETURN;
    END;

    IF @p_Tipe = '012'
    BEGIN
        SELECT GroupEquipment, Description
        FROM dbo.PIP_M_GroupEquipment B
        WHERE B.CompanyID=@p_CompanyID
          AND B.LocationID=@p_LocationID
          AND B.SectionID=@p_SectionID;
        RETURN;
    END;

    IF @p_Tipe = '013'
    BEGIN
        SELECT
            B.SectionID,
            A.ModelCode,
            A.Remark
        FROM dbo.PIP_M_GroupEquipment_Model A
        JOIN dbo.PIP_M_GroupEquipment B ON A.ID=B.ID
        WHERE B.CompanyID=@p_CompanyID
          AND B.LocationID=@p_LocationID
          AND B.GroupEquipment=@p_InspectionTypeCode;
        RETURN;
    END;

    IF @p_Tipe = '004'
    BEGIN
        SELECT
            IDVersion,
            A.IDTemplate,
            B.TemplateNo,
            B.TemplateName,
            A.Version,
            A.Status,
            A.EffectiveDate,
            A.Remark,
            A.StatusOption StatusOptionRaw,
            A.GroupEquipment,
            A.RemarkRequiredOptions RemarkRequiredOptionsRaw,
            A.SummarySampleText,
            A.IsRemark1Required,
            A.Remark1Text,
            A.IsRemark2Required,
            A.Remark2Text,
            ISNULL(A.PhotoRequirement,'NONE') PhotoRequirement,
            ISNULL(A.IsSummaryRequired,1) IsSummaryRequired,
            ISNULL(A.IsFollowUpRequired,1) IsFollowUpRequired
        FROM dbo.PIP_M_CheckListWOPM_Version A
        JOIN dbo.PIP_M_CheckListWOPM B ON B.IDTemplate = A.IDTemplate
        WHERE IDVersion = @p_IDVersion;

        SELECT IDSection, SectionName, DisplayOrder
        FROM dbo.PIP_M_CheckListWOPM_Section
        WHERE IDVersion = @p_IDVersion
        ORDER BY DisplayOrder;

        SELECT
            A.IDItem,
            A.IDSection,
            A.IDSubSection,
            A.ItemLabel,
            A.ItemType,
            A.DisplayOrder,
            A.Unit,
            A.IsRemark1Required,
            A.IsRemark2Required,
            A.IsRemark1Mandatory,
            A.IsRemark2Mandatory,
            A.Remark1Text,
            A.Remark2Text,
            A.IsUseDefaultRemark1,
            A.IsUseDefaultRemark2,
            A.IsValueRequired,
            A.ShowUnitInRange,
            UseDefaultOption = CAST(
                CASE WHEN A.ItemType='OPTION' AND ISNULL(A.OptionList,'')='' THEN 1 ELSE 0 END
                AS BIT),
            A.OptionList OptionListRaw,
            A.RemarkRequiredOptions RemarkRequiredOptionsRaw,
            A.MinValue,
            A.MaxValue,
            A.MinTolerance,
            A.MaxTolerance,
            A.ModelCode,
            A.IsToleranceRequired
        FROM dbo.PIP_M_CheckListWOPM_Item A
        JOIN dbo.PIP_M_CheckListWOPM_Section B ON B.IDSection = A.IDSection
        WHERE B.IDVersion = @p_IDVersion
        ORDER BY A.DisplayOrder;

        SELECT
            A.IDGroup,
            A.IDItem,
            A.GroupName,
            FieldListRaw = A.FieldList,
            A.Unit,
            A.DisplayOrder
        FROM dbo.PIP_M_CheckListWOPM_ItemGroup A
        JOIN dbo.PIP_M_CheckListWOPM_Item B ON B.IDItem = A.IDItem
        JOIN dbo.PIP_M_CheckListWOPM_Section C ON C.IDSection = B.IDSection
        WHERE C.IDVersion = @p_IDVersion
        ORDER BY A.DisplayOrder;

        SELECT
            SS.IDSubSection,
            SS.IDSection,
            SS.SubSectionName,
            SS.DisplayOrder
        FROM dbo.PIP_M_CheckListWOPM_SubSection SS
        JOIN dbo.PIP_M_CheckListWOPM_Section SEC ON SEC.IDSection = SS.IDSection
        WHERE SEC.IDVersion = @p_IDVersion
        ORDER BY SS.DisplayOrder;

        SELECT
            R.IDItem,
            R.RepeatMode,
            R.ColumnCount,
            R.ObjectLabel,
            R.CountMode,
            R.FixedCount,
            R.MinCount,
            R.MaxCount
        FROM dbo.PIP_M_CheckListWOPM_ItemRepeat R
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem = R.IDItem
        JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection = I.IDSection
        WHERE S.IDVersion = @p_IDVersion;

        SELECT
            F.IDItem,
            F.IDRepeat,
            F.FieldLabel,
            F.FieldType,
            F.OptionList,
            F.Unit,
            F.MinValue,
            F.MaxValue,
            F.IsRequired,
            F.GroupName,
            F.DisplayOrder,
            F.MinInclusive,
            F.MaxInclusive
        FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem = F.IDItem
        JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection = I.IDSection
        WHERE S.IDVersion = @p_IDVersion
        ORDER BY F.IDItem, F.DisplayOrder, F.IDRepeat;

        RETURN;
    END;

    IF @p_Tipe = '023'
    BEGIN
        
        SELECT TOP 1 1
        FROM dbo.SysWebUser SU
        JOIN dbo.SysWebUserUserGroup UG ON UG.UserID=SU.UserID
        WHERE SU.EmployeeID=@UserID
          AND SU.IsActive=1
          AND UG.UserGroupID='administrator'
        RETURN;
    END;

    IF @p_Tipe = '014'
    BEGIN
        
        SELECT T.IDTemplate
        FROM dbo.PIP_M_CheckListWOPM T
        WHERE T.IDTemplate=@IDTemplate
          AND T.SectionID=@SectionID
          AND T.TemplateType='I'
          
          AND (ISNULL(T.CompanyScope,'S')='A'
               OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + @CompanyID + @LocationID + ';%'))
          AND (ISNULL(T.EmployeeList,'')=''
               OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + @EmployeeID + ';%'))
          AND EXISTS (
               SELECT 1 FROM dbo.PIP_M_CheckListWOPM_Version V
               WHERE V.IDTemplate=T.IDTemplate
                 AND V.IDVersion=@IDVersion
                 AND V.Version=@TemplateVersion
                 AND V.Status IN ('Active','Archieved')
          )
          AND T.InspectionTypeCode=@InspectionTypeCode
          AND EXISTS (
               SELECT 1 FROM dbo.PIP_M_InspectionType IT
               WHERE IT.InspectionTypeCode=@InspectionTypeCode
                 AND IT.SectionID=@SectionID
                 AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')=@InspectionMode
          )
          AND (
               ISNULL(T.InspectionTypeDetailCode,'')=''
               OR EXISTS (
                   SELECT 1
                   FROM dbo.SplitStringConvertToTable(T.InspectionTypeDetailCode, ';') AllowedDetail
                   WHERE LTRIM(RTRIM(AllowedDetail.val))=@InspectionTypeDetailCode
               )
          )
        RETURN;
    END;

    IF @p_Tipe = '015'
    BEGIN
        
        SELECT ISNULL(V.PhotoRequirement,'NONE') PhotoRequirement,
               ISNULL(V.IsSummaryRequired,1) IsSummaryRequired,
               ISNULL(V.IsFollowUpRequired,1) IsFollowUpRequired,
               ISNULL(V.IsRemark1Required,0) IsRemark1Required,
               ISNULL(V.IsRemark2Required,0) IsRemark2Required,
               ISNULL(V.StatusOption,'') StatusOption,
               ISNULL(V.RemarkRequiredOptions,'') RemarkRequiredOptions
        FROM dbo.PIP_M_CheckListWOPM_Version V
        WHERE V.IDTemplate=@IDTemplate AND V.IDVersion=@IDVersion
        RETURN;
    END;

    IF @p_Tipe = '016'
    BEGIN
        
        SELECT I.IDItem, I.ItemLabel, I.ItemType, ISNULL(I.OptionList,'') OptionList,
               ISNULL(I.IsValueRequired,0) IsValueRequired,
               ISNULL(I.IsRemark1Required,0) IsRemark1Required,
               ISNULL(I.IsRemark2Required,0) IsRemark2Required,
               ISNULL(I.IsRemark1Mandatory,0) IsRemark1Mandatory,
               ISNULL(I.IsRemark2Mandatory,0) IsRemark2Mandatory,
               ISNULL(I.IsUseDefaultRemark1,0) IsUseDefaultRemark1,
               ISNULL(I.IsUseDefaultRemark2,0) IsUseDefaultRemark2,
               ISNULL(I.IsToleranceRequired,0) IsToleranceRequired,
               I.MinValue, I.MaxValue, I.MinTolerance, I.MaxTolerance,
               ISNULL(I.RemarkRequiredOptions,'') RemarkRequiredOptions
        FROM dbo.PIP_M_CheckListWOPM_Item I
        INNER JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
        WHERE S.IDVersion=@IDVersion
        ORDER BY S.DisplayOrder, I.DisplayOrder
        RETURN;
    END;

    IF @p_Tipe = '017'
    BEGIN
        
        SELECT G.IDItem, G.GroupName, G.FieldList
        FROM dbo.PIP_M_CheckListWOPM_ItemGroup G
        INNER JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=G.IDItem
        INNER JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
        WHERE S.IDVersion=@IDVersion
        ORDER BY G.DisplayOrder
        RETURN;
    END;

    IF @p_Tipe = '018'
    BEGIN
        
        SELECT R.IDItem,R.RepeatMode,R.CountMode,R.FixedCount,R.MinCount,R.MaxCount
        FROM dbo.PIP_M_CheckListWOPM_ItemRepeat R
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=R.IDItem
        JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
        WHERE S.IDVersion=@IDVersion
        RETURN;
    END;

    IF @p_Tipe = '019'
    BEGIN
        
        SELECT F.IDItem,F.IDRepeat,F.FieldLabel,F.FieldType,F.OptionList,F.MinValue,F.MaxValue,F.MinInclusive,F.MaxInclusive,F.IsRequired
        FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F
        JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=F.IDItem
        JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
        WHERE S.IDVersion=@IDVersion
        ORDER BY F.IDItem,F.DisplayOrder
        RETURN;
    END;

    IF @p_Tipe = '020'
    BEGIN
        
        SELECT P.InspectionPointID, ISNULL(M.RequireAllPoints,1) AS RequireAllPoints,
               ISNULL(P.IsNormalAbnormalRequired,0) AS IsNormalAbnormalRequired, P.PointCode
        FROM dbo.PIP_M_InspectionPoint P
        INNER JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
        LEFT JOIN dbo.PIP_M_InspectionMapGroup G ON G.MapGroupID=M.MapGroupID AND G.CompanyID=M.CompanyID AND G.LocationID=M.LocationID
        WHERE M.CompanyID=@CompanyID AND M.LocationID=@LocationID
          AND M.InspectionTypeCode=@InspectionTypeCode
          AND M.InspectionTypeDetailCode=@InspectionTypeDetailCode
          AND P.IsActive=1 AND M.IsCurrentVersion=1 AND M.IsActive=1
        RETURN;
    END;

    IF @p_Tipe = '021'
    BEGIN
        
        SELECT InspectionID, InspectionNo, InspectionDate, CompanyID, LocationID,
               StartDateTime, EndDateTime, ReasonVoid, IsSubmitted
        FROM dbo.PIP_T_Inspection
        WHERE ClientInspectionID=@ClientInspectionID
        RETURN;
    END;

    IF @p_Tipe = '022'
    BEGIN
        
        SELECT FileName, FileType, PhotoType, SeqNo
        FROM dbo.PIP_T_InspectionPhoto
        WHERE InspectionID=@InspectionID
        RETURN;
    END;
    RAISERROR('Invalid @p_Tipe for spPIP_Inspection_Query.', 16, 1);
END;
GO

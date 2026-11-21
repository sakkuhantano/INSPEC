IF OBJECT_ID('dbo.spPIP_Template_Command', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spPIP_Template_Command AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spPIP_Template_Command
    @p_Tipe VARCHAR(3),
    @p_IDTemplate INT = NULL,
    @p_IDVersion INT = NULL,
    @p_SectionID VARCHAR(50) = NULL,
    @p_SubSectionIDs VARCHAR(MAX) = NULL,
    @p_ItemIDs VARCHAR(MAX) = NULL,
    @p_GroupIDs VARCHAR(MAX) = NULL,
    @p_TemplateNo VARCHAR(100) = NULL,
    @p_Version VARCHAR(100) = NULL,
    @p_TemplateType VARCHAR(10) = NULL,
    @p_InspectionTypeCode VARCHAR(10) = NULL,
    @p_InspectionTypeDetailCode VARCHAR(500) = NULL,
    @p_CompanyScope VARCHAR(10) = NULL,
    @p_UpdateUser VARCHAR(100) = NULL,
    @p_CompanyID VARCHAR(50) = NULL,
    @p_LocationID VARCHAR(50) = NULL,
    @p_CurrentCompanyID VARCHAR(50) = NULL,
    @p_CurrentLocationID VARCHAR(50) = NULL,
    @p_UserID VARCHAR(50) = NULL,
    @p_EmployeeID VARCHAR(100) = NULL,
    @p_Action VARCHAR(10) = NULL,
    @p_IsSummaryRequired BIT = NULL,
    @p_IsFollowUpRequired BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @p_Tipe='001'
    BEGIN
        SELECT TOP 1 EntityType
        FROM (
            SELECT 'SECTION' EntityType
            FROM dbo.SplitStringConvertToTable(ISNULL(@p_SectionID,''),';') X
            WHERE LTRIM(RTRIM(X.val))<>'' AND NOT EXISTS (
                SELECT 1 FROM dbo.PIP_M_CheckListWOPM_Section S
                WHERE S.IDSection=CONVERT(INT,X.val) AND S.IDVersion=@p_IDVersion)
            UNION ALL
            SELECT 'SUBSECTION'
            FROM dbo.SplitStringConvertToTable(ISNULL(@p_SubSectionIDs,''),';') X
            WHERE LTRIM(RTRIM(X.val))<>'' AND NOT EXISTS (
                SELECT 1 FROM dbo.PIP_M_CheckListWOPM_SubSection SS
                JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=SS.IDSection
                WHERE SS.IDSubSection=CONVERT(INT,X.val) AND S.IDVersion=@p_IDVersion)
            UNION ALL
            SELECT 'ITEM'
            FROM dbo.SplitStringConvertToTable(ISNULL(@p_ItemIDs,''),';') X
            WHERE LTRIM(RTRIM(X.val))<>'' AND NOT EXISTS (
                SELECT 1 FROM dbo.PIP_M_CheckListWOPM_Item I
                JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
                WHERE I.IDItem=CONVERT(INT,X.val) AND S.IDVersion=@p_IDVersion)
            UNION ALL
            SELECT 'GROUP'
            FROM dbo.SplitStringConvertToTable(ISNULL(@p_GroupIDs,''),';') X
            WHERE LTRIM(RTRIM(X.val))<>'' AND NOT EXISTS (
                SELECT 1 FROM dbo.PIP_M_CheckListWOPM_ItemGroup G
                JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=G.IDItem
                JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
                WHERE G.IDGroup=CONVERT(INT,X.val) AND S.IDVersion=@p_IDVersion)
        ) InvalidEntities;
        RETURN;
    END;

    IF @p_Tipe='002'
    BEGIN
        SELECT IDTemplate
        FROM dbo.PIP_M_CheckListWOPM_Version
        WHERE IDVersion=@p_IDVersion;
        RETURN;
    END;

    IF @p_Tipe='003'
    BEGIN
        SELECT IDTemplate
        FROM dbo.PIP_M_CheckListWOPM_Version
        WHERE IDVersion=@p_IDVersion;
        RETURN;
    END;

    IF @p_Tipe='004'
    BEGIN
        SELECT IDTemplate
        FROM dbo.PIP_M_CheckListWOPM_Version
        WHERE IDVersion=@p_IDVersion;
        RETURN;
    END;

    IF @p_Tipe='005'
    BEGIN
        SELECT IDTemplate
        FROM dbo.PIP_M_CheckListWOPM_Version
        WHERE IDVersion=@p_IDVersion;
        RETURN;
    END;

    IF @p_Tipe='006'
    BEGIN
        SELECT
            T.IDTemplate, T.SectionID,
            InspectionSectionID=I.SectionID
        FROM dbo.PIP_M_CheckListWOPM T
        LEFT JOIN dbo.PIP_M_InspectionType I
          ON I.InspectionTypeCode=@p_InspectionTypeCode AND I.IsActive=1
        WHERE T.IDTemplate=@p_IDTemplate
          AND (
              EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation P
                      WHERE P.AppID='INSPEC' AND P.UserID=@p_UserID
                        AND P.CompanyID=@p_CompanyID AND P.LocationID=@p_LocationID)
              OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('INSPEC', @p_EmployeeID, '') L
                         WHERE L.CompanyID=@p_CompanyID AND L.LocationID=@p_LocationID)
          )
          AND (
              ISNULL(T.CompanyScope,'S')='A'
              OR (';' + ISNULL(T.CompanyLocationList,'') + ';'
                  LIKE '%;' + @p_CompanyID + @p_LocationID + ';%')
              OR ISNULL(T.CompanyLocationList,'')=''
          );
        RETURN;
    END;

    IF @p_Tipe='007'
    BEGIN
        SELECT X.val
        FROM dbo.SplitStringConvertToTable(ISNULL(@p_InspectionTypeDetailCode,''), ';') X
        LEFT JOIN dbo.PIP_M_InspectionTypeDetail D
          ON D.InspectionTypeCode=@p_InspectionTypeCode
         AND D.InspectionTypeDetailCode=LTRIM(RTRIM(X.val))
         AND D.IsActive=1
        WHERE LTRIM(RTRIM(X.val))<>'' AND D.InspectionTypeDetailCode IS NULL;
        RETURN;
    END;

    IF @p_Tipe='008'
    BEGIN
        SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
        SELECT T.CompanyScope
        FROM dbo.PIP_M_CheckListWOPM T
        WHERE T.IDTemplate=@p_IDTemplate
          AND (
              EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation P
                      WHERE P.AppID='INSPEC' AND P.UserID=@p_UserID
                        AND P.CompanyID=@p_CurrentCompanyID AND P.LocationID=@p_CurrentLocationID)
              OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('INSPEC', @p_EmployeeID, '') L
                         WHERE L.CompanyID=@p_CurrentCompanyID AND L.LocationID=@p_CurrentLocationID)
          )
          AND (
              ISNULL(T.CompanyScope,'S')='A'
              OR (';' + ISNULL(T.CompanyLocationList,'') + ';'
                  LIKE '%;' + @p_CurrentCompanyID + @p_CurrentLocationID + ';%')
          );
        RETURN;
    END;

    IF @p_Tipe='009'
    BEGIN
        IF @p_Action='ADD'
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM dbo.SysWebLocation swl
                JOIN dbo.SysWebCompany swc ON swc.CompanyID=swl.CompanyID
                WHERE swc.IsActive=1 AND swl.IsActive=1
                  AND swl.CompanyID=@p_CompanyID AND swl.LocationID=@p_LocationID
                  AND (
                      EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation P
                              WHERE P.CompanyID=swl.CompanyID AND P.LocationID=swl.LocationID
                                AND P.UserID=@p_UserID AND P.AppID='INSPEC')
                      OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('INSPEC', @p_EmployeeID, '') L
                                 WHERE L.CompanyID=swl.CompanyID AND L.LocationID=swl.LocationID)
                  )
            )
                RAISERROR('The company/location is inactive or you do not have INSPEC permission for it.',16,1);

            IF (';' + ISNULL((SELECT CompanyLocationList FROM dbo.PIP_M_CheckListWOPM WHERE IDTemplate=@p_IDTemplate),'') + ';'
                NOT LIKE '%;' + @p_CompanyID + @p_LocationID + ';%')
                UPDATE dbo.PIP_M_CheckListWOPM
                SET CompanyLocationList=CASE WHEN ISNULL(CompanyLocationList,'')=''
                                             THEN @p_CompanyID+@p_LocationID
                                             ELSE CompanyLocationList+';'+@p_CompanyID+@p_LocationID END
                WHERE IDTemplate=@p_IDTemplate;
            RETURN;
        END;

        IF @p_Action='REMOVE'
        BEGIN
            DECLARE @ScopeCount INT;
            SELECT @ScopeCount=COUNT(*)
            FROM dbo.SplitStringConvertToTable(
                (SELECT ISNULL(CompanyLocationList,'') FROM dbo.PIP_M_CheckListWOPM WHERE IDTemplate=@p_IDTemplate), ';');
            IF @ScopeCount<=1
                RAISERROR('Selected Company requires at least one company/location assignment.',16,1);

            BEGIN TRANSACTION;
            UPDATE T
            SET EmployeeList=CASE WHEN ISNULL(T.EmployeeList,'')=';' THEN ';' ELSE
                    ISNULL(STUFF((
                        SELECT ';'+X.val
                        FROM dbo.SplitStringConvertToTable(ISNULL(T.EmployeeList,''),';') X
                        WHERE NOT EXISTS (
                            SELECT 1 FROM dbo.M_HRD_Employee E
                            WHERE E.EmployeeID=X.val AND E.CompanyID=@p_CompanyID AND E.LocationID=@p_LocationID)
                        FOR XML PATH(''),TYPE).value('.','varchar(8000)'),1,1,''),'') END,
                CompanyLocationList=ISNULL(STUFF((
                    SELECT ';'+X.val
                    FROM dbo.SplitStringConvertToTable(ISNULL(T.CompanyLocationList,''),';') X
                    WHERE X.val<>@p_CompanyID+@p_LocationID
                    FOR XML PATH(''),TYPE).value('.','varchar(8000)'),1,1,''),'')
            FROM dbo.PIP_M_CheckListWOPM T
            WHERE T.IDTemplate=@p_IDTemplate;
            COMMIT TRANSACTION;
            RETURN;
        END;
        RAISERROR('Invalid company/location action.',16,1);
        RETURN;
    END;

    IF @p_Tipe='010'
    BEGIN
        SELECT 1
        FROM dbo.PIP_M_CheckListWOPM T
        WHERE T.IDTemplate=@p_IDTemplate
          AND T.TemplateType='I'
          AND (ISNULL(T.CompanyScope,'S')='A'
               OR (';' + ISNULL(T.CompanyLocationList,'') + ';'
                   LIKE '%;' + @p_CurrentCompanyID + @p_CurrentLocationID + ';%'));
        RETURN;
    END;

    IF @p_Tipe='011'
    BEGIN
        UPDATE dbo.PIP_M_CheckListWOPM
        SET EmployeeList='', UpdateUser=@p_UpdateUser, UpdateDate=GETDATE()
        WHERE IDTemplate=@p_IDTemplate AND TemplateType='I';
        RETURN;
    END;

    IF @p_Tipe='012'
    BEGIN
        SELECT
            T.TemplateType, T.CompanyScope, T.SectionID,
            E.EmployeeID, E.SectionID EmployeeSectionID,
            E.CompanyID, E.LocationID EmployeeLocationID
        FROM dbo.PIP_M_CheckListWOPM T
        JOIN dbo.M_HRD_Employee E ON E.EmployeeID=@p_EmployeeID
        WHERE T.IDTemplate=@p_IDTemplate
          AND E.SectionID=T.SectionID
          AND ISNULL(E.TerminationDate,'')=''
          AND (
              EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation P
                      WHERE P.AppID='INSPEC'
                        AND P.UserID=(SELECT TOP 1 SU.UserID FROM dbo.SysWebUser SU WHERE SU.employeeid=E.EmployeeID)
                        AND P.CompanyID=@p_CurrentCompanyID AND P.LocationID=@p_CurrentLocationID)
              OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('INSPEC', E.EmployeeID, '') L
                         WHERE L.CompanyID=@p_CurrentCompanyID AND L.LocationID=@p_CurrentLocationID)
          )
          AND (ISNULL(T.CompanyScope,'S')='A'
               OR (';' + ISNULL(T.CompanyLocationList,'') + ';'
                   LIKE '%;' + @p_CurrentCompanyID + @p_CurrentLocationID + ';%'));
        RETURN;
    END;

    IF @p_Tipe='013'
    BEGIN
        BEGIN TRANSACTION;
        UPDATE dbo.PIP_M_CheckListWOPM
        SET EmployeeList=REPLACE(ISNULL(EmployeeList,''),':',';')
        WHERE IDTemplate=@p_IDTemplate AND EmployeeList LIKE '%:%';

        DECLARE @CurrentEmployeeList VARCHAR(8000);
        SELECT @CurrentEmployeeList=ISNULL(EmployeeList,'')
        FROM dbo.PIP_M_CheckListWOPM WITH (UPDLOCK,HOLDLOCK)
        WHERE IDTemplate=@p_IDTemplate;

        IF @CurrentEmployeeList IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR('Template was not found.',16,1);
            RETURN;
        END;

        IF @p_Action='REMOVE'
        BEGIN
            IF @CurrentEmployeeList=''
            BEGIN
                UPDATE T
                SET EmployeeList=CASE WHEN ISNULL(STUFF((
                    SELECT ';'+E.EmployeeID
                    FROM dbo.M_HRD_Employee E
                    WHERE E.SectionID=T.SectionID
                      AND ISNULL(E.TerminationDate,'')=''
                      AND (
                          EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation P
                                  WHERE P.AppID='INSPEC'
                                    AND P.UserID=(SELECT TOP 1 SU.UserID FROM dbo.SysWebUser SU WHERE SU.employeeid=E.EmployeeID)
                                    AND P.CompanyID=@p_CurrentCompanyID AND P.LocationID=@p_CurrentLocationID)
                          OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('INSPEC', E.EmployeeID, '') L
                                     WHERE L.CompanyID=@p_CurrentCompanyID AND L.LocationID=@p_CurrentLocationID)
                      )
                      AND (ISNULL(T.CompanyScope,'S')='A'
                           OR (';' + ISNULL(T.CompanyLocationList,'') + ';'
                               LIKE '%;' + @p_CurrentCompanyID + @p_CurrentLocationID + ';%'))
                      AND E.EmployeeID<>@p_EmployeeID
                    ORDER BY E.EmployeeID
                    FOR XML PATH(''),TYPE).value('.','varchar(8000)'),1,1,''),'')='' THEN ';'
                    ELSE STUFF((
                        SELECT ';'+E.EmployeeID
                        FROM dbo.M_HRD_Employee E
                        WHERE E.SectionID=T.SectionID
                          AND ISNULL(E.TerminationDate,'')=''
                          AND (
                              EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation P
                                      WHERE P.AppID='INSPEC'
                                        AND P.UserID=(SELECT TOP 1 SU.UserID FROM dbo.SysWebUser SU WHERE SU.employeeid=E.EmployeeID)
                                        AND P.CompanyID=@p_CurrentCompanyID AND P.LocationID=@p_CurrentLocationID)
                              OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('INSPEC', E.EmployeeID, '') L
                                         WHERE L.CompanyID=@p_CurrentCompanyID AND L.LocationID=@p_CurrentLocationID)
                          )
                          AND (ISNULL(T.CompanyScope,'S')='A'
                               OR (';' + ISNULL(T.CompanyLocationList,'') + ';'
                                   LIKE '%;' + @p_CurrentCompanyID + @p_CurrentLocationID + ';%'))
                          AND E.EmployeeID<>@p_EmployeeID
                        ORDER BY E.EmployeeID
                        FOR XML PATH(''),TYPE).value('.','varchar(8000)'),1,1,'')
                END
                FROM dbo.PIP_M_CheckListWOPM T
                WHERE T.IDTemplate=@p_IDTemplate;
            END
            ELSE
            BEGIN
                UPDATE T
                SET EmployeeList=CASE WHEN ISNULL(STUFF((
                    SELECT ';'+X.val
                    FROM dbo.SplitStringConvertToTable(ISNULL(T.EmployeeList,''),';') X
                    WHERE X.val<>@p_EmployeeID
                    FOR XML PATH(''),TYPE).value('.','varchar(8000)'),1,1,''),'')='' THEN ';'
                    ELSE STUFF((
                        SELECT ';'+X.val
                        FROM dbo.SplitStringConvertToTable(ISNULL(T.EmployeeList,''),';') X
                        WHERE X.val<>@p_EmployeeID
                        FOR XML PATH(''),TYPE).value('.','varchar(8000)'),1,1,'') END
                FROM dbo.PIP_M_CheckListWOPM T WHERE T.IDTemplate=@p_IDTemplate;
            END;
        END
        ELSE IF @p_Action='ADD'
        BEGIN
            IF @CurrentEmployeeList=';'
            BEGIN
                UPDATE dbo.PIP_M_CheckListWOPM
                SET EmployeeList=@p_EmployeeID, UpdateUser=@p_UpdateUser, UpdateDate=GETDATE()
                WHERE IDTemplate=@p_IDTemplate;
            END
            ELSE IF @CurrentEmployeeList<>''
            BEGIN
                UPDATE dbo.PIP_M_CheckListWOPM
                SET EmployeeList=CASE
                    WHEN (';' + @CurrentEmployeeList + ';' NOT LIKE '%;' + @p_EmployeeID + ';%')
                    THEN @CurrentEmployeeList+';'+@p_EmployeeID
                    ELSE @CurrentEmployeeList END
                WHERE IDTemplate=@p_IDTemplate;

                UPDATE T
                SET EmployeeList=''
                FROM dbo.PIP_M_CheckListWOPM T
                WHERE T.IDTemplate=@p_IDTemplate
                  AND NOT EXISTS (
                      SELECT 1 FROM dbo.M_HRD_Employee E
                      WHERE E.SectionID=T.SectionID
                        AND ISNULL(E.TerminationDate,'')=''
                        AND (
                            EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation P
                                    WHERE P.AppID='INSPEC'
                                      AND P.UserID=(SELECT TOP 1 SU.UserID FROM dbo.SysWebUser SU WHERE SU.employeeid=E.EmployeeID)
                                      AND P.CompanyID=@p_CurrentCompanyID AND P.LocationID=@p_CurrentLocationID)
                            OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('INSPEC', E.EmployeeID, '') L
                                       WHERE L.CompanyID=@p_CurrentCompanyID AND L.LocationID=@p_CurrentLocationID)
                        )
                        AND (ISNULL(T.CompanyScope,'S')='A'
                             OR (';' + ISNULL(T.CompanyLocationList,'') + ';'
                                 LIKE '%;' + @p_CurrentCompanyID + @p_CurrentLocationID + ';%'))
                        AND (';' + ISNULL(T.EmployeeList,'') + ';' NOT LIKE '%;' + E.EmployeeID + ';%')
                  );
            END;
        END
        ELSE
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR('Invalid employee assignment action.',16,1);
            RETURN;
        END;
        COMMIT TRANSACTION;
        RETURN;
    END;

    IF @p_Tipe='014'
    BEGIN
        BEGIN TRANSACTION;
        IF EXISTS (
            SELECT 1 FROM dbo.PIP_T_Inspection I WITH (UPDLOCK,HOLDLOCK)
            JOIN dbo.PIP_M_CheckListWOPM T
              ON T.IDTemplate=@p_IDTemplate AND T.TemplateType='I'
            WHERE I.IDTemplate=@p_IDTemplate AND I.IDVersion=@p_IDVersion)
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR('Version sudah digunakan pada Inspection dan tidak dapat dikembalikan ke Draft.',16,1);
            RETURN;
        END;
        IF EXISTS (
            SELECT 1 FROM dbo.PIP_T_WO W WITH (UPDLOCK,HOLDLOCK)
            WHERE LTRIM(RTRIM(CONVERT(VARCHAR(100),W.TemplateWOPM))) IN
                  (@p_TemplateNo,CONVERT(VARCHAR(20),@p_IDTemplate))
              AND LTRIM(RTRIM(CONVERT(VARCHAR(50),W.TemplateVersion)))=@p_Version)
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR('Version sudah digunakan pada Work Order dan tidak dapat dikembalikan ke Draft.',16,1);
            RETURN;
        END;
        UPDATE dbo.PIP_M_CheckListWOPM_Version
        SET Status='Draft', EffectiveDate=NULL
        WHERE IDTemplate=@p_IDTemplate AND IDVersion=@p_IDVersion
          AND Status IN ('Active','Archieved');
        IF @@ROWCOUNT=0
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR('Version status changed. Refresh the template and try again.',16,1);
            RETURN;
        END;
        COMMIT TRANSACTION;
        SELECT CAST(1 AS BIT) Success;
        RETURN;
    END;

    IF @p_Tipe='015'
    BEGIN
        BEGIN TRANSACTION;
        IF NOT EXISTS (
            SELECT 1 FROM dbo.PIP_M_CheckListWOPM WITH (UPDLOCK,HOLDLOCK)
            WHERE IDTemplate=@p_IDTemplate)
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR('Template was not found.',16,1);
            RETURN;
        END;
        IF EXISTS (
            SELECT 1 FROM dbo.PIP_M_CheckListWOPM_Version WITH (UPDLOCK,HOLDLOCK)
            WHERE IDTemplate=@p_IDTemplate AND Status='Active')
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR('Template cannot be deactivated while it has an Active version.',16,1);
            RETURN;
        END;
        UPDATE dbo.PIP_M_CheckListWOPM
        SET IsActive=0, UpdateUser=@p_UpdateUser, UpdateDate=GETDATE()
        WHERE IDTemplate=@p_IDTemplate;
        COMMIT TRANSACTION;
        SELECT CAST(1 AS BIT) Success;
        RETURN;
    END;

    IF @p_Tipe='016'
    BEGIN
        UPDATE dbo.PIP_M_CheckListWOPM_Version
        SET IsSummaryRequired=@p_IsSummaryRequired,
            IsFollowUpRequired=@p_IsFollowUpRequired
        WHERE IDVersion=@p_IDVersion;
        RETURN;
    END;

    IF @p_Tipe='017'
    BEGIN
        BEGIN TRANSACTION;
        UPDATE dbo.PIP_M_CheckListWOPM
        SET EmployeeList=REPLACE(ISNULL(EmployeeList,''),':',';')
        WHERE IDTemplate=@p_IDTemplate AND EmployeeList LIKE '%:%';

        UPDATE dbo.PIP_M_CheckListWOPM
        SET TemplateType=@p_TemplateType,
            InspectionTypeCode=@p_InspectionTypeCode,
            InspectionTypeDetailCode=@p_InspectionTypeDetailCode,
            CompanyScope=@p_CompanyScope,
            UpdateUser=@p_UpdateUser,
            UpdateDate=GETDATE()
        WHERE IDTemplate=@p_IDTemplate;

        IF @p_CompanyScope='S'
        AND (';' + ISNULL((SELECT CompanyLocationList FROM dbo.PIP_M_CheckListWOPM WHERE IDTemplate=@p_IDTemplate),'') + ';'
             NOT LIKE '%;' + @p_CompanyID + @p_LocationID + ';%')
        BEGIN
            UPDATE dbo.PIP_M_CheckListWOPM
            SET CompanyLocationList=CASE WHEN ISNULL(CompanyLocationList,'')=''
                                         THEN @p_CompanyID+@p_LocationID
                                         ELSE CompanyLocationList+';'+@p_CompanyID+@p_LocationID END
            WHERE IDTemplate=@p_IDTemplate;
        END;

        IF @p_TemplateType='W'
            UPDATE dbo.PIP_M_CheckListWOPM SET EmployeeList='' WHERE IDTemplate=@p_IDTemplate;

        IF @p_CompanyScope='S' AND @p_TemplateType='I'
        BEGIN
            UPDATE T
            SET EmployeeList=ISNULL(STUFF((
                SELECT ';'+X.val
                FROM dbo.SplitStringConvertToTable(ISNULL(T.EmployeeList,''),';') X
                JOIN dbo.M_HRD_Employee E ON E.EmployeeID=X.val
                WHERE (';'+ISNULL(T.CompanyLocationList,'')+';' LIKE '%;'+E.CompanyID+E.LocationID+';%')
                FOR XML PATH(''),TYPE).value('.','varchar(8000)'),1,1,''),'')
            FROM dbo.PIP_M_CheckListWOPM T
            WHERE T.IDTemplate=@p_IDTemplate AND ISNULL(T.EmployeeList,'')<>'';
        END;
        COMMIT TRANSACTION;
        RETURN;
    END;

    RAISERROR('Invalid @p_Tipe for spPIP_Template_Command.',16,1);
END;
GO

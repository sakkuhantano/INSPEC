IF OBJECT_ID('dbo.spUTL_INSPEC_Login_Command', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.spUTL_INSPEC_Login_Command AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.spUTL_INSPEC_Login_Command
    @p_Tipe VARCHAR(3),
    @p_Data dbo.Type_N_Tbl_C13 READONLY
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @C1 NVARCHAR(MAX), @C2 NVARCHAR(MAX), @C3 NVARCHAR(MAX),
            @C4 NVARCHAR(MAX), @C5 NVARCHAR(MAX);

    SELECT TOP 1 @C1=C1,@C2=C2,@C3=C3,@C4=C4,@C5=C5
    FROM @p_Data;

    -- 001: C1=BrowserGuid, C2=ServerGuid, C3=Token (logout current browser session)
    IF @p_Tipe='001'
    BEGIN
        UPDATE dbo.UserSession
        SET IsActive=0
        WHERE BrowserGuid=@C1 AND ServerGuid=@C2 AND Token=@C3 AND IsActive=1;
        RETURN;
    END;

    -- 002: C1=InfoID (atomically consume a one-time portal login ticket)
    IF @p_Tipe='002'
    BEGIN
        UPDATE dbo.SysWebInfo
        SET ExpiredDate=GETDATE(), UpdateDate=GETDATE()
        OUTPUT deleted.Description1 AS EmployeeID,
               deleted.Description2 AS PasswordHash
        WHERE ID=@C1
          AND Type='LinkApp'
          AND AppID='WebApp'
          AND ExpiredDate>GETDATE();
        RETURN;
    END;

    -- 003: C1=EmployeeID, C2=BrowserGuid (load login profile for this browser)
    IF @p_Tipe='003'
    BEGIN
        SELECT U.UserID,U.UserName,U.employeeid AS EmployeeID,U.Password,
               ISNULL(L.SectionList,'') AS Section,
               ISNULL(NULLIF(L.Theme,''),'L') AS Theme,
               A.JobTitleName,A.EmailAddress,A.ProfitCenterNo,
               ISNULL(US.LastSyncMaster,CAST('' AS SMALLDATETIME)) AS LastSyncMaster,
               A.UserName AS UserName1,
               ISNULL(US.LastSyncWO,CAST('' AS SMALLDATETIME)) AS LastSyncWO
        FROM dbo.SysWebUser U
        LEFT JOIN dbo.INSPEC_User L ON L.UserID=U.employeeid
        OUTER APPLY
        (
            SELECT TOP 1 LastSyncMaster,LastSyncWO
            FROM dbo.UserSession
            WHERE UserID=U.EmployeeID AND BrowserGuid=@C2
            ORDER BY LoginTime DESC,ID DESC
        ) US
        CROSS APPLY dbo.F_SelectOneLogin('pip',U.employeeid,'') A
        WHERE U.employeeid=@C1 AND U.IsActive=1;
        RETURN;
    END;

    -- 004: C1=EmployeeID (authorized company/location choices)
    IF @p_Tipe='004'
    BEGIN
        SELECT CompanyLocation,CompanyName
        FROM
        (
            SELECT CompanyLocation,CompanyName,SourcePriority,
                   ROW_NUMBER() OVER (PARTITION BY CompanyLocation ORDER BY SourcePriority) RN
            FROM
            (
                SELECT A.companyid+';'+A.locationid AS CompanyLocation,
                       A.alias AS CompanyName,0 AS SourcePriority
                FROM dbo.F_SelectOneLogin('pip',@C1,'') A
                UNION ALL
                SELECT A.companyid+';'+A.locationid,B.alias,1
                FROM dbo.syswebusercompanylocation A
                JOIN dbo.syswebcompany B ON B.companyid=A.companyid
                WHERE A.userid=@C1 AND A.appid='pip'
            ) Sources
        ) Ranked
        WHERE RN=1
        ORDER BY SourcePriority,CompanyLocation;
        RETURN;
    END;

    -- 005: C1=EmployeeID, C2=BrowserGuid, C3=ServerGuid, C4=Token, C5=DeviceName
    -- The procedure owns this transaction. Call EQueryP with p_IsSP=true only (no client transaction flag).
    IF @p_Tipe='005'
    BEGIN
        SET XACT_ABORT ON;
        BEGIN TRY
            BEGIN TRANSACTION;

            DECLARE @NewID INT;
            DECLARE @SessionID INT;

            SELECT @NewID=ISNULL(MAX(ID),0)
            FROM dbo.UserSession WITH (TABLOCKX,HOLDLOCK);

            SELECT TOP 1 @SessionID=ID
            FROM dbo.UserSession
            WHERE UserID=@C1 AND BrowserGuid=@C2
            ORDER BY LoginTime DESC,ID DESC;

            UPDATE dbo.UserSession
            SET IsActive=0
            WHERE UserID=@C1 AND BrowserGuid=@C2 AND IsActive=1;

            IF @SessionID IS NULL
            BEGIN
                DELETE FROM dbo.UserSession
                WHERE ISNULL(IsActive,0)=0 OR ExpireTime<=GETDATE();

                SELECT @NewID=ISNULL(MAX(ID),0)+1 FROM dbo.UserSession;

                INSERT dbo.UserSession
                    (ID,UserID,BrowserGuid,ServerGuid,Token,LoginTime,ExpireTime,IsActive,DeviceName,LastSyncMaster,LastSyncWO)
                VALUES
                    (@NewID,@C1,@C2,@C3,@C4,GETDATE(),DATEADD(DAY,2,GETDATE()),1,@C5,'','');
            END
            ELSE
            BEGIN
                UPDATE dbo.UserSession
                SET ServerGuid=@C3,
                    Token=@C4,
                    LoginTime=GETDATE(),
                    ExpireTime=DATEADD(DAY,2,GETDATE()),
                    IsActive=1,
                    DeviceName=@C5
                WHERE ID=@SessionID;
            END;

            COMMIT TRANSACTION;
            RETURN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
            DECLARE @LoginError NVARCHAR(4000);
            SET @LoginError=ERROR_MESSAGE();
            RAISERROR('%s',16,1,@LoginError);
            RETURN;
        END CATCH;
    END;

    RAISERROR('Invalid @p_Tipe for spUTL_INSPEC_Login_Command.',16,1);
END;
GO

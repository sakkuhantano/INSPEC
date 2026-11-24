/* Master Inspection Geofence
   Compatible with SQL Server 2008.
   Header: PIP_M_InspectionGeofence
   Detail: PIP_M_InspectionGeofencePoint
*/
IF OBJECT_ID('dbo.PIP_M_InspectionGeofence','U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_M_InspectionGeofence
    (
        GeofenceID INT IDENTITY(1,1) NOT NULL,
        CompanyID VARCHAR(10) NOT NULL,
        LocationID VARCHAR(3) NOT NULL,
        GeofenceName NVARCHAR(100) NOT NULL,
        Description NVARCHAR(500) NOT NULL CONSTRAINT DF_PIP_M_InspectionGeofence_Description DEFAULT(''),
        IsActive BIT NOT NULL CONSTRAINT DF_PIP_M_InspectionGeofence_IsActive DEFAULT(1),
        EntryUser VARCHAR(50) NOT NULL,
        EntryDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionGeofence_EntryDate DEFAULT(GETDATE()),
        UpdateUser VARCHAR(50) NOT NULL,
        UpdateDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionGeofence_UpdateDate DEFAULT(GETDATE()),
        CONSTRAINT PK_PIP_M_InspectionGeofence PRIMARY KEY CLUSTERED (GeofenceID)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.PIP_M_InspectionGeofence') AND name='UX_PIP_M_InspectionGeofence_ScopeName')
    CREATE UNIQUE NONCLUSTERED INDEX UX_PIP_M_InspectionGeofence_ScopeName
    ON dbo.PIP_M_InspectionGeofence(CompanyID, LocationID, GeofenceName)
    WHERE IsActive=1;
GO

IF OBJECT_ID('dbo.PIP_M_InspectionGeofencePoint','U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_M_InspectionGeofencePoint
    (
        GeofenceID INT NOT NULL,
        SequenceNo INT NOT NULL,
        Latitude DECIMAL(10,7) NOT NULL,
        Longitude DECIMAL(10,7) NOT NULL,
        EntryUser VARCHAR(50) NOT NULL,
        EntryDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionGeofencePoint_EntryDate DEFAULT(GETDATE()),
        UpdateUser VARCHAR(50) NOT NULL,
        UpdateDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionGeofencePoint_UpdateDate DEFAULT(GETDATE()),
        CONSTRAINT PK_PIP_M_InspectionGeofencePoint PRIMARY KEY CLUSTERED (GeofenceID, SequenceNo),
        CONSTRAINT FK_PIP_M_InspectionGeofencePoint_Geofence FOREIGN KEY (GeofenceID)
            REFERENCES dbo.PIP_M_InspectionGeofence(GeofenceID)
    );
END
GO

IF OBJECT_ID('dbo.spPIP_InsertUpdateDeleteInput_PIP_M_InspectionGeofence','P') IS NOT NULL
    DROP PROCEDURE dbo.spPIP_InsertUpdateDeleteInput_PIP_M_InspectionGeofence;
GO
CREATE PROCEDURE dbo.spPIP_InsertUpdateDeleteInput_PIP_M_InspectionGeofence
    @p_Tipe VARCHAR(1)='0',             -- Header: 1 Add, 2 Edit, 3 Delete (soft delete)
    @p_Tipe1 VARCHAR(1)='0',            -- Points: 1 Add, 2 Edit/replace, 3 Delete
    @p_GeofenceID INT=0 OUTPUT,
    @p_CompanyID VARCHAR(10),
    @p_LocationID VARCHAR(3),
    @p_GeofenceName NVARCHAR(100)=NULL,
    @p_Description NVARCHAR(500)=NULL,
    @p_IsActive BIT=1,
    @p_PointsXml XML=NULL,
    @p_UpdateUser VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @p_Tipe='1'
        BEGIN
            IF EXISTS
            (
                SELECT 1 FROM dbo.PIP_M_InspectionGeofence
                WHERE CompanyID=@p_CompanyID AND LocationID=@p_LocationID
                  AND GeofenceName=@p_GeofenceName AND IsActive=1
            )
                RAISERROR('Geofence name already exists for this Company and Location.',16,1);

            INSERT INTO dbo.PIP_M_InspectionGeofence
                (CompanyID,LocationID,GeofenceName,Description,IsActive,EntryUser,EntryDate,UpdateUser,UpdateDate)
            VALUES
                (@p_CompanyID,@p_LocationID,@p_GeofenceName,ISNULL(@p_Description,''),@p_IsActive,
                 @p_UpdateUser,GETDATE(),@p_UpdateUser,GETDATE());

            SET @p_GeofenceID=CONVERT(INT,SCOPE_IDENTITY());
        END
        ELSE IF @p_Tipe='2'
        BEGIN
            IF EXISTS
            (
                SELECT 1 FROM dbo.PIP_M_InspectionGeofence
                WHERE CompanyID=@p_CompanyID AND LocationID=@p_LocationID
                  AND GeofenceName=@p_GeofenceName AND GeofenceID<>@p_GeofenceID AND IsActive=1
            )
                RAISERROR('Geofence name already exists for this Company and Location.',16,1);

            UPDATE dbo.PIP_M_InspectionGeofence
            SET GeofenceName=@p_GeofenceName,
                Description=ISNULL(@p_Description,''),
                IsActive=@p_IsActive,
                UpdateUser=@p_UpdateUser,
                UpdateDate=GETDATE()
            WHERE GeofenceID=@p_GeofenceID
              AND CompanyID=@p_CompanyID AND LocationID=@p_LocationID;

            IF @@ROWCOUNT=0 RAISERROR('Geofence record was not found in the current Company and Location.',16,1);
        END
        ELSE IF @p_Tipe='3'
        BEGIN
            UPDATE dbo.PIP_M_InspectionGeofence
            SET IsActive=0,UpdateUser=@p_UpdateUser,UpdateDate=GETDATE()
            WHERE GeofenceID=@p_GeofenceID
              AND CompanyID=@p_CompanyID AND LocationID=@p_LocationID;

            IF @@ROWCOUNT=0 RAISERROR('Geofence record was not found in the current Company and Location.',16,1);
        END
        ELSE IF ISNULL(@p_Tipe,'0')<>'0'
            RAISERROR('Invalid header operation type.',16,1);

        IF @p_Tipe1 IN ('1','2','3')
        BEGIN
            IF NOT EXISTS
            (
                SELECT 1 FROM dbo.PIP_M_InspectionGeofence
                WHERE GeofenceID=@p_GeofenceID
                  AND CompanyID=@p_CompanyID AND LocationID=@p_LocationID
            )
                RAISERROR('Geofence header is not available for point maintenance.',16,1);

            IF @p_Tipe1='1'
            BEGIN
                IF EXISTS (SELECT 1 FROM dbo.PIP_M_InspectionGeofencePoint WHERE GeofenceID=@p_GeofenceID)
                    RAISERROR('Geofence points already exist. Use Edit to replace the polygon.',16,1);

                IF @p_PointsXml IS NULL
                    RAISERROR('Polygon point data cannot be empty.',16,1);

                INSERT INTO dbo.PIP_M_InspectionGeofencePoint
                    (GeofenceID,SequenceNo,Latitude,Longitude,EntryUser,EntryDate,UpdateUser,UpdateDate)
                SELECT @p_GeofenceID,
                       P.N.value('@SequenceNo','INT'),
                       P.N.value('@Latitude','DECIMAL(10,7)'),
                       P.N.value('@Longitude','DECIMAL(10,7)'),
                       @p_UpdateUser,GETDATE(),@p_UpdateUser,GETDATE()
                FROM @p_PointsXml.nodes('/Points/Point') AS P(N);
            END
            ELSE IF @p_Tipe1='2'
            BEGIN
                IF @p_PointsXml IS NULL
                    RAISERROR('Polygon point data cannot be empty.',16,1);

                DELETE dbo.PIP_M_InspectionGeofencePoint WHERE GeofenceID=@p_GeofenceID;

                INSERT INTO dbo.PIP_M_InspectionGeofencePoint
                    (GeofenceID,SequenceNo,Latitude,Longitude,EntryUser,EntryDate,UpdateUser,UpdateDate)
                SELECT @p_GeofenceID,
                       P.N.value('@SequenceNo','INT'),
                       P.N.value('@Latitude','DECIMAL(10,7)'),
                       P.N.value('@Longitude','DECIMAL(10,7)'),
                       @p_UpdateUser,GETDATE(),@p_UpdateUser,GETDATE()
                FROM @p_PointsXml.nodes('/Points/Point') AS P(N);
            END
            ELSE IF @p_Tipe1='3'
                DELETE dbo.PIP_M_InspectionGeofencePoint WHERE GeofenceID=@p_GeofenceID;
        END
        ELSE IF ISNULL(@p_Tipe1,'0')<>'0'
            RAISERROR('Invalid detail operation type.',16,1);

        COMMIT TRANSACTION;

        SELECT @p_GeofenceID AS GeofenceID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
        DECLARE @ErrorMessage NVARCHAR(4000);
        SET @ErrorMessage=ERROR_MESSAGE();
        RAISERROR(@ErrorMessage,16,1);
        RETURN;
    END CATCH
END
GO

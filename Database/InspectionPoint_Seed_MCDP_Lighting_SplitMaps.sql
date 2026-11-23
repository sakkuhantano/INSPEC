/*
    INSPEC - MCDP Lighting Point Seed for split maps (MapID 3, 4, 5)
    Source drawings:
      docs/INSPEC_Outdoor_Lighting.png       -> MapID 3 (44 labelled points)
      docs/INSPEC_Signboard_Lighting.png    -> MapID 4 (9 numbered panels)
      docs/INSPEC_Logo_M_LED_Facade.png     -> MapID 5 (6 labelled groups)

    Coordinates are normalized percentage positions (0..100) relative to each image.
    They are first-pass visual plots from the supplied raster drawings; verify/adjust
    alignment in Inspection Master before operational use. Existing point codes are
    left untouched; only missing MapID + PointCode rows are inserted.
    SQL Server 2008 compatible. This script does not create or alter map master rows.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF COL_LENGTH('dbo.PIP_M_InspectionPoint','MapX') IS NULL OR COL_LENGTH('dbo.PIP_M_InspectionPoint','MapY') IS NULL
BEGIN
    RAISERROR('PIP_M_InspectionPoint.MapX/MapY are required. Run the inspection point coordinate migration first.',16,1);
    RETURN;
END;
GO

BEGIN TRANSACTION;
DECLARE @UserID VARCHAR(50); SET @UserID='SYSTEM';

IF OBJECT_ID('tempdb..#ExpectedMaps') IS NOT NULL DROP TABLE #ExpectedMaps;
CREATE TABLE #ExpectedMaps (MapID BIGINT NOT NULL, CompanyID VARCHAR(50) NOT NULL, LocationID VARCHAR(50) NOT NULL, MapCode VARCHAR(50) NOT NULL, InspectionTypeCode VARCHAR(2) NOT NULL, InspectionTypeDetailCode VARCHAR(20) NOT NULL);
INSERT INTO #ExpectedMaps(MapID,CompanyID,LocationID,MapCode,InspectionTypeCode,InspectionTypeDetailCode) VALUES
(3,'I00024012','R02','MCDP-LT-OUTDOOR','LT','MCDP-LT'),
(4,'I00024012','R02','MCDP-LT-SIGNBOARD','LT','MCDP-LT'),
(5,'I00024012','R02','MCDP-LT-LOGO','LT','MCDP-LT');

IF EXISTS (
    SELECT 1 FROM #ExpectedMaps E
    LEFT JOIN dbo.PIP_M_InspectionMap M ON M.MapID=E.MapID
      AND M.CompanyID=E.CompanyID AND M.LocationID=E.LocationID
      AND M.MapCode=E.MapCode AND M.InspectionTypeCode=E.InspectionTypeCode
      AND M.InspectionTypeDetailCode=E.InspectionTypeDetailCode AND M.IsActive=1
    WHERE M.MapID IS NULL
)
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('One or more expected lighting maps (MapID 3, 4, 5) do not match Company, Location, MapCode, Type, Detail, or active status. No points were inserted.',16,1);
    RETURN;
END;

IF OBJECT_ID('tempdb..#LightingPoints') IS NOT NULL DROP TABLE #LightingPoints;
CREATE TABLE #LightingPoints (MapID BIGINT NOT NULL, PointCode VARCHAR(50) NOT NULL, PointName VARCHAR(200) NOT NULL, MapX DECIMAL(9,4) NOT NULL, MapY DECIMAL(9,4) NOT NULL, DisplayOrder INT NOT NULL);
INSERT INTO #LightingPoints(MapID,PointCode,PointName,MapX,MapY,DisplayOrder) VALUES
(3,N'B.1',N'Outdoor Lighting - B.1',49.5000,64.2000,1),
(3,N'B.2',N'Outdoor Lighting - B.2',31.8000,49.0000,2),
(3,N'B.3',N'Outdoor Lighting - B.3',49.5000,31.2000,3),
(3,N'B.4',N'Outdoor Lighting - B.4',67.3000,49.0000,4),
(3,N'C.1',N'Outdoor Lighting - C.1',68.0000,72.0000,5),
(3,N'C.2',N'Outdoor Lighting - C.2',27.0000,72.0000,6),
(3,N'C.3',N'Outdoor Lighting - C.3',27.0000,29.0000,7),
(3,N'C.4',N'Outdoor Lighting - C.4',68.5000,29.0000,8),
(3,N'D.1',N'Outdoor Lighting - D.1',73.5000,75.5000,9),
(3,N'D.2',N'Outdoor Lighting - D.2',24.5000,75.5000,10),
(3,N'D.3',N'Outdoor Lighting - D.3',24.5000,24.5000,11),
(3,N'D.4',N'Outdoor Lighting - D.4',73.5000,24.5000,12),
(3,N'E.1',N'Outdoor Lighting - E.1',71.5000,68.5000,13),
(3,N'E.2',N'Outdoor Lighting - E.2',26.0000,68.5000,14),
(3,N'E.3',N'Outdoor Lighting - E.3',26.0000,31.5000,15),
(3,N'E.4',N'Outdoor Lighting - E.4',71.5000,31.5000,16),
(3,N'F.1',N'Outdoor Lighting - F.1',61.0000,78.0000,17),
(3,N'F.2',N'Outdoor Lighting - F.2',51.5000,78.0000,18),
(3,N'F.3',N'Outdoor Lighting - F.3',42.0000,78.0000,19),
(3,N'F.4',N'Outdoor Lighting - F.4',32.5000,78.0000,20),
(3,N'F.5',N'Outdoor Lighting - F.5',32.5000,22.0000,21),
(3,N'F.6',N'Outdoor Lighting - F.6',42.0000,22.0000,22),
(3,N'F.7',N'Outdoor Lighting - F.7',51.5000,22.0000,23),
(3,N'F.8',N'Outdoor Lighting - F.8',61.0000,22.0000,24),
(3,N'G.1',N'Outdoor Lighting - G.1',62.0000,95.0000,25),
(3,N'G.2',N'Outdoor Lighting - G.2',51.5000,95.0000,26),
(3,N'G.3',N'Outdoor Lighting - G.3',41.0000,95.0000,27),
(3,N'G.4',N'Outdoor Lighting - G.4',30.5000,95.0000,28),
(3,N'G.5',N'Outdoor Lighting - G.5',30.5000,5.0000,29),
(3,N'G.6',N'Outdoor Lighting - G.6',41.0000,5.0000,30),
(3,N'G.7',N'Outdoor Lighting - G.7',51.5000,5.0000,31),
(3,N'G.8',N'Outdoor Lighting - G.8',62.0000,5.0000,32),
(3,N'H.1',N'Outdoor Lighting - H.1',84.0000,72.0000,33),
(3,N'H.2',N'Outdoor Lighting - H.2',16.0000,72.0000,34),
(3,N'H.3',N'Outdoor Lighting - H.3',16.0000,28.0000,35),
(3,N'H.4',N'Outdoor Lighting - H.4',84.0000,28.0000,36),
(3,N'I.1',N'Outdoor Lighting - I.1',62.0000,88.0000,37),
(3,N'I.2',N'Outdoor Lighting - I.2',51.5000,88.0000,38),
(3,N'I.3',N'Outdoor Lighting - I.3',41.0000,88.0000,39),
(3,N'I.4',N'Outdoor Lighting - I.4',30.5000,88.0000,40),
(3,N'I.5',N'Outdoor Lighting - I.5',30.5000,12.0000,41),
(3,N'I.6',N'Outdoor Lighting - I.6',41.0000,12.0000,42),
(3,N'I.7',N'Outdoor Lighting - I.7',51.5000,12.0000,43),
(3,N'I.8',N'Outdoor Lighting - I.8',62.0000,12.0000,44),
(4,N'SB-01',N'Signboard Lighting - Segment 1',58.5000,24.5000,1),
(4,N'SB-02',N'Signboard Lighting - Segment 2',58.5000,31.7000,2),
(4,N'SB-03',N'Signboard Lighting - Segment 3',58.5000,38.9000,3),
(4,N'SB-04',N'Signboard Lighting - Segment 4',58.5000,46.1000,4),
(4,N'SB-05',N'Signboard Lighting - Segment 5',58.5000,53.3000,5),
(4,N'SB-06',N'Signboard Lighting - Segment 6',58.5000,60.5000,6),
(4,N'SB-07',N'Signboard Lighting - Segment 7',58.5000,67.7000,7),
(4,N'SB-08',N'Signboard Lighting - Segment 8',58.5000,74.9000,8),
(4,N'SB-09',N'Signboard Lighting - Segment 9',58.5000,82.1000,9),
(5,N'A.1',N'Logo M-LED Facade - Arah Sudirman',23.0000,16.0000,1),
(5,N'A.2',N'Logo M-LED Facade - Arah Walahar',80.0000,16.0000,2),
(5,N'A.3',N'Logo M-LED Facade - LED Vertical Sudirman',26.0000,44.0000,3),
(5,N'A.4',N'Logo M-LED Facade - LED Vertical Walahar',79.0000,44.0000,4),
(5,N'A.5',N'Logo M-LED Facade - LED Pillar Sudirman',24.0000,86.0000,5),
(5,N'A.6',N'Logo M-LED Facade - LED Pillar Walahar',80.0000,86.0000,6);

IF EXISTS (SELECT 1 FROM #LightingPoints WHERE MapX<0 OR MapX>100 OR MapY<0 OR MapY>100)
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('One or more plotted coordinates are outside the 0..100 map plane.',16,1);
    RETURN;
END;

/* Allocate IDs consistently with the existing MCDP seed convention. */
DECLARE @BasePointID BIGINT;
SELECT @BasePointID=ISNULL(MAX(InspectionPointID),0)
FROM dbo.PIP_M_InspectionPoint WITH (TABLOCKX,HOLDLOCK);

;WITH Missing AS
(
    SELECT S.MapID,S.PointCode,S.PointName,S.MapX,S.MapY,S.DisplayOrder,
           ROW_NUMBER() OVER (ORDER BY S.MapID,S.DisplayOrder,S.PointCode) AS RN
    FROM #LightingPoints S
    WHERE NOT EXISTS
    (
        SELECT 1 FROM dbo.PIP_M_InspectionPoint P
        WHERE P.MapID=S.MapID AND P.PointCode=S.PointCode
    )
)
INSERT INTO dbo.PIP_M_InspectionPoint
(InspectionPointID,InspectionTypeCode,InspectionTypeDetailCode,PointCode,PointName,PointObjectType,PointDescription,
 ObjectReferenceType,ObjectReferenceID,ObjectReferenceCode,MapID,MapX,MapY,DisplayOrder,IsActive,IsNormalAbnormalRequired,EntryUser,UpdateUser)
SELECT @BasePointID+RN,'LT','MCDP-LT',PointCode,PointName,'GENERAL',
       'Initial plotted coordinate from supplied lighting drawing; verify alignment in Inspection Master.',
       'GENERAL','',PointCode,MapID,MapX,MapY,DisplayOrder,1,0,@UserID,@UserID
FROM Missing;

COMMIT TRANSACTION;
GO

/* Verification: point totals and plotted coordinates by MapID. */
SELECT M.MapID,M.MapCode,M.MapName,COUNT(P.InspectionPointID) AS ActivePointCount,
       MIN(P.MapX) AS MinMapX,MAX(P.MapX) AS MaxMapX,MIN(P.MapY) AS MinMapY,MAX(P.MapY) AS MaxMapY
FROM dbo.PIP_M_InspectionMap M
LEFT JOIN dbo.PIP_M_InspectionPoint P ON P.MapID=M.MapID AND P.IsActive=1
WHERE M.MapID IN (3,4,5)
GROUP BY M.MapID,M.MapCode,M.MapName
ORDER BY M.MapID;
GO

SELECT MapID,PointCode,PointName,MapX,MapY,DisplayOrder
FROM dbo.PIP_M_InspectionPoint
WHERE MapID IN (3,4,5) AND IsActive=1
ORDER BY MapID,DisplayOrder,PointCode;
GO

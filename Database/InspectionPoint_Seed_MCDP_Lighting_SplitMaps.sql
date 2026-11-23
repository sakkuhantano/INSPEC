/*
    INSPEC - MCDP Lighting geometry correction (MapID 3, 4, 5)
    Replaces the earlier approximate seed coordinates and geometry.
    Coordinates are percentages (0..100) of the supplied source raster.
    Prerequisite: run Database/InspectionPoint_ShapeGeometry_Migration.sql first.
    Outdoor: B.1-B.4 curved PATH arcs; C.1-E.4 ORTHOGONAL outlines; H.1-H.4 and I.1-I.8 RECTANGLE frames; remaining F/G points CIRCLE markers.
    Signboard: nine RECTANGLE outlines aligned to the numbered panel frames.
    Logo facade: six CIRCLE inspection targets centered on the labelled assemblies.
    SQL Server 2008 compatible. Existing map master rows are not changed.
    IMPORTANT: coordinates and outlines are re-plotted from the source raster; inspect overlay alignment before operational use.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF COL_LENGTH('dbo.PIP_M_InspectionPoint','MapX') IS NULL
 OR COL_LENGTH('dbo.PIP_M_InspectionPoint','MapY') IS NULL
 OR COL_LENGTH('dbo.PIP_M_InspectionPoint','ShapeType') IS NULL
 OR COL_LENGTH('dbo.PIP_M_InspectionPoint','SvgPathData') IS NULL
 OR COL_LENGTH('dbo.PIP_M_InspectionPoint','ShapeAttributes') IS NULL
 OR COL_LENGTH('dbo.PIP_M_InspectionPoint','StrokeWidth') IS NULL
BEGIN
    RAISERROR('Coordinate and shape columns are required. Run InspectionPoint_Coordinate_Consolidation.sql and InspectionPoint_ShapeGeometry_Migration.sql first.',16,1);
    RETURN;
END;
GO

BEGIN TRANSACTION;
DECLARE @UserID VARCHAR(50);
SET @UserID='SYSTEM';

IF OBJECT_ID('tempdb..#ExpectedMaps') IS NOT NULL DROP TABLE #ExpectedMaps;
CREATE TABLE #ExpectedMaps
(
 MapID BIGINT NOT NULL, CompanyID VARCHAR(50) NOT NULL, LocationID VARCHAR(50) NOT NULL,
 MapCode VARCHAR(50) NOT NULL, InspectionTypeCode VARCHAR(2) NOT NULL, InspectionTypeDetailCode VARCHAR(20) NOT NULL
);
INSERT INTO #ExpectedMaps VALUES
(3,'I00024012','R02','MCDP-LT-OUTDOOR','LT','MCDP-LT'),
(4,'I00024012','R02','MCDP-LT-SIGNBOARD','LT','MCDP-LT'),
(5,'I00024012','R02','MCDP-LT-LOGO','LT','MCDP-LT');

IF EXISTS
(
 SELECT 1 FROM #ExpectedMaps E
 LEFT JOIN dbo.PIP_M_InspectionMap M ON M.MapID=E.MapID
  AND M.CompanyID=E.CompanyID AND M.LocationID=E.LocationID
  AND M.MapCode=E.MapCode AND M.InspectionTypeCode=E.InspectionTypeCode
  AND M.InspectionTypeDetailCode=E.InspectionTypeDetailCode AND M.IsActive=1
 WHERE M.MapID IS NULL
)
BEGIN
 ROLLBACK TRANSACTION;
 RAISERROR('Expected lighting map validation failed. No points were changed.',16,1);
 RETURN;
END;

IF OBJECT_ID('tempdb..#LightingPoints') IS NOT NULL DROP TABLE #LightingPoints;
CREATE TABLE #LightingPoints
(
 MapID BIGINT NOT NULL, PointCode VARCHAR(50) NOT NULL, PointName NVARCHAR(200) NOT NULL,
 MapX DECIMAL(9,4) NOT NULL, MapY DECIMAL(9,4) NOT NULL,
 ShapeType VARCHAR(20) NOT NULL, SvgPathData NVARCHAR(4000) NULL,
 ShapeAttributes NVARCHAR(1000) NOT NULL, DisplayOrder INT NOT NULL
);
INSERT INTO #LightingPoints
(MapID,PointCode,PointName,MapX,MapY,ShapeType,SvgPathData,ShapeAttributes,DisplayOrder)
VALUES
(3,N'B.1',N'Outdoor Lighting - B.1',50.1035,73.9421,N'PATH',N'M 28.3644 50.7795 L 29.1925 57.9065 L 32.7122 63.9198 L 37.8882 68.8196 L 43.6853 72.3831 L 50.1035 73.9421 L 56.5217 72.3831 L 62.3188 68.8196 L 67.4948 63.9198 L 71.0145 57.9065 L 71.8427 50.7795',N'{"coordinateSpace":"PERCENT_100","closed":false}',1),
(3,N'B.2',N'Outdoor Lighting - B.2',28.3644,50.7795,N'PATH',N'M 50.1035 27.6169 L 43.6853 29.1759 L 37.8882 32.7394 L 32.7122 37.6392 L 29.1925 43.6526 L 28.3644 50.7795',N'{"coordinateSpace":"PERCENT_100","closed":false}',2),
(3,N'B.3',N'Outdoor Lighting - B.3',50.1035,27.6169,N'PATH',N'M 28.3644 50.7795 L 29.1925 43.6526 L 32.7122 37.6392 L 37.8882 32.7394 L 43.6853 29.1759 L 50.1035 27.6169 L 56.5217 29.1759 L 62.3188 32.7394 L 67.4948 37.6392 L 71.0145 43.6526 L 71.8427 50.7795',N'{"coordinateSpace":"PERCENT_100","closed":false}',3),
(3,N'B.4',N'Outdoor Lighting - B.4',71.8427,50.7795,N'PATH',N'M 50.1035 27.6169 L 56.5217 29.1759 L 62.3188 32.7394 L 67.4948 37.6392 L 71.0145 43.6526 L 71.8427 50.7795 L 71.0145 57.9065 L 67.4948 63.9198 L 62.3188 68.8196 L 56.5217 72.3831 L 50.1035 73.9421',N'{"coordinateSpace":"PERCENT_100","closed":false}',4),
(3,N'C.1',N'Outdoor Lighting - C.1',72.6708,69.9332,N'ORTHOGONAL',N'M 72.0083 67.9287 L 73.3333 67.9287 L 73.3333 71.9376 L 72.0083 71.9376 L 72.0083 67.9287',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',5),
(3,N'C.2',N'Outdoor Lighting - C.2',26.7081,69.9332,N'ORTHOGONAL',N'M 26.0455 67.9287 L 27.3706 67.9287 L 27.3706 71.9376 L 26.0455 71.9376 L 26.0455 67.9287',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',6),
(3,N'C.3',N'Outdoor Lighting - C.3',26.7081,30.0668,N'ORTHOGONAL',N'M 26.0455 28.0624 L 27.3706 28.0624 L 27.3706 32.0713 L 26.0455 32.0713 L 26.0455 28.0624',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',7),
(3,N'C.4',N'Outdoor Lighting - C.4',72.6708,30.0668,N'ORTHOGONAL',N'M 72.0083 28.0624 L 73.3333 28.0624 L 73.3333 32.0713 L 72.0083 32.0713 L 72.0083 28.0624',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',8),
(3,N'D.1',N'Outdoor Lighting - D.1',69.7723,68.1514,N'ORTHOGONAL',N'M 69.1097 66.147 L 70.4348 66.147 L 70.4348 70.1559 L 69.1097 70.1559 L 69.1097 66.147',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',9),
(3,N'D.2',N'Outdoor Lighting - D.2',23.8095,68.1514,N'ORTHOGONAL',N'M 23.147 66.147 L 24.472 66.147 L 24.472 70.1559 L 23.147 70.1559 L 23.147 66.147',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',10),
(3,N'D.3',N'Outdoor Lighting - D.3',23.8095,31.8486,N'ORTHOGONAL',N'M 23.147 29.8441 L 24.472 29.8441 L 24.472 33.853 L 23.147 33.853 L 23.147 29.8441',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',11),
(3,N'D.4',N'Outdoor Lighting - D.4',69.7723,31.8486,N'ORTHOGONAL',N'M 69.1097 29.8441 L 70.4348 29.8441 L 70.4348 33.853 L 69.1097 33.853 L 69.1097 29.8441',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',12),
(3,N'E.1',N'Outdoor Lighting - E.1',73.9130,65.0334,N'ORTHOGONAL',N'M 73.2505 63.029 L 74.5756 63.029 L 74.5756 67.0379 L 73.2505 67.0379 L 73.2505 63.029',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',13),
(3,N'E.2',N'Outdoor Lighting - E.2',20.4969,65.0334,N'ORTHOGONAL',N'M 19.8344 63.029 L 21.1594 63.029 L 21.1594 67.0379 L 19.8344 67.0379 L 19.8344 63.029',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',14),
(3,N'E.3',N'Outdoor Lighting - E.3',20.4969,34.9666,N'ORTHOGONAL',N'M 19.8344 32.9621 L 21.1594 32.9621 L 21.1594 36.971 L 19.8344 36.971 L 19.8344 32.9621',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',15),
(3,N'E.4',N'Outdoor Lighting - E.4',73.9130,34.9666,N'ORTHOGONAL',N'M 73.2505 32.9621 L 74.5756 32.9621 L 74.5756 36.971 L 73.2505 36.971 L 73.2505 32.9621',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',16),
(3,N'F.1',N'Outdoor Lighting - F.1',31.6770,77.5056,N'CIRCLE',NULL,N'{"cx":31.677,"cy":77.5056,"r":1.8}',17),
(3,N'F.2',N'Outdoor Lighting - F.2',42.0290,77.5056,N'CIRCLE',NULL,N'{"cx":42.029,"cy":77.5056,"r":1.8}',18),
(3,N'F.3',N'Outdoor Lighting - F.3',51.9669,77.5056,N'CIRCLE',NULL,N'{"cx":51.9669,"cy":77.5056,"r":1.8}',19),
(3,N'F.4',N'Outdoor Lighting - F.4',62.3188,77.5056,N'CIRCLE',NULL,N'{"cx":62.3188,"cy":77.5056,"r":1.8}',20),
(3,N'F.5',N'Outdoor Lighting - F.5',31.6770,23.3853,N'CIRCLE',NULL,N'{"cx":31.677,"cy":23.3853,"r":1.8}',21),
(3,N'F.6',N'Outdoor Lighting - F.6',42.0290,23.3853,N'CIRCLE',NULL,N'{"cx":42.029,"cy":23.3853,"r":1.8}',22),
(3,N'F.7',N'Outdoor Lighting - F.7',51.9669,23.3853,N'CIRCLE',NULL,N'{"cx":51.9669,"cy":23.3853,"r":1.8}',23),
(3,N'F.8',N'Outdoor Lighting - F.8',62.3188,23.3853,N'CIRCLE',NULL,N'{"cx":62.3188,"cy":23.3853,"r":1.8}',24),
(3,N'G.1',N'Outdoor Lighting - G.1',62.3188,94.6548,N'CIRCLE',NULL,N'{"cx":62.3188,"cy":94.6548,"r":1.8}',25),
(3,N'G.2',N'Outdoor Lighting - G.2',51.9669,94.6548,N'CIRCLE',NULL,N'{"cx":51.9669,"cy":94.6548,"r":1.8}',26),
(3,N'G.3',N'Outdoor Lighting - G.3',42.0290,94.6548,N'CIRCLE',NULL,N'{"cx":42.029,"cy":94.6548,"r":1.8}',27),
(3,N'G.4',N'Outdoor Lighting - G.4',31.6770,94.6548,N'CIRCLE',NULL,N'{"cx":31.677,"cy":94.6548,"r":1.8}',28),
(3,N'G.5',N'Outdoor Lighting - G.5',31.6770,6.2361,N'CIRCLE',NULL,N'{"cx":31.677,"cy":6.2361,"r":1.8}',29),
(3,N'G.6',N'Outdoor Lighting - G.6',42.0290,6.2361,N'CIRCLE',NULL,N'{"cx":42.029,"cy":6.2361,"r":1.8}',30),
(3,N'G.7',N'Outdoor Lighting - G.7',51.9669,6.2361,N'CIRCLE',NULL,N'{"cx":51.9669,"cy":6.2361,"r":1.8}',31),
(3,N'G.8',N'Outdoor Lighting - G.8',62.3188,6.2361,N'CIRCLE',NULL,N'{"cx":62.3188,"cy":6.2361,"r":1.8}',32),
(3,N'H.1',N'Outdoor Lighting - H.1',72.8778,NaN,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":75.5694,"y":72.6058,"width":9.9378,"height":11.5813}',33),
(3,N'H.2',N'Outdoor Lighting - H.2',72.8778,NaN,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":14.4928,"y":72.6058,"width":8.9026,"height":11.5813}',34),
(3,N'H.3',N'Outdoor Lighting - H.3',19.8758,NaN,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":14.4928,"y":15.5902,"width":8.9026,"height":12.0267}',35),
(3,N'H.4',N'Outdoor Lighting - H.4',19.8758,NaN,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":75.5694,"y":15.5902,"width":9.9378,"height":12.0267}',36),
(3,N'I.1',N'Outdoor Lighting - I.1',62.1118,85.5234,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":60.8696,"y":81.2918,"width":2.4844,"height":8.9086}',37),
(3,N'I.2',N'Outdoor Lighting - I.2',51.9669,85.5234,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":50.7246,"y":81.2918,"width":2.4845,"height":8.9086}',38),
(3,N'I.3',N'Outdoor Lighting - I.3',42.0290,85.5234,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":40.7867,"y":81.2918,"width":2.4845,"height":8.9086}',39),
(3,N'I.4',N'Outdoor Lighting - I.4',31.6770,85.5234,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":30.4348,"y":81.2918,"width":2.4845,"height":8.9086}',40),
(3,N'I.5',N'Outdoor Lighting - I.5',31.6770,14.2539,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":30.4348,"y":9.7996,"width":2.4845,"height":9.3541}',41),
(3,N'I.6',N'Outdoor Lighting - I.6',42.0290,14.2539,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":40.7867,"y":9.7996,"width":2.4845,"height":9.3541}',42),
(3,N'I.7',N'Outdoor Lighting - I.7',51.9669,14.2539,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":50.7246,"y":9.7996,"width":2.4845,"height":9.3541}',43),
(3,N'I.8',N'Outdoor Lighting - I.8',62.1118,14.2539,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":60.8696,"y":9.7996,"width":2.4844,"height":9.3541}',44),
(4,N'SB-01',N'Signboard Lighting - Segment 1',48.2328,27.1429,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":39.9168,"y":23.1169,"width":16.6321,"height":8.0519}',1),
(4,N'SB-02',N'Signboard Lighting - Segment 2',48.2328,34.6753,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":39.9168,"y":31.1688,"width":16.6321,"height":7.013}',2),
(4,N'SB-03',N'Signboard Lighting - Segment 3',48.2328,41.8182,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":39.9168,"y":38.1818,"width":16.6321,"height":7.2727}',3),
(4,N'SB-04',N'Signboard Lighting - Segment 4',48.2328,49.0909,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":39.9168,"y":45.4545,"width":16.6321,"height":7.2728}',4),
(4,N'SB-05',N'Signboard Lighting - Segment 5',48.2328,56.3636,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":39.9168,"y":52.7273,"width":16.6321,"height":7.2727}',5),
(4,N'SB-06',N'Signboard Lighting - Segment 6',48.2328,63.6364,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":39.9168,"y":60,"width":16.6321,"height":7.2727}',6),
(4,N'SB-07',N'Signboard Lighting - Segment 7',48.2328,70.9091,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":39.9168,"y":67.2727,"width":16.6321,"height":7.2728}',7),
(4,N'SB-08',N'Signboard Lighting - Segment 8',48.2328,78.1818,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":39.9168,"y":74.5455,"width":16.6321,"height":7.2727}',8),
(4,N'SB-09',N'Signboard Lighting - Segment 9',48.2328,85.5844,N'RECTANGLE',NULL,N'{"coordinateSpace":"PERCENT_100","x":39.9168,"y":81.8182,"width":16.6321,"height":7.5324}',9),
(5,N'A.1',N'Logo M-LED Facade - A.1',16.0221,14.5089,N'CIRCLE',NULL,N'{"cx":16.0221,"cy":14.5089,"r":1.6}',1),
(5,N'A.2',N'Logo M-LED Facade - A.2',73.4807,14.5089,N'CIRCLE',NULL,N'{"cx":73.4807,"cy":14.5089,"r":1.6}',2),
(5,N'A.3',N'Logo M-LED Facade - A.3',24.3094,39.0625,N'CIRCLE',NULL,N'{"cx":24.3094,"cy":39.0625,"r":1.6}',3),
(5,N'A.4',N'Logo M-LED Facade - A.4',75.6906,39.0625,N'CIRCLE',NULL,N'{"cx":75.6906,"cy":39.0625,"r":1.6}',4),
(5,N'A.5',N'Logo M-LED Facade - A.5',19.3370,72.7679,N'CIRCLE',NULL,N'{"cx":19.337,"cy":72.7679,"r":1.6}',5),
(5,N'A.6',N'Logo M-LED Facade - A.6',76.7956,72.7679,N'CIRCLE',NULL,N'{"cx":76.7956,"cy":72.7679,"r":1.6}',6);

IF EXISTS
(
 SELECT 1 FROM #LightingPoints
 WHERE MapX<0 OR MapX>100 OR MapY<0 OR MapY>100
  OR ShapeType NOT IN ('CIRCLE','RECTANGLE','PATH','ORTHOGONAL')
)
BEGIN
 ROLLBACK TRANSACTION;
 RAISERROR('Invalid coordinate or shape in correction data. No points were changed.',16,1);
 RETURN;
END;

/* Update existing active point codes first: unlike the old seed, this corrects
   previously inserted approximate coordinates and geometry. */
UPDATE P
 SET P.PointName=S.PointName,
     P.MapX=S.MapX,
     P.MapY=S.MapY,
     P.ShapeType=CASE WHEN S.ShapeType='ORTHOGONAL' THEN 'PATH' ELSE S.ShapeType END,
     P.SvgPathData=S.SvgPathData,
     P.ShapeAttributes=S.ShapeAttributes,
     P.DisplayOrder=S.DisplayOrder,
     P.UpdateUser=@UserID
FROM dbo.PIP_M_InspectionPoint P
INNER JOIN #LightingPoints S ON S.MapID=P.MapID AND S.PointCode=P.PointCode
WHERE P.IsActive=1;

/* Insert only point codes that do not exist, preserving the existing ID sequence. */
DECLARE @BasePointID BIGINT;
SELECT @BasePointID=ISNULL(MAX(InspectionPointID),0)
FROM dbo.PIP_M_InspectionPoint WITH (TABLOCKX,HOLDLOCK);

;WITH Missing AS
(
 SELECT S.*,
        ROW_NUMBER() OVER (ORDER BY S.MapID,S.DisplayOrder,S.PointCode) AS RN
 FROM #LightingPoints S
 WHERE NOT EXISTS
 (
  SELECT 1 FROM dbo.PIP_M_InspectionPoint P
  WHERE P.MapID=S.MapID AND P.PointCode=S.PointCode
 )
)
INSERT INTO dbo.PIP_M_InspectionPoint
(InspectionPointID,PointCode,PointName,PointObjectType,PointDescription,
 ObjectReferenceType,ObjectReferenceID,ObjectReferenceCode,MapID,MapX,MapY,
 ShapeType,SvgPathData,ShapeAttributes,StrokeWidth,DisplayOrder,IsActive,
 IsNormalAbnormalRequired,EntryUser,UpdateUser)
SELECT @BasePointID+RN,PointCode,PointName,'GENERAL',
       'Geometry plotted from supplied MCDP lighting drawing; verify overlay alignment.',
       'GENERAL','',PointCode,MapID,MapX,MapY,
       CASE WHEN ShapeType='ORTHOGONAL' THEN 'PATH' ELSE ShapeType END,
       SvgPathData,ShapeAttributes,1.5,DisplayOrder,1,0,@UserID,@UserID
FROM Missing;

COMMIT TRANSACTION;
GO

/* Verify counts and geometry types after correction. */
SELECT M.MapID,M.MapCode,M.MapName,P.ShapeType,COUNT(*) AS PointCount
FROM dbo.PIP_M_InspectionMap M
INNER JOIN dbo.PIP_M_InspectionPoint P ON P.MapID=M.MapID AND P.IsActive=1
WHERE M.MapID IN (3,4,5)
GROUP BY M.MapID,M.MapCode,M.MapName,P.ShapeType
ORDER BY M.MapID,P.ShapeType;
GO

SELECT MapID,PointCode,MapX,MapY,ShapeType,SvgPathData,ShapeAttributes,DisplayOrder
FROM dbo.PIP_M_InspectionPoint
WHERE MapID IN (3,4,5) AND IsActive=1
ORDER BY MapID,DisplayOrder,PointCode;
GO

/*
    INSPEC - MCDP Lighting geometry correction (MapID 3, 4, 5)
    Replaces the earlier approximate seed coordinates and geometry.
    Coordinates are percentages (0..100) of the supplied source raster.
    Prerequisite: run Database/InspectionPoint_ShapeGeometry_Migration.sql first.
    Outdoor: discrete CIRCLE markers, ORTHOGONAL fixture runs, and PATH curved runs.
    Signboard: nine RECTANGLE outlines aligned to the numbered panel frames.
    Logo facade: six CIRCLE inspection targets centered on the labelled assemblies.
    SQL Server 2008 compatible. Existing map master rows are not changed.
    IMPORTANT: review the overlay visually after execution; these are raster-derived
    coordinates, not survey measurements.
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
(3,N'B.1',N'Outdoor Lighting - B.1',46.7909,70.1559,N'CIRCLE',NULL,N'{"cx":46.7909,"cy":70.1559,"r":1.6}',1),
(3,N'B.2',N'Outdoor Lighting - B.2',32.7122,49.4432,N'CIRCLE',NULL,N'{"cx":32.7122,"cy":49.4432,"r":1.6}',2),
(3,N'B.3',N'Outdoor Lighting - B.3',46.7909,31.6258,N'CIRCLE',NULL,N'{"cx":46.7909,"cy":31.6258,"r":1.6}',3),
(3,N'B.4',N'Outdoor Lighting - B.4',63.3540,49.4432,N'CIRCLE',NULL,N'{"cx":63.354,"cy":49.4432,"r":1.6}',4),
(3,N'C.1',N'Outdoor Lighting - C.1',73.0849,66.8151,N'CIRCLE',NULL,N'{"cx":73.0849,"cy":66.8151,"r":1.6}',5),
(3,N'C.2',N'Outdoor Lighting - C.2',26.5010,73.4967,N'CIRCLE',NULL,N'{"cx":26.501,"cy":73.4967,"r":1.6}',6),
(3,N'C.3',N'Outdoor Lighting - C.3',26.5010,27.3942,N'CIRCLE',NULL,N'{"cx":26.501,"cy":27.3942,"r":1.6}',7),
(3,N'C.4',N'Outdoor Lighting - C.4',73.0849,27.3942,N'CIRCLE',NULL,N'{"cx":73.0849,"cy":27.3942,"r":1.6}',8),
(3,N'D.1',N'Outdoor Lighting - D.1',69.9793,70.6013,N'CIRCLE',NULL,N'{"cx":69.9793,"cy":70.6013,"r":1.6}',9),
(3,N'D.2',N'Outdoor Lighting - D.2',24.0166,70.6013,N'CIRCLE',NULL,N'{"cx":24.0166,"cy":70.6013,"r":1.6}',10),
(3,N'D.3',N'Outdoor Lighting - D.3',24.0166,30.2895,N'CIRCLE',NULL,N'{"cx":24.0166,"cy":30.2895,"r":1.6}',11),
(3,N'D.4',N'Outdoor Lighting - D.4',69.9793,30.2895,N'CIRCLE',NULL,N'{"cx":69.9793,"cy":30.2895,"r":1.6}',12),
(3,N'E.1',N'Outdoor Lighting - E.1',73.9130,67.9287,N'CIRCLE',NULL,N'{"cx":73.913,"cy":67.9287,"r":1.6}',13),
(3,N'E.2',N'Outdoor Lighting - E.2',20.9110,67.9287,N'CIRCLE',NULL,N'{"cx":20.911,"cy":67.9287,"r":1.6}',14),
(3,N'E.3',N'Outdoor Lighting - E.3',20.9110,32.2940,N'CIRCLE',NULL,N'{"cx":20.911,"cy":32.294,"r":1.6}',15),
(3,N'E.4',N'Outdoor Lighting - E.4',73.9130,32.2940,N'CIRCLE',NULL,N'{"cx":73.913,"cy":32.294,"r":1.6}',16),
(3,N'F.1',N'Outdoor Lighting - F.1',31.6770,77.5056,N'ORTHOGONAL',N'M 31.677 77.5056 L 31.677 74.1648',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',17),
(3,N'F.2',N'Outdoor Lighting - F.2',41.8219,77.5056,N'ORTHOGONAL',N'M 41.8219 77.5056 L 41.8219 74.1648',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',18),
(3,N'F.3',N'Outdoor Lighting - F.3',51.9669,77.5056,N'ORTHOGONAL',N'M 51.9669 77.5056 L 51.9669 74.1648',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',19),
(3,N'F.4',N'Outdoor Lighting - F.4',62.1118,77.5056,N'ORTHOGONAL',N'M 62.1118 77.5056 L 62.1118 74.1648',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',20),
(3,N'F.5',N'Outdoor Lighting - F.5',31.6770,22.9399,N'ORTHOGONAL',N'M 31.677 22.9399 L 31.677 26.2806',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',21),
(3,N'F.6',N'Outdoor Lighting - F.6',41.8219,22.9399,N'ORTHOGONAL',N'M 41.8219 22.9399 L 41.8219 26.2806',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',22),
(3,N'F.7',N'Outdoor Lighting - F.7',51.9669,22.9399,N'ORTHOGONAL',N'M 51.9669 22.9399 L 51.9669 26.2806',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',23),
(3,N'F.8',N'Outdoor Lighting - F.8',62.1118,22.9399,N'ORTHOGONAL',N'M 62.1118 22.9399 L 62.1118 26.2806',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',24),
(3,N'G.1',N'Outdoor Lighting - G.1',62.1118,94.4321,N'ORTHOGONAL',N'M 62.1118 94.4321 L 62.1118 91.314',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',25),
(3,N'G.2',N'Outdoor Lighting - G.2',51.9669,94.4321,N'ORTHOGONAL',N'M 51.9669 94.4321 L 51.9669 91.314',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',26),
(3,N'G.3',N'Outdoor Lighting - G.3',41.8219,94.4321,N'ORTHOGONAL',N'M 41.8219 94.4321 L 41.8219 91.314',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',27),
(3,N'G.4',N'Outdoor Lighting - G.4',31.6770,94.4321,N'ORTHOGONAL',N'M 31.677 94.4321 L 31.677 91.314',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',28),
(3,N'G.5',N'Outdoor Lighting - G.5',31.6770,6.4588,N'ORTHOGONAL',N'M 31.677 6.4588 L 31.677 9.5768',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',29),
(3,N'G.6',N'Outdoor Lighting - G.6',41.8219,6.4588,N'ORTHOGONAL',N'M 41.8219 6.4588 L 41.8219 9.5768',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',30),
(3,N'G.7',N'Outdoor Lighting - G.7',51.9669,6.4588,N'ORTHOGONAL',N'M 51.9669 6.4588 L 51.9669 9.5768',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',31),
(3,N'G.8',N'Outdoor Lighting - G.8',62.1118,6.4588,N'ORTHOGONAL',N'M 62.1118 6.4588 L 62.1118 9.5768',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',32),
(3,N'I.1',N'Outdoor Lighting - I.1',62.1118,85.0780,N'ORTHOGONAL',N'M 62.1118 85.078 L 62.1118 81.5145',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',33),
(3,N'I.2',N'Outdoor Lighting - I.2',51.9669,85.0780,N'ORTHOGONAL',N'M 51.9669 85.078 L 51.9669 81.5145',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',34),
(3,N'I.3',N'Outdoor Lighting - I.3',41.8219,85.0780,N'ORTHOGONAL',N'M 41.8219 85.078 L 41.8219 81.5145',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',35),
(3,N'I.4',N'Outdoor Lighting - I.4',31.6770,85.0780,N'ORTHOGONAL',N'M 31.677 85.078 L 31.677 81.5145',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',36),
(3,N'I.5',N'Outdoor Lighting - I.5',31.6770,14.6993,N'ORTHOGONAL',N'M 31.677 14.6993 L 31.677 18.2628',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',37),
(3,N'I.6',N'Outdoor Lighting - I.6',41.8219,14.6993,N'ORTHOGONAL',N'M 41.8219 14.6993 L 41.8219 18.2628',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',38),
(3,N'I.7',N'Outdoor Lighting - I.7',51.9669,14.6993,N'ORTHOGONAL',N'M 51.9669 14.6993 L 51.9669 18.2628',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',39),
(3,N'I.8',N'Outdoor Lighting - I.8',62.1118,14.6993,N'ORTHOGONAL',N'M 62.1118 14.6993 L 62.1118 18.2628',N'{"coordinateSpace":"PERCENT_100","closed":false,"renderMode":"ORTHOGONAL"}',40),
(3,N'H.1',N'Outdoor Lighting - H.1',77.6398,78.3964,N'PATH',N'M 78.5 74.0 L 81.0 78.0 L 83.5 82.0',N'{"coordinateSpace":"PERCENT_100","closed":false}',41),
(3,N'H.2',N'Outdoor Lighting - H.2',18.8406,78.3964,N'PATH',N'M 19.0 82.0 L 16.5 78.0 L 14.0 74.0',N'{"coordinateSpace":"PERCENT_100","closed":false}',42),
(3,N'H.3',N'Outdoor Lighting - H.3',18.8406,21.1581,N'PATH',N'M 14.0 26.0 L 16.5 22.0 L 19.0 18.0',N'{"coordinateSpace":"PERCENT_100","closed":false}',43),
(3,N'H.4',N'Outdoor Lighting - H.4',77.6398,21.1581,N'PATH',N'M 83.5 18.0 L 81.0 22.0 L 78.5 26.0',N'{"coordinateSpace":"PERCENT_100","closed":false}',44),
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

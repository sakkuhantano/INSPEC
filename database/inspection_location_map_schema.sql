/*
    Location / Map based Inspection
    Branch: feature/inspection-location-map
    SQL Server 2008 compatible.

    Design:
      - PIP_T_Inspection remains the existing transaction HEADER / BATCH.
      - One batch = one inspection execution:
          Company + Location + InspectionType + InspectionTypeDetail/Schedule
          + InspectionDate + Inspector + Template/Version.
      - One batch can contain many InspectionPoint transactions.
      - One InspectionPoint is the master object/location to be inspected.
      - A point belongs to one InspectionType + InspectionTypeDetail.
      - A point may be displayed on a map, but a map is not mandatory.
      - Existing PIP_T_InspectionResult / Photo are extended so legacy
        transactions continue to use InspectionID while map transactions
        additionally use InspectionPointTransactionID.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ============================================================
   1. MASTER MAP
   ============================================================ */
IF OBJECT_ID('dbo.PIP_M_InspectionMap', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_M_InspectionMap
    (
        MapID BIGINT NOT NULL,
        CompanyID VARCHAR(10) NOT NULL,
        LocationID VARCHAR(3) NOT NULL,
        MapCode VARCHAR(50) NOT NULL,
        MapName VARCHAR(200) NOT NULL,
        ImagePath VARCHAR(500) NOT NULL CONSTRAINT DF_PIP_M_InspectionMap_ImagePath DEFAULT (''),
        ViewBoxX DECIMAL(18,4) NOT NULL CONSTRAINT DF_PIP_M_InspectionMap_ViewBoxX DEFAULT (0),
        ViewBoxY DECIMAL(18,4) NOT NULL CONSTRAINT DF_PIP_M_InspectionMap_ViewBoxY DEFAULT (0),
        ViewBoxWidth DECIMAL(18,4) NOT NULL CONSTRAINT DF_PIP_M_InspectionMap_ViewBoxWidth DEFAULT (0),
        ViewBoxHeight DECIMAL(18,4) NOT NULL CONSTRAINT DF_PIP_M_InspectionMap_ViewBoxHeight DEFAULT (0),
        MapVersion INT NOT NULL CONSTRAINT DF_PIP_M_InspectionMap_MapVersion DEFAULT (1),
        IsCurrentVersion BIT NOT NULL CONSTRAINT DF_PIP_M_InspectionMap_IsCurrentVersion DEFAULT (1),
        IsActive BIT NOT NULL CONSTRAINT DF_PIP_M_InspectionMap_IsActive DEFAULT (1),
        Description VARCHAR(500) NOT NULL CONSTRAINT DF_PIP_M_InspectionMap_Description DEFAULT (''),
        EntryUser VARCHAR(50) NOT NULL,
        EntryDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionMap_EntryDate DEFAULT (GETDATE()),
        UpdateUser VARCHAR(50) NOT NULL,
        UpdateDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionMap_UpdateDate DEFAULT (GETDATE()),

        CONSTRAINT PK_PIP_M_InspectionMap PRIMARY KEY CLUSTERED (MapID),
        CONSTRAINT UQ_PIP_M_InspectionMap_Version
            UNIQUE (CompanyID, LocationID, MapCode, MapVersion),
        CONSTRAINT CK_PIP_M_InspectionMap_Version CHECK (MapVersion >= 1),
        CONSTRAINT CK_PIP_M_InspectionMap_Size CHECK
        (
            ViewBoxWidth > 0 AND ViewBoxHeight > 0
        )
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_M_InspectionMap')
      AND name = 'UX_PIP_M_InspectionMap_Current'
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_PIP_M_InspectionMap_Current
        ON dbo.PIP_M_InspectionMap
        (CompanyID, LocationID, MapCode)
        WHERE IsCurrentVersion = 1;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_M_InspectionMap')
      AND name = 'IX_PIP_M_InspectionMap_Location'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_M_InspectionMap_Location
        ON dbo.PIP_M_InspectionMap
        (CompanyID, LocationID, IsActive, IsCurrentVersion);
END;
GO

/* ============================================================
   2. MAP ELEMENT / DRAWING OBJECT
   ============================================================ */
IF OBJECT_ID('dbo.PIP_M_InspectionMapElement', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_M_InspectionMapElement
    (
        MapElementID BIGINT NOT NULL,
        MapID BIGINT NOT NULL,
        InspectionPointID BIGINT NULL,
        ElementID VARCHAR(100) NOT NULL,
        ShapeType VARCHAR(20) NOT NULL,
        SvgPathData VARCHAR(8000) NOT NULL CONSTRAINT DF_PIP_M_InspectionMapElement_SvgPathData DEFAULT (''),
        ShapeAttributes VARCHAR(1000) NOT NULL CONSTRAINT DF_PIP_M_InspectionMapElement_ShapeAttributes DEFAULT (''),
        StrokeWidth DECIMAL(10,2) NOT NULL CONSTRAINT DF_PIP_M_InspectionMapElement_StrokeWidth DEFAULT (5),
        DisplayOrder INT NOT NULL CONSTRAINT DF_PIP_M_InspectionMapElement_DisplayOrder DEFAULT (0),
        IsVisible BIT NOT NULL CONSTRAINT DF_PIP_M_InspectionMapElement_IsVisible DEFAULT (1),
        IsActive BIT NOT NULL CONSTRAINT DF_PIP_M_InspectionMapElement_IsActive DEFAULT (1),
        IsDeleted BIT NOT NULL CONSTRAINT DF_PIP_M_InspectionMapElement_IsDeleted DEFAULT (0),
        DeletedBy VARCHAR(50) NOT NULL CONSTRAINT DF_PIP_M_InspectionMapElement_DeletedBy DEFAULT (''),
        DeletedDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionMapElement_DeletedDate DEFAULT ('19000101'),
        EntryUser VARCHAR(50) NOT NULL,
        EntryDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionMapElement_EntryDate DEFAULT (GETDATE()),
        UpdateUser VARCHAR(50) NOT NULL,
        UpdateDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionMapElement_UpdateDate DEFAULT (GETDATE()),

        CONSTRAINT PK_PIP_M_InspectionMapElement PRIMARY KEY CLUSTERED (MapElementID),
        CONSTRAINT UQ_PIP_M_InspectionMapElement_Element
            UNIQUE (MapID, ElementID),
        CONSTRAINT FK_PIP_M_InspectionMapElement_Map
            FOREIGN KEY (MapID)
            REFERENCES dbo.PIP_M_InspectionMap(MapID),
        CONSTRAINT CK_PIP_M_InspectionMapElement_ShapeType CHECK
        (
            ShapeType IN
            ('ELLIPSE','RECT','CIRCLE','LINE','POLYLINE','PATH','POLYGON','TEXT')
        ),
        CONSTRAINT CK_PIP_M_InspectionMapElement_StrokeWidth CHECK
        (
            StrokeWidth >= 0
        )
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_M_InspectionMapElement')
      AND name = 'IX_PIP_M_InspectionMapElement_Point'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_M_InspectionMapElement_Point
        ON dbo.PIP_M_InspectionMapElement
        (InspectionPointID, MapID, IsActive, IsDeleted);
END;
GO

/* ============================================================
   3. MASTER INSPECTION POINT
   ============================================================ */
IF OBJECT_ID('dbo.PIP_M_InspectionPoint', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_M_InspectionPoint
    (
        InspectionPointID BIGINT NOT NULL,
        /*
           The point itself belongs to exactly one inspection
           type/detail scope. The actual template/version used
           for a batch is frozen on PIP_T_Inspection.
        */
        InspectionTypeCode VARCHAR(2) NOT NULL,
        InspectionTypeDetailCode VARCHAR(20) NOT NULL,

        PointCode VARCHAR(50) NOT NULL,
        PointName VARCHAR(200) NOT NULL,
        PointObjectType VARCHAR(30) NOT NULL,
        PointDescription VARCHAR(500) NOT NULL CONSTRAINT DF_PIP_M_InspectionPoint_Description DEFAULT (''),
        IsNormalAbnormalRequired BIT NOT NULL CONSTRAINT DF_PIP_M_InspectionPoint_IsNormalAbnormalRequired DEFAULT (0),

        /*
           Universal master-object reference.
           Examples:
             LIGHTING   -> Lighting master ID
             TRANSFORMER-> Transformer master ID
             GENSET     -> Genset master ID
             PARKING_BAY-> parking bay master ID if one exists
           ObjectReferenceID is intentionally generic because the
           actual master table differs by object type.
        */
        ObjectReferenceType VARCHAR(30) NOT NULL CONSTRAINT DF_PIP_M_InspectionPoint_ObjectReferenceType DEFAULT (''),
        ObjectReferenceID VARCHAR(50) NOT NULL CONSTRAINT DF_PIP_M_InspectionPoint_ObjectReferenceID DEFAULT (''),
        ObjectReferenceCode VARCHAR(100) NOT NULL CONSTRAINT DF_PIP_M_InspectionPoint_ObjectReferenceCode DEFAULT (''),

        MapID BIGINT NULL,

        DisplayOrder INT NOT NULL CONSTRAINT DF_PIP_M_InspectionPoint_DisplayOrder DEFAULT (0),
        IsActive BIT NOT NULL CONSTRAINT DF_PIP_M_InspectionPoint_IsActive DEFAULT (1),
        EntryUser VARCHAR(50) NOT NULL,
        EntryDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionPoint_EntryDate DEFAULT (GETDATE()),
        UpdateUser VARCHAR(50) NOT NULL,
        UpdateDate DATETIME NOT NULL CONSTRAINT DF_PIP_M_InspectionPoint_UpdateDate DEFAULT (GETDATE()),

        CONSTRAINT PK_PIP_M_InspectionPoint PRIMARY KEY CLUSTERED (InspectionPointID),

        CONSTRAINT FK_PIP_M_InspectionPoint_Map
            FOREIGN KEY (MapID)
            REFERENCES dbo.PIP_M_InspectionMap(MapID)
    );
END;
GO


/* PointCode is unique inside its Map. Company/Location scope is inherited
   from PIP_M_InspectionMap through MapID. */
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_M_InspectionPoint')
      AND name = 'UX_PIP_M_InspectionPoint_Map_PointCode'
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_PIP_M_InspectionPoint_Map_PointCode
        ON dbo.PIP_M_InspectionPoint (MapID, PointCode)
        WHERE MapID IS NOT NULL;
END;
GO

/* ============================================================
   4. ADD POINT REFERENCE TO MAP ELEMENT
   ============================================================ */
IF COL_LENGTH('dbo.PIP_M_InspectionMapElement', 'InspectionPointID') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_M_InspectionMapElement
        ADD InspectionPointID BIGINT NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_PIP_M_InspectionMapElement_Point'
      AND parent_object_id = OBJECT_ID('dbo.PIP_M_InspectionMapElement')
)
BEGIN
    ALTER TABLE dbo.PIP_M_InspectionMapElement
        ADD CONSTRAINT FK_PIP_M_InspectionMapElement_Point
        FOREIGN KEY (InspectionPointID)
        REFERENCES dbo.PIP_M_InspectionPoint(InspectionPointID);
END;
GO

/* ============================================================
   5. EXTEND EXISTING PIP_T_Inspection AS BATCH HEADER
   ============================================================ */
IF COL_LENGTH('dbo.PIP_T_Inspection', 'InspectionMode') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_T_Inspection
        ADD InspectionMode VARCHAR(10) NOT NULL
            CONSTRAINT DF_PIP_T_Inspection_InspectionMode DEFAULT ('STANDARD');
END;
GO

IF COL_LENGTH('dbo.PIP_T_Inspection', 'InspectionMapID') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_T_Inspection
        ADD InspectionMapID BIGINT NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_PIP_T_Inspection_InspectionMode'
      AND parent_object_id = OBJECT_ID('dbo.PIP_T_Inspection')
)
BEGIN
    ALTER TABLE dbo.PIP_T_Inspection
        ADD CONSTRAINT CK_PIP_T_Inspection_InspectionMode
        CHECK (InspectionMode IN ('STANDARD','MAP'));
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_PIP_T_Inspection_Map'
      AND parent_object_id = OBJECT_ID('dbo.PIP_T_Inspection')
)
BEGIN
    ALTER TABLE dbo.PIP_T_Inspection
        ADD CONSTRAINT FK_PIP_T_Inspection_Map
        FOREIGN KEY (InspectionMapID)
        REFERENCES dbo.PIP_M_InspectionMap(MapID);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_T_Inspection')
      AND name = 'IX_PIP_T_Inspection_MapBatch'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_T_Inspection_MapBatch
        ON dbo.PIP_T_Inspection
        (
            CompanyID,
            LocationID,
            InspectionTypeCode,
            InspectionTypeDetailCode,
            InspectionDate,
            ScheduledTime,
            InspectionMode
        );
END;
GO

/* ============================================================
   6. POINT TRANSACTION
   ============================================================ */
IF OBJECT_ID('dbo.PIP_T_InspectionPoint', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_T_InspectionPoint
    (
        InspectionPointTransactionID BIGINT NOT NULL,
        InspectionID BIGINT NOT NULL,
        InspectionPointID BIGINT NOT NULL,

        /*
           Snapshot values are intentionally stored here.
           If the master point is renamed later, historical
           transactions still show what was inspected.
        */
        PointCode VARCHAR(50) NOT NULL,
        PointName VARCHAR(200) NOT NULL,
        PointObjectType VARCHAR(30) NOT NULL,
        ObjectReferenceCode VARCHAR(100) NOT NULL CONSTRAINT DF_PIP_T_InspectionPoint_ObjectReferenceCode DEFAULT (''),

        PointInspectionDateTime DATETIME NOT NULL,
        Status VARCHAR(10) NOT NULL CONSTRAINT DF_PIP_T_InspectionPoint_Status DEFAULT ('PENDING'),
        AbnormalRemark VARCHAR(500) NULL,

        EntryUser VARCHAR(50) NOT NULL,
        EntryDate DATETIME NOT NULL CONSTRAINT DF_PIP_T_InspectionPoint_EntryDate DEFAULT (GETDATE()),
        UpdateUser VARCHAR(50) NOT NULL,
        UpdateDate DATETIME NOT NULL CONSTRAINT DF_PIP_T_InspectionPoint_UpdateDate DEFAULT (GETDATE()),

        CONSTRAINT PK_PIP_T_InspectionPoint
            PRIMARY KEY CLUSTERED (InspectionPointTransactionID),

        CONSTRAINT UQ_PIP_T_InspectionPoint_BatchPoint
            UNIQUE (InspectionID, InspectionPointID),

        CONSTRAINT FK_PIP_T_InspectionPoint_Batch
            FOREIGN KEY (InspectionID)
            REFERENCES dbo.PIP_T_Inspection(InspectionID),

        CONSTRAINT FK_PIP_T_InspectionPoint_Master
            FOREIGN KEY (InspectionPointID)
            REFERENCES dbo.PIP_M_InspectionPoint(InspectionPointID),

        CONSTRAINT CK_PIP_T_InspectionPoint_Status
            CHECK (Status IN ('PENDING','DONE'))
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_T_InspectionPoint')
      AND name = 'IX_PIP_T_InspectionPoint_BatchStatus'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_T_InspectionPoint_BatchStatus
        ON dbo.PIP_T_InspectionPoint
        (InspectionID, Status, PointInspectionDateTime);
END;
GO

/* ============================================================
   7. EXTEND EXISTING RESULT TABLE
      Legacy:
        InspectionID + IDItem
      Map:
        InspectionPointTransactionID + IDItem

      Filtered unique indexes keep both models alive in the
      same table without changing old transaction rows.
   ============================================================ */
IF COL_LENGTH('dbo.PIP_T_InspectionResult', 'InspectionPointTransactionID') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_T_InspectionResult
        ADD InspectionPointTransactionID BIGINT NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_PIP_T_InspectionResult_Point'
      AND parent_object_id = OBJECT_ID('dbo.PIP_T_InspectionResult')
)
BEGIN
    ALTER TABLE dbo.PIP_T_InspectionResult
        ADD CONSTRAINT FK_PIP_T_InspectionResult_Point
        FOREIGN KEY (InspectionPointTransactionID)
        REFERENCES dbo.PIP_T_InspectionPoint(InspectionPointTransactionID);
END;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.key_constraints
    WHERE parent_object_id = OBJECT_ID('dbo.PIP_T_InspectionResult')
      AND name = 'UQ_PIP_T_InspectionResult_Inspection_Item'
)
BEGIN
    ALTER TABLE dbo.PIP_T_InspectionResult
        DROP CONSTRAINT UQ_PIP_T_InspectionResult_Inspection_Item;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_T_InspectionResult')
      AND name = 'UX_PIP_T_InspectionResult_Legacy'
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_PIP_T_InspectionResult_Legacy
        ON dbo.PIP_T_InspectionResult (InspectionID, IDItem)
        WHERE InspectionPointTransactionID IS NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_T_InspectionResult')
      AND name = 'UX_PIP_T_InspectionResult_PointItem'
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_PIP_T_InspectionResult_PointItem
        ON dbo.PIP_T_InspectionResult (InspectionPointTransactionID, IDItem)
        WHERE InspectionPointTransactionID IS NOT NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_T_InspectionResult')
      AND name = 'IX_PIP_T_InspectionResult_Point'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_T_InspectionResult_Point
        ON dbo.PIP_T_InspectionResult
        (InspectionPointTransactionID, DisplayOrder);
END;
GO

/* ============================================================
   8. EXTEND EXISTING PHOTO TABLE
   ============================================================ */
IF COL_LENGTH('dbo.PIP_T_InspectionPhoto', 'InspectionPointTransactionID') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_T_InspectionPhoto
        ADD InspectionPointTransactionID BIGINT NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_PIP_T_InspectionPhoto_Point'
      AND parent_object_id = OBJECT_ID('dbo.PIP_T_InspectionPhoto')
)
BEGIN
    ALTER TABLE dbo.PIP_T_InspectionPhoto
        ADD CONSTRAINT FK_PIP_T_InspectionPhoto_Point
        FOREIGN KEY (InspectionPointTransactionID)
        REFERENCES dbo.PIP_T_InspectionPoint(InspectionPointTransactionID);
END;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_T_InspectionPhoto')
      AND name = 'UX_PIP_T_InspectionPhoto_InspectionSeqNo'
)
BEGIN
    DROP INDEX UX_PIP_T_InspectionPhoto_InspectionSeqNo
        ON dbo.PIP_T_InspectionPhoto;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_T_InspectionPhoto')
      AND name = 'UX_PIP_T_InspectionPhoto_Legacy'
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_PIP_T_InspectionPhoto_Legacy
        ON dbo.PIP_T_InspectionPhoto (InspectionID, SeqNo)
        WHERE InspectionPointTransactionID IS NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_T_InspectionPhoto')
      AND name = 'UX_PIP_T_InspectionPhoto_PointSeqNo'
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_PIP_T_InspectionPhoto_PointSeqNo
        ON dbo.PIP_T_InspectionPhoto (InspectionPointTransactionID, SeqNo)
        WHERE InspectionPointTransactionID IS NOT NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_T_InspectionPhoto')
      AND name = 'IX_PIP_T_InspectionPhoto_Point'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_T_InspectionPhoto_Point
        ON dbo.PIP_T_InspectionPhoto
        (InspectionPointTransactionID, SeqNo);
END;
GO

/* ============================================================
   9. HELPFUL INDEXES
   ============================================================ */
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_M_InspectionPoint')
      AND name = 'IX_PIP_M_InspectionPoint_Map'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_M_InspectionPoint_Map
        ON dbo.PIP_M_InspectionPoint
        (MapID, IsActive, DisplayOrder);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_M_InspectionMapElement')
      AND name = 'IX_PIP_M_InspectionMapElement_MapOrder'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_M_InspectionMapElement_MapOrder
        ON dbo.PIP_M_InspectionMapElement
        (MapID, IsActive, IsDeleted, DisplayOrder);
END;
GO

/*
    Inspection Map Group support
    Repository: INSPEC
    Branch: feature/inspection-location-map
    SQL Server 2008 compatible.

    Scope:
      - Inspection Master Map grouping only.
      - One Group can contain many Maps.
      - MapGroupID is nullable so existing standalone Maps remain valid.
      - Inspection Points continue to belong to MapID; no Point schema change.
      - No Work Order tables or workflows are changed.
      - Deliberately no dependency on PIP_M_InspectionMapElement.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID('dbo.PIP_M_InspectionMapGroup', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_M_InspectionMapGroup
    (
        MapGroupID BIGINT NOT NULL,
        CompanyID VARCHAR(10) NOT NULL,
        LocationID VARCHAR(3) NOT NULL,
        GroupCode VARCHAR(50) NOT NULL,
        GroupName VARCHAR(200) NOT NULL,
        Description VARCHAR(500) NOT NULL
            CONSTRAINT DF_PIP_M_InspectionMapGroup_Description DEFAULT (''),
        DisplayOrder INT NOT NULL
            CONSTRAINT DF_PIP_M_InspectionMapGroup_DisplayOrder DEFAULT (0),
        IsActive BIT NOT NULL
            CONSTRAINT DF_PIP_M_InspectionMapGroup_IsActive DEFAULT (1),
        EntryUser VARCHAR(50) NOT NULL,
        EntryDate DATETIME NOT NULL
            CONSTRAINT DF_PIP_M_InspectionMapGroup_EntryDate DEFAULT (GETDATE()),
        UpdateUser VARCHAR(50) NOT NULL,
        UpdateDate DATETIME NOT NULL
            CONSTRAINT DF_PIP_M_InspectionMapGroup_UpdateDate DEFAULT (GETDATE()),

        CONSTRAINT PK_PIP_M_InspectionMapGroup
            PRIMARY KEY CLUSTERED (MapGroupID),
        CONSTRAINT UQ_PIP_M_InspectionMapGroup_Code
            UNIQUE (CompanyID, LocationID, GroupCode)
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_PIP_M_InspectionMapGroup_Required'
      AND parent_object_id = OBJECT_ID('dbo.PIP_M_InspectionMapGroup')
)
BEGIN
    ALTER TABLE dbo.PIP_M_InspectionMapGroup
        ADD CONSTRAINT CK_PIP_M_InspectionMapGroup_Required
        CHECK
        (
            LEN(LTRIM(RTRIM(GroupCode))) > 0
            AND LEN(LTRIM(RTRIM(GroupName))) > 0
        );
END;
GO

IF COL_LENGTH('dbo.PIP_M_InspectionMap', 'MapGroupID') IS NULL
BEGIN
    ALTER TABLE dbo.PIP_M_InspectionMap
        ADD MapGroupID BIGINT NULL;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_M_InspectionMapGroup')
      AND name = 'UX_PIP_M_InspectionMapGroup_MapScope'
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_PIP_M_InspectionMapGroup_MapScope
        ON dbo.PIP_M_InspectionMapGroup (MapGroupID, CompanyID, LocationID);
END;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_PIP_M_InspectionMap_MapGroup'
      AND parent_object_id = OBJECT_ID('dbo.PIP_M_InspectionMap')
)
BEGIN
    ALTER TABLE dbo.PIP_M_InspectionMap
        DROP CONSTRAINT FK_PIP_M_InspectionMap_MapGroup;
END;
GO

ALTER TABLE dbo.PIP_M_InspectionMap
    ADD CONSTRAINT FK_PIP_M_InspectionMap_MapGroup
    FOREIGN KEY (MapGroupID, CompanyID, LocationID)
    REFERENCES dbo.PIP_M_InspectionMapGroup(MapGroupID, CompanyID, LocationID);
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_M_InspectionMap')
      AND name = 'IX_PIP_M_InspectionMap_Group'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_M_InspectionMap_Group
        ON dbo.PIP_M_InspectionMap
        (MapGroupID, IsActive, IsCurrentVersion, MapCode);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.PIP_M_InspectionMapGroup')
      AND name = 'IX_PIP_M_InspectionMapGroup_Location'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_PIP_M_InspectionMapGroup_Location
        ON dbo.PIP_M_InspectionMapGroup
        (CompanyID, LocationID, IsActive, DisplayOrder, GroupName);
END;
GO

/* Existing maps are intentionally left ungrouped (MapGroupID = NULL).
   Assign them to groups explicitly from Inspection Setup after deployment. */
SELECT MapID, MapCode, MapName, MapGroupID, IsCurrentVersion, IsActive
FROM dbo.PIP_M_InspectionMap
WHERE IsCurrentVersion = 1
ORDER BY MapCode;
GO

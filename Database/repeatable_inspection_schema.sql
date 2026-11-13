/*
    INSPEC - Native REPEAT inspection schema
    SQL Server 2008 compatible.

    This is an additive schema change. It intentionally does NOT migrate or drop
    the legacy ItemGroup table: existing GROUP records are left untouched.
    New templates use ItemType='REPEAT' and the tables below.

    REPEAT modes:
      FIELDS  = one logical object (ObjectIndex 0), many dynamic child fields.
      OBJECTS = multiple objects sharing the same child field definition.

    Child fields are scalar only. REPEAT is not a valid child FieldType.
*/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.PIP_M_CheckListWOPM_ItemRepeat','U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_M_CheckListWOPM_ItemRepeat
    (
        IDItem INT NOT NULL,
        RepeatMode VARCHAR(10) NOT NULL,
        ColumnCount TINYINT NOT NULL CONSTRAINT DF_PIP_M_ItemRepeat_ColumnCount DEFAULT (3),
        ObjectLabel NVARCHAR(100) NULL,
        CountMode VARCHAR(10) NOT NULL CONSTRAINT DF_PIP_M_ItemRepeat_CountMode DEFAULT ('FLEX'),
        FixedCount INT NULL,
        MinCount INT NULL,
        MaxCount INT NULL,
        CONSTRAINT PK_PIP_M_CheckListWOPM_ItemRepeat PRIMARY KEY CLUSTERED (IDItem),
        CONSTRAINT CK_PIP_M_ItemRepeat_Mode CHECK (RepeatMode IN ('FIELDS','OBJECTS')),
        CONSTRAINT CK_PIP_M_ItemRepeat_ColumnCount CHECK (ColumnCount BETWEEN 1 AND 6),
        CONSTRAINT CK_PIP_M_ItemRepeat_CountMode CHECK (CountMode IN ('FIXED','FLEX')),
        CONSTRAINT CK_PIP_M_ItemRepeat_Count CHECK
        (
            (CountMode='FIXED' AND FixedCount IS NOT NULL AND FixedCount >= 1)
            OR
            (CountMode='FLEX' AND FixedCount IS NULL
             AND (MinCount IS NULL OR MinCount >= 0)
             AND (MaxCount IS NULL OR MaxCount >= ISNULL(MinCount,0)))
        )
    );
END;
GO

IF OBJECT_ID('dbo.PIP_M_CheckListWOPM_ItemRepeatField','U') IS NULL
BEGIN
    CREATE TABLE dbo.PIP_M_CheckListWOPM_ItemRepeatField
    (
        IDItem INT NOT NULL,
        FieldKey VARCHAR(50) NOT NULL,
        FieldLabel NVARCHAR(100) NOT NULL,
        FieldType VARCHAR(20) NOT NULL,
        OptionList NVARCHAR(1000) NULL,
        Unit NVARCHAR(30) NULL,
        MinValue DECIMAL(18,4) NULL,
        MaxValue DECIMAL(18,4) NULL,
        MinInclusive BIT NOT NULL CONSTRAINT DF_PIP_M_ItemRepeatField_MinInclusive DEFAULT (1),
        MaxInclusive BIT NOT NULL CONSTRAINT DF_PIP_M_ItemRepeatField_MaxInclusive DEFAULT (1),
        IsRequired BIT NOT NULL CONSTRAINT DF_PIP_M_ItemRepeatField_IsRequired DEFAULT (0),
        GroupName NVARCHAR(100) NULL,
        DisplayOrder INT NOT NULL,
        CONSTRAINT PK_PIP_M_CheckListWOPM_ItemRepeatField PRIMARY KEY CLUSTERED (IDItem,FieldKey),
        CONSTRAINT CK_PIP_M_ItemRepeatField_Type CHECK (FieldType IN ('NUMBER','RANGE','OPTION','TEXT')),
        CONSTRAINT CK_PIP_M_ItemRepeatField_Range CHECK (MinValue IS NULL OR MaxValue IS NULL OR MinValue <= MaxValue)
    );
    CREATE NONCLUSTERED INDEX IX_PIP_M_ItemRepeatField_Order
        ON dbo.PIP_M_CheckListWOPM_ItemRepeatField(IDItem,DisplayOrder,FieldKey);
END;
GO

/* Add boundary semantics to REPEAT fields; existing rows remain inclusive. */
IF COL_LENGTH('dbo.PIP_M_CheckListWOPM_ItemRepeatField','MinInclusive') IS NULL
    ALTER TABLE dbo.PIP_M_CheckListWOPM_ItemRepeatField
        ADD MinInclusive BIT NOT NULL CONSTRAINT DF_PIP_M_ItemRepeatField_MinInclusive DEFAULT (1);
GO
IF COL_LENGTH('dbo.PIP_M_CheckListWOPM_ItemRepeatField','MaxInclusive') IS NULL
    ALTER TABLE dbo.PIP_M_CheckListWOPM_ItemRepeatField
        ADD MaxInclusive BIT NOT NULL CONSTRAINT DF_PIP_M_ItemRepeatField_MaxInclusive DEFAULT (1);
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_M_CheckListWOPM_ItemRepeatField')
      AND name='CK_PIP_M_ItemRepeatField_RangeBoundary'
)
    ALTER TABLE dbo.PIP_M_CheckListWOPM_ItemRepeatField
        ADD CONSTRAINT CK_PIP_M_ItemRepeatField_RangeBoundary CHECK
        (
            MinValue IS NULL OR MaxValue IS NULL OR MinValue<MaxValue
            OR (MinValue=MaxValue AND MinInclusive=1 AND MaxInclusive=1)
        );
GO

/* Existing WO subvalues were numeric-only. Widen storage for OPTION/TEXT too. */
IF COL_LENGTH('dbo.PIP_T_WO_CheckList_SubValue','ObjectIndex') IS NULL
    ALTER TABLE dbo.PIP_T_WO_CheckList_SubValue
        ADD ObjectIndex INT NOT NULL CONSTRAINT DF_PIP_T_WO_SubValue_ObjectIndex DEFAULT (0);
GO

IF COL_LENGTH('dbo.PIP_T_WO_CheckList_SubValue','FieldName') < 100
    ALTER TABLE dbo.PIP_T_WO_CheckList_SubValue ALTER COLUMN FieldName VARCHAR(100) NOT NULL;
GO

IF EXISTS
(
    SELECT 1 FROM sys.columns
    WHERE object_id=OBJECT_ID('dbo.PIP_T_WO_CheckList_SubValue')
      AND name='Value' AND TYPE_NAME(user_type_id) <> 'nvarchar'
)
    ALTER TABLE dbo.PIP_T_WO_CheckList_SubValue ALTER COLUMN Value NVARCHAR(500) NULL;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE object_id=OBJECT_ID('dbo.PIP_T_WO_CheckList_SubValue')
      AND name='IX_PIP_T_WO_SubValue_Result_Object_Field'
)
    CREATE NONCLUSTERED INDEX IX_PIP_T_WO_SubValue_Result_Object_Field
        ON dbo.PIP_T_WO_CheckList_SubValue(IDResult,ObjectIndex,FieldName);
GO

/* Inspection values support Unicode text child fields and OBJECTS identity. */
IF EXISTS
(
    SELECT 1 FROM sys.columns
    WHERE object_id=OBJECT_ID('dbo.PIP_T_InspectionResultValue')
      AND name='Value' AND TYPE_NAME(user_type_id)<>'nvarchar'
)
    ALTER TABLE dbo.PIP_T_InspectionResultValue ALTER COLUMN Value NVARCHAR(500) NULL;
GO

IF COL_LENGTH('dbo.PIP_T_InspectionResultValue','ObjectIndex') IS NULL
    ALTER TABLE dbo.PIP_T_InspectionResultValue
        ADD ObjectIndex INT NOT NULL CONSTRAINT DF_PIP_T_InspectionResultValue_ObjectIndex DEFAULT (0);
GO

IF EXISTS
(
    SELECT 1 FROM sys.key_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_T_InspectionResultValue')
      AND name='PK_PIP_T_InspectionResultValue'
)
    ALTER TABLE dbo.PIP_T_InspectionResultValue DROP CONSTRAINT PK_PIP_T_InspectionResultValue;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.key_constraints
    WHERE parent_object_id=OBJECT_ID('dbo.PIP_T_InspectionResultValue')
      AND name='PK_PIP_T_InspectionResultValue'
)
    ALTER TABLE dbo.PIP_T_InspectionResultValue
        ADD CONSTRAINT PK_PIP_T_InspectionResultValue
        PRIMARY KEY CLUSTERED (InspectionResultID,ObjectIndex,FieldName);
GO

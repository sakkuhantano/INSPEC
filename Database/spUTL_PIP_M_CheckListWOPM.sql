
CREATE PROCEDURE [dbo].[spUTL_PIP_M_CheckListWOPM]
(
	@p_CompanyID VARCHAR(10), @p_LocationID VARCHAR(3),
	@p_dt_Template AS [Type_N_Tbl_C5] READONLY,
	@p_dt_Version AS [Type_N_Tbl_C13] READONLY,
	@p_dt_Section AS [Type_N_Tbl_C5] READONLY,
	@p_dt_SubSection AS [Type_N_Tbl_C5] READONLY,
	@p_dt_Item AS [Type_N_Tbl_C25] READONLY,
	@p_dt_Group AS [Type_Tbl_C7] READONLY,
	@p_dt_RepeatConfig AS [Type_N_Tbl_C10] READONLY,
	@p_dt_RepeatField AS [Type_N_Tbl_C13] READONLY,
	@p_dt_DelTemplate AS [Type_Tbl_C2] READONLY, 
	@p_dt_DelVersion AS [Type_Tbl_C2] READONLY,
	@p_UpdateUser VARCHAR(50),
	@p_IsPublished BIT = 0  
)
AS
SET NOCOUNT ON

DECLARE @tbl_Template TABLE 
(IDTemplate INT, RuntimeTemplateID INT, TemplateNo VARCHAR(50), TemplateName VARCHAR(200), SectionID VARCHAR(10))
INSERT @tbl_Template SELECT * FROM @p_dt_Template

DECLARE @tbl_Version TABLE 
(IDVersion INT, RuntimeVersionID INT, RuntimeTemplateID INT, [Version] VARCHAR(10), Remark VARCHAR(255), [Status] VARCHAR(10), EffectiveDate SMALLDATETIME, StatusOption VARCHAR(50), GroupEquipment VARCHAR(10), SummarySampleText VARCHAR(500), RemarkRequiredOptions VARCHAR(8000), IsRemark1Required BIT, Remark1Text VARCHAR(100), IsRemark2Required BIT, Remark2Text VARCHAR(100), PhotoRequirement VARCHAR(10))
INSERT @tbl_Version SELECT C1, C2, C3, C4, C5, C6, CAST(C7 AS SMALLDATETIME), C8, C9, C10, C11,
 CASE WHEN LEFT(ISNULL(C12,''),2)='1|' THEN 1 ELSE 0 END,
 CASE WHEN LEFT(ISNULL(C12,''),2)='1|' AND CHARINDEX('|',ISNULL(C12,''))>0 THEN SUBSTRING(C12,3,100) ELSE '' END,
 CASE WHEN LEFT(ISNULL(C13,''),2)='1|' THEN 1 ELSE 0 END,
 CASE WHEN LEFT(ISNULL(C13,''),2)='1|' AND CHARINDEX('|',ISNULL(C13,''))>0 THEN SUBSTRING(C13,3,CASE WHEN CHARINDEX('|',C13+'|',3)>0 THEN CHARINDEX('|',C13+'|',3)-3 ELSE 100 END) ELSE '' END,
 CASE WHEN CHARINDEX('|',ISNULL(C13,''),3)>0 AND UPPER(SUBSTRING(C13,CHARINDEX('|',C13,3)+1,10)) IN ('NONE','BEFORE','AFTER','BOTH') THEN UPPER(SUBSTRING(C13,CHARINDEX('|',C13,3)+1,10)) ELSE 'NONE' END
 FROM @p_dt_Version

DECLARE @tbl_Section TABLE 
(IDSection INT, RuntimeSectionID INT, RuntimeVersionID INT, SectionName VARCHAR(200), DisplayOrder INT)
INSERT @tbl_Section SELECT C1, C2, C3, C4, ROW_NUMBER() OVER ( PARTITION BY C3 ORDER BY (SELECT NULL)) FROM @p_dt_Section

DECLARE @tbl_SubSection TABLE
(IDSubSection INT, RuntimeSubSectionID INT, RuntimeSectionID INT, SubSectionName VARCHAR(200), DisplayOrder INT)
INSERT @tbl_SubSection SELECT C1, C2, C3, C4, C5 FROM @p_dt_SubSection

DECLARE @tbl_Item TABLE 
(IDItem INT, RuntimeItemID INT, RuntimeSectionID INT, ItemLabel NVARCHAR(500), ItemType VARCHAR(20), Unit VARCHAR(20), IsRemark1Required BIT, IsRemark2Required BIT, IsValueRequired BIT, ShowUnitInRange BIT, OptionList VARCHAR(200), MinValue DECIMAL, MaxValue DECIMAL, DisplayOrder INT, MinTolerance MONEY, MaxTolerance MONEY, ModelCode VARCHAR(50), IsToleranceRequired BIT, RemarkRequiredOptions VARCHAR(8000), Remark1Text VARCHAR(100), Remark2Text VARCHAR(100), RuntimeSubSectionID INT, IsUseDefaultRemark1 BIT, IsUseDefaultRemark2 BIT, IsRemark1Mandatory BIT, IsRemark2Mandatory BIT)
INSERT @tbl_Item SELECT C1, C2, C3, C4, C5, C6, C7, C18, C8, C9, C10, C11, C12, ISNULL(NULLIF(C22, 0), ROW_NUMBER() OVER ( PARTITION BY C3 ORDER BY (SELECT NULL))), C13, C14, C15, CAST(C16 AS BIT), C17, CASE WHEN CAST(ISNULL(NULLIF(C7, ''), '0') AS BIT)=1 THEN ISNULL(NULLIF(C19, ''), 'Remark') ELSE '' END, CASE WHEN CAST(ISNULL(NULLIF(C18, ''), '0') AS BIT)=1 THEN ISNULL(NULLIF(C20, ''), 'Remark') ELSE '' END, ISNULL(C21, 0), CAST(ISNULL(NULLIF(C23,''),'0') AS BIT), CAST(ISNULL(NULLIF(C24,''),'0') AS BIT), CAST(ISNULL(NULLIF(PARSENAME(REPLACE(ISNULL(C25,'0|0'),'|','.'), CASE WHEN LEN(ISNULL(C25,''))-LEN(REPLACE(ISNULL(C25,''),'|',''))>=2 THEN 3 ELSE 2 END),''),'0') AS BIT), CAST(ISNULL(NULLIF(PARSENAME(REPLACE(ISNULL(C25,'0|0'),'|','.'), CASE WHEN LEN(ISNULL(C25,''))-LEN(REPLACE(ISNULL(C25,''),'|',''))>=2 THEN 2 ELSE 1 END),''),'0') AS BIT) FROM @p_dt_Item

DECLARE @tbl_Group TABLE
(IDGroup INT, RuntimeGroupID INT, RuntimeItemID INT, GroupName VARCHAR(100), FieldList VARCHAR(100), Unit VARCHAR(20), DisplayOrder INT)
INSERT @tbl_Group SELECT C1, C2, C3, C4, C5, C6, ROW_NUMBER() OVER ( PARTITION BY C3 ORDER BY (SELECT NULL)) FROM @p_dt_Group

DECLARE @tbl_RepeatConfig TABLE
(IDItem INT, RuntimeItemID INT, RepeatMode VARCHAR(10), ColumnCount INT, ObjectLabel NVARCHAR(100),
 CountMode VARCHAR(10), FixedCount INT NULL, MinCount INT NULL, MaxCount INT NULL)
INSERT @tbl_RepeatConfig
SELECT CAST(C1 AS INT), CAST(C2 AS INT), UPPER(C3),
       ISNULL(NULLIF(C4,''), '3'), NULLIF(C5,''),
       UPPER(ISNULL(NULLIF(C6,''),'FLEX')),
       NULLIF(C7,''), NULLIF(C8,''), NULLIF(C9,'')
FROM @p_dt_RepeatConfig;

DECLARE @tbl_RepeatField TABLE
(RuntimeItemID INT, RuntimeRepeatID INT NOT NULL, IDRepeat INT NULL,
 FieldLabel NVARCHAR(100), FieldType VARCHAR(20), OptionList NVARCHAR(1000),
 Unit NVARCHAR(30), MinValue DECIMAL(18,4) NULL, MaxValue DECIMAL(18,4) NULL,
 IsRequired BIT, GroupName NVARCHAR(100), DisplayOrder INT,
 MinInclusive BIT, MaxInclusive BIT)
INSERT @tbl_RepeatField
SELECT CAST(C1 AS INT),
       CASE WHEN LEN(C2)<=11 AND LEFT(C2,1)='-' AND SUBSTRING(C2,2,10)<>'' AND SUBSTRING(C2,2,10) NOT LIKE '%[^0-9]%' THEN
                CASE WHEN CAST(SUBSTRING(C2,2,10) AS BIGINT)>0 THEN CAST(C2 AS INT) ELSE 0 END
            ELSE 0 END,
       CASE WHEN LEN(C2)<=10 AND C2<>'' AND C2 NOT LIKE '%[^0-9]%' THEN
                CASE WHEN CAST(C2 AS BIGINT)>0 THEN CAST(C2 AS INT) ELSE NULL END
            ELSE NULL END,
       C3, UPPER(C4), NULLIF(C5,''), NULLIF(C6,''),
       NULLIF(C7,''), NULLIF(C8,''), CAST(ISNULL(NULLIF(C9,''),'0') AS BIT),
       NULLIF(C10,''), CAST(ISNULL(NULLIF(C11,''),'0') AS INT),
       CAST(ISNULL(NULLIF(C12,''),'1') AS BIT), CAST(ISNULL(NULLIF(C13,''),'1') AS BIT)
FROM @p_dt_RepeatField;

IF EXISTS
(
    SELECT 1 FROM @tbl_RepeatField F
    WHERE (F.MinValue IS NOT NULL AND F.MaxValue IS NOT NULL AND F.MinValue>F.MaxValue)
       OR (F.MinValue IS NOT NULL AND F.MaxValue IS NOT NULL AND F.MinValue=F.MaxValue
           AND (F.MinInclusive=0 OR F.MaxInclusive=0))
)
BEGIN RAISERROR('Invalid REPEAT field range boundaries.',16,1); RETURN; END;

IF EXISTS
(
    SELECT 1 FROM @tbl_RepeatConfig C
    WHERE C.RepeatMode NOT IN ('FIELDS','OBJECTS')
       OR C.ColumnCount NOT BETWEEN 1 AND 6
       OR C.CountMode NOT IN ('FIXED','FLEX')
       OR (C.CountMode='FIXED' AND ISNULL(C.FixedCount,0)<1)
       OR (C.CountMode='FLEX' AND C.FixedCount IS NOT NULL)
       OR (C.CountMode='FLEX' AND C.MinCount IS NOT NULL AND C.MaxCount IS NOT NULL AND C.MaxCount<C.MinCount)
       OR NOT EXISTS (SELECT 1 FROM @tbl_Item I WHERE I.RuntimeItemID=C.RuntimeItemID AND I.ItemType='REPEAT')
)
BEGIN RAISERROR('Invalid REPEAT configuration.',16,1); RETURN; END;

IF EXISTS
(
    SELECT 1 FROM @tbl_Item I
    WHERE I.ItemType='REPEAT'
      AND NOT EXISTS (SELECT 1 FROM @tbl_RepeatConfig C WHERE C.RuntimeItemID=I.RuntimeItemID)
)
BEGIN RAISERROR('Every REPEAT item requires a REPEAT configuration.',16,1); RETURN; END;

IF EXISTS
(
    SELECT 1 FROM @tbl_RepeatConfig C
    WHERE NOT EXISTS (SELECT 1 FROM @tbl_RepeatField F WHERE F.RuntimeItemID=C.RuntimeItemID)
)
BEGIN RAISERROR('Every REPEAT item requires at least one child field.',16,1); RETURN; END;

IF EXISTS
(
    SELECT 1 FROM @tbl_RepeatField F
    WHERE (ISNULL(F.IDRepeat,0)<=0 AND F.RuntimeRepeatID>=0)
       OR F.FieldLabel IS NULL OR LTRIM(RTRIM(F.FieldLabel))=''
       OR F.FieldType NOT IN ('NUMBER','RANGE','OPTION','TEXT')
       OR NOT EXISTS (SELECT 1 FROM @tbl_RepeatConfig C WHERE C.RuntimeItemID=F.RuntimeItemID)
)
BEGIN RAISERROR('Invalid REPEAT field definition. IDRepeat identity and FieldLabel are required.',16,1); RETURN; END;

IF EXISTS
(
    SELECT RuntimeItemID, CASE WHEN IDRepeat IS NULL THEN RuntimeRepeatID ELSE IDRepeat END
    FROM @tbl_RepeatField
    GROUP BY RuntimeItemID, CASE WHEN IDRepeat IS NULL THEN RuntimeRepeatID ELSE IDRepeat END
    HAVING COUNT(*)>1
)
BEGIN RAISERROR('Duplicate IDRepeat identity in one REPEAT item.',16,1); RETURN; END;

IF EXISTS
(
    SELECT RuntimeRepeatID
    FROM @tbl_RepeatField
    WHERE IDRepeat IS NULL
    GROUP BY RuntimeRepeatID
    HAVING COUNT(*)>1
)
BEGIN RAISERROR('Duplicate RuntimeRepeatID submitted for new REPEAT fields.',16,1); RETURN; END;

DECLARE @tbl_DelTemplate TABLE (IDTemplate INT)
INSERT @tbl_DelTemplate SELECT C1 FROM @p_dt_DelTemplate

DECLARE @tbl_DelVersion TABLE (IDTemplate INT, IDVersion INT)
INSERT @tbl_DelVersion SELECT * FROM @p_dt_DelVersion

DECLARE @tbl_Identity TABLE (Entity VARCHAR(50), RuntimeID INT, ID INT)

DECLARE @p_IsDebug BIT = 0
IF @p_IsDebug=1
BEGIN
	IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES AS t WHERE t.TABLE_NAME='tmpDebug_PIP_M_CheckListWOPM')
		DROP TABLE tmpDebug_PIP_M_CheckListWOPM
	IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES AS t WHERE t.TABLE_NAME='tmpDebug_PIP_M_CheckListWOPM_Version')
		DROP TABLE tmpDebug_PIP_M_CheckListWOPM_Version
	IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES AS t WHERE t.TABLE_NAME='tmpDebug_PIP_M_CheckListWOPM_Section')
		DROP TABLE tmpDebug_PIP_M_CheckListWOPM_Section
	IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES AS t WHERE t.TABLE_NAME='tmpDebug_PIP_M_CheckListWOPM_Item')
		DROP TABLE tmpDebug_PIP_M_CheckListWOPM_Item
	IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES AS t WHERE t.TABLE_NAME='tmpDebug_PIP_M_CheckListWOPM_ItemGroup')
		DROP TABLE tmpDebug_PIP_M_CheckListWOPM_ItemGroup
	IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES AS t WHERE t.TABLE_NAME='tmpDebug_PIP_M_CheckListWOPM_SubSection')
		DROP TABLE tmpDebug_PIP_M_CheckListWOPM_SubSection
	IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES AS t WHERE t.TABLE_NAME='tmpDebug_PIP_M_CheckListWOPM_SubSectionSource')
		DROP TABLE tmpDebug_PIP_M_CheckListWOPM_SubSectionSource
	SELECT * INTO tmpDebug_PIP_M_CheckListWOPM FROM @tbl_Template
	SELECT * INTO tmpDebug_PIP_M_CheckListWOPM_Version FROM @tbl_Version
	SELECT * INTO tmpDebug_PIP_M_CheckListWOPM_Section FROM @tbl_Section
	SELECT * INTO tmpDebug_PIP_M_CheckListWOPM_Item FROM @tbl_Item
	SELECT * INTO tmpDebug_PIP_M_CheckListWOPM_ItemGroup FROM @tbl_Group
	SELECT * INTO tmpDebug_PIP_M_CheckListWOPM_SubSection FROM @tbl_SubSection
END


/* Published/Active and archived versions are immutable at the database boundary. */
IF EXISTS (SELECT 1 FROM @tbl_Version S JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDVersion=S.IDVersion
           WHERE S.IDVersion>0 AND ISNULL(V.[Status],'')<>'Draft')
BEGIN RAISERROR('Only Draft versions can be edited or published.',16,1); RETURN; END;
IF EXISTS (SELECT 1 FROM @tbl_DelVersion D JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDVersion=D.IDVersion
           WHERE ISNULL(V.[Status],'')<>'Draft')
BEGIN RAISERROR('Only Draft versions can be deleted.',16,1); RETURN; END;
IF EXISTS (SELECT 1 FROM @tbl_Section X JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=X.IDSection
           JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDVersion=S.IDVersion
           WHERE X.IDSection>0 AND ISNULL(V.[Status],'')<>'Draft')
OR EXISTS (SELECT 1 FROM @tbl_Item X JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=X.IDItem
           JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
           JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDVersion=S.IDVersion
           WHERE X.IDItem>0 AND ISNULL(V.[Status],'')<>'Draft')
OR EXISTS (SELECT 1 FROM @tbl_Group X JOIN dbo.PIP_M_CheckListWOPM_ItemGroup G ON G.IDGroup=X.IDGroup
           JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=G.IDItem
           JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
           JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDVersion=S.IDVersion
           WHERE X.IDGroup>0 AND ISNULL(V.[Status],'')<>'Draft')
OR EXISTS (SELECT 1 FROM @tbl_SubSection X JOIN dbo.PIP_M_CheckListWOPM_SubSection SS ON SS.IDSubSection=X.IDSubSection
           JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=SS.IDSection
           JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDVersion=S.IDVersion
           WHERE X.IDSubSection>0 AND ISNULL(V.[Status],'')<>'Draft')
BEGIN RAISERROR('Published/Active version structure is immutable.',16,1); RETURN; END;
IF EXISTS (SELECT 1 FROM @tbl_DelTemplate D JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDTemplate=D.IDTemplate
           WHERE V.[Status] IN ('Active','Archieved'))
BEGIN RAISERROR('Templates with published versions cannot be deleted.',16,1); RETURN; END;

--- begin processsing
--- DELETED
DELETE S2 FROM PIP_M_CheckListWOPM_itemgroup S2 JOIN PIP_M_CheckListWOPM_Item S1 ON S1.IDItem = S2.IDItem
JOIN PIP_M_CheckListWOPM_Section S3 ON S3.IDSection = S1.IDSection
JOIN @tbl_Version S4 ON S4.IDVersion=S3.IDVersion
JOIN PIP_M_CheckListWOPM_Version AS pmclwv ON pmclwv.IDVersion = S4.IDVersion
JOIN PIP_M_CheckListWOPM AS pmclw ON pmclw.IDTemplate=pmclwv.IDTemplate
WHERE NOT EXISTS (SELECT * FROM @tbl_Group S WHERE S.IDGroup=S2.IDGroup)
AND (ISNULL(pmclw.CompanyScope,'S')='A'
     OR (';' + ISNULL(pmclw.CompanyLocationList, '') + ';' LIKE '%;' + @p_CompanyID + @p_LocationID + ';%'))


DELETE RF
FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField RF
JOIN dbo.PIP_M_CheckListWOPM_Item RI ON RI.IDItem=RF.IDItem
JOIN dbo.PIP_M_CheckListWOPM_Section RS ON RS.IDSection=RI.IDSection
JOIN @tbl_Version RV ON RV.IDVersion=RS.IDVersion
WHERE NOT EXISTS (SELECT 1 FROM @tbl_Item KeepItem WHERE KeepItem.IDItem=RI.IDItem);
DELETE R
FROM dbo.PIP_M_CheckListWOPM_ItemRepeat R
JOIN dbo.PIP_M_CheckListWOPM_Item RI ON RI.IDItem=R.IDItem
JOIN dbo.PIP_M_CheckListWOPM_Section RS ON RS.IDSection=RI.IDSection
JOIN @tbl_Version RV ON RV.IDVersion=RS.IDVersion
WHERE NOT EXISTS (SELECT 1 FROM @tbl_Item KeepItem WHERE KeepItem.IDItem=RI.IDItem);

DELETE S2 FROM PIP_M_CheckListWOPM_item S2 JOIN PIP_M_CheckListWOPM_Section S1 ON S1.IDSection = S2.IDSection
JOIN @tbl_Version S3 ON S3.IDVersion=S1.IDVersion
JOIN PIP_M_CheckListWOPM_Version AS pmclwv ON pmclwv.IDVersion = S3.IDVersion
JOIN PIP_M_CheckListWOPM AS pmclw ON pmclw.IDTemplate=pmclwv.IDTemplate
WHERE NOT EXISTS (SELECT * FROM @tbl_Item S WHERE S.IDItem=S2.IDItem)
AND (ISNULL(pmclw.CompanyScope,'S')='A'
     OR (';' + ISNULL(pmclw.CompanyLocationList, '') + ';' LIKE '%;' + @p_CompanyID + @p_LocationID + ';%'))


DELETE OldSub
FROM PIP_M_CheckListWOPM_SubSection OldSub
JOIN PIP_M_CheckListWOPM_Section OldSec ON OldSec.IDSection=OldSub.IDSection
JOIN @tbl_Version V ON V.IDVersion=OldSec.IDVersion
JOIN PIP_M_CheckListWOPM_Version VER ON VER.IDVersion=V.IDVersion
JOIN PIP_M_CheckListWOPM T ON T.IDTemplate=VER.IDTemplate
WHERE NOT EXISTS (SELECT 1 FROM @tbl_Section S WHERE S.IDSection=OldSec.IDSection)
AND (ISNULL(T.CompanyScope,'S')='A' OR (';' + ISNULL(T.CompanyLocationList, '') + ';' LIKE '%;' + @p_CompanyID + @p_LocationID + ';%'));

DELETE S2 FROM PIP_M_CheckListWOPM_section S2 JOIN @tbl_Version S1 ON S1.IDVersion = S2.IDVersion
JOIN PIP_M_CheckListWOPM_Version AS pmclwv ON pmclwv.IDVersion = S2.IDVersion
JOIN PIP_M_CheckListWOPM AS pmclw ON pmclw.IDTemplate=pmclwv.IDTemplate
WHERE NOT EXISTS (SELECT * FROM @tbl_Section S WHERE S.IDSection=S2.IDSection)
AND (ISNULL(pmclw.CompanyScope,'S')='A'
     OR (';' + ISNULL(pmclw.CompanyLocationList, '') + ';' LIKE '%;' + @p_CompanyID + @p_LocationID + ';%'))


IF EXISTS (SELECT * FROM @tbl_DelVersion)
BEGIN
	DELETE A FROM PIP_M_CheckListWOPM_ItemGroup A JOIN PIP_M_CheckListWOPM_item AA ON AA.IDItem = A.IDItem
	JOIN PIP_M_CheckListWOPM_section AAA ON AAA.IDSection = AA.IDSection
	JOIN @tbl_DelVersion B ON B.IDVersion=AAA.IDVersion
	JOIN PIP_M_CheckListWOPM_Version AS pmclwv ON pmclwv.IDVersion = B.IDVersion
	JOIN PIP_M_CheckListWOPM AS pmclw ON pmclw.IDTemplate=pmclwv.IDTemplate
	WHERE (ISNULL(pmclw.CompanyScope,'S')='A'
       OR (';' + ISNULL(pmclw.CompanyLocationList, '') + ';' LIKE '%;' + @p_CompanyID + @p_LocationID + ';%'))
	
	DELETE RF FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField RF
	JOIN dbo.PIP_M_CheckListWOPM_Item RI ON RI.IDItem=RF.IDItem
	JOIN dbo.PIP_M_CheckListWOPM_Section RS ON RS.IDSection=RI.IDSection
	JOIN @tbl_DelVersion DV ON DV.IDVersion=RS.IDVersion;
	DELETE R FROM dbo.PIP_M_CheckListWOPM_ItemRepeat R
	JOIN dbo.PIP_M_CheckListWOPM_Item RI ON RI.IDItem=R.IDItem
	JOIN dbo.PIP_M_CheckListWOPM_Section RS ON RS.IDSection=RI.IDSection
	JOIN @tbl_DelVersion DV ON DV.IDVersion=RS.IDVersion;

	DELETE A FROM PIP_M_CheckListWOPM_item A JOIN PIP_M_CheckListWOPM_section AA ON AA.IDSection = A.IDSection
	JOIN @tbl_DelVersion B ON B.IDVersion=AA.IDVersion
	JOIN PIP_M_CheckListWOPM_Version AS pmclwv ON pmclwv.IDVersion = B.IDVersion
	JOIN PIP_M_CheckListWOPM AS pmclw ON pmclw.IDTemplate=pmclwv.IDTemplate
	WHERE (ISNULL(pmclw.CompanyScope,'S')='A'
       OR (';' + ISNULL(pmclw.CompanyLocationList, '') + ';' LIKE '%;' + @p_CompanyID + @p_LocationID + ';%'))
	
	DELETE SS FROM PIP_M_CheckListWOPM_SubSection SS
	JOIN PIP_M_CheckListWOPM_section AAA ON AAA.IDSection=SS.IDSection
	JOIN @tbl_DelVersion B ON B.IDVersion=AAA.IDVersion
	JOIN PIP_M_CheckListWOPM_Version VER ON VER.IDVersion=B.IDVersion
	JOIN PIP_M_CheckListWOPM T ON T.IDTemplate=VER.IDTemplate
	WHERE (ISNULL(T.CompanyScope,'S')='A' OR (';' + ISNULL(T.CompanyLocationList, '') + ';' LIKE '%;' + @p_CompanyID + @p_LocationID + ';%'));

	DELETE A FROM PIP_M_CheckListWOPM_section A JOIN @tbl_DelVersion B ON B.IDVersion=A.IDVersion
	JOIN PIP_M_CheckListWOPM_Version AS pmclwv ON pmclwv.IDVersion = B.IDVersion
	JOIN PIP_M_CheckListWOPM AS pmclw ON pmclw.IDTemplate=pmclwv.IDTemplate
	WHERE (ISNULL(pmclw.CompanyScope,'S')='A'
       OR (';' + ISNULL(pmclw.CompanyLocationList, '') + ';' LIKE '%;' + @p_CompanyID + @p_LocationID + ';%'))
	
END

DELETE V FROM PIP_M_CheckListWOPM_version V
INNER JOIN @tbl_DelVersion D ON V.IDTemplate = D.IDTemplate AND V.IDVersion = D.IDVersion
JOIN PIP_M_CheckListWOPM AS pmclw ON pmclw.IDTemplate=V.IDTemplate
WHERE (ISNULL(pmclw.CompanyScope,'S')='A'
       OR (';' + ISNULL(pmclw.CompanyLocationList, '') + ';' LIKE '%;' + @p_CompanyID + @p_LocationID + ';%'))


/* Resolve which requested templates are visible in this company/location before removing their relations. */
DECLARE @tbl_AllowedDelTemplate TABLE (IDTemplate INT PRIMARY KEY);
INSERT INTO @tbl_AllowedDelTemplate (IDTemplate)
SELECT T.IDTemplate
FROM dbo.PIP_M_CheckListWOPM T
JOIN @tbl_DelTemplate D ON D.IDTemplate=T.IDTemplate
WHERE ISNULL(T.CompanyScope,'S')='A'
   OR (';' + ISNULL(T.CompanyLocationList, '') + ';' LIKE '%;' + @p_CompanyID + @p_LocationID + ';%');

UPDATE I SET I.IDSubSection=NULL
FROM PIP_M_CheckListWOPM_Item I
JOIN PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
JOIN PIP_M_CheckListWOPM_Version V ON V.IDVersion=S.IDVersion
JOIN @tbl_AllowedDelTemplate D ON D.IDTemplate=V.IDTemplate;

DELETE SS
FROM PIP_M_CheckListWOPM_SubSection SS
JOIN PIP_M_CheckListWOPM_Section S ON S.IDSection=SS.IDSection
JOIN PIP_M_CheckListWOPM_Version V ON V.IDVersion=S.IDVersion
JOIN @tbl_AllowedDelTemplate D ON D.IDTemplate=V.IDTemplate;

DELETE T FROM PIP_M_CheckListWOPM T
JOIN @tbl_AllowedDelTemplate D ON T.IDTemplate = D.IDTemplate


--- TEMPLATE
UPDATE T
SET
  T.TemplateNo = S.TemplateNo,
  T.TemplateName = S.TemplateName,
  T.SectionID = S.SectionID,
  T.UpdateUser=@p_UpdateUser, T.UpdateDate=GETDATE()
FROM PIP_M_CheckListWOPM T
JOIN @tbl_Template S ON T.IDTemplate = S.IDTemplate
WHERE S.IDTemplate > 0 
MERGE INTO PIP_M_CheckListWOPM AS target
USING (
    SELECT 
        templateno, 
        templatename, 
        sectionid, 
        runtimetemplateid,
        -- Menggunakan ISNULL(..., 0) untuk antisipasi jika tabel target masih kosong
        (SELECT ISNULL(MAX(IDTemplate), 0) FROM PIP_M_CheckListWOPM) 
        + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS NewIDTemplate
    FROM @tbl_template 
    WHERE idtemplate = 0
) AS source
ON 1 = 0 
WHEN NOT MATCHED THEN
    INSERT (IDTemplate, TemplateNo, TemplateName, SectionID, IsActive, EntryUser, EntryDate, UpdateUser, UpdateDate, CompanyLocationList, EmployeeList)
    VALUES (source.NewIDTemplate, source.templateno, source.templatename, source.sectionid, 1, @p_UpdateUser, GETDATE(), @p_UpdateUser, GETDATE(), @p_CompanyID + @p_LocationID, '')
OUTPUT 
    'Template' Entity,
    source.runtimetemplateid,   
    inserted.IDTemplate   -- Tetap mengembalikan IDTemplate manual yang baru saja dimasukkan
INTO @tbl_Identity (Entity, RuntimeID, ID);

--- Version
UPDATE V
SET 
    V.Version = S.Version,
    V.[Status] = S.[Status],
    V.Remark = S.Remark,
    V.EffectiveDate = S.EffectiveDate,
    V.StatusOption = S.StatusOption, V.UpdateUser=@p_UpdateUser, V.UpdateDate=GETDATE(), 
    V.GroupEquipment=S.GroupEquipment, V.SummarySampleText=S.SummarySampleText, V.RemarkRequiredOptions=S.RemarkRequiredOptions,
    V.IsRemark1Required=S.IsRemark1Required, V.Remark1Text=CASE WHEN S.IsRemark1Required=1 THEN ISNULL(NULLIF(S.Remark1Text,''),'Remark') ELSE '' END,
    V.IsRemark2Required=S.IsRemark2Required, V.Remark2Text=CASE WHEN S.IsRemark2Required=1 THEN ISNULL(NULLIF(S.Remark2Text,''),'Remark') ELSE '' END,
    V.PhotoRequirement=S.PhotoRequirement
FROM PIP_M_CheckListWOPM_version V
JOIN @tbl_Version S ON V.IDVersion = S.IDVersion
WHERE S.IDVersion > 0 
MERGE INTO PIP_M_CheckListWOPM_version AS target
USING (
    SELECT 
        v.RuntimeVersionID,
        v.RuntimeTemplateID,
        v.[Version],
        v.Remark,
        v.[Status],
        v.EffectiveDate,
        v.StatusOption,
        v.GroupEquipment, v.SummarySampleText, v.RemarkRequiredOptions, v.IsRemark1Required, v.Remark1Text, v.IsRemark2Required, v.Remark2Text, v.PhotoRequirement,
        tmpl.IDTemplate, -- Hubungkan dengan tabel map untuk mendapatkan IDTemplate asli database
        (SELECT ISNULL(MAX(IDVersion), 0) FROM PIP_M_CheckListWOPM_version) 
        + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS NewIDVersion
    FROM @tbl_Version v
    INNER JOIN (
        -- Gabungkan data template baru dan template existing di sini
        SELECT RuntimeID RuntimeTemplateID, ID IDTemplate FROM @tbl_Identity WHERE Entity='Template'  -- Template baru
        UNION ALL
        SELECT RuntimeTemplateID, IDTemplate FROM @tbl_Template WHERE IDTemplate <> 0 -- Template lama
    ) tmpl ON v.RuntimeTemplateID = tmpl.RuntimeTemplateID    
    WHERE v.IDVersion = 0 -- Sesuai request: hanya insert yang IDVersion = 0
) AS source
ON 1 = 0 -- Trik agar selalu memicu aksi INSERT
WHEN NOT MATCHED THEN
    -- Sebutkan nama kolom target di tabel PIP_M_CheckListWOPM_version
    -- Kolom IDVersion tidak ditulis karena IDENTITY ON
    INSERT (IDTemplate, IDVersion, [Version], StatusOption, EffectiveDate, Remark, [Status], EntryUser, EntryDate, UpdateUser, UpdateDate, GroupEquipment, SummarySampleText, RemarkRequiredOptions, IsRemark1Required, Remark1Text, IsRemark2Required, Remark2Text, PhotoRequirement)
    -- Masukkan nilai yang berasal dari blok USING (source)
    VALUES (source.IDTemplate, source.NewIDVersion, source.[Version], source.StatusOption, source.EffectiveDate, source.Remark, source.[Status], @p_UpdateUser, GETDATE(), @p_UpdateUser, GETDATE(), source.GroupEquipment, source.SummarySampleText, source.RemarkRequiredOptions, source.IsRemark1Required, CASE WHEN source.IsRemark1Required=1 THEN ISNULL(NULLIF(source.Remark1Text,''),'Remark') ELSE '' END, source.IsRemark2Required, CASE WHEN source.IsRemark2Required=1 THEN ISNULL(NULLIF(source.Remark2Text,''),'Remark') ELSE '' END, source.PhotoRequirement)
OUTPUT 
	'Version' Entity,
    source.RuntimeVersionID,  -- Dari tabel asal
    inserted.IDVersion       -- Identity baru yang digenerate oleh database
INTO @tbl_Identity (Entity, RuntimeID, ID); 

--- section
UPDATE S2
SET S2.SectionName = S.SectionName, S2.DisplayOrder=S.DisplayOrder
FROM PIP_M_CheckListWOPM_section S2
JOIN @tbl_Section S
  ON S2.IDSection = S.IDSection
WHERE S.IDSection > 0
MERGE INTO PIP_M_CheckListWOPM_section AS target
USING (
    SELECT 
        v.RuntimeSectionID,
        v.RuntimeVersionID,
        v.SectionName,
        v.DisplayOrder,
        tmpl.IDVersion,
        (SELECT ISNULL(MAX(IDSection), 0) FROM PIP_M_CheckListWOPM_section) 
        + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS NewIDSection
    FROM @tbl_Section v
    INNER JOIN (
        SELECT RuntimeID RuntimeVersionID, ID IDVersion FROM @tbl_Identity WHERE Entity='Version'   
        UNION ALL
        SELECT RuntimeVersionID, IDVersion FROM @tbl_Version WHERE IDVersion <> 0 
    ) tmpl ON v.RuntimeVersionID = tmpl.RuntimeVersionID
    WHERE v.IDSection = 0 
) AS source
ON 1 = 0 -- Trik agar selalu memicu aksi INSERT
WHEN NOT MATCHED THEN
    INSERT (IDVersion,IDSection,SectionName,DisplayOrder)
    VALUES (source.IDVersion, source.NewIDSection, source.SectionName, source.DisplayOrder)
OUTPUT 
	'Section' Entity,
    source.RuntimeSectionID,  
    inserted.IDSection
INTO @tbl_Identity (Entity, RuntimeID, ID);    

-- Capture resolved IDs only in debug mode, after new Sections have been mapped.
IF @p_IsDebug=1
BEGIN
    SELECT v.IDSubSection, v.RuntimeSubSectionID, v.RuntimeSectionID, v.SubSectionName, v.DisplayOrder, sec.IDSection AS ResolvedIDSection
    INTO tmpDebug_PIP_M_CheckListWOPM_SubSectionSource
    FROM @tbl_SubSection v
    LEFT JOIN (
        SELECT RuntimeID AS RuntimeSectionID, ID AS IDSection FROM @tbl_Identity WHERE Entity='Section'
        UNION ALL
        SELECT RuntimeSectionID, IDSection FROM @tbl_Section WHERE IDSection <> 0
    ) sec ON sec.RuntimeSectionID = v.RuntimeSectionID;
END;

IF EXISTS (SELECT 1 FROM @tbl_SubSection v
    WHERE NOT EXISTS (
        SELECT 1
        FROM (
            SELECT RuntimeID AS RuntimeSectionID, ID AS IDSection FROM @tbl_Identity WHERE Entity='Section'
            UNION ALL
            SELECT RuntimeSectionID, IDSection FROM @tbl_Section WHERE IDSection <> 0
        ) sec
        WHERE sec.RuntimeSectionID = v.RuntimeSectionID
    ))
BEGIN
    RAISERROR('SaveAllTemplate: a Sub-section RuntimeSectionID could not be mapped to a database Section ID.', 16, 1);
    RETURN;
END;

-- Resolve/create sub-sections before linking items to them.
MERGE INTO PIP_M_CheckListWOPM_SubSection AS target
USING (
    SELECT v.RuntimeSubSectionID, v.RuntimeSectionID, v.SubSectionName, v.DisplayOrder, sec.IDSection,
           (SELECT ISNULL(MAX(IDSubSection),0) FROM PIP_M_CheckListWOPM_SubSection WITH (UPDLOCK, HOLDLOCK)) +
           ROW_NUMBER() OVER (ORDER BY v.RuntimeSectionID, v.RuntimeSubSectionID) AS NewIDSubSection
    FROM @tbl_SubSection v
    INNER JOIN (
        SELECT RuntimeID RuntimeSectionID, ID IDSection FROM @tbl_Identity WHERE Entity='Section'
        UNION ALL SELECT RuntimeSectionID, IDSection FROM @tbl_Section WHERE IDSection <> 0
    ) sec ON sec.RuntimeSectionID=v.RuntimeSectionID
    WHERE v.IDSubSection=0
) AS source
ON 1=0
WHEN NOT MATCHED THEN
    INSERT (IDSubSection, IDSection, SubSectionName, DisplayOrder)
    VALUES (source.NewIDSubSection, source.IDSection, source.SubSectionName, source.DisplayOrder)
OUTPUT 'SubSection',source.RuntimeSubSectionID,inserted.IDSubSection INTO @tbl_Identity (Entity,RuntimeID,ID);

UPDATE ExistingSub
SET ExistingSub.SubSectionName = Incoming.SubSectionName,
    ExistingSub.DisplayOrder = Incoming.DisplayOrder,
    ExistingSub.IDSection = SectionMap.IDSection
FROM PIP_M_CheckListWOPM_SubSection ExistingSub
JOIN @tbl_SubSection Incoming ON Incoming.IDSubSection = ExistingSub.IDSubSection
JOIN (SELECT RuntimeID RuntimeSectionID, ID IDSection FROM @tbl_Identity WHERE Entity='Section' UNION ALL SELECT RuntimeSectionID, IDSection FROM @tbl_Section WHERE IDSection<>0) SectionMap ON SectionMap.RuntimeSectionID = Incoming.RuntimeSectionID;

UPDATE I
SET 
    I.ItemLabel = S.ItemLabel,
    I.ItemType = S.ItemType,
    I.Unit = S.Unit,
    I.IsRemark1Required = S.IsRemark1Required,
    I.IsRemark2Required = S.IsRemark2Required,
    I.Remark1Text = S.Remark1Text,
    I.Remark2Text = S.Remark2Text,
    I.IsValueRequired = S.IsValueRequired,
    I.ShowUnitInRange = S.ShowUnitInRange,
    I.OptionList = S.OptionList,
    I.MinTolerance = S.MinTolerance, I.MaxTolerance = S.MaxTolerance, I.ModelCode = S.ModelCode,
    I.MinValue = S.MinValue,
    I.MaxValue = S.MaxValue, I.DisplayOrder=S.DisplayOrder, I.IDSection=SS.IDSection, I.IsToleranceRequired=S.IsToleranceRequired,
    I.RemarkRequiredOptions=S.RemarkRequiredOptions,
    I.IsUseDefaultRemark1=S.IsUseDefaultRemark1,
    I.IsUseDefaultRemark2=S.IsUseDefaultRemark2,
    I.IsRemark1Mandatory=S.IsRemark1Mandatory,
    I.IsRemark2Mandatory=S.IsRemark2Mandatory,
    I.IDSubSection = CASE WHEN ISNULL(S.RuntimeSubSectionID,0)=0 THEN NULL ELSE SubS.IDSubSection END
FROM PIP_M_CheckListWOPM_item I
JOIN @tbl_Item S JOIN @tbl_Section SS ON SS.RuntimeSectionID=S.RuntimeSectionID ON I.IDItem = S.IDItem
LEFT JOIN (SELECT RuntimeID RuntimeSubSectionID, ID IDSubSection FROM @tbl_Identity WHERE Entity='SubSection' UNION ALL SELECT RuntimeSubSectionID, IDSubSection FROM @tbl_SubSection WHERE IDSubSection<>0) SubS ON SubS.RuntimeSubSectionID=S.RuntimeSubSectionID
WHERE S.IDItem > 0

DELETE SS
FROM PIP_M_CheckListWOPM_SubSection SS
JOIN PIP_M_CheckListWOPM_Section SEC ON SEC.IDSection=SS.IDSection
JOIN @tbl_Version V ON V.IDVersion=SEC.IDVersion
JOIN PIP_M_CheckListWOPM_Version VER ON VER.IDVersion=V.IDVersion
JOIN PIP_M_CheckListWOPM T ON T.IDTemplate=VER.IDTemplate
WHERE NOT EXISTS (SELECT 1 FROM @tbl_SubSection S WHERE S.IDSubSection=SS.IDSubSection)
-- Newly inserted rows have generated database IDs that are not present in the TVP's IDSubSection=0 rows.
-- Preserve them during this cleanup; otherwise every new Sub-section is deleted in the same Save All call.
AND NOT EXISTS (SELECT 1 FROM @tbl_Identity NewSub WHERE NewSub.Entity='SubSection' AND NewSub.ID=SS.IDSubSection)
AND (ISNULL(T.CompanyScope,'S')='A' OR (';' + ISNULL(T.CompanyLocationList, '') + ';' LIKE '%;' + @p_CompanyID + @p_LocationID + ';%'));

MERGE INTO PIP_M_CheckListWOPM_item AS target
USING (
    SELECT 
        v.RuntimeItemID,
        v.RuntimeSectionID,
        v.ItemLabel, v.ItemType, V.Unit, V.IsRemark1Required, V.IsRemark2Required, V.IsValueRequired, V.ShowUnitInRange,
        v.OptionList, v.MinValue, v.MaxValue, v.DisplayOrder,
        tmpl.IDSection, subMap.IDSubSection, v.MinTolerance, v.MaxTolerance, v.ModelCode, v.IsToleranceRequired, v.RemarkRequiredOptions, v.Remark1Text, v.Remark2Text, v.IsUseDefaultRemark1, v.IsUseDefaultRemark2, v.IsRemark1Mandatory, v.IsRemark2Mandatory,
        (SELECT ISNULL(MAX(IDItem), 0) FROM PIP_M_CheckListWOPM_item) 
        + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS NewIDItem
    FROM @tbl_Item v
    INNER JOIN (
        SELECT RuntimeID RuntimeSectionID, ID IDSection FROM @tbl_Identity WHERE Entity='Section'  
        UNION ALL
        SELECT RuntimeSectionID, IDSection FROM @tbl_Section WHERE IDSection <> 0 
    ) tmpl ON v.RuntimeSectionID = tmpl.RuntimeSectionID
    LEFT JOIN (SELECT RuntimeID RuntimeSubSectionID, ID IDSubSection FROM @tbl_Identity WHERE Entity='SubSection' UNION ALL SELECT RuntimeSubSectionID, IDSubSection FROM @tbl_SubSection WHERE IDSubSection<>0) subMap ON subMap.RuntimeSubSectionID=v.RuntimeSubSectionID
    WHERE v.IDItem = 0 
) AS source
ON 1 = 0 -- Trik agar selalu memicu aksi INSERT
WHEN NOT MATCHED THEN
    INSERT (IDSection,IDSubSection,IDItem,ItemLabel,ItemType,OptionList,MinValue,MaxValue,Unit,
            ShowUnitInRange,IsValueRequired,IsRemark1Required,IsRemark2Required,Remark1Text,Remark2Text,DisplayOrder,MinTolerance,MaxTolerance,ModelCode,IsToleranceRequired,RemarkRequiredOptions,IsUseDefaultRemark1,IsUseDefaultRemark2,IsRemark1Mandatory,IsRemark2Mandatory)
    VALUES (source.IDSection, source.IDSubSection, source.NewIDItem, source.ItemLabel, source.ItemType, source.OptionList, source.MinValue, source.MaxValue, source.Unit,
            source.ShowUnitInRange, source.IsValueRequired, source.IsRemark1Required, source.IsRemark2Required, source.Remark1Text, source.Remark2Text, source.DisplayOrder,
            source.MinTolerance, source.MaxTolerance, source.ModelCode,source.IsToleranceRequired,source.RemarkRequiredOptions,source.IsUseDefaultRemark1,source.IsUseDefaultRemark2,source.IsRemark1Mandatory,source.IsRemark2Mandatory)
OUTPUT
	'Item' Entity, 
    source.RuntimeItemID,  
    inserted.IDItem
INTO @tbl_Identity (Entity, RuntimeID, ID);    

--- item group
UPDATE I
SET 
    I.GroupName = S.GroupName,
    I.FieldList = S.FieldList,
    I.Unit = S.Unit, 
	I.DisplayOrder=S.DisplayOrder, I.IDItem=SS.IDItem
FROM PIP_M_CheckListWOPM_itemgroup I
JOIN @tbl_Group S JOIN @tbl_Item SS ON SS.RuntimeItemID=S.RuntimeItemID ON I.IDGroup = S.IDGroup 
WHERE S.IDGroup > 0
MERGE INTO PIP_M_CheckListWOPM_itemgroup AS target
USING (
    SELECT 
        v.RuntimeGroupID,
        v.RuntimeItemID,
        v.GroupName, v.FieldList, V.Unit, v.DisplayOrder,
        tmpl.IDItem,
        (SELECT ISNULL(MAX(IDGroup), 0) FROM PIP_M_CheckListWOPM_itemgroup) 
        + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS NewIDGroup
    FROM @tbl_Group v 
    INNER JOIN (
        SELECT RuntimeID RuntimeItemID, ID IDItem FROM @tbl_Identity WHERE Entity='Item'
        UNION ALL
        SELECT RuntimeItemID, IDItem FROM @tbl_Item WHERE IDItem<> 0 
    ) tmpl ON v.RuntimeItemID = tmpl.RuntimeItemID
    WHERE v.IDGroup = 0 
) AS source
ON 1 = 0 -- Trik agar selalu memicu aksi INSERT
WHEN NOT MATCHED THEN
    INSERT (IDItem,IDGroup,GroupName,FieldList,Unit,DisplayOrder)
    VALUES (source.IDItem, source.NewIDGroup, source.GroupName, source.FieldList, source.Unit, source.DisplayOrder)
OUTPUT 
	'Group',
    source.RuntimeGroupID,  
    inserted.IDGroup

INTO @tbl_Identity (Entity, RuntimeID, ID);

--- native REPEAT configuration and child fields
DECLARE @tbl_ResolvedRepeat TABLE
(
    IDItem INT NULL,
    RuntimeItemID INT NOT NULL,
    RepeatMode VARCHAR(10) NOT NULL,
    ColumnCount INT NOT NULL,
    ObjectLabel NVARCHAR(100) NULL,
    CountMode VARCHAR(10) NOT NULL,
    FixedCount INT NULL,
    MinCount INT NULL,
    MaxCount INT NULL
);
INSERT INTO @tbl_ResolvedRepeat
SELECT COALESCE(ItemIdentity.ID, ExistingItem.IDItem), C.RuntimeItemID, C.RepeatMode,
       C.ColumnCount, C.ObjectLabel, C.CountMode, C.FixedCount, C.MinCount, C.MaxCount
FROM @tbl_RepeatConfig C
LEFT JOIN @tbl_Identity ItemIdentity ON ItemIdentity.Entity='Item' AND ItemIdentity.RuntimeID=C.RuntimeItemID
LEFT JOIN @tbl_Item ExistingItem ON ExistingItem.RuntimeItemID=C.RuntimeItemID AND ExistingItem.IDItem>0;

IF EXISTS (SELECT 1 FROM @tbl_ResolvedRepeat WHERE ISNULL(IDItem,0)<=0)
BEGIN RAISERROR('A REPEAT item could not be resolved to a database Item ID.',16,1); RETURN; END;

UPDATE R
SET RepeatMode=S.RepeatMode, ColumnCount=S.ColumnCount, ObjectLabel=S.ObjectLabel,
    CountMode=S.CountMode, FixedCount=S.FixedCount, MinCount=S.MinCount, MaxCount=S.MaxCount
FROM dbo.PIP_M_CheckListWOPM_ItemRepeat R
JOIN @tbl_ResolvedRepeat S ON S.IDItem=R.IDItem;

INSERT dbo.PIP_M_CheckListWOPM_ItemRepeat
    (IDItem,RepeatMode,ColumnCount,ObjectLabel,CountMode,FixedCount,MinCount,MaxCount)
SELECT S.IDItem,S.RepeatMode,S.ColumnCount,S.ObjectLabel,S.CountMode,S.FixedCount,S.MinCount,S.MaxCount
FROM @tbl_ResolvedRepeat S
WHERE NOT EXISTS (SELECT 1 FROM dbo.PIP_M_CheckListWOPM_ItemRepeat R WHERE R.IDItem=S.IDItem);

IF EXISTS
(
    SELECT 1
    FROM @tbl_RepeatField S
    JOIN @tbl_ResolvedRepeat R ON R.RuntimeItemID=S.RuntimeItemID
    WHERE S.IDRepeat IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F
                      WHERE F.IDItem=R.IDItem AND F.IDRepeat=S.IDRepeat)
)
BEGIN RAISERROR('An IDRepeat does not belong to the submitted REPEAT item.',16,1); RETURN; END;

DELETE F
FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F
JOIN @tbl_ResolvedRepeat R ON R.IDItem=F.IDItem
WHERE NOT EXISTS
(
    SELECT 1 FROM @tbl_RepeatField S
    WHERE S.RuntimeItemID=R.RuntimeItemID AND S.IDRepeat=F.IDRepeat
);

UPDATE F
SET FieldLabel=S.FieldLabel, FieldType=S.FieldType, OptionList=S.OptionList, Unit=S.Unit,
    MinValue=S.MinValue, MaxValue=S.MaxValue, IsRequired=S.IsRequired,
    GroupName=S.GroupName, DisplayOrder=S.DisplayOrder,
    MinInclusive=S.MinInclusive, MaxInclusive=S.MaxInclusive
FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F
JOIN @tbl_ResolvedRepeat R ON R.IDItem=F.IDItem
JOIN @tbl_RepeatField S ON S.RuntimeItemID=R.RuntimeItemID AND S.IDRepeat=F.IDRepeat;

/* Allocate manual IDRepeat values under an exclusive table lock.
   The lock is held until the inserts and identity-map output are committed. */
DECLARE @tbl_NewRepeatField TABLE
(
    IDRepeat INT NOT NULL PRIMARY KEY,
    IDItem INT NOT NULL,
    RuntimeRepeatID INT NOT NULL,
    FieldLabel NVARCHAR(100),
    FieldType VARCHAR(20),
    OptionList NVARCHAR(1000),
    Unit NVARCHAR(30),
    MinValue DECIMAL(18,4),
    MaxValue DECIMAL(18,4),
    IsRequired BIT,
    GroupName NVARCHAR(100),
    DisplayOrder INT,
    MinInclusive BIT,
    MaxInclusive BIT
);
DECLARE @V_NextRepeatID INT;

IF EXISTS (SELECT 1 FROM @tbl_RepeatField WHERE IDRepeat IS NULL)
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @V_NextRepeatID=CASE WHEN MAX(IDRepeat)=2147483647 THEN NULL ELSE ISNULL(MAX(IDRepeat),0)+1 END
        FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField WITH (TABLOCKX,HOLDLOCK);

        IF @V_NextRepeatID IS NULL
           OR @V_NextRepeatID > 2147483647 - (SELECT COUNT(*) FROM @tbl_RepeatField WHERE IDRepeat IS NULL) + 1
        BEGIN
            RAISERROR('IDRepeat has reached the INT limit; the new REPEAT field IDs cannot be allocated.',16,1);
        END;

        INSERT @tbl_NewRepeatField
            (IDRepeat,IDItem,RuntimeRepeatID,FieldLabel,FieldType,OptionList,Unit,MinValue,MaxValue,
             IsRequired,GroupName,DisplayOrder,MinInclusive,MaxInclusive)
        SELECT @V_NextRepeatID+CONVERT(INT,ROW_NUMBER() OVER(ORDER BY R.IDItem,S.RuntimeRepeatID))-1,
               R.IDItem,S.RuntimeRepeatID,S.FieldLabel,S.FieldType,S.OptionList,S.Unit,S.MinValue,S.MaxValue,
               S.IsRequired,S.GroupName,S.DisplayOrder,S.MinInclusive,S.MaxInclusive
        FROM @tbl_RepeatField S
        JOIN @tbl_ResolvedRepeat R ON R.RuntimeItemID=S.RuntimeItemID
        WHERE S.IDRepeat IS NULL;

        MERGE dbo.PIP_M_CheckListWOPM_ItemRepeatField AS target
        USING @tbl_NewRepeatField AS source
        ON 1=0
        WHEN NOT MATCHED THEN
            INSERT (IDRepeat,IDItem,FieldLabel,FieldType,OptionList,Unit,MinValue,MaxValue,IsRequired,
                    GroupName,DisplayOrder,MinInclusive,MaxInclusive)
            VALUES (source.IDRepeat,source.IDItem,source.FieldLabel,source.FieldType,source.OptionList,source.Unit,
                    source.MinValue,source.MaxValue,source.IsRequired,source.GroupName,source.DisplayOrder,
                    source.MinInclusive,source.MaxInclusive)
        OUTPUT 'RepeatField',source.RuntimeRepeatID,inserted.IDRepeat
        INTO @tbl_Identity (Entity,RuntimeID,ID);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        DECLARE @V_RepeatError NVARCHAR(4000);
        SET @V_RepeatError=ERROR_MESSAGE();
        RAISERROR('%s',16,1,@V_RepeatError);
        RETURN;
    END CATCH;
END;

-- Remove REPEAT definitions when an item is changed back to a scalar type.
DELETE F
FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F
JOIN @tbl_Item I ON I.IDItem=F.IDItem AND I.ItemType<>'REPEAT';
DELETE R
FROM dbo.PIP_M_CheckListWOPM_ItemRepeat R
JOIN @tbl_Item I ON I.IDItem=R.IDItem AND I.ItemType<>'REPEAT';

IF @p_IsPublished=1
BEGIN
	IF EXISTS (SELECT * FROM @tbl_Identity WHERE Entity='Version')
	BEGIN
		UPDATE A SET a.[Status]='Archieved' 
		FROM PIP_M_CheckListWOPM_Version a 
		JOIN @tbl_Identity b JOIN PIP_M_CheckListWOPM_Version aa ON aa.IDVersion=b.ID ON aa.IDTemplate=a.IDTemplate 
		WHERE Entity='Version' AND a.[Status]='Active'
		UPDATE a SET a.[Status]='Active' 
		FROM PIP_M_CheckListWOPM_Version a JOIN @tbl_Identity b ON b.ID=a.IDVersion  
		WHERE Entity='Version' AND a.[Status]='Draft'
	END
	ELSE
	BEGIN
		UPDATE A SET a.[Status]='Archieved' 
		FROM PIP_M_CheckListWOPM_Version a 
		JOIN @tbl_Version b JOIN PIP_M_CheckListWOPM_Version aa ON aa.IDVersion=b.IDVersion ON aa.IDTemplate=a.IDTemplate 
		WHERE b.IDVersion<>0 AND a.[Status]='Active'
		UPDATE a SET a.[Status]='Active' 
		FROM PIP_M_CheckListWOPM_Version a JOIN @tbl_Version b ON b.IDVersion=a.IDVersion  
		WHERE a.[Status]='Draft' AND b.IDVersion<>0
		
	END
END
SELECT * FROM @tbl_Identity    

--- end processsing

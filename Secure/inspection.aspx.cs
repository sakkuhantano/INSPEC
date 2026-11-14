using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.Linq;
using System.IO;
using System.Net.Mail;
using System.Text;
using System.Web;
using System.Web.Services;
using Newtonsoft.Json.Linq;
using WAL;

namespace INSPEC.Secure
{
    public partial class inspection : System.Web.UI.Page
    {
        protected void Page_Load(object sender, EventArgs e)
        {
            // Handle report downloads first. Download URLs use ?download=TOKEN.
            string downloadToken = (Request.QueryString["download"] ?? String.Empty).Trim();

            if (!String.IsNullOrWhiteSpace(downloadToken))
            {
                DownloadInspectionReport(downloadToken);
                return;
            }

            // Normal inspection entry / approval page.
            string mode = (Request.QueryString["type"] ?? String.Empty)
                .Trim()
                .ToLowerInvariant();

            if (mode == "entry")
                GFC.RequireMenuEmployee("20021");
            else if (mode == "approval")
                GFC.RequireMenuEmployee("20022");
            else
                throw new HttpException(400, "Invalid Inspection mode.");
        }

        [WebMethod]
        public static object SyncInspections(object inspections, string userId)
        {
            userId = GFC.RequireMenuEmployee("20021");
            var outcomes = new List<object>();
            if (String.IsNullOrWhiteSpace(userId))
                return new { success = false, message = "Login employee is required.", results = outcomes };

            JArray records;
            try
            {
                records = JArray.FromObject(inspections);
            }
            catch (Exception ex)
            {
                return new { success = false, message = ex.Message, results = outcomes };
            }

            foreach (JObject record in records.OfType<JObject>())
            {
                string clientId = TokenString(record, "ClientInspectionID");
                string syncStage = "validate request";
                try
                {
                    if (String.IsNullOrWhiteSpace(clientId))
                        throw new Exception("ClientInspectionID is required.");

                    string status = TokenString(record, "Status").ToUpperInvariant();
                    string inspectionMode = TokenString(record, "InspectionMode").Trim().ToUpperInvariant();
                    if (inspectionMode == "") inspectionMode = "STANDARD";
                    bool isLightningInspection = String.Equals(inspectionMode, "LIGHTNING", StringComparison.OrdinalIgnoreCase);
                    bool isBatchInspection = String.Equals(inspectionMode, "BATCH", StringComparison.OrdinalIgnoreCase) || isLightningInspection;
                    if (status != "DONE")
                        throw new Exception("Only completed inspections (DONE) can be synced to SQL Server.");

                    GFC.RequireCompanyLocation(userId, TokenString(record, "CompanyID"), TokenString(record, "LocationID"));
                    string recordOwner = TokenString(record, "OwnerEmployeeID");
                    if (String.IsNullOrWhiteSpace(recordOwner) ||
                        !String.Equals(recordOwner, userId, StringComparison.OrdinalIgnoreCase))
                        throw new Exception("This offline inspection belongs to another employee. No data was uploaded.");

                    syncStage = "build checklist data";
                    // dbo.Type_N_Tbl_C13: C1=IDItem, C2=ItemLabel, C3=ItemType,
                    // C4=Value, C5=Remark1, C6=IsAnomali, C7=DisplayOrder, C8=Remark2; C9-C13 unused.
                    DataTable items = new DataTable();
                    for (int i = 1; i <= 13; i++)
                        items.Columns.Add("C" + i, typeof(string));

                    // dbo.Type_N_Tbl_C5: C1=IDItem, C2=FieldKey, C3=Value, C4=ObjectIndex.
                    DataTable itemValues = new DataTable();
                    for (int i = 1; i <= 5; i++)
                        itemValues.Columns.Add("C" + i, typeof(string));

                    DataTable batchPoints = new DataTable();
                    for (int i = 1; i <= 13; i++)
                        batchPoints.Columns.Add("C" + i, typeof(string));
                    DataTable batchItems = new DataTable();
                    for (int i = 1; i <= 13; i++)
                        batchItems.Columns.Add("C" + i, typeof(string));
                    DataTable batchItemValues = new DataTable();
                    for (int i = 1; i <= 5; i++)
                        batchItemValues.Columns.Add("C" + i, typeof(string));
                    DataTable lightningSchedules = new DataTable();
                    for (int i = 1; i <= 13; i++)
                        lightningSchedules.Columns.Add("C" + i, typeof(string));
                    if (isLightningInspection)
                    {
                        JArray scheduleArray = record["Schedules"] as JArray ?? new JArray();
                        var uniqueSchedules = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                        foreach (JToken scheduleToken in scheduleArray)
                        {
                            string scheduleTime = (scheduleToken.Type == JTokenType.Object
                                ? TokenString((JObject)scheduleToken, "ScheduleTime")
                                : scheduleToken.ToString()).Trim();
                            if (scheduleTime.Length != 5 || !uniqueSchedules.Add(scheduleTime))
                                throw new Exception("LIGHTNING ScheduleTime is invalid or duplicated.");
                            DataRow scheduleRow = lightningSchedules.NewRow();
                            scheduleRow["C1"] = scheduleTime;
                            lightningSchedules.Rows.Add(scheduleRow);
                        }
                        if (lightningSchedules.Rows.Count == 0)
                            throw new Exception("LIGHTNING daily inspection must contain all configured ScheduleTime values.");
                    }

                    JArray itemArray = record["Items"] as JArray ?? new JArray();
                    int displayOrder = 0;
                    foreach (JObject item in itemArray.OfType<JObject>())
                    {
                        displayOrder++;
                        DataRow row = items.NewRow();
                        row["C1"] = TokenInt(item, "IDItem").ToString(CultureInfo.InvariantCulture);
                        row["C2"] = Limit(TokenString(item, "ItemLabel"), 500);
                        row["C3"] = Limit(TokenString(item, "Type"), 20);
                        row["C4"] = DbString(Limit(TokenString(item, "Value"), 50));
                        row["C5"] = DbString(Limit((TokenString(item, "Remark1") == "" ? TokenString(item, "Remark") : TokenString(item, "Remark1")), 500));
                        row["C8"] = DbString(Limit(TokenString(item, "Remark2"), 500));
                        row["C6"] = TokenBool(item, "IsAnomali") ? "1" : "0";
                        row["C7"] = (item["DisplayOrder"] == null ? displayOrder : TokenInt(item, "DisplayOrder")).ToString(CultureInfo.InvariantCulture);
                        items.Rows.Add(row);

                        JObject values = item["Values"] as JObject;
                        if (values != null)
                        {
                            foreach (JProperty field in values.Properties())
                            {
                                DataRow valueRow = itemValues.NewRow();
                                valueRow["C1"] = TokenInt(item, "IDItem").ToString(CultureInfo.InvariantCulture);
                                valueRow["C2"] = Limit(field.Name, 100);
                                valueRow["C3"] = DbString(field.Value == null || field.Value.Type == JTokenType.Null ? "" : field.Value.ToString());
                                itemValues.Rows.Add(valueRow);
                            }
                        }
                        JArray repeatValues = item["RepeatValues"] as JArray;
                        if (repeatValues != null)
                        {
                            foreach (JObject repeatObject in repeatValues.OfType<JObject>())
                            {
                                int objectIndex = TokenInt(repeatObject, "ObjectIndex");
                                JObject repeatFields = repeatObject["Values"] as JObject;
                                if (repeatFields == null) continue;
                                foreach (JProperty field in repeatFields.Properties())
                                {
                                    DataRow valueRow = itemValues.NewRow();
                                    valueRow["C1"] = TokenInt(item, "IDItem").ToString(CultureInfo.InvariantCulture);
                                    valueRow["C2"] = Limit(field.Name, 100);
                                    valueRow["C3"] = DbString(field.Value == null || field.Value.Type == JTokenType.Null ? "" : field.Value.ToString());
                                    valueRow["C4"] = objectIndex.ToString(CultureInfo.InvariantCulture);
                                    itemValues.Rows.Add(valueRow);
                                }
                            }
                        }
                    }

                    if (isBatchInspection)
                    {
                        JArray pointArray = record["Points"] as JArray ?? new JArray();
                        if (pointArray.Count == 0)
                            throw new Exception("BATCH inspection must contain at least one Inspection Point.");

                        var clientPointIDs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                        var masterPointIDs = new HashSet<long>();
                        var schedulePointIDs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                        foreach (JObject point in pointArray.OfType<JObject>())
                        {
                            string clientPointID = Limit(TokenString(point, "ClientPointID"), 36);
                            long masterPointID = TokenLong(point, "InspectionPointID");
                            string pointStatus = TokenString(point, "Status").ToUpperInvariant();
                            string pointScheduleTime = isLightningInspection ? TokenString(point, "ScheduleTime").Trim() : "";
                            bool duplicateMasterPoint = isLightningInspection
                                ? !schedulePointIDs.Add(pointScheduleTime + "|" + masterPointID.ToString(CultureInfo.InvariantCulture))
                                : !masterPointIDs.Add(masterPointID);
                            if (String.IsNullOrWhiteSpace(clientPointID) || masterPointID <= 0 ||
                                !clientPointIDs.Add(clientPointID) || duplicateMasterPoint)
                                throw new Exception("BATCH/LIGHTNING Inspection Point identity is invalid or duplicated.");
                            if (pointStatus != "DONE" && pointStatus != "ABNORMAL")
                                throw new Exception("Every selected BATCH Inspection Point must be DONE or ABNORMAL.");

                            DataRow pointRow = batchPoints.NewRow();
                            pointRow["C1"] = clientPointID;
                            pointRow["C2"] = masterPointID.ToString(CultureInfo.InvariantCulture);
                            pointRow["C3"] = TokenString(point, "InspectionDateTime");
                            pointRow["C4"] = pointStatus;
                            pointRow["C5"] = DbString(Limit(TokenString(point, "AbnormalRemark").Trim(), 500));
                            pointRow["C6"] = TokenString(point, "PointCondition").ToUpperInvariant();
                            pointRow["C7"] = pointScheduleTime;
                            batchPoints.Rows.Add(pointRow);

                            JArray pointItems = point["Items"] as JArray ?? new JArray();
                            foreach (JObject item in pointItems.OfType<JObject>())
                            {
                                DataRow itemRow = batchItems.NewRow();
                                itemRow["C1"] = clientPointID;
                                itemRow["C2"] = TokenInt(item, "IDItem").ToString(CultureInfo.InvariantCulture);
                                itemRow["C3"] = Limit(TokenString(item, "ItemLabel"), 500);
                                itemRow["C4"] = Limit(TokenString(item, "Type"), 20);
                                itemRow["C5"] = DbString(Limit(TokenString(item, "Value"), 50));
                                itemRow["C6"] = DbString(Limit((TokenString(item, "Remark1") == "" ? TokenString(item, "Remark") : TokenString(item, "Remark1")), 500));
                                itemRow["C7"] = TokenBool(item, "IsAnomali") ? "1" : "0";
                                itemRow["C8"] = (item["DisplayOrder"] == null ? batchItems.Rows.Count + 1 : TokenInt(item, "DisplayOrder")).ToString(CultureInfo.InvariantCulture);
                                itemRow["C9"] = DbString(Limit(TokenString(item, "Remark2"), 500));
                                batchItems.Rows.Add(itemRow);

                                JObject values = item["Values"] as JObject;
                                if (values != null)
                                {
                                    foreach (JProperty field in values.Properties())
                                    {
                                        DataRow valueRow = batchItemValues.NewRow();
                                        valueRow["C1"] = clientPointID;
                                        valueRow["C2"] = TokenInt(item, "IDItem").ToString(CultureInfo.InvariantCulture);
                                        valueRow["C3"] = Limit(field.Name, 100);
                                        valueRow["C4"] = DbString(field.Value == null || field.Value.Type == JTokenType.Null ? "" : field.Value.ToString());
                                        batchItemValues.Rows.Add(valueRow);
                                    }
                                }
                                JArray repeatValues = item["RepeatValues"] as JArray;
                                if (repeatValues != null)
                                {
                                    foreach (JObject repeatObject in repeatValues.OfType<JObject>())
                                    {
                                        int objectIndex = TokenInt(repeatObject, "ObjectIndex");
                                        JObject repeatFields = repeatObject["Values"] as JObject;
                                        if (repeatFields == null) continue;
                                        foreach (JProperty field in repeatFields.Properties())
                                        {
                                            DataRow valueRow = batchItemValues.NewRow();
                                            valueRow["C1"] = clientPointID;
                                            valueRow["C2"] = TokenInt(item, "IDItem").ToString(CultureInfo.InvariantCulture);
                                            valueRow["C3"] = Limit(field.Name, 100);
                                            valueRow["C4"] = DbString(field.Value == null || field.Value.Type == JTokenType.Null ? "" : field.Value.ToString());
                                            valueRow["C5"] = objectIndex.ToString(CultureInfo.InvariantCulture);
                                            batchItemValues.Rows.Add(valueRow);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if (status != "DONE")
                        throw new Exception("Invalid inspection status.");

                        syncStage = "parse inspection photos";
                        JArray photoArray = record["Photos"] as JArray ?? new JArray();
                        var incomingPhotos = new List<Tuple<string, int, string, byte[]>>();
                        var incomingBatchPhotos = new List<Tuple<string, string, int, string, byte[]>>();
                        var pointPhotoSeqs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                        var usedSeqNos = new HashSet<int>();
                        foreach (JObject photo in photoArray.OfType<JObject>())
                        {
                            string type = TokenString(photo, "Type").ToUpperInvariant();
                            if (type != "BEFORE" && type != "AFTER")
                                throw new Exception("Invalid inspection photo type.");

                            int seqNo = TokenInt(photo, "SeqNo");
                            if (seqNo <= 0 || !usedSeqNos.Add(seqNo))
                                throw new Exception("Inspection photo SeqNo must be unique and greater than zero.");

                            string dataUrl = TokenString(photo, "Data");
                            int comma = dataUrl.IndexOf(',');
                            if (comma < 0)
                                throw new Exception("Inspection photo data is invalid.");
                            string header = dataUrl.Substring(0, comma).ToLowerInvariant();
                            string extension;
                            if (header.StartsWith("data:image/jpeg;") || header.StartsWith("data:image/jpg;")) extension = "jpg";
                            else if (header.StartsWith("data:image/png;")) extension = "png";
                            else if (header.StartsWith("data:image/webp;")) extension = "webp";
                            else if (header.StartsWith("data:image/gif;")) extension = "gif";
                            else throw new Exception("Unsupported Inspection photo format. Use JPEG, PNG, WEBP, or GIF.");

                            byte[] bytes = Convert.FromBase64String(dataUrl.Substring(comma + 1));
                            if (bytes.Length == 0 || bytes.Length > 1024 * 1024)
                                throw new Exception("Inspection photo must be between 1 byte and 1 MB.");
                            incomingPhotos.Add(Tuple.Create(type, seqNo, extension, bytes));
                        }

                        if (isBatchInspection)
                        {
                            JArray pointArray = record["Points"] as JArray ?? new JArray();
                            foreach (JObject point in pointArray.OfType<JObject>())
                            {
                                string clientPointID = Limit(TokenString(point, "ClientPointID"), 36);
                                JArray pointPhotos = point["Photos"] as JArray ?? new JArray();
                                foreach (JObject photo in pointPhotos.OfType<JObject>())
                                {
                                    string type = TokenString(photo, "Type").ToUpperInvariant();
                                    if (type != "BEFORE" && type != "AFTER")
                                        throw new Exception("Invalid BATCH inspection photo type.");
                                    int seqNo = TokenInt(photo, "SeqNo");
                                    string sequenceKey = clientPointID + "|" + seqNo.ToString(CultureInfo.InvariantCulture);
                                    if (seqNo <= 0 || !pointPhotoSeqs.Add(sequenceKey))
                                        throw new Exception("BATCH photo SeqNo must be unique within each Inspection Point.");
                                    string dataUrl = TokenString(photo, "Data");
                                    int comma = dataUrl.IndexOf(',');
                                    if (comma < 0) throw new Exception("BATCH inspection photo data is invalid.");
                                    string header = dataUrl.Substring(0, comma).ToLowerInvariant();
                                    string extension;
                                    if (header.StartsWith("data:image/jpeg;") || header.StartsWith("data:image/jpg;")) extension = "jpg";
                                    else if (header.StartsWith("data:image/png;")) extension = "png";
                                    else if (header.StartsWith("data:image/webp;")) extension = "webp";
                                    else if (header.StartsWith("data:image/gif;")) extension = "gif";
                                    else throw new Exception("Unsupported BATCH inspection photo format.");
                                    byte[] bytes = Convert.FromBase64String(dataUrl.Substring(comma + 1));
                                    if (bytes.Length == 0 || bytes.Length > 1024 * 1024)
                                        throw new Exception("Each BATCH inspection photo must be between 1 byte and 1 MB.");
                                    incomingBatchPhotos.Add(Tuple.Create(clientPointID, type, seqNo, extension, bytes));
                                }
                            }
                        }

                    string companyId = Limit(TokenString(record, "CompanyID"), 10);
                    string locationId = Limit(TokenString(record, "LocationID"), 3);
                    string sectionId = Limit(TokenString(record, "SectionID"), 10);
                    var employeeSections = GFC.GetEmployeeSection(userId)
                        .Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)
                        .Select(x => x.Trim());
                    if (!employeeSections.Contains(sectionId, StringComparer.OrdinalIgnoreCase))
                        throw new HttpException(403, "Inspection section is not assigned to the logged-in employee.");
                    string inspectionTypeCode = Limit(TokenString(record, "InspectionTypeCode"), 2);
                    string inspectionTypeDetailCode = Limit(TokenString(record, "InspectionTypeDetailCode"), 20);
                    DateTime inspectionDate = ParseDate(TokenString(record, "InspectionDate"), DateTime.Today);
                    string inspectionNo = "";
                    long existingInspectionId = 0;
                    DateTime oldInspectionDate = inspectionDate;
                    string oldCompanyId = companyId;
                    string oldLocationId = locationId;
                    string oldInspectionNo = "";
                    DataTable oldPhotoRows = null;

                    using (var br = new WAL.BR.CF())
                    {
                        syncStage = "validate inspection template detail";
                        DataTable templateDetailCheck = br.EQueryP(@"
SELECT T.IDTemplate
FROM dbo.PIP_M_CheckListWOPM T
WHERE T.IDTemplate=@IDTemplate
  AND T.SectionID=@SectionID
  AND T.TemplateType='I'
  
  AND (ISNULL(T.CompanyScope,'S')='A'
       OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + @CompanyID + @LocationID + ';%'))
  AND (ISNULL(T.EmployeeList,'')=''
       OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + @EmployeeID + ';%'))
  AND EXISTS (
       SELECT 1 FROM dbo.PIP_M_CheckListWOPM_Version V
       WHERE V.IDTemplate=T.IDTemplate
         AND V.IDVersion=@IDVersion
         AND V.Version=@TemplateVersion
         AND V.Status IN ('Active','Archieved')
  )
  AND T.InspectionTypeCode=@InspectionTypeCode
  AND EXISTS (
       SELECT 1 FROM dbo.PIP_M_InspectionType IT
       WHERE IT.InspectionTypeCode=@InspectionTypeCode
         AND IT.SectionID=@SectionID
         AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')=@InspectionMode
  )
  AND (
       ISNULL(T.InspectionTypeDetailCode,'')=''
       OR EXISTS (
           SELECT 1
           FROM dbo.SplitStringConvertToTable(T.InspectionTypeDetailCode, ';') AllowedDetail
           WHERE LTRIM(RTRIM(AllowedDetail.val))=@InspectionTypeDetailCode
       )
  )",
                            new SqlParameter[] {
                                new SqlParameter("@IDTemplate", TokenInt(record, "IDTemplate")),
                                new SqlParameter("@IDVersion", TokenInt(record, "IDVersion")),
                                new SqlParameter("@TemplateVersion", Limit(TokenString(record, "TemplateVersion"), 10)),
                                new SqlParameter("@SectionID", sectionId),
                                new SqlParameter("@CompanyID", companyId),
                                new SqlParameter("@LocationID", locationId),
                                new SqlParameter("@EmployeeID", userId),
                                new SqlParameter("@InspectionTypeCode", inspectionTypeCode),
                                new SqlParameter("@InspectionMode", inspectionMode),
                                new SqlParameter("@InspectionTypeDetailCode", inspectionTypeDetailCode)
                            });
                        if (templateDetailCheck == null || templateDetailCheck.Rows.Count == 0)
                            throw new Exception("Inspection Detail tidak sesuai dengan batasan Inspection Detail pada Master Template.");

                        if (isBatchInspection)
                        {
                            syncStage = "validate batch checklist version rules";
                            DataTable versionRules = br.EQueryP(@"
SELECT ISNULL(V.PhotoRequirement,'NONE') PhotoRequirement,
       ISNULL(V.IsSummaryRequired,1) IsSummaryRequired,
       ISNULL(V.IsFollowUpRequired,1) IsFollowUpRequired,
       ISNULL(V.IsRemark1Required,0) IsRemark1Required,
       ISNULL(V.IsRemark2Required,0) IsRemark2Required,
       ISNULL(V.StatusOption,'') StatusOption,
       ISNULL(V.RemarkRequiredOptions,'') RemarkRequiredOptions
FROM dbo.PIP_M_CheckListWOPM_Version V
WHERE V.IDTemplate=@IDTemplate AND V.IDVersion=@IDVersion",
                                new SqlParameter[] {
                                    new SqlParameter("@IDTemplate", TokenInt(record, "IDTemplate")),
                                    new SqlParameter("@IDVersion", TokenInt(record, "IDVersion"))
                                });
                            if (versionRules == null || versionRules.Rows.Count != 1)
                                throw new Exception("Master Checklist Version tidak ditemukan untuk validasi BATCH.");

                            DataRow versionRule = versionRules.Rows[0];
                            string photoRequirement = Convert.ToString(versionRule["PhotoRequirement"]).Trim().ToUpperInvariant();
                            if (photoRequirement != "NONE" && photoRequirement != "BEFORE" &&
                                photoRequirement != "AFTER" && photoRequirement != "BOTH")
                                throw new Exception("Photo Requirement pada Master Checklist Version tidak valid.");

                            if (Convert.ToBoolean(versionRule["IsSummaryRequired"]) &&
                                String.IsNullOrWhiteSpace(TokenString(record, "Summary")))
                                throw new Exception("Final Inspection Summary wajib diisi sesuai Master Checklist Version.");

                            if (Convert.ToBoolean(versionRule["IsFollowUpRequired"]) &&
                                String.Equals(TokenString(record, "FollowUp"), "Recommend Follow Up", StringComparison.OrdinalIgnoreCase) &&
                                (String.IsNullOrWhiteSpace(TokenString(record, "FollowUpSection")) ||
                                 String.IsNullOrWhiteSpace(TokenString(record, "FollowUpRemark"))))
                                throw new Exception("Responsible Section dan Follow Up Remark wajib diisi sesuai Master Checklist Version.");

                            DataTable versionItems = br.EQueryP(@"
SELECT I.IDItem, I.ItemLabel, I.ItemType, ISNULL(I.OptionList,'') OptionList,
       ISNULL(I.IsValueRequired,0) IsValueRequired,
       ISNULL(I.IsRemark1Required,0) IsRemark1Required,
       ISNULL(I.IsRemark2Required,0) IsRemark2Required,
       ISNULL(I.IsRemark1Mandatory,0) IsRemark1Mandatory,
       ISNULL(I.IsRemark2Mandatory,0) IsRemark2Mandatory,
       ISNULL(I.IsUseDefaultRemark1,0) IsUseDefaultRemark1,
       ISNULL(I.IsUseDefaultRemark2,0) IsUseDefaultRemark2,
       ISNULL(I.IsToleranceRequired,0) IsToleranceRequired,
       I.MinValue, I.MaxValue, I.MinTolerance, I.MaxTolerance,
       ISNULL(I.RemarkRequiredOptions,'') RemarkRequiredOptions
FROM dbo.PIP_M_CheckListWOPM_Item I
INNER JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
WHERE S.IDVersion=@IDVersion
ORDER BY S.DisplayOrder, I.DisplayOrder",
                                new SqlParameter[] {
                                    new SqlParameter("@IDVersion", TokenInt(record, "IDVersion"))
                                });
                            if (versionItems == null || versionItems.Rows.Count == 0)
                                throw new Exception("Master Checklist Version tidak memiliki item checklist.");

                            DataTable versionGroups = br.EQueryP(@"
SELECT G.IDItem, G.GroupName, G.FieldList
FROM dbo.PIP_M_CheckListWOPM_ItemGroup G
INNER JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=G.IDItem
INNER JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
WHERE S.IDVersion=@IDVersion
ORDER BY G.DisplayOrder",
                                new SqlParameter[] {
                                    new SqlParameter("@IDVersion", TokenInt(record, "IDVersion"))
                                });
                            DataTable versionRepeatConfig = br.EQueryP(@"
SELECT R.IDItem,R.RepeatMode,R.CountMode,R.FixedCount,R.MinCount,R.MaxCount
FROM dbo.PIP_M_CheckListWOPM_ItemRepeat R
JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=R.IDItem
JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
WHERE S.IDVersion=@IDVersion",
                                new SqlParameter[] { new SqlParameter("@IDVersion", TokenInt(record, "IDVersion")) });
                            DataTable versionRepeatFields = br.EQueryP(@"
SELECT F.IDItem,F.FieldKey,F.FieldType,F.OptionList,F.MinValue,F.MaxValue,F.MinInclusive,F.MaxInclusive,F.IsRequired
FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F
JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=F.IDItem
JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
WHERE S.IDVersion=@IDVersion
ORDER BY F.IDItem,F.DisplayOrder",
                                new SqlParameter[] { new SqlParameter("@IDVersion", TokenInt(record, "IDVersion")) });

                            string versionRemarkOptions = Convert.ToString(versionRule["RemarkRequiredOptions"]);
                            JArray versionPointArray = record["Points"] as JArray ?? new JArray();
                            foreach (JObject versionPoint in versionPointArray.OfType<JObject>())
                            {
                                string pointCode = TokenString(versionPoint, "PointCode");
                                if (String.IsNullOrWhiteSpace(pointCode))
                                    pointCode = "Inspection Point " + TokenLong(versionPoint, "InspectionPointID").ToString(CultureInfo.InvariantCulture);
                                string pointPrefix = pointCode + ": ";
                                JArray submittedItems = versionPoint["Items"] as JArray ?? new JArray();
                                var submittedItemsById = new Dictionary<int, JObject>();
                                foreach (JObject submittedItem in submittedItems.OfType<JObject>())
                                {
                                    int submittedItemId = TokenInt(submittedItem, "IDItem");
                                    if (submittedItemId <= 0 || submittedItemsById.ContainsKey(submittedItemId))
                                        throw new Exception(pointPrefix + "Checklist item identity is invalid or duplicated.");
                                    submittedItemsById.Add(submittedItemId, submittedItem);
                                }

                                foreach (JObject submittedItem in submittedItems.OfType<JObject>())
                                {
                                    int submittedItemId = TokenInt(submittedItem, "IDItem");
                                    if (versionItems.Select("IDItem=" + submittedItemId.ToString(CultureInfo.InvariantCulture)).Length == 0)
                                        throw new Exception(pointPrefix + "Checklist item " + submittedItemId.ToString(CultureInfo.InvariantCulture) +
                                            " tidak termasuk Master Checklist Version yang dipilih.");
                                }

                                bool hasAnomalousItem = false;
                                foreach (DataRow templateItem in versionItems.Rows)
                                {
                                    int itemId = Convert.ToInt32(templateItem["IDItem"]);
                                    string itemLabel = Convert.ToString(templateItem["ItemLabel"]);
                                    string itemType = Convert.ToString(templateItem["ItemType"]).ToUpperInvariant();
                                    JObject answer;
                                    submittedItemsById.TryGetValue(itemId, out answer);
                                    string value = answer == null ? "" : TokenString(answer, "Value");
                                    JObject values = answer == null ? null : answer["Values"] as JObject;
                                    string remark1 = answer == null ? "" : TokenString(answer, "Remark1");
                                    string remark2 = answer == null ? "" : TokenString(answer, "Remark2");

                                    if (itemType == "REPEAT")
                                    {
                                        DataRow[] repeatConfigRows = versionRepeatConfig.Select("IDItem=" + itemId.ToString(CultureInfo.InvariantCulture));
                                        DataRow[] repeatFields = versionRepeatFields.Select("IDItem=" + itemId.ToString(CultureInfo.InvariantCulture));
                                        if (repeatConfigRows.Length != 1 || repeatFields.Length == 0)
                                            throw new Exception(pointPrefix + "REPEAT " + itemLabel + " belum memiliki konfigurasi field yang valid.");
                                        DataRow repeatConfig = repeatConfigRows[0];
                                        string repeatMode = Convert.ToString(repeatConfig["RepeatMode"]).ToUpperInvariant();
                                        JArray repeatObjects = answer == null ? null : answer["RepeatValues"] as JArray;
                                        if (repeatObjects == null) repeatObjects = new JArray();
                                        if (repeatMode == "FIELDS" && repeatObjects.Count != 1)
                                            throw new Exception(pointPrefix + "REPEAT FIELDS " + itemLabel + " harus memiliki tepat satu record.");
                                        if (repeatMode == "OBJECTS")
                                        {
                                            int objectCount = repeatObjects.Count;
                                            string countMode = Convert.ToString(repeatConfig["CountMode"]).ToUpperInvariant();
                                            int minCount = repeatConfig["MinCount"] == DBNull.Value ? 0 : Convert.ToInt32(repeatConfig["MinCount"]);
                                            int maxCount = repeatConfig["MaxCount"] == DBNull.Value ? Int32.MaxValue : Convert.ToInt32(repeatConfig["MaxCount"]);
                                            if (countMode == "FIXED" && objectCount != Convert.ToInt32(repeatConfig["FixedCount"]))
                                                throw new Exception(pointPrefix + "Jumlah " + itemLabel + " harus " + Convert.ToString(repeatConfig["FixedCount"]) + ".");
                                            if (countMode == "FLEX" && (objectCount < minCount || objectCount > maxCount))
                                                throw new Exception(pointPrefix + "Jumlah " + itemLabel + " di luar batas yang ditentukan.");
                                        }
                                        var objectIndexes = new HashSet<int>();
                                        foreach (JObject repeatObject in repeatObjects.OfType<JObject>())
                                        {
                                            int objectIndex = TokenInt(repeatObject, "ObjectIndex");
                                            if (objectIndex < 0 || !objectIndexes.Add(objectIndex))
                                                throw new Exception(pointPrefix + "ObjectIndex REPEAT " + itemLabel + " tidak valid atau duplikat.");
                                            JObject childValues = repeatObject["Values"] as JObject;
                                            foreach (JProperty submittedField in (childValues == null ? new JObject() : childValues).Properties())
                                                if (!repeatFields.Any(f => String.Equals(Convert.ToString(f["FieldKey"]), submittedField.Name, StringComparison.Ordinal)))
                                                    throw new Exception(pointPrefix + "Field REPEAT " + submittedField.Name + " tidak dikenal pada " + itemLabel + ".");
                                            foreach (DataRow field in repeatFields)
                                            {
                                                string fieldKey = Convert.ToString(field["FieldKey"]);
                                                JToken childValue = childValues == null ? null : childValues[fieldKey];
                                                string childText = childValue == null || childValue.Type == JTokenType.Null ? "" : childValue.ToString().Trim();
                                                if (Convert.ToBoolean(field["IsRequired"]) && childText.Length == 0)
                                                    throw new Exception(pointPrefix + fieldKey + " pada " + itemLabel + " wajib diisi.");
                                                if (childText.Length == 0) continue;
                                                string fieldType = Convert.ToString(field["FieldType"]).ToUpperInvariant();
                                                if (fieldType == "OPTION")
                                                {
                                                    string options = Convert.ToString(field["OptionList"]);
                                                    if (String.IsNullOrWhiteSpace(options) || !options.Split(';').Any(x => String.Equals(x.Trim(), childText, StringComparison.OrdinalIgnoreCase)))
                                                        throw new Exception(pointPrefix + "Pilihan " + fieldKey + " pada " + itemLabel + " tidak valid.");
                                                }
                                                if (fieldType == "NUMBER" || fieldType == "RANGE")
                                                {
                                                    decimal numeric;
                                                    if (!Decimal.TryParse(childText, NumberStyles.Any, CultureInfo.InvariantCulture, out numeric))
                                                        throw new Exception(pointPrefix + fieldKey + " pada " + itemLabel + " harus berupa angka.");
                                                    bool minInclusive = field["MinInclusive"] == DBNull.Value || Convert.ToBoolean(field["MinInclusive"]);
                                                    bool maxInclusive = field["MaxInclusive"] == DBNull.Value || Convert.ToBoolean(field["MaxInclusive"]);
                                                    if (field["MinValue"] != DBNull.Value &&
                                                        (numeric < Convert.ToDecimal(field["MinValue"]) || (!minInclusive && numeric == Convert.ToDecimal(field["MinValue"]))))
                                                        throw new Exception(pointPrefix + fieldKey + " pada " + itemLabel + " di bawah atau tepat pada batas minimum eksklusif.");
                                                    if (field["MaxValue"] != DBNull.Value &&
                                                        (numeric > Convert.ToDecimal(field["MaxValue"]) || (!maxInclusive && numeric == Convert.ToDecimal(field["MaxValue"]))))
                                                        throw new Exception(pointPrefix + fieldKey + " pada " + itemLabel + " di atas atau tepat pada batas maksimum eksklusif.");
                                                }
                                            }
                                        }
                                        if (repeatMode == "OBJECTS" && objectIndexes.Count > 0 &&
                                            (objectIndexes.Min() != 0 || objectIndexes.Max() != objectIndexes.Count - 1))
                                            throw new Exception(pointPrefix + "ObjectIndex REPEAT " + itemLabel + " harus berurutan mulai dari 0.");
                                    }

                                    if (Convert.ToBoolean(templateItem["IsValueRequired"]))
                                    {
                                        if (itemType == "GROUP")
                                        {
                                            DataRow[] groups = versionGroups.Select("IDItem=" + itemId.ToString(CultureInfo.InvariantCulture));
                                            if (groups.Length == 0)
                                                throw new Exception(pointPrefix + "GROUP " + itemLabel + " tidak memiliki konfigurasi kolom.");
                                            foreach (DataRow group in groups)
                                            {
                                                string[] fields = Convert.ToString(group["FieldList"]).Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)
                                                    .Select(x => x.Trim()).Where(x => x.Length > 0).ToArray();
                                                if (fields.Length > 3 || fields.Length < 2)
                                                    throw new Exception(pointPrefix + "Konfigurasi GROUP " + Convert.ToString(group["GroupName"]) + " pada " + itemLabel + " tidak valid.");
                                                int filled = 0;
                                                foreach (string field in fields)
                                                {
                                                    JToken fieldValue = values == null ? null : values[field];
                                                    if (fieldValue != null && fieldValue.Type != JTokenType.Null &&
                                                        !String.IsNullOrWhiteSpace(fieldValue.ToString())) filled++;
                                                }
                                                if (filled < 2)
                                                    throw new Exception(pointPrefix + "Minimal 2 kolom GROUP " + Convert.ToString(group["GroupName"]) +
                                                        " pada " + itemLabel + " wajib diisi.");
                                            }
                                        }
                                        else if (itemType == "REPEAT")
                                        {
                                            JArray requiredRepeatValues = answer == null ? null : answer["RepeatValues"] as JArray;
                                            bool hasRepeatValue = requiredRepeatValues != null && requiredRepeatValues
                                                .OfType<JObject>()
                                                .Any(repeatObject =>
                                                {
                                                    JObject childValues = repeatObject["Values"] as JObject;
                                                    return childValues != null && childValues.Properties().Any(property =>
                                                        property.Value != null && property.Value.Type != JTokenType.Null &&
                                                        !String.IsNullOrWhiteSpace(property.Value.ToString()));
                                                });
                                            if (!hasRepeatValue)
                                                throw new Exception(pointPrefix + "Minimal satu nilai pada REPEAT " + itemLabel + " wajib diisi.");
                                        }
                                        else if (String.IsNullOrWhiteSpace(value))
                                        {
                                            throw new Exception(pointPrefix + "Checklist " + itemLabel + " wajib diisi.");
                                        }
                                    }

                                    if (itemType == "OPTION" && !String.IsNullOrWhiteSpace(value))
                                    {
                                        string optionList = Convert.ToString(templateItem["OptionList"]);
                                        if (String.IsNullOrWhiteSpace(optionList))
                                            optionList = Convert.ToString(versionRule["StatusOption"]);
                                        if (!String.IsNullOrWhiteSpace(optionList))
                                        {
                                            bool validOption = optionList.Split(';').Any(option =>
                                                String.Equals(option.Trim(), value.Trim(), StringComparison.OrdinalIgnoreCase));
                                            if (!validOption)
                                                throw new Exception(pointPrefix + "Option '" + value + "' pada " + itemLabel + " tidak tersedia di Master Version.");
                                        }
                                    }

                                    bool itemIsAnomalous = false;
                                    if (Convert.ToBoolean(templateItem["IsToleranceRequired"]) &&
                                        !String.IsNullOrWhiteSpace(value))
                                    {
                                        decimal numericValue;
                                        if (!Decimal.TryParse(value, NumberStyles.Any, CultureInfo.InvariantCulture, out numericValue))
                                            throw new Exception(pointPrefix + "Nilai " + itemLabel + " harus berupa angka.");

                                        bool hasLower = false;
                                        bool hasUpper = false;
                                        decimal lowerLimit = 0;
                                        decimal upperLimit = 0;
                                        if (itemType == "INPUT" &&
                                            templateItem["MinTolerance"] != DBNull.Value &&
                                            templateItem["MaxTolerance"] != DBNull.Value)
                                        {
                                            lowerLimit = Convert.ToDecimal(templateItem["MinTolerance"]);
                                            upperLimit = Convert.ToDecimal(templateItem["MaxTolerance"]);
                                            hasLower = hasUpper = true;
                                        }
                                        else if (itemType == "RANGE" &&
                                            templateItem["MinValue"] != DBNull.Value &&
                                            templateItem["MaxValue"] != DBNull.Value &&
                                            templateItem["MinTolerance"] != DBNull.Value &&
                                            templateItem["MaxTolerance"] != DBNull.Value)
                                        {
                                            lowerLimit = Convert.ToDecimal(templateItem["MinValue"]) -
                                                Convert.ToDecimal(templateItem["MinTolerance"]);
                                            upperLimit = Convert.ToDecimal(templateItem["MaxValue"]) +
                                                Convert.ToDecimal(templateItem["MaxTolerance"]);
                                            hasLower = hasUpper = true;
                                        }
                                        if (hasLower && hasUpper)
                                            itemIsAnomalous = numericValue <= lowerLimit || numericValue >= upperLimit;
                                        if (answer != null) answer["IsAnomali"] = itemIsAnomalous;
                                        hasAnomalousItem = hasAnomalousItem || itemIsAnomalous;
                                    }

                                    string itemRemarkOptions = Convert.ToString(templateItem["RemarkRequiredOptions"]);
                                    bool selectedOptionRequiresRemark = itemType == "OPTION" &&
                                        ((!String.IsNullOrWhiteSpace(itemRemarkOptions) &&
                                            itemRemarkOptions.Split(';').Any(option => String.Equals(option.Trim(), value.Trim(), StringComparison.OrdinalIgnoreCase))) ||
                                         (!String.IsNullOrWhiteSpace(versionRemarkOptions) &&
                                            versionRemarkOptions.Split(';').Any(option => String.Equals(option.Trim(), value.Trim(), StringComparison.OrdinalIgnoreCase))));
                                    bool versionRemark1Enabled = Convert.ToBoolean(versionRule["IsRemark1Required"]);
                                    bool versionRemark2Enabled = Convert.ToBoolean(versionRule["IsRemark2Required"]);
                                    bool remark1Required = versionRemark1Enabled &&
                                        ((Convert.ToBoolean(templateItem["IsRemark1Mandatory"]) &&
                                          (Convert.ToBoolean(templateItem["IsUseDefaultRemark1"]) || Convert.ToBoolean(templateItem["IsRemark1Required"]))) ||
                                         selectedOptionRequiresRemark);
                                    bool remark2Required = versionRemark2Enabled &&
                                        ((Convert.ToBoolean(templateItem["IsRemark2Mandatory"]) &&
                                          (Convert.ToBoolean(templateItem["IsUseDefaultRemark2"]) || Convert.ToBoolean(templateItem["IsRemark2Required"]))) ||
                                         selectedOptionRequiresRemark);
                                    if (remark1Required && String.IsNullOrWhiteSpace(remark1))
                                        throw new Exception(pointPrefix + "Remark 1 wajib diisi pada " + itemLabel + ".");
                                    if (remark2Required && String.IsNullOrWhiteSpace(remark2))
                                        throw new Exception(pointPrefix + "Remark 2 wajib diisi pada " + itemLabel + ".");
                                }

                                if (hasAnomalousItem &&
                                    String.Equals(TokenString(versionPoint, "Status"), "DONE", StringComparison.OrdinalIgnoreCase))
                                    versionPoint["Status"] = "ABNORMAL";

                                JArray submittedPhotos = versionPoint["Photos"] as JArray ?? new JArray();
                                bool hasBefore = submittedPhotos.OfType<JObject>().Any(photo =>
                                    String.Equals(TokenString(photo, "Type"), "BEFORE", StringComparison.OrdinalIgnoreCase));
                                bool hasAfter = submittedPhotos.OfType<JObject>().Any(photo =>
                                    String.Equals(TokenString(photo, "Type"), "AFTER", StringComparison.OrdinalIgnoreCase));
                                if ((photoRequirement == "BEFORE" || photoRequirement == "BOTH") && !hasBefore)
                                    throw new Exception(pointPrefix + "Foto BEFORE wajib dilampirkan sesuai Master Checklist Version.");
                                if ((photoRequirement == "AFTER" || photoRequirement == "BOTH") && !hasAfter)
                                    throw new Exception(pointPrefix + "Foto AFTER wajib dilampirkan sesuai Master Checklist Version.");
                            }
                        }

                        if (isBatchInspection)
                        {
                            syncStage = "validate batch map coverage";
                            JArray submittedPointArray = record["Points"] as JArray ?? new JArray();
                            var submittedPointIDs = new HashSet<long>();
                            foreach (JObject submittedPoint in submittedPointArray.OfType<JObject>())
                                submittedPointIDs.Add(TokenLong(submittedPoint, "InspectionPointID"));

                            DataTable coveragePoints = br.EQueryP(@"
SELECT P.InspectionPointID, ISNULL(M.RequireAllPoints,1) AS RequireAllPoints,
       ISNULL(P.IsNormalAbnormalRequired,0) AS IsNormalAbnormalRequired, P.PointCode
FROM dbo.PIP_M_InspectionPoint P
INNER JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
LEFT JOIN dbo.PIP_M_InspectionMapGroup G ON G.MapGroupID=M.MapGroupID AND G.CompanyID=M.CompanyID AND G.LocationID=M.LocationID
WHERE M.CompanyID=@CompanyID AND M.LocationID=@LocationID
  AND M.InspectionTypeCode=@InspectionTypeCode
  AND M.InspectionTypeDetailCode=@InspectionTypeDetailCode
  AND P.IsActive=1 AND M.IsCurrentVersion=1 AND M.IsActive=1",
                                new SqlParameter[] {
                                    new SqlParameter("@CompanyID", companyId),
                                    new SqlParameter("@LocationID", locationId),
                                    new SqlParameter("@InspectionTypeCode", inspectionTypeCode),
                                    new SqlParameter("@InspectionTypeDetailCode", inspectionTypeDetailCode)
                                });
                            var validMasterPointIDs = new HashSet<long>();
                            foreach (DataRow masterPoint in coveragePoints.Rows)
                            {
                                long masterPointID = Convert.ToInt64(masterPoint["InspectionPointID"]);
                                validMasterPointIDs.Add(masterPointID);
                                if (Convert.ToBoolean(masterPoint["RequireAllPoints"]) && !submittedPointIDs.Contains(masterPointID))
                                    throw new Exception("Titik " + Convert.ToString(masterPoint["PointCode"]) +
                                        " wajib diinspeksi sesuai pengaturan master map.");

                                JObject submittedPoint = (submittedPointArray.OfType<JObject>()).FirstOrDefault(point =>
                                    TokenLong(point, "InspectionPointID") == masterPointID);
                                if (submittedPoint != null && Convert.ToBoolean(masterPoint["IsNormalAbnormalRequired"]))
                                {
                                    string condition = TokenString(submittedPoint, "PointCondition").ToUpperInvariant();
                                    string abnormalRemark = TokenString(submittedPoint, "AbnormalRemark").Trim();
                                    if (condition != "NORMAL" && condition != "ABNORMAL")
                                        throw new Exception("Titik " + Convert.ToString(masterPoint["PointCode"]) +
                                            " wajib memilih kondisi NORMAL atau ABNORMAL.");
                                    if (condition == "ABNORMAL" && String.IsNullOrWhiteSpace(abnormalRemark))
                                        throw new Exception("Titik " + Convert.ToString(masterPoint["PointCode"]) +
                                            " wajib mengisi Abnormal Remark.");
                                }
                            }
                            foreach (long submittedPointID in submittedPointIDs)
                                if (!validMasterPointIDs.Contains(submittedPointID))
                                    throw new Exception("Inspection Point " + submittedPointID +
                                        " tidak termasuk master point aktif untuk Inspection Type dan Detail ini.");
                        }

                        syncStage = "preflight existing inspection";
                        DataTable existingRows = br.EQueryP(@"
SELECT InspectionID, InspectionNo, InspectionDate, CompanyID, LocationID,
       StartDateTime, EndDateTime, ReasonVoid
FROM dbo.PIP_T_Inspection
WHERE ClientInspectionID=@ClientInspectionID",
                            new SqlParameter[] { new SqlParameter("@ClientInspectionID", Limit(clientId, 36)) });
                        if (existingRows != null && existingRows.Rows.Count > 0)
                        {
                            DataRow existing = existingRows.Rows[0];
                            existingInspectionId = Convert.ToInt64(existing["InspectionID"]);
                            oldInspectionNo = Convert.ToString(existing["InspectionNo"]);
                            if (existing["InspectionDate"] != DBNull.Value) oldInspectionDate = Convert.ToDateTime(existing["InspectionDate"]);
                            oldCompanyId = Convert.ToString(existing["CompanyID"]);
                            oldLocationId = Convert.ToString(existing["LocationID"]);
                            inspectionNo = oldInspectionNo;

                            // A voided inspection returns to DRAFT for correction, but its original
                            // work timestamps are historical data and must not be reset/overwritten.
                            if (!String.IsNullOrWhiteSpace(Convert.ToString(existing["ReasonVoid"])))
                            {
                                if (existing["StartDateTime"] == DBNull.Value)
                                    record["StartDateTime"] = null;
                                else
                                    record["StartDateTime"] = JToken.FromObject(Convert.ToDateTime(existing["StartDateTime"]));

                                if (existing["EndDateTime"] == DBNull.Value)
                                    record["EndDateTime"] = null;
                                else
                                    record["EndDateTime"] = JToken.FromObject(Convert.ToDateTime(existing["EndDateTime"]));
                            }
                            oldPhotoRows = br.EQueryP(@"
SELECT FileName, FileType, PhotoType, SeqNo
FROM dbo.PIP_T_InspectionPhoto
WHERE InspectionID=@InspectionID",
                                new SqlParameter[] { new SqlParameter("@InspectionID", existingInspectionId) });
                            if (oldPhotoRows == null)
                                throw new Exception("Could not load existing Inspection photo records before sync.");
                        }

                        if (String.IsNullOrWhiteSpace(inspectionNo))
                        {
                            // Both STANDARD and BATCH use the same canonical InspectionNo generator.
                            // The number is obtained before staging photos because the photo folder is keyed by InspectionNo.
                            syncStage = "generate InspectionNo";
                            DataTable generatedNo = br.EQueryP(@"
DECLARE @AutoNumResult TABLE (ID VARCHAR(10), SeqNo INT);
INSERT INTO @AutoNumResult EXECUTE dbo.sp_GetGenerateAutoNumID 'pip', @AutoNum, 1;
SELECT ID FROM @AutoNumResult;",
                                new SqlParameter[] { new SqlParameter("@AutoNum", "PIPINS" + companyId + locationId) });
                            if (generatedNo == null || generatedNo.Rows.Count == 0 || generatedNo.Rows[0]["ID"] == DBNull.Value ||
                                String.IsNullOrWhiteSpace(Convert.ToString(generatedNo.Rows[0]["ID"])))
                                throw new Exception("Failed to generate InspectionNo before saving transaction data.");
                            inspectionNo = Convert.ToString(generatedNo.Rows[0]["ID"]);
                        }

                        string photoFolder = GetInspectionPhotoFolder(companyId, locationId, inspectionDate, inspectionNo);
                        var createdPhotoPaths = new List<string>();
                        // dbo.Type_N_Tbl_C5: C1=PhotoType, C2=FileName, C3=FileType, C4=SeqNo; C5 unused.
                        DataTable photoTable = new DataTable();
                        for (int i = 1; i <= 5; i++)
                            photoTable.Columns.Add("C" + i, typeof(string));

                        // Keep this flag outside the try so the catch can inspect it.
                        bool sqlCallReturned = false;
                        try
                        {
                            syncStage = "stage photo files before SQL transaction";
                            if (incomingPhotos.Count > 0 && !Directory.Exists(photoFolder))
                                Directory.CreateDirectory(photoFolder);

                            foreach (var photo in incomingPhotos)
                            {
                                string fileName = "INS" + clientId.Replace("-", "").Substring(0, Math.Min(12, clientId.Replace("-", "").Length)) +
                                    "_" + photo.Item2.ToString(CultureInfo.InvariantCulture) +
                                    "_" + Guid.NewGuid().ToString("N").Substring(0, 8);
                                string fullPath = Path.Combine(photoFolder, fileName + "." + photo.Item3);
                                createdPhotoPaths.Add(fullPath);
                                File.WriteAllBytes(fullPath, photo.Item4);
                                photoTable.Rows.Add(photo.Item1, fileName, photo.Item3,
                                    photo.Item2.ToString(CultureInfo.InvariantCulture), "");
                            }

                            foreach (var photo in incomingBatchPhotos)
                            {
                                string safePoint = new string((photo.Item1 ?? "").Where(Char.IsLetterOrDigit).ToArray());
                                string fileName = "INS" + clientId.Replace("-", "").Substring(0, Math.Min(12, clientId.Replace("-", "").Length)) +
                                    "_" + safePoint.Substring(0, Math.Min(8, safePoint.Length)) +
                                    "_" + photo.Item3.ToString(CultureInfo.InvariantCulture) +
                                    "_" + Guid.NewGuid().ToString("N").Substring(0, 8);
                                string fullPath = Path.Combine(photoFolder, fileName + "." + photo.Item4);
                                createdPhotoPaths.Add(fullPath);
                                File.WriteAllBytes(fullPath, photo.Item5);
                                photoTable.Rows.Add(photo.Item1, photo.Item2, fileName, photo.Item4,
                                    photo.Item3.ToString(CultureInfo.InvariantCulture));
                            }

                            syncStage = "save header, point checklist, and photo metadata atomically";
                            SqlParameter[] commonParameters = new SqlParameter[]
                            {
                                new SqlParameter("@p_ClientInspectionID", Limit(clientId, 36)),
                                new SqlParameter("@p_CompanyID", companyId),
                                new SqlParameter("@p_LocationID", locationId),
                                new SqlParameter("@p_SectionID", sectionId),
                                new SqlParameter("@p_InspectionTypeCode", inspectionTypeCode),
                                new SqlParameter("@p_InspectionTypeDetailCode", inspectionTypeDetailCode),
                                new SqlParameter("@p_ScheduledTime", Limit(TokenString(record, "ScheduledTime"), 5)),
                                new SqlParameter("@p_IDTemplate", TokenInt(record, "IDTemplate")),
                                new SqlParameter("@p_IDVersion", TokenInt(record, "IDVersion")),
                                new SqlParameter("@p_TemplateNo", Limit(TokenString(record, "TemplateNo"), 50)),
                                new SqlParameter("@p_TemplateVersion", Limit(TokenString(record, "TemplateVersion"), 10)),
                                new SqlParameter("@p_InspectionDate", inspectionDate),
                                new SqlParameter("@p_StartDateTime", ParseNullableDate(TokenString(record, "StartDateTime"))),
                                new SqlParameter("@p_EndDateTime", ParseNullableDate(TokenString(record, "EndDateTime"))),
                                new SqlParameter("@p_Status", status),
                                new SqlParameter("@p_Summary", Limit(TokenString(record, "Summary"), 500)),
                                new SqlParameter("@p_FollowUp", Limit(String.IsNullOrWhiteSpace(TokenString(record, "FollowUp")) ? "No Follow Up" : TokenString(record, "FollowUp"), 30)),
                                new SqlParameter("@p_FollowUpSection", Limit(TokenString(record, "FollowUpSection"), 10)),
                                new SqlParameter("@p_FollowUpRemark", Limit(TokenString(record, "FollowUpRemark"), 300)),
                                new SqlParameter("@p_UpdateUser", Limit(userId, 50))
                            };
                            DataTable saved;
                            if (isLightningInspection)
                            {
                                string appRoot = (HttpContext.Current.Request.ApplicationPath ?? "").TrimEnd('/');
                                string siteOrigin = HttpContext.Current.Request.Url.GetLeftPart(UriPartial.Authority);
                                string lightningApprovalUrl = siteOrigin + appRoot + "/Secure/inspection.aspx?type=approval";
                                saved = br.EQueryP("spUTL_PIP_T_Inspection_Lightning_Sync",
                                    commonParameters.Concat(new SqlParameter[] {
                                        new SqlParameter("@p_ApprovalUrl", lightningApprovalUrl),
                                        new SqlParameter("@p_InspectionNo", Limit(inspectionNo, 10)),
                                        new SqlParameter("@p_Points", batchPoints),
                                        new SqlParameter("@p_Schedules", lightningSchedules),
                                        new SqlParameter("@p_Photos", photoTable),
                                        new SqlParameter("@p_Items", batchItems),
                                        new SqlParameter("@p_ItemValues", batchItemValues)
                                    }).ToArray(), true, true);
                            }
                            else if (isBatchInspection)
                            {
                                saved = br.EQueryP("spUTL_PIP_T_Inspection_Batch_Sync",
                                    commonParameters.Concat(new SqlParameter[] {
                                        new SqlParameter("@p_InspectionNo", Limit(inspectionNo, 10)),
                                        new SqlParameter("@p_Points", batchPoints),
                                        new SqlParameter("@p_Photos", photoTable),
                                        new SqlParameter("@p_Items", batchItems),
                                        new SqlParameter("@p_ItemValues", batchItemValues)
                                    }).ToArray(), true, true);
                            }
                            else
                            {
                                saved = br.EQueryP("spUTL_PIP_T_Inspection_Sync",
                                    commonParameters.Concat(new SqlParameter[] {
                                        new SqlParameter("@p_InspectionNo", Limit(inspectionNo, 10)),
                                        new SqlParameter("@p_Photos", photoTable),
                                        new SqlParameter("@p_Items", items),
                                        new SqlParameter("@p_ItemValues", itemValues)
                                    }).ToArray(), true, true);
                            }
                            sqlCallReturned = true;

                            if (saved == null || saved.Rows.Count == 0 || !saved.Columns.Contains("InspectionID") || saved.Rows[0]["InspectionID"] == DBNull.Value)
                                throw new Exception("Inspection sync procedure returned no saved header.");
                            long inspectionId = Convert.ToInt64(saved.Rows[0]["InspectionID"]);
                            if (inspectionId <= 0)
                                throw new Exception("Inspection header was not saved.");

                            /* SQL metadata has committed successfully. Old photo files can now be cleaned up safely. */
                            if (oldPhotoRows != null && !String.IsNullOrWhiteSpace(oldInspectionNo))
                            {
                                foreach (DataRow oldPhoto in oldPhotoRows.Rows)
                                {
                                    string oldName = Convert.ToString(oldPhoto["FileName"]);
                                    string oldType = Convert.ToString(oldPhoto["FileType"]);
                                    if (String.IsNullOrWhiteSpace(oldName) || String.IsNullOrWhiteSpace(oldType)) continue;
                                    try
                                    {
                                        string oldPath = GetInspectionPhotoPath(oldCompanyId, oldLocationId, oldInspectionDate, oldInspectionNo, oldName, oldType);
                                        if (!createdPhotoPaths.Contains(oldPath) && File.Exists(oldPath)) File.Delete(oldPath);
                                    }
                                    catch (Exception cleanupError)
                                    {
                                        System.Diagnostics.Trace.TraceWarning("Could not remove superseded Inspection photo file {0}: {1}", oldName, cleanupError.Message);
                                    }
                                }
                            }

                            outcomes.Add(new
                            {
                                ClientInspectionID = clientId,
                                success = true,
                                InspectionID = inspectionId,
                                InspectionNo = saved.Rows[0]["InspectionNo"] == DBNull.Value ? inspectionNo : Convert.ToString(saved.Rows[0]["InspectionNo"]),
                                message = ""
                            });
                        }
                        catch
                        {
                            /* If the SQL call threw, its transaction rolled back and staged files are safe to remove.
                               If it returned, preserve files even if the response shape is unexpected: SQL may already have committed metadata. */
                            if (!sqlCallReturned)
                            {
                                foreach (string path in createdPhotoPaths)
                                {
                                    try { if (File.Exists(path)) File.Delete(path); } catch { }
                                }
                            }
                            throw;
                        }
                    }
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Trace.TraceError("SyncInspections failed at stage '{0}' for ClientInspectionID={1}, userId={2}: {3}",
                        syncStage, clientId, userId, ex.ToString());
                    string userMessage;
                    if (ex.Message.IndexOf("An inspection already exists for this date", StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        userMessage = "Jadwal inspeksi ini sudah memiliki data di server. Silakan periksa data inspeksi yang sudah tersimpan.";
                    }
                    else if (syncStage == "validate batch checklist version rules" ||
                             syncStage == "validate batch map coverage")
                    {
                        // These are business-rule failures with Point Code context, not technical diagnostics.
                        userMessage = ex.Message;
                    }
                    else
                    {
                        // Keep technical details in the server log; do not expose them to technicians.
                        userMessage = "Sinkronisasi belum berhasil. Silakan coba lagi. Jika masih terjadi, hubungi supervisor.";
                    }

                    outcomes.Add(new
                    {
                        ClientInspectionID = clientId,
                        success = false,
                        InspectionID = 0,
                        InspectionNo = "",
                        message = userMessage
                    });
                }
            }

            bool allSuccess = outcomes.All(x => Convert.ToBoolean(x.GetType().GetProperty("success").GetValue(x, null)));
            object emailDispatch;
            try { emailDispatch = DispatchInspectionEmailOutbox(20); }
            catch (Exception emailError) { emailDispatch = new { configured = false, error = emailError.Message }; }
            return new { success = allSuccess, results = outcomes, emailDispatch = emailDispatch };
        }

        private static string GetInspectionPhotoFolder(string companyId, string locationId, DateTime inspectionDate, string inspectionNo)
        {
            if (String.IsNullOrWhiteSpace(companyId) || String.IsNullOrWhiteSpace(locationId) || String.IsNullOrWhiteSpace(inspectionNo) ||
                !String.Equals(Path.GetFileName(companyId), companyId, StringComparison.Ordinal) ||
                !String.Equals(Path.GetFileName(locationId), locationId, StringComparison.Ordinal) ||
                !String.Equals(Path.GetFileName(inspectionNo), inspectionNo, StringComparison.Ordinal))
                throw new Exception("Invalid Inspection photo folder identity.");

            HttpContext context = HttpContext.Current;
            if (context == null || context.Request == null)
                throw new InvalidOperationException("HTTP request context is unavailable while preparing Inspection photo storage.");
            string appPath = context.Request.ApplicationPath ?? "";
            string appId = PB.AppID ?? "";
            string root = appPath.Replace("/", "");
            if (!String.IsNullOrEmpty(appId)) root = root.Replace(appId, "PIP");
            string webFolder = PB.Path_WebFolder1;
            if (String.IsNullOrWhiteSpace(webFolder))
                throw new InvalidOperationException("PB.Path_WebFolder1 is empty; Inspection photo storage root is not configured.");
            return Path.Combine(webFolder, root, "PIP_T_Inspection",
                companyId + "_" + locationId,
                inspectionDate.ToString("yyyyMM", CultureInfo.InvariantCulture),
                inspectionNo);
        }

        private static string GetInspectionPhotoPath(string companyId, string locationId, DateTime inspectionDate, string inspectionNo, string fileName, string fileType)
        {
            if (String.IsNullOrWhiteSpace(fileName) || String.IsNullOrWhiteSpace(fileType) ||
                !String.Equals(Path.GetFileName(fileName), fileName, StringComparison.Ordinal) ||
                !String.Equals(Path.GetFileName(fileType), fileType, StringComparison.Ordinal))
                throw new Exception("Invalid Inspection photo filename.");
            return Path.Combine(GetInspectionPhotoFolder(companyId, locationId, inspectionDate, inspectionNo), fileName + "." + fileType);
        }

        private static string GetInspectionPhotoDataUrl(string companyId, string locationId, DateTime inspectionDate, string inspectionNo, string fileName, string fileType)
        {
            string path = GetInspectionPhotoPath(companyId, locationId, inspectionDate, inspectionNo, fileName, fileType);
            if (!File.Exists(path)) return "";
            byte[] bytes = File.ReadAllBytes(path);
            string mime = "image/jpeg";
            switch ((fileType ?? "").ToLowerInvariant())
            {
                case "png": mime = "image/png"; break;
                case "webp": mime = "image/webp"; break;
                case "gif": mime = "image/gif"; break;
            }
            return "data:" + mime + ";base64," + Convert.ToBase64String(bytes);
        }

        [WebMethod]
        public static object CheckInspectionDuplicate(string employeeId, string companyId, string locationId,
            string sectionId, string inspectionTypeCode, string inspectionTypeDetailCode,
            string scheduledTime, int templateId, string inspectionDate)
        {
            employeeId = GFC.RequireMenuEmployee("20021");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (String.IsNullOrWhiteSpace(employeeId) || String.IsNullOrWhiteSpace(companyId) || String.IsNullOrWhiteSpace(locationId))
                throw new HttpException(400, "Employee, company, and location are required.");

            using (var br = new WAL.BR.CF())
            {
                DataTable auth = br.EQueryP(@"
SELECT @SectionList Section, CASE WHEN EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20021') THEN 1 ELSE 0 END IsWO
FROM dbo.SysWebUser SU

WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1
  AND (
      EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
              WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                AND C.CompanyID=@CompanyID AND C.LocationID=@LocationID)
      OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                 WHERE L.CompanyID=@CompanyID AND L.LocationID=@LocationID)
  )",
                    new SqlParameter[] {
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId)
                    });

                if (auth.Rows.Count == 0 || !Convert.ToBoolean(auth.Rows[0]["IsWO"]))
                    throw new HttpException(403, "This account is not authorized for Inspection entry.");

                var sections = auth.Rows[0]["Section"].ToString()
                    .Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)
                    .Select(s => s.Trim()).Where(s => s.Length > 0).ToList();
                if (!sections.Contains(sectionId, StringComparer.OrdinalIgnoreCase))
                    throw new HttpException(403, "This inspection section is not assigned to the current employee.");

                DataTable templateAccess = br.EQueryP(@"
SELECT 1
FROM dbo.PIP_M_CheckListWOPM T
WHERE T.IDTemplate=@IDTemplate
  AND T.SectionID=@SectionID
  AND ISNULL(T.TemplateType,'W')='I'
  AND (ISNULL(T.CompanyScope,'S')='A'
       OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + @CompanyID + @LocationID + ';%'))
  AND (ISNULL(T.EmployeeList,'')=''
       OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + @EmployeeID + ';%'))",
                    new SqlParameter[] {
new SqlParameter("@IDTemplate", templateId),
                        new SqlParameter("@SectionID", sectionId),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId),
                        new SqlParameter("@EmployeeID", employeeId)
                    });
                if (templateAccess.Rows.Count == 0)
                    throw new HttpException(403, "This employee is not assigned to the selected Inspection template and company/location.");

                DataTable duplicate = br.EQueryP(@"
SELECT TOP 1 InspectionNo, OwnerEmployeeID, Status
FROM dbo.PIP_T_Inspection
WHERE CompanyID=@CompanyID AND LocationID=@LocationID AND SectionID=@SectionID
  AND InspectionTypeCode=@InspectionTypeCode
  AND InspectionTypeDetailCode=@InspectionTypeDetailCode
  AND ISNULL(ScheduledTime,'')=ISNULL(@ScheduledTime,'')
  AND IDTemplate=@IDTemplate
  AND InspectionDate >= CONVERT(DATETIME, CONVERT(VARCHAR(10), @InspectionDate, 120), 120)
  AND InspectionDate < DATEADD(DAY, 1, CONVERT(DATETIME, CONVERT(VARCHAR(10), @InspectionDate, 120), 120))
ORDER BY InspectionID DESC",
                    new SqlParameter[] {
new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId),
                        new SqlParameter("@SectionID", sectionId),
                        new SqlParameter("@InspectionTypeCode", inspectionTypeCode),
                        new SqlParameter("@InspectionTypeDetailCode", inspectionTypeDetailCode),
                        new SqlParameter("@ScheduledTime", scheduledTime ?? ""),
                        new SqlParameter("@IDTemplate", templateId),
                        new SqlParameter("@InspectionDate", ParseDate(inspectionDate, DateTime.Today))
                    });

                return new {
                    success = true,
                    duplicate = duplicate.Rows.Count > 0,
                    InspectionNo = duplicate.Rows.Count > 0 ? Convert.ToString(duplicate.Rows[0]["InspectionNo"]) : "",
                    OwnerEmployeeID = duplicate.Rows.Count > 0 ? Convert.ToString(duplicate.Rows[0]["OwnerEmployeeID"]) : "",
                    Status = duplicate.Rows.Count > 0 ? Convert.ToString(duplicate.Rows[0]["Status"]) : ""
                };
            }
        }

        [WebMethod]
        public static object GetTodayInspectionSlots(string employeeId, string companyId, string locationId)
        {
            employeeId = GFC.RequireMenuEmployee("20021");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (String.IsNullOrWhiteSpace(employeeId) || String.IsNullOrWhiteSpace(companyId) || String.IsNullOrWhiteSpace(locationId))
                throw new HttpException(400, "Employee, company, and location are required.");

            using (var br = new WAL.BR.CF())
            {
                DataTable auth = br.EQueryP(@"
SELECT @SectionList Section, CASE WHEN EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20021') THEN 1 ELSE 0 END IsWO
FROM dbo.SysWebUser SU

WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1
  AND (EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
               WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                 AND C.CompanyID=@CompanyID AND C.LocationID=@LocationID)
       OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                  WHERE L.CompanyID=@CompanyID AND L.LocationID=@LocationID))",
                    new SqlParameter[] {
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId)
                    });
                if (auth.Rows.Count == 0 || !Convert.ToBoolean(auth.Rows[0]["IsWO"]))
                    throw new HttpException(403, "This account is not authorized to view Inspection schedules.");

                var sections = auth.Rows[0]["Section"].ToString()
                    .Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)
                    .Select(s => s.Trim()).Where(s => s.Length > 0).ToList();
                if (sections.Count == 0)
                    return new { success = true, data = new List<Dictionary<string, object>>() };

                DataTable rows = br.EQueryP(@"
SELECT I.InspectionID, I.ClientInspectionID, I.InspectionNo,
       I.CompanyID, I.LocationID, I.SectionID, I.InspectionTypeCode,
       I.InspectionTypeName, I.InspectionTypeDetailCode, I.InspectionTypeDetailName,
       I.ScheduledTime, I.IDTemplate, I.IDVersion, I.TemplateNo, I.TemplateName,
       I.TemplateVersion, I.InspectionDate, I.StartDateTime, I.EndDateTime,
       I.OwnerEmployeeID, ISNULL(E.Name, I.OwnerEmployeeID) TechnicianName,
       I.Status, I.IsApprove, I.ReasonVoid
FROM dbo.PIP_T_Inspection I
LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=I.OwnerEmployeeID
WHERE I.CompanyID=@CompanyID AND I.LocationID=@LocationID
  AND ISNULL(I.IsActive,1)=1
  AND I.InspectionDate >= CONVERT(DATETIME, CONVERT(VARCHAR(10), GETDATE(), 120), 120)
  AND I.InspectionDate < DATEADD(DAY, 1, CONVERT(DATETIME, CONVERT(VARCHAR(10), GETDATE(), 120), 120))
  AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S WHERE S.val=I.SectionID)
  AND EXISTS (
      SELECT 1
      FROM dbo.PIP_M_CheckListWOPM T
      WHERE T.IDTemplate=I.IDTemplate
        AND T.SectionID=I.SectionID
        AND ISNULL(T.TemplateType,'W')='I'
        AND (ISNULL(T.CompanyScope,'S')='A'
             OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
        AND (ISNULL(T.EmployeeList,'')=''
             OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
  )
ORDER BY I.InspectionDate, I.ScheduledTime, I.InspectionID",
                    new SqlParameter[] {
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId),
                        new SqlParameter("@SectionList", String.Join(";", sections))
                    });
                var result = new List<Dictionary<string, object>>();
                foreach (DataRow row in rows.Rows)
                {
                    var item = new Dictionary<string, object>();
                    foreach (DataColumn col in rows.Columns)
                        item[col.ColumnName] = row[col] == DBNull.Value ? null : row[col];
                    result.Add(item);
                }
                return new { success = true, data = result };
            }
        }

        private static void ValidateInspectionDeleteAccess(WAL.BR.CF br, JObject record,
            string employeeId, string companyId, string locationId)
        {
            string sectionId = TokenString(record, "SectionID");
            DataTable auth = br.EQueryP(@"
SELECT @SectionList Section, CASE WHEN EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20021') THEN 1 ELSE 0 END IsWO
FROM dbo.SysWebUser SU

WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1
  AND (EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
               WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                 AND C.CompanyID=@CompanyID AND C.LocationID=@LocationID)
       OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                  WHERE L.CompanyID=@CompanyID AND L.LocationID=@LocationID))",
                new SqlParameter[] {
                    new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)),
                    new SqlParameter("@CompanyID", companyId),
                    new SqlParameter("@LocationID", locationId)
                });
            if (auth.Rows.Count == 0 || !Convert.ToBoolean(auth.Rows[0]["IsWO"]))
                throw new HttpException(403, "This account is not authorized to delete Inspection transactions.");
            var sections = auth.Rows[0]["Section"].ToString()
                .Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)
                .Select(s => s.Trim()).Where(s => s.Length > 0);
            if (!sections.Contains(sectionId, StringComparer.OrdinalIgnoreCase))
                throw new HttpException(403, "This inspection section is not assigned to the current employee.");

            DataTable templateAccess = br.EQueryP(@"
SELECT 1
FROM dbo.PIP_M_CheckListWOPM T
WHERE T.IDTemplate=@IDTemplate
  AND T.SectionID=@SectionID
  AND ISNULL(T.TemplateType,'W')='I'
  AND (ISNULL(T.CompanyScope,'S')='A'
       OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + @CompanyID + @LocationID + ';%'))
  AND (ISNULL(T.EmployeeList,'')=''
       OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + @EmployeeID + ';%'))",
                new SqlParameter[] {
new SqlParameter("@IDTemplate", TokenInt(record, "IDTemplate")),
                    new SqlParameter("@SectionID", sectionId),
                    new SqlParameter("@CompanyID", companyId),
                    new SqlParameter("@LocationID", locationId),
                    new SqlParameter("@EmployeeID", employeeId)
                });
            if (templateAccess.Rows.Count == 0)
                throw new HttpException(403, "This employee is not assigned to the Inspection template and company/location.");
        }

        [WebMethod]
        public static object ArchiveInspectionDelete(string employeeId, string companyId, string locationId,
            string clientInspectionId, string reasonCancel, string originalTransactionJson)
        {
            employeeId = GFC.RequireMenuEmployee("20021");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (String.IsNullOrWhiteSpace(employeeId) || String.IsNullOrWhiteSpace(clientInspectionId) ||
                String.IsNullOrWhiteSpace(originalTransactionJson))
                throw new HttpException(400, "Employee, client transaction ID, and transaction snapshot are required.");
            JObject record;
            try { record = JObject.Parse(originalTransactionJson); }
            catch { throw new HttpException(400, "The original inspection snapshot is invalid."); }
            if (!String.Equals(TokenString(record, "LocalInspectionID"), clientInspectionId, StringComparison.OrdinalIgnoreCase) ||
                !String.Equals(TokenString(record, "OwnerEmployeeID"), employeeId, StringComparison.OrdinalIgnoreCase) ||
                !String.Equals(TokenString(record, "CompanyID"), companyId, StringComparison.OrdinalIgnoreCase) ||
                !String.Equals(TokenString(record, "LocationID"), locationId, StringComparison.OrdinalIgnoreCase))
                throw new HttpException(403, "The transaction snapshot does not match the logged-in employee and company/location.");
            if (!String.Equals(TokenString(record, "SyncStatus"), "DELETE_PENDING", StringComparison.OrdinalIgnoreCase) ||
                !String.Equals(TokenString(record, "DeleteOriginalSyncStatus"), "CONFLICT", StringComparison.OrdinalIgnoreCase))
                throw new HttpException(400, "Only a queued local conflict can be archived for deletion.");

            reasonCancel = Limit(String.IsNullOrWhiteSpace(reasonCancel)
                ? (TokenString(record, "DeleteReasonCancel") == "" ? TokenString(record, "ConflictReason") : TokenString(record, "DeleteReasonCancel"))
                : reasonCancel, 1000);
            if (String.IsNullOrWhiteSpace(reasonCancel)) reasonCancel = "Deleted by technician due to sync conflict.";
            using (var br = new WAL.BR.CF())
            {
                ValidateInspectionDeleteAccess(br, record, employeeId, companyId, locationId);
                br.EQueryP(@"
SET XACT_ABORT ON;
BEGIN TRANSACTION;
IF NOT EXISTS (SELECT 1 FROM dbo.PIP_T_Inspection_Delete WITH (UPDLOCK, HOLDLOCK) WHERE ClientInspectionID=@ClientInspectionID)
BEGIN
    DECLARE @NextDeleteArchiveID BIGINT;
    SELECT @NextDeleteArchiveID=ISNULL(MAX(DeleteArchiveID),0)+1 FROM dbo.PIP_T_Inspection_Delete WITH (UPDLOCK, HOLDLOCK);
    INSERT dbo.PIP_T_Inspection_Delete
    (DeleteArchiveID, ClientInspectionID, CompanyID, LocationID, SectionID,
     InspectionTypeCode, InspectionTypeDetailCode, IDTemplate, InspectionDate,
     OriginalStatus, OriginalSyncStatus, ReasonCancel, DeletedBy, OriginalTransactionJson)
    VALUES
    (@NextDeleteArchiveID, @ClientInspectionID, @CompanyID, @LocationID, @SectionID,
     @InspectionTypeCode, @InspectionTypeDetailCode, @IDTemplate, @InspectionDate,
     @OriginalStatus, @OriginalSyncStatus, @ReasonCancel, @DeletedBy, @OriginalTransactionJson);
END;
COMMIT TRANSACTION;",
                    new SqlParameter[] {
new SqlParameter("@ClientInspectionID", Limit(clientInspectionId, 36)),
                        new SqlParameter("@CompanyID", Limit(companyId, 10)),
                        new SqlParameter("@LocationID", Limit(locationId, 3)),
                        new SqlParameter("@SectionID", Limit(TokenString(record, "SectionID"), 10)),
                        new SqlParameter("@InspectionTypeCode", Limit(TokenString(record, "InspectionTypeCode"), 2)),
                        new SqlParameter("@InspectionTypeDetailCode", Limit(TokenString(record, "InspectionTypeDetailCode"), 20)),
                        new SqlParameter("@IDTemplate", TokenInt(record, "IDTemplate")),
                        new SqlParameter("@InspectionDate", ParseDate(TokenString(record, "InspectionDate"), DateTime.Today)),
                        new SqlParameter("@OriginalStatus", DbString(Limit(TokenString(record, "Status"), 10))),
                        new SqlParameter("@OriginalSyncStatus", DbString(Limit(TokenString(record, "DeleteOriginalSyncStatus"), 20))),
                        new SqlParameter("@ReasonCancel", DbString(reasonCancel)),
                        new SqlParameter("@DeletedBy", Limit(employeeId, 50)),
                        new SqlParameter("@OriginalTransactionJson", SqlDbType.NVarChar, -1) { Value = originalTransactionJson }
                    });
                DataTable confirmed = br.EQueryP(
                    "SELECT COUNT(1) AS SavedCount FROM dbo.PIP_T_Inspection_Delete WHERE ClientInspectionID=@ClientInspectionID AND DeletedBy=@DeletedBy",
                    new SqlParameter[] {
new SqlParameter("@ClientInspectionID", Limit(clientInspectionId, 36)),
                        new SqlParameter("@DeletedBy", Limit(employeeId, 50))
                    });
                return new { success = confirmed.Rows.Count > 0 && Convert.ToInt32(confirmed.Rows[0]["SavedCount"]) > 0 };
            }
        }

        [WebMethod]
        public static object DeactivateVoidedInspection(string employeeId, string companyId, string locationId,
            string clientInspectionId, string reasonCancel, string originalTransactionJson)
        {
            employeeId = GFC.RequireMenuEmployee("20021");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (String.IsNullOrWhiteSpace(employeeId) || String.IsNullOrWhiteSpace(clientInspectionId) ||
                String.IsNullOrWhiteSpace(originalTransactionJson))
                throw new HttpException(400, "Employee, client transaction ID, and transaction snapshot are required.");
            JObject record;
            try { record = JObject.Parse(originalTransactionJson); }
            catch { throw new HttpException(400, "The original inspection snapshot is invalid."); }
            if (!String.Equals(TokenString(record, "LocalInspectionID"), clientInspectionId, StringComparison.OrdinalIgnoreCase) ||
                !String.Equals(TokenString(record, "OwnerEmployeeID"), employeeId, StringComparison.OrdinalIgnoreCase) ||
                !String.Equals(TokenString(record, "CompanyID"), companyId, StringComparison.OrdinalIgnoreCase) ||
                !String.Equals(TokenString(record, "LocationID"), locationId, StringComparison.OrdinalIgnoreCase))
                throw new HttpException(403, "The transaction snapshot does not match the logged-in employee and company/location.");
            if (!String.Equals(TokenString(record, "SyncStatus"), "DELETE_PENDING", StringComparison.OrdinalIgnoreCase) ||
                !String.Equals(TokenString(record, "DeleteOriginalSyncStatus"), "VOIDED", StringComparison.OrdinalIgnoreCase) ||
                String.IsNullOrWhiteSpace(TokenString(record, "ReasonVoid")) || TokenInt(record, "ServerInspectionID") <= 0)
                throw new HttpException(400, "Only a queued server-backed SPV-voided inspection can be deactivated.");
            reasonCancel = Limit(String.IsNullOrWhiteSpace(reasonCancel) ? TokenString(record, "DeleteReasonCancel") : reasonCancel, 500);
            if (String.IsNullOrWhiteSpace(reasonCancel)) reasonCancel = "Deleted by technician after SPV void.";

            using (var br = new WAL.BR.CF())
            {
                ValidateInspectionDeleteAccess(br, record, employeeId, companyId, locationId);
                br.EQueryP(@"
SET XACT_ABORT ON;
BEGIN TRANSACTION;
IF EXISTS
(
    SELECT 1 FROM dbo.PIP_T_Inspection WITH (UPDLOCK, HOLDLOCK)
    WHERE InspectionID=@InspectionID AND ClientInspectionID=@ClientInspectionID
      AND CompanyID=@CompanyID AND LocationID=@LocationID AND SectionID=@SectionID
      AND OwnerEmployeeID=@EmployeeID AND ISNULL(IsActive,1)=0
)
BEGIN
    UPDATE dbo.PIP_T_Inspection SET ReasonCancel=CASE WHEN ISNULL(ReasonCancel,'')='' THEN @ReasonCancel ELSE ReasonCancel END
    WHERE InspectionID=@InspectionID AND ClientInspectionID=@ClientInspectionID
      AND CompanyID=@CompanyID AND LocationID=@LocationID AND OwnerEmployeeID=@EmployeeID;
END
ELSE
BEGIN
    UPDATE dbo.PIP_T_Inspection
    SET IsActive=0, ReasonCancel=@ReasonCancel, UpdateUser=@EmployeeID, UpdateDate=GETDATE(), SyncDate=GETDATE()
    WHERE InspectionID=@InspectionID AND ClientInspectionID=@ClientInspectionID
      AND CompanyID=@CompanyID AND LocationID=@LocationID AND SectionID=@SectionID
      AND OwnerEmployeeID=@EmployeeID AND ISNULL(IsActive,1)=1
      AND ISNULL(IsApprove,0)=0 AND ISNULL(ReasonVoid,'')<>''
      AND ISNULL(ApprovedBy,'')<>'' AND ApprovedDate>CONVERT(DATETIME,'19000101',112);
    IF @@ROWCOUNT=0
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR('The server inspection is not eligible for technician deletion.',16,1);
        RETURN;
    END;
END;
COMMIT TRANSACTION;",
                    new SqlParameter[] {
new SqlParameter("@InspectionID", TokenInt(record, "ServerInspectionID")),
                        new SqlParameter("@ClientInspectionID", Limit(clientInspectionId, 36)),
                        new SqlParameter("@CompanyID", Limit(companyId, 10)),
                        new SqlParameter("@LocationID", Limit(locationId, 3)),
                        new SqlParameter("@SectionID", Limit(TokenString(record, "SectionID"), 10)),
                        new SqlParameter("@EmployeeID", Limit(employeeId, 50)),
                        new SqlParameter("@ReasonCancel", DbString(reasonCancel))
                    });
                DataTable confirmed = br.EQueryP(@"
SELECT COUNT(1) AS SavedCount FROM dbo.PIP_T_Inspection
WHERE InspectionID=@InspectionID AND ClientInspectionID=@ClientInspectionID
  AND CompanyID=@CompanyID AND LocationID=@LocationID AND OwnerEmployeeID=@EmployeeID AND IsActive=0",
                    new SqlParameter[] {
new SqlParameter("@InspectionID", TokenInt(record, "ServerInspectionID")),
                        new SqlParameter("@ClientInspectionID", Limit(clientInspectionId, 36)),
                        new SqlParameter("@CompanyID", Limit(companyId, 10)),
                        new SqlParameter("@LocationID", Limit(locationId, 3)),
                        new SqlParameter("@EmployeeID", Limit(employeeId, 50))
                    });
                return new { success = confirmed.Rows.Count > 0 && Convert.ToInt32(confirmed.Rows[0]["SavedCount"]) > 0 };
            }
        }

        [WebMethod]
        public static object GetBatchInspectionMap(string inspectionTypeCode, string inspectionTypeDetailCode,
            string employeeId, string companyId, string locationId)
        {
            employeeId = GFC.RequireAnyMenuEmployee("20021", "20022");
            if (String.IsNullOrWhiteSpace(employeeId))
                throw new HttpException(403, "Inspection identity is required.");

            companyId = (companyId ?? "").Trim();
            locationId = (locationId ?? "").Trim();
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);

            string sectionList = GFC.GetEmployeeSection(employeeId);
            string typeCode = Limit(inspectionTypeCode, 2).ToUpperInvariant();
            string detailCode = Limit(inspectionTypeDetailCode, 20).ToUpperInvariant();
            if (typeCode == "" || detailCode == "")
                throw new HttpException(400, "Inspection Type and Detail are required.");

            using (var br = new WAL.BR.CF())
            {
                DataTable type = br.EQueryP(@"
SELECT IT.InspectionTypeCode, IT.InspectionTypeName, IT.SectionID
FROM dbo.PIP_M_InspectionType IT
WHERE IT.InspectionTypeCode=@TypeCode AND IT.IsActive=1
  AND ISNULL(IT.InspectionMode,'STANDARD') IN ('BATCH','LIGHTNING')
  AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S WHERE S.val=IT.SectionID)",
                    new SqlParameter[] {
                        new SqlParameter("@TypeCode", typeCode),
                        new SqlParameter("@SectionList", sectionList)
                    });
                if (type == null || type.Rows.Count == 0)
                    throw new HttpException(403, "Inspection Type is not configured for BATCH/LIGHTNING map inspection or not assigned to this inspector.");

                DataTable detail = br.EQueryP(@"
SELECT InspectionTypeDetailCode, InspectionTypeDetailName, ScheduleTime
FROM dbo.PIP_M_InspectionTypeDetail
WHERE InspectionTypeCode=@TypeCode AND InspectionTypeDetailCode=@DetailCode
  AND CompanyID=@CompanyID AND LocationID=@LocationID AND IsActive=1",
                    new SqlParameter[] {
                        new SqlParameter("@TypeCode", typeCode),
                        new SqlParameter("@DetailCode", detailCode),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId)
                    });
                if (detail == null || detail.Rows.Count == 0)
                    throw new HttpException(404, "Inspection Type Detail is not active for this company/location.");

                DataTable points = br.EQueryP(@"
SELECT P.InspectionPointID, P.PointCode, P.PointName, P.PointObjectType,
       P.PointDescription, P.ObjectReferenceType, P.ObjectReferenceID,
       P.ObjectReferenceCode, M.MapID AS MapID, P.MapX, P.MapY,
       ISNULL(P.ShapeType,'CIRCLE') AS ShapeType,P.SvgPathData,P.ShapeAttributes,P.StrokeWidth,P.DisplayOrder,
       M.MapCode, M.MapName, M.Description, M.ImagePath AS MapUrl, M.MapVersion,
       M.MapGroupID, ISNULL(G.GroupCode,'') AS GroupCode, ISNULL(G.GroupName,'') AS GroupName,
       ISNULL(G.Description,'') AS GroupDescription,
       ISNULL(M.RequireAllPoints,1) AS RequireAllPoints,
       ISNULL(P.IsNormalAbnormalRequired,0) AS IsNormalAbnormalRequired
FROM dbo.PIP_M_InspectionMap M
LEFT JOIN dbo.PIP_M_InspectionPoint P ON P.MapID=M.MapID AND P.IsActive=1
LEFT JOIN dbo.PIP_M_InspectionMapGroup G ON G.MapGroupID=M.MapGroupID AND G.CompanyID=M.CompanyID AND G.LocationID=M.LocationID
WHERE M.CompanyID=@CompanyID AND M.LocationID=@LocationID
  AND M.InspectionTypeCode=@TypeCode
  AND M.InspectionTypeDetailCode=@DetailCode
  AND M.IsCurrentVersion=1 AND M.IsActive=1
ORDER BY ISNULL(M.MapCode,''), P.DisplayOrder, P.PointCode",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId),
                        new SqlParameter("@TypeCode", typeCode),
                        new SqlParameter("@DetailCode", detailCode)
                    });

                var mapRows = new List<Dictionary<string, object>>();
                var mapIds = new HashSet<long>();
                var pointRows = new List<Dictionary<string, object>>();
                foreach (DataRow row in points.Rows)
                {
                    long mapId = row["MapID"] == DBNull.Value ? 0 : Convert.ToInt64(row["MapID"]);
                    if (mapId > 0 && mapIds.Add(mapId))
                    {
                        mapRows.Add(new Dictionary<string, object> {
                            { "MapID", mapId },
                            { "MapCode", GF.GetString(row["MapCode"]) },
                            { "MapName", GF.GetString(row["MapName"]) },
                            { "Description", GF.GetString(row["Description"]) },
                            { "MapGroupID", row["MapGroupID"] == DBNull.Value ? 0 : Convert.ToInt64(row["MapGroupID"]) },
                            { "GroupCode", GF.GetString(row["GroupCode"]) },
                            { "GroupName", GF.GetString(row["GroupName"]) },
                            { "GroupDescription", GF.GetString(row["GroupDescription"]) },
                            { "MapUrl", ResolveInspectionMapUrl(GF.GetString(row["MapUrl"]), companyId, locationId) },
                            { "MapVersion", row["MapVersion"] == DBNull.Value ? 0 : Convert.ToInt32(row["MapVersion"]) },
                            { "RequireAllPoints", Convert.ToBoolean(row["RequireAllPoints"]) }
                        });
                    }

                    if (row["InspectionPointID"] == DBNull.Value) continue;

                    pointRows.Add(new Dictionary<string, object> {
                        { "InspectionPointID", Convert.ToInt64(row["InspectionPointID"]) },
                        { "PointCode", GF.GetString(row["PointCode"]) },
                        { "PointName", GF.GetString(row["PointName"]) },
                        { "PointObjectType", GF.GetString(row["PointObjectType"]) },
                        { "PointDescription", GF.GetString(row["PointDescription"]) },
                        { "ObjectReferenceType", GF.GetString(row["ObjectReferenceType"]) },
                        { "ObjectReferenceID", GF.GetString(row["ObjectReferenceID"]) },
                        { "ObjectReferenceCode", GF.GetString(row["ObjectReferenceCode"]) },
                        { "MapID", mapId },
                        { "MapX", row["MapX"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(row["MapX"]) },
                        { "MapY", row["MapY"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(row["MapY"]) },
                        { "ShapeType", GF.GetString(row["ShapeType"]) },
                        { "SvgPathData", GF.GetString(row["SvgPathData"]) },
                        { "ShapeAttributes", GF.GetString(row["ShapeAttributes"]) },
                        { "StrokeWidth", row["StrokeWidth"] == DBNull.Value ? 1.5m : Convert.ToDecimal(row["StrokeWidth"]) },
                        { "DisplayOrder", Convert.ToInt32(row["DisplayOrder"]) },
                        { "MapCode", GF.GetString(row["MapCode"]) },
                        { "RequireAllPoints", Convert.ToBoolean(row["RequireAllPoints"]) },
                        { "IsNormalAbnormalRequired", Convert.ToBoolean(row["IsNormalAbnormalRequired"]) }
                    });
                }

                var groupRows = new List<Dictionary<string, object>>();
                var groupIds = new HashSet<long>();
                foreach (var map in mapRows)
                {
                    long groupId = Convert.ToInt64(map["MapGroupID"]);
                    if (groupIds.Add(groupId))
                    {
                        groupRows.Add(new Dictionary<string, object> {
                            { "MapGroupID", groupId },
                            { "GroupCode", Convert.ToString(map["GroupCode"]) },
                            { "GroupName", Convert.ToString(map["GroupName"]) },
                            { "Description", Convert.ToString(map["GroupDescription"]) },
                            { "MapCount", mapRows.Count(m => Convert.ToInt64(m["MapGroupID"]) == groupId) }
                        });
                    }
                }

                DataRow t = type.Rows[0];
                DataRow d = detail.Rows[0];
                return new {
                    success = true,
                    inspectionType = new {
                        InspectionTypeCode = GF.GetString(t["InspectionTypeCode"]),
                        InspectionTypeName = GF.GetString(t["InspectionTypeName"]),
                        SectionID = GF.GetString(t["SectionID"])
                    },
                    inspectionDetail = new {
                        InspectionTypeDetailCode = GF.GetString(d["InspectionTypeDetailCode"]),
                        InspectionTypeDetailName = GF.GetString(d["InspectionTypeDetailName"]),
                        ScheduleTime = GF.GetString(d["ScheduleTime"])
                    },
                    groups = groupRows,
                    maps = mapRows,
                    points = pointRows
                };
            }
        }

        [WebMethod]
        public static object GetInspectionEntryList(string employeeId, string companyId, string locationId, string fromDate, string thruDate)
        {
            employeeId = GFC.RequireMenuEmployee("20021");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (String.IsNullOrWhiteSpace(employeeId) || String.IsNullOrWhiteSpace(companyId) || String.IsNullOrWhiteSpace(locationId))
                throw new HttpException(400, "Employee, company, and location are required.");

            DateTime submittedFrom = ParseDate(fromDate, DateTime.Today).Date;
            DateTime submittedThru = ParseDate(thruDate, DateTime.Today).Date;
            if (submittedFrom > submittedThru)
                throw new HttpException(400, "From date cannot be later than Thru date.");

            using (var br = new WAL.BR.CF())
            {
                DataTable auth = br.EQueryP(@"
SELECT @SectionList Section, CASE WHEN EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20021') THEN 1 ELSE 0 END IsWO,
       ISNULL(E.Name, SU.EmployeeID) TechnicianName
FROM dbo.SysWebUser SU

LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=SU.EmployeeID
WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1
  AND (
      EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
              WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                AND C.CompanyID=@CompanyID AND C.LocationID=@LocationID)
      OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                 WHERE L.CompanyID=@CompanyID AND L.LocationID=@LocationID)
  )",
                    new SqlParameter[] {
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId)
                    });

                if (auth.Rows.Count == 0 || !Convert.ToBoolean(auth.Rows[0]["IsWO"]))
                    throw new HttpException(403, "This account is not authorized to view Inspection entry records.");

                var sections = auth.Rows[0]["Section"].ToString()
                    .Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)
                    .Select(s => s.Trim()).Where(s => s.Length > 0).ToList();
                string technicianName = Convert.ToString(auth.Rows[0]["TechnicianName"]);
                if (sections.Count == 0)
                    return new { success = true, technicianName = technicianName, data = new List<Dictionary<string, object>>() };

                DataTable rows = br.EQueryP(@"
SELECT I.InspectionID, I.ClientInspectionID, I.InspectionNo,
       I.CompanyID, I.LocationID, I.SectionID, I.InspectionTypeCode,
       I.InspectionTypeName, I.InspectionTypeDetailCode, I.InspectionTypeDetailName,
       I.ScheduledTime, I.IDTemplate, I.IDVersion, I.TemplateNo, I.TemplateName,
       I.TemplateVersion, I.InspectionDate, I.StartDateTime, I.EndDateTime,
       I.OwnerEmployeeID, ISNULL(E.Name, I.OwnerEmployeeID) TechnicianName, I.Status,
       I.IsApprove, I.ApprovedDate, I.SyncDate, I.ReasonVoid,
       ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') AS InspectionMode
FROM dbo.PIP_T_Inspection I
LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=I.OwnerEmployeeID
WHERE I.CompanyID=@CompanyID AND I.LocationID=@LocationID
  AND I.OwnerEmployeeID=@EmployeeID
  AND ISNULL(I.IsActive,1)=1
  AND EXISTS (
      SELECT 1
      FROM dbo.PIP_M_CheckListWOPM T
      WHERE T.IDTemplate=I.IDTemplate
        AND T.SectionID=I.SectionID
        AND ISNULL(T.TemplateType,'W')='I'
        AND (ISNULL(T.CompanyScope,'S')='A'
             OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
        AND (ISNULL(T.EmployeeList,'')=''
             OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
  )
  AND I.SyncDate >= @FromDate AND I.SyncDate < DATEADD(DAY, 1, @ThruDate)
  -- A supervisor-voided transaction is surfaced in Draft for technician handling,
  -- not again in Submitted just because its SyncDate falls in the selected range.
  AND NOT (
      I.Status='DRAFT'
      AND ISNULL(I.IsApprove,0)=0
      AND ISNULL(I.ApprovedBy,'')<>''
      AND ISNULL(I.ApprovedDate,CONVERT(DATETIME,'19000101',112))>CONVERT(DATETIME,'19000101',112)
      AND ISNULL(I.ReasonVoid,'')<>''
  )
  AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S WHERE S.val=I.SectionID)
ORDER BY I.ApprovedDate DESC, I.EndDateTime DESC, I.StartDateTime DESC, I.InspectionID DESC",
                    new SqlParameter[] {
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId),
                        new SqlParameter("@FromDate", submittedFrom),
                        new SqlParameter("@ThruDate", submittedThru),
                        new SqlParameter("@SectionList", String.Join(";", sections))
                    });

                var result = new List<Dictionary<string, object>>();
                foreach (DataRow row in rows.Rows)
                {
                    var item = new Dictionary<string, object>();
                    foreach (DataColumn col in rows.Columns)
                        item[col.ColumnName] = row[col] == DBNull.Value ? null : row[col];
                    result.Add(item);
                }
                return new { success = true, technicianName = technicianName, data = result };
            }
        }

        [WebMethod]
        public static object GetInspectionApprovalQueue(string employeeId, string companyId, string locationId,
            string approvalTab, string dateFrom, string dateThru, string inspectionTypeCode,
            string inspectionTypeDetailCode, string templateId)
        {
            employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (String.IsNullOrWhiteSpace(employeeId))
                throw new HttpException(403, "Supervisor identity is required.");

            approvalTab = String.Equals(approvalTab, "APPROVED", StringComparison.OrdinalIgnoreCase)
                ? "APPROVED"
                : (String.Equals(approvalTab, "VOID", StringComparison.OrdinalIgnoreCase) ? "VOID" : "OUTSTANDING");
            DateTime fromDate;
            DateTime thruDate;
            if (!DateTime.TryParseExact(dateFrom, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out fromDate))
                fromDate = DateTime.Today;
            if (!DateTime.TryParseExact(dateThru, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out thruDate))
                thruDate = fromDate;
            if (fromDate > thruDate)
                throw new HttpException(400, "Approved From tidak boleh melewati Approved Thru.");

            string fromWhere = @"
FROM dbo.PIP_T_Inspection I
LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=I.OwnerEmployeeID
WHERE I.CompanyID=@CompanyID AND I.LocationID=@LocationID
  AND ISNULL(I.IsActive,1)=1
  AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')<>'LIGHTNING'
  AND EXISTS (
      SELECT 1
      FROM dbo.PIP_M_CheckListWOPM T
      WHERE T.IDTemplate=I.IDTemplate
        AND T.SectionID=I.SectionID
        AND ISNULL(T.TemplateType,'W')='I'
        AND (ISNULL(T.CompanyScope,'S')='A'
             OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
        AND (ISNULL(T.EmployeeList,'')=''
             OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
  )
  AND (
       (I.Status='DONE'
        AND ISNULL(I.IsApprove,0)=0
        AND ISNULL(I.ApprovedBy,'')=''
        AND ISNULL(I.ApprovedDate,CONVERT(DATETIME,'19000101',112))<=CONVERT(DATETIME,'19000101',112)
        AND ISNULL(I.ApprovalRemark,'')=''
        AND ISNULL(I.ReasonVoid,'')='')
       OR
       (I.Status='DONE'
        AND ISNULL(I.IsApprove,0)=1
        AND ISNULL(I.ApprovedBy,'')<>''
        AND ISNULL(I.ApprovedDate,CONVERT(DATETIME,'19000101',112))>CONVERT(DATETIME,'19000101',112)
        AND I.ApprovedDate>=@DateFrom AND I.ApprovedDate<DATEADD(DAY,1,@DateThru))
       OR
       (I.Status='DRAFT'
        AND ISNULL(I.IsApprove,0)=0
        AND ISNULL(I.ApprovedBy,'')<>''
        AND ISNULL(I.ApprovedDate,CONVERT(DATETIME,'19000101',112))>CONVERT(DATETIME,'19000101',112)
        AND ISNULL(I.ReasonVoid,'')<>'')
  )
  AND EXISTS (
      SELECT 1
      FROM dbo.SysWebUser SU
      WHERE SU.EmployeeID=@EmployeeID
        AND SU.IsActive=1
        AND (
             EXISTS (
                 SELECT 1
                 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM
                 WHERE AM.MenuID='20022'
             )
             OR (
                 EXISTS (
                     SELECT 1
                     FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM
                     WHERE AM.MenuID='20021'
                 )
                 AND I.OwnerEmployeeID=SU.EmployeeID
             )
        )
        AND EXISTS (
            SELECT 1
            FROM dbo.SplitStringConvertToTable(@SectionList,';') S
            WHERE S.val=I.SectionID
        )
        AND (
            EXISTS (
                SELECT 1
                FROM dbo.SysWebUserCompanyLocation C
                WHERE C.UserID=SU.EmployeeID
                  AND C.AppID='pip'
                  AND C.CompanyID=I.CompanyID
                  AND C.LocationID=I.LocationID
            )
            OR EXISTS (
                SELECT 1
                FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                WHERE L.CompanyID=I.CompanyID
                  AND L.LocationID=I.LocationID
            )
        )
  )";

            SqlParameter[] filterOptionParameters = new SqlParameter[] {
                new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)),
                new SqlParameter("@CompanyID", companyId),
                new SqlParameter("@LocationID", locationId),
                new SqlParameter("@DateFrom", fromDate),
                new SqlParameter("@DateThru", thruDate)
            };

            using (var br = new WAL.BR.CF())
            {
                DataTable filterRows = br.EQueryP(@"
SELECT DISTINCT I.InspectionTypeCode, I.InspectionTypeName,
       I.InspectionTypeDetailCode, I.InspectionTypeDetailName,
       I.IDTemplate, I.TemplateNo" + fromWhere + @"
ORDER BY I.InspectionTypeName, I.InspectionTypeDetailName, I.TemplateNo",
                    filterOptionParameters);

                var filters = new List<Dictionary<string, object>>();
                foreach (DataRow row in filterRows.Rows)
                {
                    var item = new Dictionary<string, object>();
                    foreach (DataColumn col in filterRows.Columns)
                        item[col.ColumnName] = row[col] == DBNull.Value ? null : row[col];
                    filters.Add(item);
                }

                DataTable rows = br.EQueryP(@"
SELECT I.InspectionID, I.ClientInspectionID, I.InspectionNo, I.CompanyID, I.LocationID, I.SectionID,
       I.InspectionTypeCode, I.InspectionTypeName, I.InspectionTypeDetailCode, I.InspectionTypeDetailName,
       I.IDTemplate, I.IDVersion, I.ScheduledTime, I.TemplateNo, I.TemplateName, I.TemplateVersion,
       I.InspectionDate, CONVERT(VARCHAR(23), I.StartDateTime, 126) AS StartDateTime, CONVERT(VARCHAR(23), I.EndDateTime, 126) AS EndDateTime, I.Summary, I.OwnerEmployeeID,
       ISNULL(E.Name, I.OwnerEmployeeID) AS TechnicianName, I.Status, I.IsApprove,
       I.ApprovedBy, I.ApprovedDate, I.ApprovalRemark, I.ReasonVoid,
       I.FollowUp, I.FollowUpSection, I.FollowUpRemark, I.FollowUpWONo,
       ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') AS InspectionMode" + fromWhere + @"
  AND (@InspectionTypeCode='' OR I.InspectionTypeCode=@InspectionTypeCode)
  AND (@InspectionTypeDetailCode='' OR I.InspectionTypeDetailCode=@InspectionTypeDetailCode)
  AND (@TemplateId='' OR CONVERT(VARCHAR(20),I.IDTemplate)=@TemplateId)
ORDER BY I.InspectionDate DESC, I.InspectionID DESC",
                    new SqlParameter[] {
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId),
                        new SqlParameter("@DateFrom", fromDate),
                        new SqlParameter("@DateThru", thruDate),
                        new SqlParameter("@InspectionTypeCode", inspectionTypeCode ?? ""),
                        new SqlParameter("@InspectionTypeDetailCode", inspectionTypeDetailCode ?? ""),
                        new SqlParameter("@TemplateId", templateId ?? "")
                    });

                var result = new List<Dictionary<string, object>>();
                foreach (DataRow row in rows.Rows)
                {
                    var item = new Dictionary<string, object>();
                    foreach (DataColumn col in rows.Columns)
                        item[col.ColumnName] = row[col] == DBNull.Value ? null : row[col];
                    result.Add(item);
                }
                return new { success = true, data = result, filters = filters };
            }
        }

        [WebMethod]
        public static object GetInspectionDashboardSummary(string employeeId, string companyId, string locationId)
        {
            employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (String.IsNullOrWhiteSpace(employeeId))
                throw new HttpException(403, "Supervisor identity is required.");
            using (var br = new WAL.BR.CF())
            {
                DataTable rows = br.EQueryP(@"
SELECT
    SUM(CASE WHEN I.Status='DONE' AND I.IsApprove=0 AND ISNULL(I.ApprovedBy,'')='' AND ISNULL(I.ApprovedDate,CONVERT(DATETIME,'19000101',112))<=CONVERT(DATETIME,'19000101',112) AND ISNULL(I.ApprovalRemark,'')='' AND ISNULL(I.ReasonVoid,'')='' THEN 1 ELSE 0 END) PendingApproval,
    SUM(CASE WHEN ISNULL(I.IsApprove,0)=1 AND I.ApprovedDate>=CONVERT(DATETIME, CONVERT(VARCHAR(10), GETDATE(), 120), 120) THEN 1 ELSE 0 END) ApprovedToday,
    SUM(CASE WHEN I.IsApprove=0 AND ISNULL(I.ApprovedBy,'')<>'' AND ISNULL(I.ApprovedDate,CONVERT(DATETIME,'19000101',112))>CONVERT(DATETIME,'19000101',112) THEN 1 ELSE 0 END) VoidCount
FROM dbo.PIP_T_Inspection I
WHERE I.CompanyID=@CompanyID AND I.LocationID=@LocationID
  AND ISNULL(I.IsActive,1)=1
  AND EXISTS (
      SELECT 1
      FROM dbo.PIP_M_CheckListWOPM T
      WHERE T.IDTemplate=I.IDTemplate
        AND T.SectionID=I.SectionID
        AND ISNULL(T.TemplateType,'W')='I'
        AND (ISNULL(T.CompanyScope,'S')='A'
             OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
        AND (ISNULL(T.EmployeeList,'')=''
             OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
  )
  AND EXISTS (
      SELECT 1 FROM dbo.SysWebUser SU

WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1 AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20022')
        AND (
          EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S WHERE S.val=I.SectionID)
          OR EXISTS (
              SELECT 1 FROM dbo.PIP_T_InspectionWorkflow W
              JOIN dbo.PIP_M_InspectionEmailSetup ES
                ON ES.CompanyID=W.CompanyID AND ES.LocationID=W.LocationID AND ES.IsActive=1
              WHERE W.EntityType='LIGHTNING' AND W.EntityID=I.InspectionID
                AND (ES.ChiefEngEmployeeID=@EmployeeID OR ES.ChiefSecEmployeeID=@EmployeeID)
          )
        )
        AND (
          EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                  WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                    AND C.CompanyID=I.CompanyID AND C.LocationID=I.LocationID)
          OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                     WHERE L.CompanyID=I.CompanyID AND L.LocationID=I.LocationID)
        )
  )",
                    new SqlParameter[] {
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId)
                    });
                if (rows.Rows.Count == 0)
                    return new { success = true, pendingApproval = 0, approvedToday = 0, voidCount = 0 };
                DataRow row = rows.Rows[0];
                return new {
                    success = true,
                    pendingApproval = row["PendingApproval"] == DBNull.Value ? 0 : Convert.ToInt32(row["PendingApproval"]),
                    approvedToday = row["ApprovedToday"] == DBNull.Value ? 0 : Convert.ToInt32(row["ApprovedToday"]),
                    voidCount = row["VoidCount"] == DBNull.Value ? 0 : Convert.ToInt32(row["VoidCount"])
                };
            }
        }

        [WebMethod]
        public static object GetReturnedInspectionPhotos(string clientInspectionId, string employeeId, string companyId, string locationId)
        {
            employeeId = GFC.RequireMenuEmployee("20021");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (String.IsNullOrWhiteSpace(clientInspectionId) || String.IsNullOrWhiteSpace(employeeId))
                throw new HttpException(400, "Inspection and technician identity are required.");
            using (var br = new WAL.BR.CF())
            {
                DataTable rows = br.EQueryP(@"
SELECT P.PhotoType, P.FileName, P.FileType, P.SeqNo, TP.ClientPointID,
       I.InspectionID, I.InspectionNo, I.CompanyID, I.LocationID, I.InspectionDate
FROM dbo.PIP_T_InspectionPhoto P
JOIN dbo.PIP_T_Inspection I ON I.InspectionID=P.InspectionID
LEFT JOIN dbo.PIP_T_InspectionPoint TP ON TP.InspectionPointTransactionID=P.InspectionPointTransactionID
WHERE I.ClientInspectionID=@ClientInspectionID
  AND I.OwnerEmployeeID=@EmployeeID AND I.CompanyID=@CompanyID AND I.LocationID=@LocationID
  AND I.Status='DRAFT' AND I.IsApprove=0
  AND EXISTS (
      SELECT 1 FROM dbo.SysWebUser SU

WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1 AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20021')
        AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S WHERE S.val=I.SectionID)
        AND (
            EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                    WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                      AND C.CompanyID=I.CompanyID AND C.LocationID=I.LocationID)
            OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                       WHERE L.CompanyID=I.CompanyID AND L.LocationID=I.LocationID)
        )
  )
ORDER BY P.SeqNo",
                    new SqlParameter[] {
                        new SqlParameter("@ClientInspectionID", clientInspectionId),
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId)
                    });
                var photos = new List<Dictionary<string, object>>();
                foreach (DataRow row in rows.Rows)
                {
                    string fileName = row["FileName"] == DBNull.Value ? "" : row["FileName"].ToString();
                    string fileType = row["FileType"] == DBNull.Value ? "" : row["FileType"].ToString();
                    DateTime photoDate = Convert.ToDateTime(row["InspectionDate"]);
                    string dataUrl = GetInspectionPhotoDataUrl(row["CompanyID"].ToString(), row["LocationID"].ToString(), photoDate, row["InspectionNo"].ToString(), fileName, fileType);
                    if (String.IsNullOrEmpty(dataUrl)) continue;
                    photos.Add(new Dictionary<string, object> {
                        { "Type", row["PhotoType"] == DBNull.Value ? "" : row["PhotoType"].ToString() },
                        { "FileName", fileName + "." + fileType },
                        { "SeqNo", row["SeqNo"] == DBNull.Value ? 0 : Convert.ToInt32(row["SeqNo"]) },
                        { "PointID", GF.GetString(row["ClientPointID"]) },
                        { "Data", dataUrl }
                    });
                }
                return new { success = true, data = photos };
            }
        }

        [WebMethod]
        public static object GetLightningInspectionApprovalQueue(string employeeId, string companyId, string locationId,
            string approvalTab, string dateFrom, string dateThru, string inspectionTypeCode,
            string inspectionTypeDetailCode, string templateId)
        {
            employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (String.IsNullOrWhiteSpace(employeeId))
                throw new HttpException(403, "Chief Engineering / Chief Security identity is required.");

            approvalTab = String.Equals(approvalTab, "APPROVED", StringComparison.OrdinalIgnoreCase) ? "APPROVED" :
                (String.Equals(approvalTab, "VOID", StringComparison.OrdinalIgnoreCase) ? "VOID" : "OUTSTANDING");
            DateTime fromDate, thruDate;
            if (!DateTime.TryParseExact(dateFrom, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out fromDate))
                fromDate = DateTime.Today;
            if (!DateTime.TryParseExact(dateThru, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out thruDate))
                thruDate = fromDate;
            if (fromDate > thruDate) throw new HttpException(400, "Approved From tidak boleh melewati Approved Thru.");

            using (var br = new WAL.BR.CF())
            {
                SqlParameter[] parameters = new SqlParameter[] {
                    new SqlParameter("@EmployeeID", employeeId),
                    new SqlParameter("@CompanyID", companyId),
                    new SqlParameter("@LocationID", locationId),
                    new SqlParameter("@ApprovalTab", approvalTab),
                    new SqlParameter("@DateFrom", fromDate),
                    new SqlParameter("@DateThru", thruDate),
                    new SqlParameter("@InspectionTypeCode", inspectionTypeCode ?? ""),
                    new SqlParameter("@InspectionTypeDetailCode", inspectionTypeDetailCode ?? ""),
                    new SqlParameter("@TemplateId", templateId ?? "")
                };
                const string scope = @"
FROM dbo.PIP_T_InspectionWorkflow W
JOIN dbo.PIP_T_Inspection I ON I.InspectionID=W.EntityID
JOIN dbo.PIP_M_InspectionEmailSetup ES
  ON ES.CompanyID=W.CompanyID AND ES.LocationID=W.LocationID AND ES.IsActive=1
LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=I.OwnerEmployeeID
WHERE W.EntityType='LIGHTNING'
  AND I.CompanyID=@CompanyID AND I.LocationID=@LocationID
  AND ISNULL(I.IsActive,1)=1
  AND (
      (@ApprovalTab='OUTSTANDING' AND (
          (W.CurrentStageCode='CHIEF_ENG' AND ES.ChiefEngEmployeeID=@EmployeeID)
          OR (W.CurrentStageCode='CHIEF_SEC' AND ES.ChiefSecEmployeeID=@EmployeeID)
      ) AND W.WorkflowStatus IN ('CHECKED','ACKNOWLEDGE 1'))
      OR (@ApprovalTab='APPROVED' AND W.WorkflowStatus='ACKNOWLEDGE'
          AND (ES.ChiefEngEmployeeID=@EmployeeID OR ES.ChiefSecEmployeeID=@EmployeeID))
      OR (@ApprovalTab='VOID' AND W.WorkflowStatus='VOID'
          AND (ES.ChiefEngEmployeeID=@EmployeeID OR ES.ChiefSecEmployeeID=@EmployeeID))
  )
  AND (@ApprovalTab='OUTSTANDING' OR
       (I.InspectionDate>=@DateFrom AND I.InspectionDate<DATEADD(DAY,1,@DateThru)))
  AND (@InspectionTypeCode='' OR I.InspectionTypeCode=@InspectionTypeCode)
  AND (@InspectionTypeDetailCode='' OR I.InspectionTypeDetailCode=@InspectionTypeDetailCode)
  AND (@TemplateId='' OR CONVERT(VARCHAR(20),I.IDTemplate)=@TemplateId)
  AND EXISTS (
      SELECT 1 FROM dbo.PIP_M_CheckListWOPM T
      WHERE T.IDTemplate=I.IDTemplate AND T.SectionID=I.SectionID
        AND ISNULL(T.TemplateType,'W')='I'
        AND (ISNULL(T.CompanyScope,'S')='A'
             OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
        AND (ISNULL(T.EmployeeList,'')='' OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
  )";
                DataTable filtersTable = br.EQueryP(@"
SELECT DISTINCT I.InspectionTypeCode,I.InspectionTypeName,I.InspectionTypeDetailCode,
       I.InspectionTypeDetailName,I.IDTemplate,I.TemplateNo " + scope + @"
ORDER BY I.InspectionTypeName,I.InspectionTypeDetailName,I.TemplateNo", parameters);
                var filters = new List<Dictionary<string, object>>();
                foreach (DataRow row in filtersTable.Rows)
                {
                    var item = new Dictionary<string, object>();
                    foreach (DataColumn col in filtersTable.Columns) item[col.ColumnName] = row[col] == DBNull.Value ? null : row[col];
                    filters.Add(item);
                }
                DataTable rows = br.EQueryP(@"
SELECT I.InspectionID,I.ClientInspectionID,I.InspectionNo,I.CompanyID,I.LocationID,I.SectionID,
       I.InspectionTypeCode,I.InspectionTypeName,I.InspectionTypeDetailCode,I.InspectionTypeDetailName,
       I.IDTemplate,I.IDVersion,I.ScheduledTime,I.TemplateNo,I.TemplateName,I.TemplateVersion,
       I.InspectionDate,CONVERT(VARCHAR(23),I.StartDateTime,126) StartDateTime,
       CONVERT(VARCHAR(23),I.EndDateTime,126) EndDateTime,I.Summary,I.OwnerEmployeeID,
       ISNULL(E.Name,I.OwnerEmployeeID) TechnicianName,I.Status,I.IsApprove,I.ApprovedBy,I.ApprovedDate,
       I.ApprovalRemark,I.ReasonVoid,I.FollowUp,I.FollowUpSection,I.FollowUpRemark,I.FollowUpWONo,
       'LIGHTNING' InspectionMode,W.WorkflowStatus,W.CurrentStageCode
" + scope + @"
ORDER BY I.InspectionDate DESC,I.InspectionID DESC", parameters);
                var data = new List<Dictionary<string, object>>();
                foreach (DataRow row in rows.Rows)
                {
                    var item = new Dictionary<string, object>();
                    foreach (DataColumn col in rows.Columns) item[col.ColumnName] = row[col] == DBNull.Value ? null : row[col];
                    data.Add(item);
                }
                return new { data = data, filters = filters };
            }
        }

        [WebMethod]
        public static object ProcessLightningInspectionApproval(long inspectionId, string action, string employeeId,
            string companyId, string locationId, string remark)
        {
            employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (String.IsNullOrWhiteSpace(employeeId))
                throw new HttpException(403, "Approver identity is required.");
            if (!String.Equals(action, "APPROVE", StringComparison.OrdinalIgnoreCase) &&
                !String.Equals(action, "VOID", StringComparison.OrdinalIgnoreCase))
                throw new HttpException(400, "Invalid Lightning approval action.");
            if (String.Equals(action, "VOID", StringComparison.OrdinalIgnoreCase) && String.IsNullOrWhiteSpace(remark))
                throw new HttpException(400, "Reason for void is required.");

            string appRoot = (HttpContext.Current.Request.ApplicationPath ?? "").TrimEnd('/');
            string origin = HttpContext.Current.Request.Url.GetLeftPart(UriPartial.Authority);
            string approvalUrl = origin + appRoot + "/Secure/inspection.aspx?type=approval";
            string correctionUrl = origin + appRoot + "/Secure/inspection.aspx?type=entry&inspectionId=" +
                inspectionId.ToString(CultureInfo.InvariantCulture);

            using (var br = new WAL.BR.CF())
            {
                DataTable saved = br.EQueryP("spUTL_PIP_T_Inspection_Lightning_Approval", new SqlParameter[] {
                    new SqlParameter("@p_InspectionID", inspectionId),
                    new SqlParameter("@p_ActorEmployeeID", employeeId),
                    new SqlParameter("@p_Action", action.ToUpperInvariant()),
                    new SqlParameter("@p_Remark", String.IsNullOrWhiteSpace(remark) ? "" : remark),
                    new SqlParameter("@p_ApprovalUrl", approvalUrl),
                    new SqlParameter("@p_CorrectionUrl", correctionUrl)
                }, true, true);
                object emailDispatch;
                try { emailDispatch = DispatchInspectionEmailOutbox(20); }
                catch (Exception emailError) { emailDispatch = new { configured = false, error = emailError.Message }; }
                return new {
                    success = true,
                    action = action.ToUpperInvariant(),
                    inspectionId = inspectionId,
                    workflowStatus = saved != null && saved.Rows.Count > 0 ? Convert.ToString(saved.Rows[0]["WorkflowStatus"]) : "",
                    currentStageCode = saved != null && saved.Rows.Count > 0 ? Convert.ToString(saved.Rows[0]["CurrentStageCode"]) : "",
                    emailDispatch = emailDispatch
                };
            }
        }

        [WebMethod]
        public static object GetInspectionApprovalDetail(long inspectionId, string employeeId)
        {
            employeeId = GFC.RequireMenuEmployee("20022");
            if (String.IsNullOrWhiteSpace(employeeId))
                throw new HttpException(403, "Supervisor identity is required.");

            using (var br = new WAL.BR.CF())
            {
                DataTable header = br.EQueryP(@"
SELECT I.InspectionID, I.InspectionNo, I.CompanyID, I.LocationID, I.SectionID, I.InspectionTypeName,
       I.InspectionTypeDetailName, ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') AS InspectionMode,
       W.WorkflowStatus, W.CurrentStageCode,
       I.InspectionTypeCode, I.InspectionTypeDetailCode, I.ScheduledTime, I.IDTemplate, I.IDVersion, I.TemplateNo, I.TemplateVersion,
       I.InspectionDate, CONVERT(VARCHAR(23), I.StartDateTime, 126) AS StartDateTime, CONVERT(VARCHAR(23), I.EndDateTime, 126) AS EndDateTime, I.Summary, I.OwnerEmployeeID,
       I.IsApprove, I.ApprovedBy, I.ApprovedDate, I.ApprovalRemark, I.ReasonVoid,
       I.FollowUp, I.FollowUpSection, I.FollowUpRemark, I.FollowUpWONo
FROM dbo.PIP_T_Inspection I
LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
LEFT JOIN dbo.PIP_T_InspectionWorkflow W
  ON W.EntityType='LIGHTNING' AND W.EntityID=I.InspectionID
WHERE I.InspectionID=@InspectionID
  AND EXISTS (
      SELECT 1
      FROM dbo.PIP_M_CheckListWOPM T
      WHERE T.IDTemplate=I.IDTemplate
        AND T.SectionID=I.SectionID
        AND ISNULL(T.TemplateType,'W')='I'
        AND (ISNULL(T.CompanyScope,'S')='A'
             OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
        AND (ISNULL(T.EmployeeList,'')=''
             OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
  )
  AND (
       (I.Status='DONE' AND (
            (ISNULL(I.IsApprove,0)=0 AND ISNULL(I.ApprovedBy,'')='' AND ISNULL(I.ApprovedDate,CONVERT(DATETIME,'19000101',112))<=CONVERT(DATETIME,'19000101',112) AND ISNULL(I.ApprovalRemark,'')='' AND ISNULL(I.ReasonVoid,'')='')
            OR (ISNULL(I.IsApprove,0)=1 AND ISNULL(I.ApprovedBy,'')<>'' AND ISNULL(I.ApprovedDate,CONVERT(DATETIME,'19000101',112))>CONVERT(DATETIME,'19000101',112))
       ))
       OR (I.Status='DRAFT' AND ISNULL(I.IsApprove,0)=0 AND ISNULL(I.ReasonVoid,'')<>'' AND (
            (ISNULL(I.ApprovedBy,'')<>'' AND ISNULL(I.ApprovedDate,CONVERT(DATETIME,'19000101',112))>CONVERT(DATETIME,'19000101',112))
            OR (ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')='LIGHTNING' AND EXISTS (
                SELECT 1 FROM dbo.PIP_T_InspectionWorkflow W
                WHERE W.EntityType='LIGHTNING' AND W.EntityID=I.InspectionID AND W.WorkflowStatus='VOID'
            ))
       ))
  )
  AND EXISTS (
      SELECT 1 FROM dbo.SysWebUser SU

WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1 AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20022')
        AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S WHERE S.val=I.SectionID)
        AND (
          EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                  WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                    AND C.CompanyID=I.CompanyID AND C.LocationID=I.LocationID)
          OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                     WHERE L.CompanyID=I.CompanyID AND L.LocationID=I.LocationID)
        )
  )",
                    new SqlParameter[] {
                        new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)),
                        new SqlParameter("@InspectionID", inspectionId),
                        new SqlParameter("@EmployeeID", employeeId)
                    });
                if (header.Rows.Count == 0)
                    throw new HttpException(404, "Inspection not found or not authorized for approval.");

                DataTable results = br.EQueryP(@"
SELECT R.IDItem, R.ItemLabel, R.ItemType, R.Value, R.Remark1, R.Remark2, R.IsAnomali,
       V.ObjectIndex, V.FieldName, V.Value AS FieldValue, R.DisplayOrder
FROM dbo.PIP_T_InspectionResult R
JOIN dbo.PIP_T_Inspection I ON I.InspectionID=R.InspectionID
LEFT JOIN dbo.PIP_T_InspectionResultValue V ON V.InspectionResultID=R.InspectionResultID
WHERE I.InspectionID=@InspectionID AND R.InspectionPointTransactionID IS NULL
ORDER BY R.DisplayOrder, V.FieldName",
                    new SqlParameter[] {
new SqlParameter("@InspectionID", inspectionId) });

                var groupedItems = new Dictionary<int, Dictionary<string, object>>();
                foreach (DataRow row in results.Rows)
                {
                    int itemId = Convert.ToInt32(row["IDItem"]);
                    Dictionary<string, object> item;
                    if (!groupedItems.TryGetValue(itemId, out item))
                    {
                        item = new Dictionary<string, object> {
                            { "IDItem", itemId },
                            { "ItemLabel", row["ItemLabel"] == DBNull.Value ? "" : row["ItemLabel"].ToString() },
                            { "ItemType", row["ItemType"] == DBNull.Value ? "" : row["ItemType"].ToString() },
                            { "Value", row["Value"] == DBNull.Value ? "" : row["Value"].ToString() },
                            { "Remark1", row["Remark1"] == DBNull.Value ? "" : row["Remark1"].ToString() },
                            { "Remark2", row["Remark2"] == DBNull.Value ? "" : row["Remark2"].ToString() },
                            { "IsAnomali", row["IsAnomali"] != DBNull.Value && Convert.ToBoolean(row["IsAnomali"]) },
                            { "DisplayOrder", row["DisplayOrder"] == DBNull.Value ? 0 : Convert.ToInt32(row["DisplayOrder"]) },
                            { "Values", new Dictionary<string, object>() },
                            { "RepeatValues", new List<Dictionary<string, object>>() }
                        };
                        groupedItems.Add(itemId, item);
                    }
                    if (row["FieldName"] != DBNull.Value)
                    {
                        if (String.Equals(Convert.ToString(item["ItemType"]), "REPEAT", StringComparison.OrdinalIgnoreCase))
                        {
                            int objectIndex = row["ObjectIndex"] == DBNull.Value ? 0 : Convert.ToInt32(row["ObjectIndex"]);
                            var repeatRows = (List<Dictionary<string, object>>)item["RepeatValues"];
                            var repeatRow = repeatRows.FirstOrDefault(x => Convert.ToInt32(x["ObjectIndex"]) == objectIndex);
                            if (repeatRow == null)
                            {
                                repeatRow = new Dictionary<string, object> { { "ObjectIndex", objectIndex }, { "Values", new Dictionary<string, object>() } };
                                repeatRows.Add(repeatRow);
                            }
                            ((Dictionary<string, object>)repeatRow["Values"])[row["FieldName"].ToString()] =
                                row["FieldValue"] == DBNull.Value ? "" : row["FieldValue"].ToString();
                        }
                        else
                            ((Dictionary<string, object>)item["Values"])[row["FieldName"].ToString()] =
                                row["FieldValue"] == DBNull.Value ? "" : row["FieldValue"].ToString();
                    }
                }
                var itemRows = groupedItems.Values.OrderBy(x => Convert.ToInt32(x["DisplayOrder"])).ToList();

                var batchPointRows = new List<Dictionary<string, object>>();
                var batchMapRows = new List<Dictionary<string, object>>();
                var batchScheduleRows = new List<Dictionary<string, object>>();
                string approvalInspectionMode = Convert.ToString(header.Rows[0]["InspectionMode"]);
                if (String.Equals(approvalInspectionMode, "BATCH", StringComparison.OrdinalIgnoreCase) ||
                    String.Equals(approvalInspectionMode, "LIGHTNING", StringComparison.OrdinalIgnoreCase))
                {
                    DataTable pointMasterRows = br.EQueryP(@"
SELECT TP.InspectionPointTransactionID, TP.ClientPointID, TP.InspectionPointID,
       TP.ScheduleTime, TP.InspectionDateTime, TP.Status, TP.AbnormalRemark, P.IsNormalAbnormalRequired,
       P.PointCode, P.PointName, P.PointObjectType,
       P.PointDescription, P.MapID, P.MapX, P.MapY,
       P.ShapeType,P.SvgPathData,P.ShapeAttributes,P.StrokeWidth,
       M.MapCode, M.MapName, M.ImagePath AS MapUrl, M.MapVersion
FROM dbo.PIP_T_InspectionPoint TP
JOIN dbo.PIP_M_InspectionPoint P ON P.InspectionPointID=TP.InspectionPointID
LEFT JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
WHERE TP.InspectionID=@InspectionID
ORDER BY P.DisplayOrder,P.PointCode",
                        new SqlParameter[] { new SqlParameter("@InspectionID", inspectionId) });

                    DataTable pointResultRows = br.EQueryP(@"
SELECT R.InspectionPointTransactionID,R.IDItem,R.ItemLabel,R.ItemType,R.Value,
       R.Remark1,R.Remark2,R.IsAnomali,R.DisplayOrder,V.ObjectIndex,V.FieldName,V.Value AS FieldValue
FROM dbo.PIP_T_InspectionResult R
LEFT JOIN dbo.PIP_T_InspectionResultValue V ON V.InspectionResultID=R.InspectionResultID
WHERE R.InspectionID=@InspectionID AND R.InspectionPointTransactionID IS NOT NULL
ORDER BY R.InspectionPointTransactionID,R.DisplayOrder,V.FieldName",
                        new SqlParameter[] { new SqlParameter("@InspectionID", inspectionId) });

                    var pointItems = new Dictionary<long, Dictionary<int, Dictionary<string, object>>>();
                    foreach (DataRow row in pointResultRows.Rows)
                    {
                        long pointTransactionID = Convert.ToInt64(row["InspectionPointTransactionID"]);
                        int itemID = Convert.ToInt32(row["IDItem"]);
                        if (!pointItems.ContainsKey(pointTransactionID))
                            pointItems[pointTransactionID] = new Dictionary<int, Dictionary<string, object>>();
                        Dictionary<string, object> item;
                        if (!pointItems[pointTransactionID].TryGetValue(itemID, out item))
                        {
                            item = new Dictionary<string, object> {
                                { "IDItem", itemID },
                                { "ItemLabel", GF.GetString(row["ItemLabel"]) },
                                { "Type", GF.GetString(row["ItemType"]) },
                                { "Value", GF.GetString(row["Value"]) },
                                { "Remark1", GF.GetString(row["Remark1"]) },
                                { "Remark2", GF.GetString(row["Remark2"]) },
                                { "IsAnomali", row["IsAnomali"] != DBNull.Value && Convert.ToBoolean(row["IsAnomali"]) },
                                { "DisplayOrder", row["DisplayOrder"] == DBNull.Value ? 0 : Convert.ToInt32(row["DisplayOrder"]) },
                                { "Values", new Dictionary<string, object>() },
                                { "RepeatValues", new List<Dictionary<string, object>>() }
                            };
                            pointItems[pointTransactionID].Add(itemID, item);
                        }
                        if (row["FieldName"] != DBNull.Value)
                        {
                            if (String.Equals(Convert.ToString(item["Type"]), "REPEAT", StringComparison.OrdinalIgnoreCase))
                            {
                                int objectIndex = row["ObjectIndex"] == DBNull.Value ? 0 : Convert.ToInt32(row["ObjectIndex"]);
                                var repeatRows = (List<Dictionary<string, object>>)item["RepeatValues"];
                                var repeatRow = repeatRows.FirstOrDefault(x => Convert.ToInt32(x["ObjectIndex"]) == objectIndex);
                                if (repeatRow == null)
                                {
                                    repeatRow = new Dictionary<string, object> { { "ObjectIndex", objectIndex }, { "Values", new Dictionary<string, object>() } };
                                    repeatRows.Add(repeatRow);
                                }
                                ((Dictionary<string, object>)repeatRow["Values"])[GF.GetString(row["FieldName"])] = GF.GetString(row["FieldValue"]);
                            }
                            else
                                ((Dictionary<string, object>)item["Values"])[GF.GetString(row["FieldName"])] = GF.GetString(row["FieldValue"]);
                        }
                    }

                    var mapIDs = new HashSet<long>();
                    foreach (DataRow pointRow in pointMasterRows.Rows)
                    {
                        long pointTransactionID = Convert.ToInt64(pointRow["InspectionPointTransactionID"]);
                        long mapID = pointRow["MapID"] == DBNull.Value ? 0 : Convert.ToInt64(pointRow["MapID"]);
                        var pointData = new Dictionary<string, object> {
                            { "InspectionPointTransactionID", pointTransactionID },
                            { "ClientPointID", GF.GetString(pointRow["ClientPointID"]) },
                            { "InspectionPointID", Convert.ToInt64(pointRow["InspectionPointID"]) },
                            { "ScheduleTime", GF.GetString(pointRow["ScheduleTime"]) },
                            { "InspectionDateTime", pointRow["InspectionDateTime"] == DBNull.Value ? "" : Convert.ToDateTime(pointRow["InspectionDateTime"]).ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture) },
                            { "Status", GF.GetString(pointRow["Status"]) },
                            { "AbnormalRemark", GF.GetString(pointRow["AbnormalRemark"]) },
                            { "PointCondition", String.IsNullOrWhiteSpace(GF.GetString(pointRow["AbnormalRemark"])) ? (String.Equals(GF.GetString(pointRow["Status"]), "DONE", StringComparison.OrdinalIgnoreCase) || String.Equals(GF.GetString(pointRow["Status"]), "ABNORMAL", StringComparison.OrdinalIgnoreCase) ? "NORMAL" : "") : "ABNORMAL" },
                            { "IsNormalAbnormalRequired", pointRow["IsNormalAbnormalRequired"] != DBNull.Value && Convert.ToBoolean(pointRow["IsNormalAbnormalRequired"]) },
                            { "PointCode", GF.GetString(pointRow["PointCode"]) },
                            { "PointName", GF.GetString(pointRow["PointName"]) },
                            { "PointObjectType", GF.GetString(pointRow["PointObjectType"]) },
                            { "PointDescription", GF.GetString(pointRow["PointDescription"]) },
                            { "MapID", mapID },
                            { "MapX", pointRow["MapX"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(pointRow["MapX"]) },
                            { "MapY", pointRow["MapY"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(pointRow["MapY"]) },
                            { "ShapeType", GF.GetString(pointRow["ShapeType"]) },
                            { "SvgPathData", GF.GetString(pointRow["SvgPathData"]) },
                            { "ShapeAttributes", GF.GetString(pointRow["ShapeAttributes"]) },
                            { "StrokeWidth", pointRow["StrokeWidth"] == DBNull.Value ? 1.5m : Convert.ToDecimal(pointRow["StrokeWidth"]) },
                            { "MapCode", GF.GetString(pointRow["MapCode"]) },
                            { "Items", pointItems.ContainsKey(pointTransactionID) ? (object)pointItems[pointTransactionID].Values.OrderBy(x => Convert.ToInt32(x["DisplayOrder"])).ToList() : new List<Dictionary<string, object>>() }
                        };
                        batchPointRows.Add(pointData);
                        if (mapID > 0 && mapIDs.Add(mapID))
                        {
                            batchMapRows.Add(new Dictionary<string, object> {
                                { "MapID", mapID },
                                { "MapCode", GF.GetString(pointRow["MapCode"]) },
                                { "MapName", GF.GetString(pointRow["MapName"]) },
                                { "MapUrl", ResolveInspectionMapUrl(GF.GetString(pointRow["MapUrl"]), GF.GetString(header.Rows[0]["CompanyID"]), GF.GetString(header.Rows[0]["LocationID"])) },
                                { "MapVersion", pointRow["MapVersion"] == DBNull.Value ? 0 : Convert.ToInt32(pointRow["MapVersion"]) }
                            });
                        }
                    }

                    if (String.Equals(approvalInspectionMode, "LIGHTNING", StringComparison.OrdinalIgnoreCase))
                    {
                        DataTable scheduleRows = br.EQueryP(@"
SELECT ScheduleTime,ScheduleStatus,SubmittedDate
FROM dbo.PIP_T_InspectionLightningSchedule
WHERE InspectionID=@InspectionID
ORDER BY ScheduleTime",
                            new SqlParameter[] { new SqlParameter("@InspectionID", inspectionId) });
                        foreach (DataRow scheduleRow in scheduleRows.Rows)
                            batchScheduleRows.Add(new Dictionary<string, object> {
                                { "ScheduleTime", GF.GetString(scheduleRow["ScheduleTime"]) },
                                { "ScheduleStatus", GF.GetString(scheduleRow["ScheduleStatus"]) },
                                { "SubmittedDate", scheduleRow["SubmittedDate"] == DBNull.Value ? "" : Convert.ToDateTime(scheduleRow["SubmittedDate"]).ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture) }
                            });
                    }
                }

                var h = new Dictionary<string, object>();
                foreach (DataColumn col in header.Columns)
                    h[col.ColumnName] = header.Rows[0][col] == DBNull.Value ? null : header.Rows[0][col];
object approvalTemplateSnapshot = null;
                DataTable meta = br.EQueryP(@"
SELECT T.IDTemplate, T.TemplateNo, T.TemplateName, T.SectionID, T.InspectionTypeCode,
   V.IDVersion, V.Version, V.StatusOption, ISNULL(V.PhotoRequirement,'NONE') PhotoRequirement, ISNULL(V.SummarySampleText,'') SummarySampleText, ISNULL(V.IsSummaryRequired,1) VersionIsSummaryRequired, ISNULL(V.IsFollowUpRequired,1) VersionIsFollowUpRequired, V.IsRemark1Required VersionIsRemark1Required, V.Remark1Text VersionRemark1Text, V.IsRemark2Required VersionIsRemark2Required, V.Remark2Text VersionRemark2Text, V.RemarkRequiredOptions VersionRemarkRequiredOptions
FROM dbo.PIP_M_CheckListWOPM T
JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDTemplate=T.IDTemplate
WHERE T.IDTemplate=@IDTemplate AND V.IDVersion=@IDVersion AND ISNULL(T.TemplateType,'W')='I'",
                    new SqlParameter[] {
new SqlParameter("@IDTemplate", Convert.ToInt32(header.Rows[0]["IDTemplate"])),
                        new SqlParameter("@IDVersion", Convert.ToInt32(header.Rows[0]["IDVersion"]))
                    });
                if (meta.Rows.Count > 0)
                {
                    DataRow m = meta.Rows[0];
                    DataTable templateItems = br.EQueryP(@"
SELECT S.IDSection, S.SectionName, S.DisplayOrder AS SectionOrder,
   I.IDItem, I.IDSubSection, ISNULL(SS.SubSectionName,'') AS SubSectionName,
   ISNULL(SS.DisplayOrder,0) AS SubSectionOrder,
   I.ItemLabel, I.ItemType, ISNULL(I.OptionList,'') OptionList,
   I.MinValue, I.MaxValue, ISNULL(I.Unit,'') Unit, ISNULL(I.ShowUnitInRange,0) ShowUnitInRange, I.IsValueRequired,
   I.IsRemark1Required, I.IsRemark2Required, I.IsRemark1Mandatory, I.IsRemark2Mandatory, I.Remark1Text, I.Remark2Text, I.IsUseDefaultRemark1, I.IsUseDefaultRemark2, ISNULL(I.RemarkRequiredOptions,'') RemarkRequiredOptions, I.DisplayOrder AS ItemOrder, V.StatusOption,
   I.ModelCode, I.MinTolerance, I.MaxTolerance, I.IsToleranceRequired
FROM dbo.PIP_M_CheckListWOPM_Section S
JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDSection=S.IDSection
LEFT JOIN dbo.PIP_M_CheckListWOPM_SubSection SS ON SS.IDSubSection=I.IDSubSection
JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDVersion=S.IDVersion
WHERE V.IDVersion=@IDVersion
ORDER BY S.DisplayOrder,
     CASE WHEN ISNULL(I.IDSubSection,0)=0 THEN I.DisplayOrder ELSE SS.DisplayOrder END,
     I.DisplayOrder",
                        new SqlParameter[] {
new SqlParameter("@IDVersion", Convert.ToInt32(header.Rows[0]["IDVersion"])) });
                    DataTable templateGroups = br.EQueryP(@"
SELECT G.IDItem, G.GroupName, G.FieldList, G.Unit, G.DisplayOrder
FROM dbo.PIP_M_CheckListWOPM_ItemGroup G
JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=G.IDItem
JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
WHERE S.IDVersion=@IDVersion
ORDER BY G.DisplayOrder",
                        new SqlParameter[] {
new SqlParameter("@IDVersion", Convert.ToInt32(header.Rows[0]["IDVersion"])) });

                    var sections = templateItems.AsEnumerable()
                        .GroupBy(row => new {
                            IDSection = Convert.ToInt32(row["IDSection"]),
                            SectionName = row["SectionName"].ToString(),
                            SectionOrder = Convert.ToInt32(row["SectionOrder"])
                        })
                        .OrderBy(group => group.Key.SectionOrder)
                        .Select(group => new {
                            idSection = group.Key.IDSection,
                            sectionName = group.Key.SectionName,
                            items = group.Select(itemRow => {
                                string itemType = itemRow["ItemType"].ToString();
                                string optionList = itemType == "OPTION"
                                    ? (String.IsNullOrEmpty(itemRow["OptionList"].ToString())
                                        ? itemRow["StatusOption"].ToString() : itemRow["OptionList"].ToString())
                                    : "";
                                var itemGroups = templateGroups.AsEnumerable()
                                    .Where(g => g["IDItem"].ToString() == itemRow["IDItem"].ToString())
                                    .OrderBy(g => g["DisplayOrder"])
                                    .Select(g => new {
                                        groupName = g["GroupName"].ToString(),
                                        fieldList = g["FieldList"].ToString(),
                                        unit = g["Unit"].ToString()
                                    }).ToList();
                                return new {
                                    idItem = Convert.ToInt32(itemRow["IDItem"]),
                                    idSubSection = itemRow["IDSubSection"] == DBNull.Value ? 0 : Convert.ToInt32(itemRow["IDSubSection"]),
                                    subSectionName = itemRow["SubSectionName"] == DBNull.Value ? "" : itemRow["SubSectionName"].ToString(),
                                    subSectionOrder = itemRow["SubSectionOrder"] == DBNull.Value ? 0 : Convert.ToInt32(itemRow["SubSectionOrder"]),
                                    itemOrder = itemRow["ItemOrder"] == DBNull.Value ? 0 : Convert.ToInt32(itemRow["ItemOrder"]),
                                    label = itemRow["ItemLabel"].ToString(),
                                    type = itemType,
                                    optionList = optionList,
                                    min = itemRow["MinValue"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(itemRow["MinValue"]),
                                    max = itemRow["MaxValue"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(itemRow["MaxValue"]),
                                    unit = itemRow["Unit"].ToString(),
                                    showUnitInRange = Convert.ToBoolean(itemRow["ShowUnitInRange"]),
                                    isValueRequired = Convert.ToBoolean(itemRow["IsValueRequired"]),
                                    
                                    versionIsRemark1Required = Convert.ToBoolean(m["VersionIsRemark1Required"]),
                                    versionIsRemark2Required = Convert.ToBoolean(m["VersionIsRemark2Required"]),
                                    versionRemark1Text = GF.GetString(m["VersionRemark1Text"]),
                                    versionRemark2Text = GF.GetString(m["VersionRemark2Text"]),
                                    isRemark1Required = Convert.ToBoolean(m["VersionIsRemark1Required"]) && (Convert.ToBoolean(itemRow["IsUseDefaultRemark1"]) || Convert.ToBoolean(itemRow["IsRemark1Required"])),
                                    isRemark2Required = Convert.ToBoolean(m["VersionIsRemark2Required"]) && (Convert.ToBoolean(itemRow["IsUseDefaultRemark2"]) || Convert.ToBoolean(itemRow["IsRemark2Required"])),
                                    isRemark1Mandatory = Convert.ToBoolean(itemRow["IsRemark1Mandatory"]),
                                    isRemark2Mandatory = Convert.ToBoolean(itemRow["IsRemark2Mandatory"]),
                                    remark1Text = Convert.ToBoolean(itemRow["IsUseDefaultRemark1"]) ? GF.GetString(m["VersionRemark1Text"]) : (itemRow["Remark1Text"] == DBNull.Value ? "Remark" : itemRow["Remark1Text"].ToString()),
                                    remark2Text = Convert.ToBoolean(itemRow["IsUseDefaultRemark2"]) ? GF.GetString(m["VersionRemark2Text"]) : (itemRow["Remark2Text"] == DBNull.Value ? "Remark" : itemRow["Remark2Text"].ToString()),
                                    remarkRequiredOptions = !(Convert.ToBoolean(m["VersionIsRemark1Required"]) || Convert.ToBoolean(m["VersionIsRemark2Required"])) ? new string[0] : (String.IsNullOrWhiteSpace(GF.GetString(m["VersionRemarkRequiredOptions"])) ? new string[0] : GF.GetString(m["VersionRemarkRequiredOptions"]).Split(';')),
                                    isToleranceRequired = itemRow["IsToleranceRequired"] != DBNull.Value && Convert.ToBoolean(itemRow["IsToleranceRequired"]),
                                    mintol = itemRow["MinTolerance"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(itemRow["MinTolerance"]),
                                    maxtol = itemRow["MaxTolerance"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(itemRow["MaxTolerance"]),
                                    modelcode = itemRow["ModelCode"] == DBNull.Value ? "" : itemRow["ModelCode"].ToString(),
                                    groups = itemGroups.Count > 0 ? itemGroups : null
                                };
                            }).ToList()
                        }).ToList();
                    approvalTemplateSnapshot = new {
                        IDTemplate = Convert.ToInt32(m["IDTemplate"]),
                        IDVersion = Convert.ToInt32(m["IDVersion"]),
                        Version = m["Version"].ToString(),
                        SectionID = m["SectionID"].ToString(),
                        TemplateType = "I",
                        InspectionTypeCode = m["InspectionTypeCode"].ToString(),
                        TemplateNo = m["TemplateNo"].ToString(),
                        TemplateName = m["TemplateName"].ToString(),
                        StatusOption = m["StatusOption"].ToString(),
                        SummarySampleText = GF.GetString(m["SummarySampleText"]),
                        IsSummaryRequired = m["VersionIsSummaryRequired"] == DBNull.Value || Convert.ToBoolean(m["VersionIsSummaryRequired"]),
                        IsFollowUpRequired = m["VersionIsFollowUpRequired"] == DBNull.Value || Convert.ToBoolean(m["VersionIsFollowUpRequired"]),
                        IsRemark1Required = Convert.ToBoolean(m["VersionIsRemark1Required"]),
                        Remark1Text = GF.GetString(m["VersionRemark1Text"]),
                        IsRemark2Required = Convert.ToBoolean(m["VersionIsRemark2Required"]),
                        Remark2Text = GF.GetString(m["VersionRemark2Text"]),
                        RemarkRequiredOptions = String.IsNullOrWhiteSpace(GF.GetString(m["VersionRemarkRequiredOptions"])) ? new string[0] : GF.GetString(m["VersionRemarkRequiredOptions"]).Split(';'),
                        sections = sections
                    };
                }
                DataTable photoTable = br.EQueryP(@"
SELECT P.PhotoType, P.FileName, P.FileType, P.SeqNo, P.InspectionPointTransactionID
FROM dbo.PIP_T_InspectionPhoto P
WHERE P.InspectionID=@InspectionID
ORDER BY P.SeqNo",
                    new SqlParameter[] { new SqlParameter("@InspectionID", inspectionId) });
                var photos = new List<Dictionary<string, object>>();
                foreach (DataRow photo in photoTable.Rows)
                {
                    string fileName = photo["FileName"] == DBNull.Value ? "" : photo["FileName"].ToString();
                    string fileType = photo["FileType"] == DBNull.Value ? "" : photo["FileType"].ToString();
                    DateTime inspectionDate = Convert.ToDateTime(header.Rows[0]["InspectionDate"]);
                    string dataUrl = GetInspectionPhotoDataUrl(header.Rows[0]["CompanyID"].ToString(), header.Rows[0]["LocationID"].ToString(), inspectionDate, header.Rows[0]["InspectionNo"].ToString(), fileName, fileType);
                    if (String.IsNullOrEmpty(dataUrl)) continue;
                    photos.Add(new Dictionary<string, object> {
                        { "Type", photo["PhotoType"] == DBNull.Value ? "" : photo["PhotoType"].ToString() },
                        { "FileName", fileName + "." + fileType },
                        { "SeqNo", photo["SeqNo"] == DBNull.Value ? 0 : Convert.ToInt32(photo["SeqNo"]) },
                        { "PointID", photo["InspectionPointTransactionID"] == DBNull.Value ? "" : Convert.ToString(photo["InspectionPointTransactionID"]) },
                        { "Data", dataUrl }
                    });
                }
                return new { success = true, header = h, items = itemRows, photos = photos, template = approvalTemplateSnapshot,
                    points = batchPointRows, maps = batchMapRows, schedules = batchScheduleRows };
            }
        }

        [WebMethod]
        public static object GetReturnedInspections(string employeeId, string companyId, string locationId)
        {
            employeeId = GFC.RequireMenuEmployee("20021");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (String.IsNullOrWhiteSpace(employeeId))
                throw new HttpException(403, "Technician identity is required.");
            using (var br = new WAL.BR.CF())
            {
                DataTable headers = br.EQueryP(@"
SELECT I.InspectionID, I.ClientInspectionID, I.InspectionNo, I.CompanyID, I.LocationID, I.SectionID,
       I.InspectionTypeCode, I.InspectionTypeName, I.InspectionTypeDetailCode,
       I.InspectionTypeDetailName, I.ScheduledTime, I.IDTemplate, I.IDVersion,
       I.TemplateNo, I.TemplateName, I.TemplateVersion, I.InspectionDate,
       I.StartDateTime, I.EndDateTime, I.Status, I.Summary, I.OwnerEmployeeID,
       I.ReasonVoid, I.UpdateDate,
       ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') AS InspectionMode
FROM dbo.PIP_T_Inspection I
LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
WHERE I.OwnerEmployeeID=@EmployeeID AND I.CompanyID=@CompanyID AND I.LocationID=@LocationID
  AND ISNULL(I.IsActive,1)=1
  AND I.Status='DRAFT' AND I.IsApprove=0 AND ISNULL(I.ReasonVoid,'')<>''
  AND (
      (ISNULL(I.ApprovedBy,'')<>'' AND ISNULL(I.ApprovedDate,CONVERT(DATETIME,'19000101',112))>CONVERT(DATETIME,'19000101',112))
      OR (ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')='LIGHTNING' AND EXISTS (
          SELECT 1 FROM dbo.PIP_T_InspectionWorkflow W
          WHERE W.EntityType='LIGHTNING' AND W.EntityID=I.InspectionID AND W.WorkflowStatus='VOID'
      ))
  )
  AND EXISTS (SELECT 1 FROM dbo.SysWebUser SU

WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1 AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20021')
              AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S WHERE S.val=I.SectionID)
              AND (
                  EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                          WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                            AND C.CompanyID=I.CompanyID AND C.LocationID=I.LocationID)
                  OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                             WHERE L.CompanyID=I.CompanyID AND L.LocationID=I.LocationID)
              ))
ORDER BY I.UpdateDate DESC",
                    new SqlParameter[] {
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId)
                    });
                var result = new List<Dictionary<string, object>>();
                foreach (DataRow header in headers.Rows)
                {
                    long id = Convert.ToInt64(header["InspectionID"]);
                    DataTable rows = br.EQueryP(@"
SELECT R.IDItem, R.ItemLabel, R.ItemType, R.Value, R.Remark1, R.Remark2, R.IsAnomali, R.DisplayOrder,
       V.ObjectIndex,V.FieldName, V.Value AS FieldValue
FROM dbo.PIP_T_InspectionResult R
LEFT JOIN dbo.PIP_T_InspectionResultValue V ON V.InspectionResultID=R.InspectionResultID
WHERE R.InspectionID=@InspectionID
ORDER BY R.DisplayOrder, V.FieldName",
                        new SqlParameter[] {
new SqlParameter("@InspectionID", id) });
                    var grouped = new Dictionary<int, Dictionary<string, object>>();
                    foreach (DataRow row in rows.Rows)
                    {
                        int itemId = Convert.ToInt32(row["IDItem"]);
                        Dictionary<string, object> item;
                        if (!grouped.TryGetValue(itemId, out item))
                        {
                            item = new Dictionary<string, object> {
                                { "IDItem", itemId },
                                { "ItemLabel", row["ItemLabel"] == DBNull.Value ? "" : row["ItemLabel"].ToString() },
                                { "Type", row["ItemType"] == DBNull.Value ? "" : row["ItemType"].ToString() },
                                { "Value", row["Value"] == DBNull.Value ? "" : row["Value"].ToString() },
                                { "Remark1", row["Remark1"] == DBNull.Value ? "" : row["Remark1"].ToString() },
                                { "Remark2", row["Remark2"] == DBNull.Value ? "" : row["Remark2"].ToString() },
                                { "IsAnomali", row["IsAnomali"] != DBNull.Value && Convert.ToBoolean(row["IsAnomali"]) },
                                { "DisplayOrder", row["DisplayOrder"] == DBNull.Value ? 0 : Convert.ToInt32(row["DisplayOrder"]) },
                                { "Values", new Dictionary<string, object>() },
                                { "RepeatValues", new List<Dictionary<string, object>>() }
                            };
                            grouped.Add(itemId, item);
                        }
                        if (row["FieldName"] != DBNull.Value)
                        {
                            if (String.Equals(Convert.ToString(item["Type"]), "REPEAT", StringComparison.OrdinalIgnoreCase))
                            {
                                int objectIndex = row["ObjectIndex"] == DBNull.Value ? 0 : Convert.ToInt32(row["ObjectIndex"]);
                                var repeatRows = (List<Dictionary<string, object>>)item["RepeatValues"];
                                var repeatRow = repeatRows.FirstOrDefault(x => Convert.ToInt32(x["ObjectIndex"]) == objectIndex);
                                if (repeatRow == null) { repeatRow = new Dictionary<string, object> { { "ObjectIndex", objectIndex }, { "Values", new Dictionary<string, object>() } }; repeatRows.Add(repeatRow); }
                                ((Dictionary<string, object>)repeatRow["Values"])[row["FieldName"].ToString()] = row["FieldValue"] == DBNull.Value ? "" : row["FieldValue"].ToString();
                            }
                            else ((Dictionary<string, object>)item["Values"])[row["FieldName"].ToString()] = row["FieldValue"] == DBNull.Value ? "" : row["FieldValue"].ToString();
                        }
                    }
                    var record = new Dictionary<string, object>();
                    foreach (DataColumn col in headers.Columns)
                        record[col.ColumnName] = header[col] == DBNull.Value ? null : header[col];
                    record["Items"] = grouped.Values.OrderBy(x => Convert.ToInt32(x["DisplayOrder"])).ToList();

                    if (String.Equals(GF.GetString(header["InspectionMode"]), "BATCH", StringComparison.OrdinalIgnoreCase) ||
                        String.Equals(GF.GetString(header["InspectionMode"]), "LIGHTNING", StringComparison.OrdinalIgnoreCase))
                    {
                        DataTable returnedPoints = br.EQueryP(@"
SELECT TP.InspectionPointTransactionID,TP.ClientPointID,TP.InspectionPointID,
       TP.ScheduleTime,TP.InspectionDateTime,TP.Status,TP.AbnormalRemark,P.IsNormalAbnormalRequired,
       P.PointCode,P.PointName,P.PointObjectType,
       P.PointDescription,P.MapID,P.MapX,P.MapY,
       P.ShapeType,P.SvgPathData,P.ShapeAttributes,P.StrokeWidth
FROM dbo.PIP_T_InspectionPoint TP
JOIN dbo.PIP_M_InspectionPoint P ON P.InspectionPointID=TP.InspectionPointID
WHERE TP.InspectionID=@InspectionID
ORDER BY P.DisplayOrder,P.PointCode",
                            new SqlParameter[] { new SqlParameter("@InspectionID", id) });
                        DataTable returnedPointItems = br.EQueryP(@"
SELECT R.InspectionPointTransactionID,R.IDItem,R.ItemLabel,R.ItemType,R.Value,
       R.Remark1,R.Remark2,R.IsAnomali,R.DisplayOrder,V.ObjectIndex,V.FieldName,V.Value AS FieldValue
FROM dbo.PIP_T_InspectionResult R
LEFT JOIN dbo.PIP_T_InspectionResultValue V ON V.InspectionResultID=R.InspectionResultID
WHERE R.InspectionID=@InspectionID AND R.InspectionPointTransactionID IS NOT NULL
ORDER BY R.InspectionPointTransactionID,R.DisplayOrder,V.FieldName",
                            new SqlParameter[] { new SqlParameter("@InspectionID", id) });
                        var pointGroups = new Dictionary<long, Dictionary<int, Dictionary<string, object>>>();
                        foreach (DataRow pointItemRow in returnedPointItems.Rows)
                        {
                            long pointTransactionID = Convert.ToInt64(pointItemRow["InspectionPointTransactionID"]);
                            int itemID = Convert.ToInt32(pointItemRow["IDItem"]);
                            if (!pointGroups.ContainsKey(pointTransactionID))
                                pointGroups[pointTransactionID] = new Dictionary<int, Dictionary<string, object>>();
                            Dictionary<string, object> pointItem;
                            if (!pointGroups[pointTransactionID].TryGetValue(itemID, out pointItem))
                            {
                                pointItem = new Dictionary<string, object> {
                                    { "IDItem", itemID },
                                    { "ItemLabel", GF.GetString(pointItemRow["ItemLabel"]) },
                                    { "Type", GF.GetString(pointItemRow["ItemType"]) },
                                    { "Value", GF.GetString(pointItemRow["Value"]) },
                                    { "Remark1", GF.GetString(pointItemRow["Remark1"]) },
                                    { "Remark2", GF.GetString(pointItemRow["Remark2"]) },
                                    { "IsAnomali", pointItemRow["IsAnomali"] != DBNull.Value && Convert.ToBoolean(pointItemRow["IsAnomali"]) },
                                    { "DisplayOrder", pointItemRow["DisplayOrder"] == DBNull.Value ? 0 : Convert.ToInt32(pointItemRow["DisplayOrder"]) },
                                    { "Values", new Dictionary<string, object>() },
                                    { "RepeatValues", new List<Dictionary<string, object>>() }
                                };
                                pointGroups[pointTransactionID].Add(itemID, pointItem);
                            }
                            if (pointItemRow["FieldName"] != DBNull.Value)
                            {
                                if (String.Equals(Convert.ToString(pointItem["Type"]), "REPEAT", StringComparison.OrdinalIgnoreCase))
                                {
                                    int objectIndex = pointItemRow["ObjectIndex"] == DBNull.Value ? 0 : Convert.ToInt32(pointItemRow["ObjectIndex"]);
                                    var repeatRows = (List<Dictionary<string, object>>)pointItem["RepeatValues"];
                                    var repeatRow = repeatRows.FirstOrDefault(x => Convert.ToInt32(x["ObjectIndex"]) == objectIndex);
                                    if (repeatRow == null) { repeatRow = new Dictionary<string, object> { { "ObjectIndex", objectIndex }, { "Values", new Dictionary<string, object>() } }; repeatRows.Add(repeatRow); }
                                    ((Dictionary<string, object>)repeatRow["Values"])[GF.GetString(pointItemRow["FieldName"])] = GF.GetString(pointItemRow["FieldValue"]);
                                }
                                else ((Dictionary<string, object>)pointItem["Values"])[GF.GetString(pointItemRow["FieldName"])] = GF.GetString(pointItemRow["FieldValue"]);
                            }
                        }

                        var returnedPointList = new List<Dictionary<string, object>>();
                        foreach (DataRow pointRow in returnedPoints.Rows)
                        {
                            long pointTransactionID = Convert.ToInt64(pointRow["InspectionPointTransactionID"]);
                            returnedPointList.Add(new Dictionary<string, object> {
                                { "InspectionPointTransactionID", Convert.ToInt64(pointRow["InspectionPointTransactionID"]) },
                                { "ClientPointID", GF.GetString(pointRow["ClientPointID"]) },
                                { "InspectionPointID", Convert.ToInt64(pointRow["InspectionPointID"]) },
                                { "ScheduleTime", GF.GetString(pointRow["ScheduleTime"]) },
                                { "PointCode", GF.GetString(pointRow["PointCode"]) },
                                { "PointName", GF.GetString(pointRow["PointName"]) },
                                { "AbnormalRemark", GF.GetString(pointRow["AbnormalRemark"]) },
                                { "PointCondition", String.IsNullOrWhiteSpace(GF.GetString(pointRow["AbnormalRemark"])) ? (String.Equals(GF.GetString(pointRow["Status"]), "DONE", StringComparison.OrdinalIgnoreCase) || String.Equals(GF.GetString(pointRow["Status"]), "ABNORMAL", StringComparison.OrdinalIgnoreCase) ? "NORMAL" : "") : "ABNORMAL" },
                                { "IsNormalAbnormalRequired", pointRow["IsNormalAbnormalRequired"] != DBNull.Value && Convert.ToBoolean(pointRow["IsNormalAbnormalRequired"]) },
                                { "PointObjectType", GF.GetString(pointRow["PointObjectType"]) },
                                { "PointDescription", GF.GetString(pointRow["PointDescription"]) },
                                { "MapID", pointRow["MapID"] == DBNull.Value ? 0 : Convert.ToInt64(pointRow["MapID"]) },
                                { "MapX", pointRow["MapX"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(pointRow["MapX"]) },
                                { "MapY", pointRow["MapY"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(pointRow["MapY"]) },
                                { "ShapeType", GF.GetString(pointRow["ShapeType"]) },
                                { "SvgPathData", GF.GetString(pointRow["SvgPathData"]) },
                                { "ShapeAttributes", GF.GetString(pointRow["ShapeAttributes"]) },
                                { "StrokeWidth", pointRow["StrokeWidth"] == DBNull.Value ? 1.5m : Convert.ToDecimal(pointRow["StrokeWidth"]) },
                                { "InspectionDateTime", pointRow["InspectionDateTime"] == DBNull.Value ? "" : Convert.ToDateTime(pointRow["InspectionDateTime"]).ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture) },
                                { "Status", GF.GetString(pointRow["Status"]) },
                                { "Items", pointGroups.ContainsKey(pointTransactionID) ? (object)pointGroups[pointTransactionID].Values.OrderBy(x => Convert.ToInt32(x["DisplayOrder"])).ToList() : new List<Dictionary<string, object>>() }
                            });
                        }
                        record["Points"] = returnedPointList;
                        if (String.Equals(GF.GetString(header["InspectionMode"]), "LIGHTNING", StringComparison.OrdinalIgnoreCase))
                        {
                            DataTable returnedSchedules = br.EQueryP(@"
SELECT ScheduleTime,ScheduleStatus,SubmittedDate
FROM dbo.PIP_T_InspectionLightningSchedule
WHERE InspectionID=@InspectionID
ORDER BY ScheduleTime",
                                new SqlParameter[] { new SqlParameter("@InspectionID", id) });
                            record["Schedules"] = returnedSchedules.AsEnumerable().Select(row => new {
                                ScheduleTime = GF.GetString(row["ScheduleTime"]),
                                ScheduleStatus = GF.GetString(row["ScheduleStatus"]),
                                SubmittedDate = row["SubmittedDate"] == DBNull.Value ? "" :
                                    Convert.ToDateTime(row["SubmittedDate"]).ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture)
                            }).ToList();
                            record["ActiveScheduleTime"] = returnedSchedules.Rows.Count > 0
                                ? GF.GetString(returnedSchedules.Rows[0]["ScheduleTime"]) : "";
                        }
                    }

                    DataTable meta = br.EQueryP(@"
SELECT T.IDTemplate, T.TemplateNo, T.TemplateName, T.SectionID, T.InspectionTypeCode,
       V.IDVersion, V.Version, V.StatusOption, ISNULL(V.PhotoRequirement,'NONE') PhotoRequirement, ISNULL(V.SummarySampleText,'') SummarySampleText, ISNULL(V.IsSummaryRequired,1) VersionIsSummaryRequired, ISNULL(V.IsFollowUpRequired,1) VersionIsFollowUpRequired, V.IsRemark1Required VersionIsRemark1Required, V.Remark1Text VersionRemark1Text, V.IsRemark2Required VersionIsRemark2Required, V.Remark2Text VersionRemark2Text, V.RemarkRequiredOptions VersionRemarkRequiredOptions
FROM dbo.PIP_M_CheckListWOPM T
JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDTemplate=T.IDTemplate
WHERE T.IDTemplate=@IDTemplate AND V.IDVersion=@IDVersion AND ISNULL(T.TemplateType,'W')='I'",
                        new SqlParameter[] {
new SqlParameter("@IDTemplate", Convert.ToInt32(header["IDTemplate"])),
                            new SqlParameter("@IDVersion", Convert.ToInt32(header["IDVersion"]))
                        });
                    if (meta.Rows.Count > 0)
                    {
                        DataRow m = meta.Rows[0];
                        DataTable templateItems = br.EQueryP(@"
SELECT S.IDSection, S.SectionName, S.DisplayOrder AS SectionOrder,
       I.IDItem, I.IDSubSection, ISNULL(SS.SubSectionName,'') AS SubSectionName,
       ISNULL(SS.DisplayOrder,0) AS SubSectionOrder,
       I.ItemLabel, I.ItemType, ISNULL(I.OptionList,'') OptionList,
       I.MinValue, I.MaxValue, ISNULL(I.Unit,'') Unit, ISNULL(I.ShowUnitInRange,0) ShowUnitInRange, I.IsValueRequired,
       I.IsRemark1Required, I.IsRemark2Required, I.IsRemark1Mandatory, I.IsRemark2Mandatory, I.Remark1Text, I.Remark2Text, I.IsUseDefaultRemark1, I.IsUseDefaultRemark2, ISNULL(I.RemarkRequiredOptions,'') RemarkRequiredOptions, I.DisplayOrder AS ItemOrder, V.StatusOption,
       I.ModelCode, I.MinTolerance, I.MaxTolerance, I.IsToleranceRequired
FROM dbo.PIP_M_CheckListWOPM_Section S
JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDSection=S.IDSection
LEFT JOIN dbo.PIP_M_CheckListWOPM_SubSection SS ON SS.IDSubSection=I.IDSubSection
JOIN dbo.PIP_M_CheckListWOPM_Version V ON V.IDVersion=S.IDVersion
WHERE V.IDVersion=@IDVersion
ORDER BY S.DisplayOrder,
         CASE WHEN ISNULL(I.IDSubSection,0)=0 THEN I.DisplayOrder ELSE SS.DisplayOrder END,
         I.DisplayOrder",
                            new SqlParameter[] {
new SqlParameter("@IDVersion", Convert.ToInt32(header["IDVersion"])) });
                        DataTable templateGroups = br.EQueryP(@"
SELECT G.IDItem, G.GroupName, G.FieldList, G.Unit, G.DisplayOrder
FROM dbo.PIP_M_CheckListWOPM_ItemGroup G
JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=G.IDItem
JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
WHERE S.IDVersion=@IDVersion
ORDER BY G.DisplayOrder",
                            new SqlParameter[] {
new SqlParameter("@IDVersion", Convert.ToInt32(header["IDVersion"])) });

                        var sections = templateItems.AsEnumerable()
                            .GroupBy(row => new {
                                IDSection = Convert.ToInt32(row["IDSection"]),
                                SectionName = row["SectionName"].ToString(),
                                SectionOrder = Convert.ToInt32(row["SectionOrder"])
                            })
                            .OrderBy(group => group.Key.SectionOrder)
                            .Select(group => new {
                                idSection = group.Key.IDSection,
                                sectionName = group.Key.SectionName,
                                items = group.Select(itemRow => {
                                    string itemType = itemRow["ItemType"].ToString();
                                    string optionList = itemType == "OPTION"
                                        ? (String.IsNullOrEmpty(itemRow["OptionList"].ToString())
                                            ? itemRow["StatusOption"].ToString() : itemRow["OptionList"].ToString())
                                        : "";
                                    var itemGroups = templateGroups.AsEnumerable()
                                        .Where(g => g["IDItem"].ToString() == itemRow["IDItem"].ToString())
                                        .OrderBy(g => g["DisplayOrder"])
                                        .Select(g => new {
                                            groupName = g["GroupName"].ToString(),
                                            fieldList = g["FieldList"].ToString(),
                                            unit = g["Unit"].ToString()
                                        }).ToList();
                                    return new {
                                        idItem = Convert.ToInt32(itemRow["IDItem"]),
                                        idSubSection = itemRow["IDSubSection"] == DBNull.Value ? 0 : Convert.ToInt32(itemRow["IDSubSection"]),
                                        subSectionName = itemRow["SubSectionName"] == DBNull.Value ? "" : itemRow["SubSectionName"].ToString(),
                                        subSectionOrder = itemRow["SubSectionOrder"] == DBNull.Value ? 0 : Convert.ToInt32(itemRow["SubSectionOrder"]),
                                        itemOrder = itemRow["ItemOrder"] == DBNull.Value ? 0 : Convert.ToInt32(itemRow["ItemOrder"]),
                                        label = itemRow["ItemLabel"].ToString(),
                                        type = itemType,
                                        optionList = optionList,
                                        min = itemRow["MinValue"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(itemRow["MinValue"]),
                                        max = itemRow["MaxValue"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(itemRow["MaxValue"]),
                                        unit = itemRow["Unit"].ToString(),
                                    showUnitInRange = Convert.ToBoolean(itemRow["ShowUnitInRange"]),
                                        isValueRequired = Convert.ToBoolean(itemRow["IsValueRequired"]),
                                    
                                        versionIsRemark1Required = Convert.ToBoolean(m["VersionIsRemark1Required"]),
                                        versionIsRemark2Required = Convert.ToBoolean(m["VersionIsRemark2Required"]),
                                        versionRemark1Text = GF.GetString(m["VersionRemark1Text"]),
                                        versionRemark2Text = GF.GetString(m["VersionRemark2Text"]),
                                        isRemark1Required = Convert.ToBoolean(m["VersionIsRemark1Required"]) && (Convert.ToBoolean(itemRow["IsUseDefaultRemark1"]) || Convert.ToBoolean(itemRow["IsRemark1Required"])),
                                        isRemark2Required = Convert.ToBoolean(m["VersionIsRemark2Required"]) && (Convert.ToBoolean(itemRow["IsUseDefaultRemark2"]) || Convert.ToBoolean(itemRow["IsRemark2Required"])),
                                        isRemark1Mandatory = Convert.ToBoolean(itemRow["IsRemark1Mandatory"]),
                                        isRemark2Mandatory = Convert.ToBoolean(itemRow["IsRemark2Mandatory"]),
                                        remark1Text = Convert.ToBoolean(itemRow["IsUseDefaultRemark1"]) ? GF.GetString(m["VersionRemark1Text"]) : (itemRow["Remark1Text"] == DBNull.Value ? "Remark" : itemRow["Remark1Text"].ToString()),
                                        remark2Text = Convert.ToBoolean(itemRow["IsUseDefaultRemark2"]) ? GF.GetString(m["VersionRemark2Text"]) : (itemRow["Remark2Text"] == DBNull.Value ? "Remark" : itemRow["Remark2Text"].ToString()),
                                        remarkRequiredOptions = !(Convert.ToBoolean(m["VersionIsRemark1Required"]) || Convert.ToBoolean(m["VersionIsRemark2Required"])) ? new string[0] : (String.IsNullOrWhiteSpace(GF.GetString(m["VersionRemarkRequiredOptions"])) ? new string[0] : GF.GetString(m["VersionRemarkRequiredOptions"]).Split(';')),
                                        isToleranceRequired = itemRow["IsToleranceRequired"] != DBNull.Value && Convert.ToBoolean(itemRow["IsToleranceRequired"]),
                                        mintol = itemRow["MinTolerance"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(itemRow["MinTolerance"]),
                                        maxtol = itemRow["MaxTolerance"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(itemRow["MaxTolerance"]),
                                        modelcode = itemRow["ModelCode"] == DBNull.Value ? "" : itemRow["ModelCode"].ToString(),
                                        groups = itemGroups.Count > 0 ? itemGroups : null
                                    };
                                }).ToList()
                            }).ToList();
                        record["TemplateSnapshot"] = new {
                            IDTemplate = Convert.ToInt32(m["IDTemplate"]),
                            IDVersion = Convert.ToInt32(m["IDVersion"]),
                            Version = m["Version"].ToString(),
                            SectionID = m["SectionID"].ToString(),
                            TemplateType = "I",
                            InspectionTypeCode = m["InspectionTypeCode"].ToString(),
                            TemplateNo = m["TemplateNo"].ToString(),
                            TemplateName = m["TemplateName"].ToString(),
                            StatusOption = m["StatusOption"].ToString(),
                            PhotoRequirement = GF.GetString(m["PhotoRequirement"]),
                            SummarySampleText = GF.GetString(m["SummarySampleText"]),
                        IsSummaryRequired = m["VersionIsSummaryRequired"] == DBNull.Value || Convert.ToBoolean(m["VersionIsSummaryRequired"]),
                            IsFollowUpRequired = m["VersionIsFollowUpRequired"] == DBNull.Value || Convert.ToBoolean(m["VersionIsFollowUpRequired"]),
                            IsRemark1Required = Convert.ToBoolean(m["VersionIsRemark1Required"]),
                            Remark1Text = GF.GetString(m["VersionRemark1Text"]),
                            IsRemark2Required = Convert.ToBoolean(m["VersionIsRemark2Required"]),
                            Remark2Text = GF.GetString(m["VersionRemark2Text"]),
                            RemarkRequiredOptions = String.IsNullOrWhiteSpace(GF.GetString(m["VersionRemarkRequiredOptions"])) ? new string[0] : GF.GetString(m["VersionRemarkRequiredOptions"]).Split(';'),
                            sections = sections
                        };
                    }
                    result.Add(record);
                }
                return new { success = true, data = result };
            }
        }


        [WebMethod(EnableSession = true)]
        public static object GenerateReport(
            long[] inspectionIds,
            string employeeId,
            string companyId,
            string locationId)
        {
            try
            {
                // Never trust the employee identity supplied by the browser.
                employeeId = GFC.RequireMenuEmployee("20022");

                // Reuse the existing server-side authorization and single-type validation.
                DataTable authorized = GetAuthorizedInspectionSelection(
                    inspectionIds, companyId, locationId);

                if (authorized == null || authorized.Rows.Count == 0)
                    throw new InvalidOperationException(
                        "Tidak ada inspeksi yang dapat dibuatkan report.");

                DataTable selectedInspections = new DataTable();
                selectedInspections.Columns.Add("InspectionID", typeof(long));

                foreach (DataRow row in authorized.Rows)
                    selectedInspections.Rows.Add(Convert.ToInt64(row["InspectionID"]));

                // Pass the scope validated by GetAuthorizedInspectionSelection.
                // This WebMethod has no dependable Page.Master scope.
                var report = R_Report.GenerateInspectionXlsx(
                    selectedInspections, companyId, locationId, employeeId);

                if (report == null ||
                    !report.Success ||
                    String.IsNullOrWhiteSpace(report.StoragePath) ||
                    !File.Exists(report.StoragePath))
                {
                    throw new InvalidOperationException(
                        report != null && !String.IsNullOrWhiteSpace(report.Message)
                            ? report.Message
                            : "Gagal membuat file Excel.");
                }

                string token = Guid.NewGuid().ToString("N");
                HttpContext.Current.Session["InspectionReport_" + token] = report.StoragePath;
                HttpContext.Current.Session["InspectionReportName_" + token] = report.FileName;

                string downloadUrl = VirtualPathUtility.ToAbsolute(
                    "~/Secure/inspection.aspx?download=" + token);

                return new
                {
                    success = true,
                    status = "SUCCESS",
                    fileName = report.FileName,
                    filePath = downloadUrl,
                    message = "Report berhasil dibuat."
                };
            }
            catch (Exception ex)
            {
                System.Diagnostics.Trace.TraceError("GenerateReport: " + ex);
                return new
                {
                    success = false,
                    status = "FAILED",
                    fileName = "",
                    filePath = "",
                    message = HttpContext.Current != null &&
                              HttpContext.Current.IsDebuggingEnabled
                        ? ex.GetBaseException().Message
                        : "Gagal membuat preview report."
                };
            }
        }

        private void DownloadInspectionReport(string token)
        {
            if (token.Length != 32 || !token.All(Uri.IsHexDigit))
                throw new HttpException(400, "Invalid download token.");

            string pathKey = "InspectionReport_" + token;
            string nameKey = "InspectionReportName_" + token;
            string filePath = Convert.ToString(Session[pathKey]);
            string fileName = Convert.ToString(Session[nameKey]);

            if (String.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath))
                throw new HttpException(404,
                    "File report tidak ditemukan atau session download sudah berakhir.");

            fileName = String.IsNullOrWhiteSpace(fileName)
                ? "Inspection_Report.xlsx"
                : Path.GetFileName(fileName);

            // A download token is valid for one request only.
            Session.Remove(pathKey);
            Session.Remove(nameKey);

            Response.Clear();
            Response.Buffer = true;
            Response.ContentType =
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
            Response.AddHeader("Content-Disposition",
                "attachment; filename=\"" + fileName.Replace("\"", "") + "\"");
            Response.AddHeader("Content-Length",
                new FileInfo(filePath).Length.ToString(CultureInfo.InvariantCulture));
            Response.TransmitFile(filePath);
            Response.Flush();
            HttpContext.Current.ApplicationInstance.CompleteRequest();
        }

        // Server-side authorization and one-InspectionType validation for selected transactions.
        public static DataTable GetAuthorizedInspectionSelection(long[] inspectionIds, string companyId, string locationId)
        {
            string employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (inspectionIds == null || inspectionIds.Length == 0)
                throw new HttpException(400, "Pilih minimal satu transaksi inspeksi.");
            inspectionIds = inspectionIds.Where(id => id > 0).Distinct().ToArray();
            if (inspectionIds.Length == 0 || inspectionIds.Length > 200)
                throw new HttpException(400, "Jumlah transaksi tidak valid. Maksimal 200 transaksi.");

            List<SqlParameter> parameters = new List<SqlParameter>();
            parameters.Add(new SqlParameter("@EmployeeID", employeeId));
            parameters.Add(new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)));
            parameters.Add(new SqlParameter("@CompanyID", companyId));
            parameters.Add(new SqlParameter("@LocationID", locationId));
            List<string> idParameters = new List<string>();
            for (int i = 0; i < inspectionIds.Length; i++)
            {
                string name = "@InspectionID" + i.ToString(CultureInfo.InvariantCulture);
                idParameters.Add(name);
                parameters.Add(new SqlParameter(name, inspectionIds[i]));
            }

            string sql = @"
SELECT I.InspectionID, I.InspectionNo, I.CompanyID, I.LocationID,
       I.InspectionTypeCode, I.InspectionTypeName, I.InspectionTypeDetailCode,
       I.InspectionTypeDetailName, I.InspectionDate, I.TemplateNo, I.TemplateName,
       I.OwnerEmployeeID, I.Status, I.IsApprove
FROM dbo.PIP_T_Inspection I
JOIN dbo.SysWebUser SU ON SU.EmployeeID=@EmployeeID AND SU.IsActive=1
JOIN dbo.PIP_M_CheckListWOPM T ON T.IDTemplate=I.IDTemplate AND T.SectionID=I.SectionID
WHERE I.InspectionID IN (" + String.Join(",", idParameters.ToArray()) + @")
  AND I.CompanyID=@CompanyID AND I.LocationID=@LocationID
  AND ISNULL(I.IsActive,1)=1
  AND ISNULL(T.TemplateType,'W')='I'
  AND (ISNULL(T.CompanyScope,'S')='A'
       OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
  AND (ISNULL(T.EmployeeList,'')=''
       OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
  AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S WHERE S.val=I.SectionID)
  AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') M WHERE M.MenuID='20022')
  AND (
       EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
               WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                 AND C.CompanyID=I.CompanyID AND C.LocationID=I.LocationID)
       OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                  WHERE L.CompanyID=I.CompanyID AND L.LocationID=I.LocationID)
  )
ORDER BY I.InspectionID";
            using (var br = new WAL.BR.CF())
            {
                DataTable rows = br.EQueryP(sql, parameters.ToArray());
                if (rows == null || rows.Rows.Count != inspectionIds.Length)
                    throw new HttpException(403, "Satu atau lebih transaksi tidak ditemukan atau berada di luar hak akses Supervisor.");
                List<string> types = rows.AsEnumerable()
                    .Select(row => Convert.ToString(row["InspectionTypeCode"]).Trim())
                    .Distinct(StringComparer.OrdinalIgnoreCase).ToList();
                if (types.Count != 1 || String.IsNullOrWhiteSpace(types[0]))
                    throw new HttpException(400, "Inspection Type berbeda. Pilih transaksi dengan Inspection Type yang sama saja.");
                return rows;
            }
        }

        [WebMethod]
        public static object ProcessInspectionApprovalBatch(long[] inspectionIds, string action,
            string employeeId, string companyId, string locationId, string remark)
        {
            employeeId = GFC.RequireMenuEmployee("20022");
            if (!String.Equals(action, "APPROVE", StringComparison.OrdinalIgnoreCase) &&
                !String.Equals(action, "VOID", StringComparison.OrdinalIgnoreCase))
                throw new HttpException(400, "Invalid inspection action.");
            if (String.Equals(action, "VOID", StringComparison.OrdinalIgnoreCase) &&
                String.IsNullOrWhiteSpace(remark))
                throw new HttpException(400, "Reason for void is required.");

            DataTable selected = GetAuthorizedInspectionSelection(inspectionIds, companyId, locationId);
            List<object> results = new List<object>();
            foreach (DataRow row in selected.Rows)
                results.Add(ProcessInspectionApproval(Convert.ToInt64(row["InspectionID"]),
                    action, employeeId, companyId, locationId, remark));
            return new { success = true, count = results.Count, results = results };
        }

        [WebMethod]
        public static object ProcessInspectionApproval(long inspectionId, string action, string employeeId,
            string companyId, string locationId, string remark)
        {
            employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (String.IsNullOrWhiteSpace(employeeId))
                throw new HttpException(403, "Supervisor identity is required.");
            if (!String.Equals(action, "APPROVE", StringComparison.OrdinalIgnoreCase) &&
                !String.Equals(action, "VOID", StringComparison.OrdinalIgnoreCase))
                throw new HttpException(400, "Invalid inspection action.");
            if (String.Equals(action, "VOID", StringComparison.OrdinalIgnoreCase) &&
                String.IsNullOrWhiteSpace(remark))
                throw new HttpException(400, "Reason for void is required.");

            using (var br = new WAL.BR.CF())
            {
                DataTable authorized = br.EQueryP(@"
SELECT TOP 1 1
FROM dbo.PIP_T_Inspection I
JOIN dbo.SysWebUser SU ON SU.EmployeeID=@EmployeeID AND SU.IsActive=1
LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
JOIN dbo.PIP_M_CheckListWOPM T ON T.IDTemplate=I.IDTemplate AND T.SectionID=I.SectionID
WHERE I.InspectionID=@InspectionID
  AND I.CompanyID=@CompanyID AND I.LocationID=@LocationID
  AND ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')<>'LIGHTNING'
  AND ISNULL(T.TemplateType,'W')='I' 
  AND (ISNULL(T.CompanyScope,'S')='A'
       OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
  AND (ISNULL(T.EmployeeList,'')=''
       OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
  AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S WHERE S.val=I.SectionID)
  AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') M WHERE M.MenuID='20022')
",
                    new SqlParameter[] {
                        new SqlParameter("@InspectionID", inspectionId),
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId)
                    });
                if (authorized == null || authorized.Rows.Count == 0)
                    throw new HttpException(403, "Inspection is outside the supervisor's authorized section, template, or company/location scope.");

                DataTable saved = br.EQueryP("spUTL_PIP_T_Inspection_Approval", new SqlParameter[] {
                    new SqlParameter("@p_InspectionID", inspectionId),
                    new SqlParameter("@p_Action", action.ToUpperInvariant()),
                    new SqlParameter("@p_EmployeeID", employeeId),
                    new SqlParameter("@p_CompanyID", companyId),
                    new SqlParameter("@p_LocationID", locationId),
                    new SqlParameter("@p_Remark", String.IsNullOrEmpty(remark) ? "" : remark)
                }, true, true);
                string followUpWONo = saved.Rows.Count > 0 && saved.Columns.Contains("FollowUpWONo") && saved.Rows[0]["FollowUpWONo"] != DBNull.Value
                    ? Convert.ToString(saved.Rows[0]["FollowUpWONo"]) : "";
                return new { success = true, action = action.ToUpperInvariant(), inspectionId = inspectionId, followUpWONo = followUpWONo };
            }
        }

        private static object DispatchInspectionEmailOutbox(int batchSize)
        {
            string host = (System.Configuration.ConfigurationManager.AppSettings["smtpHost"] ?? "").Trim();
            string fromAddress = (System.Configuration.ConfigurationManager.AppSettings["smtpFrom"] ?? "").Trim();
            string smtpUser = (System.Configuration.ConfigurationManager.AppSettings["smtpUser"] ?? "").Trim();
            string smtpPassword = System.Configuration.ConfigurationManager.AppSettings["smtpPassword"] ?? "";
            bool useSsl = String.Equals(System.Configuration.ConfigurationManager.AppSettings["smtpUseSSL"], "true", StringComparison.OrdinalIgnoreCase);
            int port;
            if (!Int32.TryParse(System.Configuration.ConfigurationManager.AppSettings["smtpPort"], out port)) port = 25;

            using (var br = new WAL.BR.CF())
            {
                if (host == "" || fromAddress == "")
                {
                    br.EQueryP(@"
UPDATE dbo.PIP_T_InspectionEmailOutbox
SET LastError='SMTP host or smtpFrom is not configured. Configure Web.config before email dispatch.',
    NextAttemptDate=DATEADD(MINUTE,15,GETDATE())
WHERE DeliveryStatus='PENDING' AND NextAttemptDate<=GETDATE();", new SqlParameter[0], true);
                    DataTable pendingRows = br.EQueryP("SELECT COUNT(1) PendingCount FROM dbo.PIP_T_InspectionEmailOutbox WHERE DeliveryStatus IN ('PENDING','FAILED')", new SqlParameter[0]);
                    int pending = pendingRows.Rows.Count > 0 ? Convert.ToInt32(pendingRows.Rows[0]["PendingCount"]) : 0;
                    return new { attempted = 0, sent = 0, failed = 0, pending = pending, configured = false };
                }

                DataTable queue = br.EQueryP(@"
;WITH EmailQueue AS
(
    SELECT TOP (@BatchSize) *
    FROM dbo.PIP_T_InspectionEmailOutbox WITH (UPDLOCK,READPAST,ROWLOCK)
    WHERE DeliveryStatus IN ('PENDING','FAILED')
      AND NextAttemptDate<=GETDATE()
      AND AttemptCount<5
    ORDER BY EmailOutboxID
)
UPDATE EmailQueue
SET DeliveryStatus='SENDING',AttemptCount=AttemptCount+1
OUTPUT inserted.EmailOutboxID,inserted.RecipientEmail,inserted.EmailSubject,
       inserted.HtmlBody,inserted.PlainBody,inserted.AttemptCount;",
                    new SqlParameter[] { new SqlParameter("@BatchSize", Math.Max(1, Math.Min(batchSize, 50))) }, true, true);

                int sent = 0, failed = 0;
                foreach (DataRow row in queue.Rows)
                {
                    long outboxId = Convert.ToInt64(row["EmailOutboxID"]);
                    try
                    {
                        using (var message = new MailMessage())
                        {
                            message.From = new MailAddress(fromAddress, "INSPEC");
                            message.To.Add(new MailAddress(Convert.ToString(row["RecipientEmail"])));
                            message.Subject = Convert.ToString(row["EmailSubject"]);
                            message.SubjectEncoding = Encoding.UTF8;
                            message.BodyEncoding = Encoding.UTF8;
                            message.IsBodyHtml = true;
                            message.Body = Convert.ToString(row["HtmlBody"]);
                            if (row["PlainBody"] != DBNull.Value && !String.IsNullOrWhiteSpace(Convert.ToString(row["PlainBody"])))
                                message.AlternateViews.Add(AlternateView.CreateAlternateViewFromString(
                                    Convert.ToString(row["PlainBody"]), Encoding.UTF8, "text/plain"));

                            using (var smtp = new SmtpClient(host, port))
                            {
                                smtp.EnableSsl = useSsl;
                                smtp.Timeout = 20000;
                                if (!String.IsNullOrWhiteSpace(smtpUser))
                                    smtp.Credentials = new System.Net.NetworkCredential(smtpUser, smtpPassword);
                                else
                                    smtp.UseDefaultCredentials = true;
                                smtp.Send(message);
                            }
                        }
                        br.EQueryP(@"UPDATE dbo.PIP_T_InspectionEmailOutbox
SET DeliveryStatus='SENT',SentDate=GETDATE(),LastError=NULL
WHERE EmailOutboxID=@ID AND DeliveryStatus='SENDING'",
                            new SqlParameter[] { new SqlParameter("@ID", outboxId) }, true);
                        sent++;
                    }
                    catch (Exception ex)
                    {
                        string error = ex.Message ?? "SMTP send failed.";
                        if (error.Length > 1900) error = error.Substring(0, 1900);
                        br.EQueryP(@"
UPDATE dbo.PIP_T_InspectionEmailOutbox
SET DeliveryStatus='FAILED',LastError=@Error,
    NextAttemptDate=DATEADD(MINUTE,
        CASE WHEN AttemptCount=1 THEN 5 WHEN AttemptCount=2 THEN 10
             WHEN AttemptCount=3 THEN 20 WHEN AttemptCount=4 THEN 40 ELSE 60 END,GETDATE())
WHERE EmailOutboxID=@ID AND DeliveryStatus='SENDING'",
                            new SqlParameter[] {
                                new SqlParameter("@Error", error),
                                new SqlParameter("@ID", outboxId)
                            }, true);
                        failed++;
                    }
                }
                DataTable pending = br.EQueryP("SELECT COUNT(1) PendingCount FROM dbo.PIP_T_InspectionEmailOutbox WHERE DeliveryStatus IN ('PENDING','FAILED','SENDING')", new SqlParameter[0]);
                return new {
                    attempted = queue.Rows.Count,
                    sent = sent,
                    failed = failed,
                    pending = pending.Rows.Count > 0 ? Convert.ToInt32(pending.Rows[0]["PendingCount"]) : 0,
                    configured = true
                };
            }
        }

        private static string TokenString(JObject obj, string name)
        {
            JToken token = obj == null ? null : obj[name];
            return token == null || token.Type == JTokenType.Null ? "" : token.ToString();
        }

        private static int TokenInt(JObject obj, string name)
        {
            int value;
            return Int32.TryParse(TokenString(obj, name), out value) ? value : 0;
        }

        private static long TokenLong(JObject obj, string name)
        {
            long value;
            return Int64.TryParse(TokenString(obj, name), NumberStyles.Integer, CultureInfo.InvariantCulture, out value) ? value : 0L;
        }

        private static bool TokenBool(JObject obj, string name)
        {
            bool value;
            return Boolean.TryParse(TokenString(obj, name), out value) && value;
        }

        private static string ResolveInspectionMapUrl(string storedPath, string companyId, string locationId)
        {
            string path = (storedPath ?? "").Trim();
            if (path == "") return "";

            // Accept legacy absolute URLs/relative paths, but always rebuild
            // the target from this request's host and deployed INSPEC app name.
            Uri oldUrl;
            if (Uri.TryCreate(path, UriKind.Absolute, out oldUrl) &&
                (oldUrl.Scheme == Uri.UriSchemeHttp || oldUrl.Scheme == Uri.UriSchemeHttps))
                path = oldUrl.AbsolutePath;

            path = path.Replace('\\', '/');
            int slash = path.LastIndexOf('/');
            string fileName = slash >= 0 ? path.Substring(slash + 1) : path;
            int query = fileName.IndexOf('?');
            if (query >= 0) fileName = fileName.Substring(0, query);
            int fragment = fileName.IndexOf('#');
            if (fragment >= 0) fileName = fileName.Substring(0, fragment);
            if (fileName == "") return "";

            string appPath = HttpContext.Current.Request.ApplicationPath ?? "";
            string root = appPath.Trim('/').ToUpperInvariant().Replace("INSPEC", "PIP");
            if (root == "") root = "PIP";
            string companyLocation = SafeInspectionMapPathPart(companyId) + "_" +
                SafeInspectionMapPathPart(locationId);
            string relativeUrl = "/ToolsLib/" + root + "/PIP_M_InspectionMap/" +
                companyLocation + "/" + HttpUtility.UrlPathEncode(fileName);
            return HttpContext.Current.Request.Url.GetLeftPart(UriPartial.Authority) + relativeUrl;
        }

        private static string SafeInspectionMapPathPart(string value)
        {
            string result = new string((value ?? "").Where(
                c => Char.IsLetterOrDigit(c) || c == '-' || c == '_').ToArray());
            return result == "" ? "_" : result;
        }

        private static object DbString(string value)
        {
            return value ?? "";
        }

        private static string Limit(string value, int maxLength)
        {
            value = value ?? "";
            return value.Length <= maxLength ? value : value.Substring(0, maxLength);
        }

        private static DateTime ParseDate(string value, DateTime fallback)
        {
            DateTime parsed;
            return DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out parsed)
                ? parsed : fallback;
        }

        private static object ParseNullableDate(string value)
        {
            if (String.IsNullOrWhiteSpace(value)) return new DateTime(1900, 1, 1);
            DateTime parsed;
            if (!DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out parsed))
                return new DateTime(1900, 1, 1);
            return parsed;
        }
    }
}

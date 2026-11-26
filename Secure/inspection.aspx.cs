using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Configuration;
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
        private static bool IsInspectionAdministrator(string employeeId)
        {
            if (String.IsNullOrWhiteSpace(employeeId)) return false;
            using (var br = new WAL.BR.CF())
            {
                DataTable admin = br.EQueryP(@"
SELECT TOP 1 1
FROM dbo.SysWebUser SU
JOIN dbo.SysWebUserUserGroup UG ON UG.UserID=SU.UserID
WHERE SU.EmployeeID=@UserID
  AND SU.IsActive=1
  AND UG.UserGroupID='administrator'",
                    new SqlParameter[] { new SqlParameter("@UserID", employeeId) });
                return admin != null && admin.Rows.Count > 0;
            }
        }

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
            {
                string currentEmployee = GFC.CurrentEmployeeID();
                if (!IsInspectionAdministrator(currentEmployee))
                    GFC.RequireMenuEmployee("20022");
            }
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
                    string submittedMode = TokenString(record, "InspectionMode").Trim().ToUpperInvariant();
                    string inspectionMode = submittedMode;
                    if (inspectionMode == "") inspectionMode = "STANDARD";
                    string scheduleSelectionMode = TokenString(record, "ScheduleSelectionMode").Trim().ToUpperInvariant();
                    if (scheduleSelectionMode == "") scheduleSelectionMode = "PARAM";
                    bool isLightningInspection = inspectionMode == "BATCH" && scheduleSelectionMode == "INSPECT";
                    bool isBatchInspection = inspectionMode == "BATCH";
                    string inspectionPointMode = TokenString(record, "InspectionPointMode").Trim().ToUpperInvariant();
                    bool isDynamicPoints = inspectionPointMode == "DYNAMIC";
                    if (inspectionMode != "STANDARD" && inspectionMode != "BATCH")
                        throw new Exception("InspectionMode must be STANDARD or BATCH.");
                    if (inspectionMode == "STANDARD" && inspectionPointMode != "")
                        throw new Exception("STANDARD inspection must not define InspectionPointMode.");
                    if (isBatchInspection && inspectionPointMode != "MAP" && inspectionPointMode != "DYNAMIC")
                        throw new Exception("BATCH inspection requires InspectionPointMode MAP or DYNAMIC.");
                    if (isDynamicPoints && (!isBatchInspection || scheduleSelectionMode != "PARAM"))
                        throw new Exception("Dynamic inspection points require BATCH / PARAM.");
                    if (status != "DONE")
                        throw new Exception("Only completed inspections (DONE) can be synced to SQL Server.");

                    GFC.RequireCompanyLocation(userId, TokenString(record, "CompanyID"), TokenString(record, "LocationID"));
                    string recordOwner = TokenString(record, "OwnerEmployeeID");
                    if (String.IsNullOrWhiteSpace(recordOwner) ||
                        !String.Equals(recordOwner, userId, StringComparison.OrdinalIgnoreCase))
                        throw new Exception("This offline inspection belongs to another employee. No data was uploaded.");

                    /* Reconcile an interrupted client confirmation before validating/re-uploading
                       checklist and photo payloads. A submitted, active, non-void server row with
                       the same ClientInspectionID is already the committed transaction. Returning
                       its identifiers as success lets the client persist SYNCED in IndexedDB. */
                    string recordCompanyId = Limit(TokenString(record, "CompanyID"), 10);
                    string recordLocationId = Limit(TokenString(record, "LocationID"), 3);
                    string recordSectionId = Limit(TokenString(record, "SectionID"), 10);
                    using (var reconcileBr = new WAL.BR.CF())
                    {
                        syncStage = "reconcile existing submitted inspection";
                        DataTable reconciledRows = reconcileBr.EQueryP(@"
SELECT TOP 1 InspectionID, InspectionNo, CompanyID, LocationID, SectionID,
       OwnerEmployeeID, Status, IsSubmitted, IsActive,
       ReasonVoid, ReasonVoid1, ReasonVoid2
FROM dbo.PIP_T_Inspection
WHERE ClientInspectionID=@ClientInspectionID",
                            new SqlParameter[] { new SqlParameter("@ClientInspectionID", Limit(clientId, 36)) });
                        if (reconciledRows == null)
                            throw new Exception("Could not verify the existing inspection synchronization state.");

                        if (reconciledRows.Rows.Count > 0)
                        {
                            DataRow serverRecord = reconciledRows.Rows[0];
                            bool sameOwner = String.Equals(Convert.ToString(serverRecord["OwnerEmployeeID"]),
                                userId, StringComparison.OrdinalIgnoreCase);
                            bool sameCompany = String.Equals(Convert.ToString(serverRecord["CompanyID"]),
                                recordCompanyId, StringComparison.OrdinalIgnoreCase);
                            bool sameLocation = String.Equals(Convert.ToString(serverRecord["LocationID"]),
                                recordLocationId, StringComparison.OrdinalIgnoreCase);
                            bool sameSection = String.Equals(Convert.ToString(serverRecord["SectionID"]),
                                recordSectionId, StringComparison.OrdinalIgnoreCase);
                            if (!sameOwner || !sameCompany || !sameLocation || !sameSection)
                                throw new HttpException(403, "The existing server inspection does not match this employee and company/location/section.");

                            bool serverIsActive = serverRecord["IsActive"] == DBNull.Value ||
                                Convert.ToBoolean(serverRecord["IsActive"]);
                            bool serverIsSubmitted = serverRecord["IsSubmitted"] != DBNull.Value &&
                                Convert.ToBoolean(serverRecord["IsSubmitted"]);
                            bool serverIsDone = String.Equals(Convert.ToString(serverRecord["Status"]),
                                "DONE", StringComparison.OrdinalIgnoreCase);
                            bool serverHasVoidReason =
                                !String.IsNullOrWhiteSpace(Convert.ToString(serverRecord["ReasonVoid"])) ||
                                !String.IsNullOrWhiteSpace(Convert.ToString(serverRecord["ReasonVoid1"])) ||
                                !String.IsNullOrWhiteSpace(Convert.ToString(serverRecord["ReasonVoid2"]));

                            if (serverIsActive && serverIsDone && serverIsSubmitted && !serverHasVoidReason)
                            {
                                outcomes.Add(new
                                {
                                    ClientInspectionID = clientId,
                                    success = true,
                                    InspectionID = Convert.ToInt64(serverRecord["InspectionID"]),
                                    InspectionNo = Convert.ToString(serverRecord["InspectionNo"]),
                                    message = ""
                                });
                                continue;
                            }
                        }
                    }

                    syncStage = "build checklist data";
                    // dbo.Type_N_Tbl_C13: C1=IDItem, C2=ItemLabel, C3=ItemType,
                    // C4=Value, C5=Remark1, C6=IsAnomali, C7=DisplayOrder, C8=Remark2; C9-C13 unused.
                    DataTable items = new DataTable();
                    for (int i = 1; i <= 13; i++)
                        items.Columns.Add("C" + i, typeof(string));

                    // dbo.Type_N_Tbl_C5: C1=IDItem, C2=IDRepeat, C3=Value, C4=ObjectIndex.
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
                        var dynamicPointCodes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                        var dynamicPointNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                        var schedulePointIDs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                        int dynamicPointSequence = 0;
                        foreach (JObject point in pointArray.OfType<JObject>())
                        {
                            string clientPointID = Limit(TokenString(point, "ClientPointID"), 36);
                            long masterPointID = TokenLong(point, "InspectionPointID");
                            string pointStatus = TokenString(point, "Status").ToUpperInvariant();
                            string pointScheduleTime = isLightningInspection ? TokenString(point, "ScheduleTime").Trim() : "";
                            string pointCode = Limit(TokenString(point, "PointCode").Trim(), 100);
                            string pointName = Limit(TokenString(point, "PointName").Trim(), 200);
                            if (isDynamicPoints)
                            {
                                dynamicPointSequence++;
                                if (pointCode == "")
                                    pointCode = "M" + dynamicPointSequence.ToString("000", CultureInfo.InvariantCulture);
                                if (pointName == "")
                                    pointName = TokenString(point, "Nopol").Trim();
                                if (pointName == "")
                                    throw new Exception("Nopol / PointName wajib diisi untuk setiap kendaraan Motor.");
                                pointName = pointName.ToUpperInvariant();
                                if (masterPointID > 0)
                                    throw new Exception("Dynamic Motor point must not reference a master InspectionPointID.");
                            }
                            else
                            {
                                if (masterPointID <= 0)
                                    throw new Exception("Master-map InspectionPointID is required.");
                                if (pointCode == "") pointCode = "P" + masterPointID.ToString(CultureInfo.InvariantCulture);
                                if (pointName == "") pointName = pointCode;
                            }
                            bool duplicatePoint = isDynamicPoints
                                ? (!dynamicPointCodes.Add(pointCode) || !dynamicPointNames.Add(pointName))
                                : (isLightningInspection
                                    ? !schedulePointIDs.Add(pointScheduleTime + "|" + masterPointID.ToString(CultureInfo.InvariantCulture))
                                    : !masterPointIDs.Add(masterPointID));
                            if (String.IsNullOrWhiteSpace(clientPointID) ||
                                !clientPointIDs.Add(clientPointID) || duplicatePoint)
                                throw new Exception("BATCH/LIGHTNING Inspection Point identity is invalid or duplicated.");
                            if (pointStatus != "DONE" && pointStatus != "ABNORMAL")
                                throw new Exception("Every selected BATCH Inspection Point must be DONE or ABNORMAL.");

                            DataRow pointRow = batchPoints.NewRow();
                            pointRow["C1"] = clientPointID;
                            pointRow["C2"] = !isDynamicPoints ? masterPointID.ToString(CultureInfo.InvariantCulture) : "";
                            pointRow["C3"] = TokenString(point, "InspectionDateTime");
                            pointRow["C4"] = pointStatus;
                            pointRow["C5"] = DbString(Limit(TokenString(point, "AbnormalRemark").Trim(), 500));
                            pointRow["C6"] = TokenString(point, "PointCondition").ToUpperInvariant();
                            pointRow["C7"] = pointScheduleTime;
                            pointRow["C8"] = "";
                            pointRow["C9"] = pointCode;
                            pointRow["C10"] = pointName;
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
                    string inspectionTypeCode = Limit(TokenString(record, "InspectionTypeCode"), 10);
                    string inspectionTypeDetailCode = Limit(TokenString(record, "InspectionTypeDetailCode"), 20);
                    string tenantId = Limit(TokenString(record, "TenantID"), 10).Trim();
                    string suiteNo = Limit(TokenString(record, "SuiteNo"), 10).Trim();
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
                        syncStage = "validate inspection type configuration";
                        DataTable inspectionTypeConfig = br.EQueryP(@"
SELECT ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') InspectionMode,
       ISNULL(NULLIF(IT.InspectionPointMode,''),'') InspectionPointMode,
       ISNULL(NULLIF(IT.ScheduleSelectionMode,''),'PARAM') ScheduleSelectionMode
 FROM dbo.PIP_M_InspectionType IT
WHERE IT.InspectionTypeCode=@InspectionTypeCode
  AND IT.SectionID=@SectionID
  AND IT.IsActive=1",
                            new SqlParameter[] {
                                new SqlParameter("@InspectionTypeCode", inspectionTypeCode),
                                new SqlParameter("@SectionID", sectionId)
                            });
                        if (inspectionTypeConfig == null || inspectionTypeConfig.Rows.Count != 1)
                            throw new Exception("Inspection Type tidak ditemukan atau sudah tidak aktif.");

                        DataRow typeConfigRow = inspectionTypeConfig.Rows[0];
                        string serverInspectionMode = Convert.ToString(typeConfigRow["InspectionMode"]).Trim().ToUpperInvariant();
                        string serverInspectionPointMode = Convert.ToString(typeConfigRow["InspectionPointMode"]).Trim().ToUpperInvariant();
                        string serverScheduleSelectionMode = Convert.ToString(typeConfigRow["ScheduleSelectionMode"]).Trim().ToUpperInvariant();

                        if (serverInspectionMode != inspectionMode)
                            throw new Exception("Inspection Mode pada perangkat tidak sesuai dengan konfigurasi Master Inspection Type.");
                        if (serverInspectionPointMode != inspectionPointMode)
                            throw new Exception("Inspection Point Mode pada perangkat tidak sesuai dengan konfigurasi Master Inspection Type.");
                        if (serverScheduleSelectionMode != scheduleSelectionMode)
                            throw new Exception("Schedule Selection pada perangkat tidak sesuai dengan konfigurasi Master Inspection Type.");
                        if (serverInspectionMode == "STANDARD" && serverInspectionPointMode != "")
                            throw new Exception("Konfigurasi Standard tidak boleh memiliki InspectionPointMode.");
                        if (serverInspectionMode == "BATCH" && serverInspectionPointMode == "")
                            throw new Exception("Konfigurasi BATCH harus memiliki InspectionPointMode MAP atau DYNAMIC.");
                        if (serverInspectionPointMode == "DYNAMIC" &&
                            (serverInspectionMode != "BATCH" || serverScheduleSelectionMode != "PARAM"))
                            throw new Exception("Dynamic Motor harus menggunakan BATCH / DYNAMIC / PARAM.");
                        if (serverScheduleSelectionMode == "INSPECT" &&
                            (serverInspectionMode != "BATCH" || serverInspectionPointMode != "MAP"))
                            throw new Exception("Lightning daily harus menggunakan BATCH / MAP / INSPECT.");

                        record["_ServerInspectionMode"] = serverInspectionMode;
                        record["_ServerInspectionPointMode"] = serverInspectionPointMode;
                        record["_ServerScheduleSelectionMode"] = serverScheduleSelectionMode;

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

                        DataTable tenantDetail = br.EQueryP(@"
SELECT DB_NAME() AS ServerDatabaseName, ISNULL(IsTenantInspection,0) IsTenantInspection
FROM dbo.PIP_M_InspectionTypeDetail
WHERE InspectionTypeCode=@InspectionTypeCode
  AND InspectionTypeDetailCode=@InspectionTypeDetailCode
  AND CompanyID=@CompanyID AND LocationID=@LocationID AND IsActive=1",
                            new SqlParameter[] {
                                new SqlParameter("@InspectionTypeCode", inspectionTypeCode),
                                new SqlParameter("@InspectionTypeDetailCode", inspectionTypeDetailCode),
                                new SqlParameter("@CompanyID", companyId),
                                new SqlParameter("@LocationID", locationId)
                            });
                        if (tenantDetail == null || tenantDetail.Rows.Count == 0)
                            throw new Exception("Inspection Type Detail tidak ditemukan atau sudah tidak aktif.");
                        bool isTenantInspection = Convert.ToBoolean(tenantDetail.Rows[0]["IsTenantInspection"]);
                        record["_ServerDatabaseName"] = Convert.ToString(tenantDetail.Rows[0]["ServerDatabaseName"]);
                        record["_ServerIsTenantInspection"] = isTenantInspection ? "1" : "0";
                        if (isTenantInspection)
                        {
                            if (String.IsNullOrWhiteSpace(tenantId) || String.IsNullOrWhiteSpace(suiteNo))
                                throw new Exception("Tenant ID dan Suite No wajib dipilih untuk Inspection Detail ini.");
                            DataTable validTenantSuite = br.EQueryP(@"
SELECT TOP 1 G.TenantID, A.SuiteNo
FROM dbo.THD_M_GeneralInformation G
JOIN dbo.THD_M_AgreementInformation A
  ON A.CompanyID=G.CompanyID AND A.LocationID=G.LocationID AND A.TenantID=G.TenantID
WHERE G.CompanyID=@CompanyID AND G.LocationID=@LocationID AND G.TenantID=@TenantID
  AND (G.IsStoreClosed=0 OR G.DateClosed>GETDATE())
  AND A.SuiteNo=@SuiteNo AND A.LeaseTermDate>=GETDATE()",
                                new SqlParameter[] {
                                    new SqlParameter("@CompanyID", companyId),
                                    new SqlParameter("@LocationID", locationId),
                                    new SqlParameter("@TenantID", tenantId),
                                    new SqlParameter("@SuiteNo", suiteNo)
                                });
                            if (validTenantSuite == null || validTenantSuite.Rows.Count == 0)
                                throw new Exception("Tenant ID / Suite No tidak aktif atau tidak sesuai dengan master lease di lokasi ini.");
                        }
                        else
                        {
                            tenantId = "";
                            suiteNo = "";
                        }

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
SELECT F.IDItem,F.IDRepeat,F.FieldLabel,F.FieldType,F.OptionList,F.MinValue,F.MaxValue,F.MinInclusive,F.MaxInclusive,F.IsRequired
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

                                if (isDynamicPoints)
                                {
                                    string dynamicPointName = TokenString(versionPoint, "PointName").Trim();
                                    DataRow nopolTemplateItem = null;
                                    foreach (DataRow candidate in versionItems.Rows)
                                    {
                                        string candidateType = Convert.ToString(candidate["ItemType"]).ToUpperInvariant();
                                        string candidateLabel = Convert.ToString(candidate["ItemLabel"]).Trim().ToLowerInvariant();
                                        if (candidateType == "TEXT" &&
                                            (candidateLabel.Contains("nopol") || candidateLabel.Contains("no pol") || candidateLabel.Contains("polisi") ||
                                             candidateLabel.Contains("plat") || candidateLabel.Contains("nomor polisi") ||
                                             candidateLabel.Contains("license")))
                                        {
                                            nopolTemplateItem = candidate;
                                            break;
                                        }
                                    }
                                    if (nopolTemplateItem == null)
                                        throw new Exception(pointPrefix + "Master Checklist Version Motor wajib memiliki item TEXT untuk Nopol.");
                                    int nopolItemId = Convert.ToInt32(nopolTemplateItem["IDItem"]);
                                    JObject nopolAnswer;
                                    string nopolValue = submittedItemsById.TryGetValue(nopolItemId, out nopolAnswer)
                                        ? TokenString(nopolAnswer, "Value").Trim() : "";
                                    if (dynamicPointName == "" || !String.Equals(dynamicPointName, nopolValue, StringComparison.OrdinalIgnoreCase))
                                        throw new Exception(pointPrefix + "Nilai item TEXT Nopol harus sama dengan PointName kendaraan.");
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
                                                if (!repeatFields.Any(f => String.Equals(Convert.ToString(f["IDRepeat"]), submittedField.Name, StringComparison.Ordinal)))
                                                    throw new Exception(pointPrefix + "Field REPEAT " + submittedField.Name + " tidak dikenal pada " + itemLabel + ".");
                                            foreach (DataRow field in repeatFields)
                                            {
                                                string repeatId = Convert.ToString(field["IDRepeat"]);
                                                string repeatFieldLabel = Convert.ToString(field["FieldLabel"]);
                                                JToken childValue = childValues == null ? null : childValues[repeatId];
                                                string childText = childValue == null || childValue.Type == JTokenType.Null ? "" : childValue.ToString().Trim();
                                                if (Convert.ToBoolean(field["IsRequired"]) && childText.Length == 0)
                                                    throw new Exception(pointPrefix + repeatFieldLabel + " pada " + itemLabel + " wajib diisi.");
                                                if (childText.Length == 0) continue;
                                                string fieldType = Convert.ToString(field["FieldType"]).ToUpperInvariant();
                                                if (fieldType == "OPTION")
                                                {
                                                    string options = Convert.ToString(field["OptionList"]);
                                                    if (String.IsNullOrWhiteSpace(options) || !options.Split(';').Any(x => String.Equals(x.Trim(), childText, StringComparison.OrdinalIgnoreCase)))
                                                        throw new Exception(pointPrefix + "Pilihan " + repeatFieldLabel + " pada " + itemLabel + " tidak valid.");
                                                }
                                                if (fieldType == "NUMBER" || fieldType == "RANGE")
                                                {
                                                    decimal numeric;
                                                    if (!Decimal.TryParse(childText, NumberStyles.Any, CultureInfo.InvariantCulture, out numeric))
                                                        throw new Exception(pointPrefix + repeatFieldLabel + " pada " + itemLabel + " harus berupa angka.");
                                                    bool minInclusive = field["MinInclusive"] == DBNull.Value || Convert.ToBoolean(field["MinInclusive"]);
                                                    bool maxInclusive = field["MaxInclusive"] == DBNull.Value || Convert.ToBoolean(field["MaxInclusive"]);
                                                    if (field["MinValue"] != DBNull.Value &&
                                                        (numeric < Convert.ToDecimal(field["MinValue"]) || (!minInclusive && numeric == Convert.ToDecimal(field["MinValue"]))))
                                                        throw new Exception(pointPrefix + repeatFieldLabel + " pada " + itemLabel + " di bawah atau tepat pada batas minimum eksklusif.");
                                                    if (field["MaxValue"] != DBNull.Value &&
                                                        (numeric > Convert.ToDecimal(field["MaxValue"]) || (!maxInclusive && numeric == Convert.ToDecimal(field["MaxValue"]))))
                                                        throw new Exception(pointPrefix + repeatFieldLabel + " pada " + itemLabel + " di atas atau tepat pada batas maksimum eksklusif.");
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
                            if (!isDynamicPoints)
                            {
                            syncStage = "validate batch map coverage";
                            JArray submittedPointArray = record["Points"] as JArray ?? new JArray();
                            var submittedPointIDs = new HashSet<long>();
                            foreach (JObject submittedPoint in submittedPointArray.OfType<JObject>())
                                submittedPointIDs.Add(TokenLong(submittedPoint, "InspectionPointID"));

                            DataTable coveragePoints = br.EQueryP(@"
SELECT P.InspectionPointID, M.MapID, ISNULL(M.RequireAllPoints,1) AS RequireAllPoints,
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
                            var submittedMapIDs = new HashSet<long>();
                            foreach (DataRow coveragePoint in coveragePoints.Rows)
                            {
                                long coveragePointID = Convert.ToInt64(coveragePoint["InspectionPointID"]);
                                if (submittedPointIDs.Contains(coveragePointID))
                                    submittedMapIDs.Add(Convert.ToInt64(coveragePoint["MapID"]));
                            }
                            if (submittedMapIDs.Count == 0)
                                throw new Exception("Inspection Point tidak termasuk master map aktif untuk Inspection Type dan Detail ini.");

                            var validMasterPointIDs = new HashSet<long>();
                            foreach (DataRow masterPoint in coveragePoints.Rows)
                            {
                                long mapID = Convert.ToInt64(masterPoint["MapID"]);
                                if (!submittedMapIDs.Contains(mapID))
                                    continue;

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
                        }

                        syncStage = "preflight existing inspection";
                        DataTable existingRows = br.EQueryP(@"
SELECT InspectionID, InspectionNo, InspectionDate, CompanyID, LocationID,
       StartDateTime, EndDateTime, ReasonVoid, IsSubmitted
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

                            if (!isLightningInspection && existing["IsSubmitted"] != DBNull.Value &&
                                Convert.ToBoolean(existing["IsSubmitted"]))
                                throw new Exception("Inspection sudah disubmit dan terkunci sampai approver memprosesnya.");

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

                        string appRoot = (HttpContext.Current.Request.ApplicationPath ?? "").TrimEnd('/');
                        string siteOrigin = HttpContext.Current.Request.Url.GetLeftPart(UriPartial.Authority);
                        string inspectionApprovalUrl = siteOrigin + appRoot + "/Secure/inspection.aspx?type=approval";
                        SqlParameter[] commonParameters = new SqlParameter[]
                        {
                            new SqlParameter("@p_ClientInspectionID", Limit(clientId, 36)),
                            new SqlParameter("@p_CompanyID", companyId),
                            new SqlParameter("@p_LocationID", locationId),
                            new SqlParameter("@p_SectionID", sectionId),
                            new SqlParameter("@p_InspectionTypeCode", inspectionTypeCode),
                            new SqlParameter("@p_InspectionTypeDetailCode", inspectionTypeDetailCode),
                            new SqlParameter("@p_TenantID", tenantId),
                            new SqlParameter("@p_SuiteNo", suiteNo),
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
                            new SqlParameter("@p_UpdateUser", Limit(userId, 50)),
                            CreateInspectionGpsDecimalParameter("@p_GPSLatitude", TokenString(record, "GPSLatitude"), 10, 7),
                            CreateInspectionGpsDecimalParameter("@p_GPSLongitude", TokenString(record, "GPSLongitude"), 10, 7),
                            CreateInspectionGpsDecimalParameter("@p_GPSAccuracy", TokenString(record, "GPSAccuracy"), 10, 2),
                            CreateInspectionGpsDateParameter("@p_GPSCapturedAt", TokenString(record, "GPSCapturedAt"))
                        };
                        string procedureName;
                        var syncParameters = new List<SqlParameter>(commonParameters);
                        if (isLightningInspection)
                        {
                            syncStage = "execute Lightning inspection sync procedure";
                            procedureName = "spUTL_PIP_T_Inspection_Lightning_Sync";
                            syncParameters.Add(new SqlParameter("@p_ApprovalUrl", inspectionApprovalUrl));
                            syncParameters.Add(new SqlParameter("@p_Points", batchPoints));
                            syncParameters.Add(new SqlParameter("@p_Schedules", lightningSchedules));
                            syncParameters.Add(new SqlParameter("@p_Items", batchItems));
                            syncParameters.Add(new SqlParameter("@p_ItemValues", batchItemValues));
                        }
                        else if (isBatchInspection)
                        {
                            syncStage = "execute Batch inspection sync procedure";
                            procedureName = "spUTL_PIP_T_Inspection_Batch_Sync";
                            syncParameters.Add(new SqlParameter("@p_ApprovalUrl", inspectionApprovalUrl));
                            syncParameters.Add(new SqlParameter("@p_Points", batchPoints));
                            syncParameters.Add(new SqlParameter("@p_Items", batchItems));
                            syncParameters.Add(new SqlParameter("@p_ItemValues", batchItemValues));
                        }
                        else
                        {
                            syncStage = "execute Standard inspection sync procedure";
                            procedureName = "spUTL_PIP_T_Inspection_Sync";
                            syncParameters.Add(new SqlParameter("@p_Items", items));
                            syncParameters.Add(new SqlParameter("@p_ItemValues", itemValues));
                            syncParameters.Add(new SqlParameter("@p_InspectionMode", inspectionMode));
                            syncParameters.Add(new SqlParameter("@p_ApprovalUrl", inspectionApprovalUrl));
                        }

                        syncStage = "save inspection and photos in one BRC transaction";
                        DataTable saved;
                        string requestedInspectionNo = inspectionNo;
                        var inspectionBr = new INSPEC.BRC.PIP_T_WO();
                        saved = inspectionBr.SyncInspection(
                            procedureName,
                            syncParameters.ToArray(),
                            companyId,
                            locationId,
                            inspectionDate,
                            requestedInspectionNo,
                            clientId,
                            incomingPhotos,
                            incomingBatchPhotos,
                            out inspectionNo);
                        syncStage = "read saved inspection identifiers";
                        long inspectionId = Convert.ToInt64(saved.Rows[0]["InspectionID"]);

                        /* Standard and Batch submit their workflow inside the same SQL transaction
                           as the inspection header and child data. No second EQueryP call is required. */

                        bool alreadySubmitted = saved.Columns.Contains("WorkflowStatus") &&
                            String.Equals(Convert.ToString(saved.Rows[0]["WorkflowStatus"]),
                                "ALREADY_SUBMITTED", StringComparison.OrdinalIgnoreCase);

                        /* SQL metadata has committed successfully. Old photo files can now be cleaned up safely.
                           Do not remove the persisted photos when Lightning reports an idempotent retry. */
                        if (!alreadySubmitted && oldPhotoRows != null && !String.IsNullOrWhiteSpace(oldInspectionNo))
                        {
                            foreach (DataRow oldPhoto in oldPhotoRows.Rows)
                            {
                                string oldName = Convert.ToString(oldPhoto["FileName"]);
                                string oldType = Convert.ToString(oldPhoto["FileType"]);
                                if (String.IsNullOrWhiteSpace(oldName) || String.IsNullOrWhiteSpace(oldType)) continue;
                                try
                                {
                                    string oldPath = GetInspectionPhotoPath(oldCompanyId, oldLocationId, oldInspectionDate, oldInspectionNo, oldName, oldType);
                                    if (File.Exists(oldPath)) File.Delete(oldPath);
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
                            InspectionNo = saved.Columns.Contains("InspectionNo") && saved.Rows[0]["InspectionNo"] != DBNull.Value
                                ? Convert.ToString(saved.Rows[0]["InspectionNo"]) : inspectionNo,
                            message = ""
                        });
                    }

                }
                catch (Exception ex)
                {
                    WriteInspectionSyncError(syncStage, clientId, userId, record, ex);
                    System.Diagnostics.Trace.TraceError("SyncInspections failed at stage '{0}' for ClientInspectionID={1}, userId={2}: {3}",
                        syncStage, clientId, userId, ex.ToString());
                    // Keep technical diagnostics in App_Data/server logs only.
                    // Browser responses must contain a clear, non-technical explanation.
                    string userMessage = GetInspectionSyncUserMessage(ex, syncStage);

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
            string emailCompanyId = records.OfType<JObject>()
                .Select(record => TokenString(record, "CompanyID"))
                .FirstOrDefault(value => !String.IsNullOrWhiteSpace(value)) ?? "";
            object emailDispatch;
            try { emailDispatch = DispatchInspectionEmailOutbox(20, userId, emailCompanyId); }
            catch (Exception emailError) { emailDispatch = new { configured = false, error = emailError.Message }; }
            return new { success = allSuccess, results = outcomes, emailDispatch = emailDispatch };
        }

        private static string GetInspectionSyncUserMessage(Exception error, string stage)
        {
            string diagnostic = error == null ? "" : error.ToString();
            string normalized = diagnostic.ToLowerInvariant();

            // A second device may submit the same inspection slot after the first device
            // has already saved it. Treat this as a normal data conflict, not a system error.
            bool duplicateInspection =
                normalized.Contains("an inspection already exists for this date") ||
                normalized.Contains("already exists for this date") ||
                (normalized.Contains("duplicate") && normalized.Contains("inspection") &&
                 (normalized.Contains("schedule") || normalized.Contains("template")));

            if (duplicateInspection && normalized.Contains("tenant") && normalized.Contains("suite"))
            {
                return "Inspeksi untuk Tenant dan Suite yang sama sudah lebih dulu disimpan dari perangkat lain dengan jadwal dan template tersebut. Draft ini belum masuk ke data utama. Jika ini duplikat, klik Hapus Draft Ini. Bila ragu, tanyakan ke SPV.";
            }
            if (duplicateInspection)
            {
                return "Inspeksi dengan pilihan dan jadwal yang sama sudah lebih dulu disimpan dari perangkat lain. Draft ini belum masuk ke data utama. Jika ini duplikat, klik Hapus Draft Ini. Bila ragu, tanyakan ke SPV.";
            }

            string rootMessage = "";
            try
            {
                rootMessage = error == null || error.GetBaseException() == null
                    ? ""
                    : error.GetBaseException().Message ?? "";
            }
            catch { }

            string rootLower = rootMessage.ToLowerInvariant();
            if (rootLower.Contains("belongs to another employee"))
                return "Draft inspeksi ini bukan milik akun yang sedang digunakan. Silakan masuk dengan akun teknisi yang membuat draft tersebut.";
            if (rootLower.Contains("only completed inspections"))
                return "Inspeksi belum selesai. Selesaikan pemeriksaan terlebih dahulu sebelum melakukan sinkronisasi.";

            // Do not expose SQL messages, procedure names, stack traces, or transaction details.
            return "Inspeksi belum berhasil disinkronkan. Data masih tersimpan di perangkat ini. Periksa koneksi internet, lalu coba sinkronkan kembali. Jika masalah tetap muncul, hubungi SPV.";
        }

        private static string GetInspectionSyncLogField(JObject record, string field, int maxLength)
        {
            if (record == null) return "";
            string value = TokenString(record, field) ?? "";
            value = value.Replace("\r", " ").Replace("\n", " ").Trim();
            return Limit(value, maxLength);
        }

        private static void WriteInspectionSyncError(string stage, string clientInspectionId, string userId, JObject record, Exception error)
        {
            try
            {
                HttpContext context = HttpContext.Current;
                if (context == null || context.Server == null)
                    return;

                string appDataPath = context.Server.MapPath("~/App_Data");
                if (String.IsNullOrWhiteSpace(appDataPath))
                    return;

                Directory.CreateDirectory(appDataPath);
                string logPath = Path.Combine(appDataPath, "InspectionSyncErrors.log");
                string recordContext = String.Format(
                    CultureInfo.InvariantCulture,
                    "CompanyID: {0}{10}LocationID: {1}{10}SectionID: {2}{10}InspectionTypeCode: {3}{10}InspectionTypeDetailCode: {4}{10}TenantID: {5}{10}SuiteNo: {6}{10}ScheduledTime: {7}{10}IDTemplate: {8}{10}InspectionDate: {9}{10}ServerDatabaseName: {11}{10}ServerIsTenantInspection: {12}",
                    GetInspectionSyncLogField(record, "CompanyID", 10),
                    GetInspectionSyncLogField(record, "LocationID", 3),
                    GetInspectionSyncLogField(record, "SectionID", 10),
                    GetInspectionSyncLogField(record, "InspectionTypeCode", 10),
                    GetInspectionSyncLogField(record, "InspectionTypeDetailCode", 20),
                    GetInspectionSyncLogField(record, "TenantID", 10),
                    GetInspectionSyncLogField(record, "SuiteNo", 10),
                    GetInspectionSyncLogField(record, "ScheduledTime", 20),
                    GetInspectionSyncLogField(record, "IDTemplate", 20),
                    GetInspectionSyncLogField(record, "InspectionDate", 30),
                    Environment.NewLine,
                    GetInspectionSyncLogField(record, "_ServerDatabaseName", 128),
                    GetInspectionSyncLogField(record, "_ServerIsTenantInspection", 1));

                DateTime jakartaNow = TimeZoneInfo.ConvertTimeFromUtc(
                    DateTime.UtcNow,
                    TimeZoneInfo.FindSystemTimeZoneById("SE Asia Standard Time"));

                string entry = String.Format(
                    CultureInfo.InvariantCulture,
                    "===== {0:yyyy-MM-dd HH:mm:ss.fff} WIB (Asia/Jakarta) ====={1}Stage: {2}{1}ClientInspectionID: {3}{1}UserID: {4}{1}Record Context:{1}{5}{1}{6}{1}{1}",
                    jakartaNow,
                    Environment.NewLine,
                    stage ?? "",
                    clientInspectionId ?? "",
                    userId ?? "",
                    recordContext,
                    error == null ? "(no exception details)" : error.ToString());

                lock (typeof(inspection))
                {
                    File.AppendAllText(logPath, entry, Encoding.UTF8);
                }
            }
            catch (Exception logError)
            {
                System.Diagnostics.Trace.TraceError(
                    "Unable to write InspectionSyncErrors.log: {0}",
                    logError.ToString());
            }
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
            string scheduledTime, int templateId, string inspectionDate, string tenantId, string suiteNo)
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

                DataTable tenantDetail = br.EQueryP(@"
SELECT ISNULL(IsTenantInspection,0) IsTenantInspection
FROM dbo.PIP_M_InspectionTypeDetail
WHERE InspectionTypeCode=@InspectionTypeCode
  AND InspectionTypeDetailCode=@InspectionTypeDetailCode
  AND CompanyID=@CompanyID AND LocationID=@LocationID AND IsActive=1",
                    new SqlParameter[] {
                        new SqlParameter("@InspectionTypeCode", inspectionTypeCode),
                        new SqlParameter("@InspectionTypeDetailCode", inspectionTypeDetailCode),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId)
                    });
                if (tenantDetail == null || tenantDetail.Rows.Count == 0)
                    throw new HttpException(404, "Inspection Type Detail is not active for this company/location.");
                bool isTenantInspection = Convert.ToBoolean(tenantDetail.Rows[0]["IsTenantInspection"]);
                tenantId = Limit(tenantId, 10).Trim();
                suiteNo = Limit(suiteNo, 10).Trim();
                if (isTenantInspection)
                {
                    if (tenantId == "" || suiteNo == "")
                        throw new HttpException(400, "Tenant ID and Suite No are required.");
                    DataTable validTenantSuite = br.EQueryP(@"
SELECT TOP 1 G.TenantID
FROM dbo.THD_M_GeneralInformation G
JOIN dbo.THD_M_AgreementInformation A
  ON A.CompanyID=G.CompanyID AND A.LocationID=G.LocationID AND A.TenantID=G.TenantID
WHERE G.CompanyID=@CompanyID AND G.LocationID=@LocationID AND G.TenantID=@TenantID
  AND (G.IsStoreClosed=0 OR G.DateClosed>GETDATE())
  AND A.SuiteNo=@SuiteNo AND A.LeaseTermDate>=GETDATE()",
                        new SqlParameter[] {
                            new SqlParameter("@CompanyID", companyId),
                            new SqlParameter("@LocationID", locationId),
                            new SqlParameter("@TenantID", tenantId),
                            new SqlParameter("@SuiteNo", suiteNo)
                        });
                    if (validTenantSuite == null || validTenantSuite.Rows.Count == 0)
                        throw new HttpException(400, "Selected Tenant ID / Suite No is not an active lease for this company/location.");
                }
                else
                {
                    tenantId = "";
                    suiteNo = "";
                }

                DataTable duplicate = br.EQueryP(@"
SELECT TOP 1 InspectionNo, OwnerEmployeeID, Status
FROM dbo.PIP_T_Inspection
WHERE CompanyID=@CompanyID AND LocationID=@LocationID AND SectionID=@SectionID
  AND ISNULL(IsActive,1)=1
  AND InspectionTypeCode=@InspectionTypeCode
  AND InspectionTypeDetailCode=@InspectionTypeDetailCode
  AND ISNULL(ScheduledTime,'')=ISNULL(@ScheduledTime,'')
  AND IDTemplate=@IDTemplate
  AND ISNULL(TenantID,'')=CASE WHEN @IsTenantInspection=1 THEN @TenantID ELSE '' END
  AND ISNULL(SuiteNo,'')=CASE WHEN @IsTenantInspection=1 THEN @SuiteNo ELSE '' END
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
                        new SqlParameter("@IsTenantInspection", isTenantInspection ? 1 : 0),
                        new SqlParameter("@TenantID", tenantId),
                        new SqlParameter("@SuiteNo", suiteNo),
                        new SqlParameter("@InspectionDate", ParseDate(inspectionDate, DateTime.Today))
                    });

                return new
                {
                    success = true,
                    duplicate = duplicate.Rows.Count > 0,
                    InspectionNo = duplicate.Rows.Count > 0 ? Convert.ToString(duplicate.Rows[0]["InspectionNo"]) : "",
                    OwnerEmployeeID = duplicate.Rows.Count > 0 ? Convert.ToString(duplicate.Rows[0]["OwnerEmployeeID"]) : "",
                    Status = duplicate.Rows.Count > 0 ? Convert.ToString(duplicate.Rows[0]["Status"]) : ""
                };
            }
        }

        [WebMethod]
        public static object GetInspectionTenantList(string employeeId, string companyId, string locationId)
        {
            employeeId = GFC.RequireMenuEmployee("20021");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (String.IsNullOrWhiteSpace(employeeId) || String.IsNullOrWhiteSpace(companyId) || String.IsNullOrWhiteSpace(locationId))
                throw new HttpException(400, "Employee, company, and location are required.");

            using (var br = new WAL.BR.CF())
            {
                DataTable auth = br.EQueryP(@"
SELECT 1
FROM dbo.SysWebUser SU
WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1
  AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',@EmployeeID,'') AM WHERE AM.MenuID='20021')
  AND (
      EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
              WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                AND C.CompanyID=@CompanyID AND C.LocationID=@LocationID)
      OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip',SU.EmployeeID,'') L
                 WHERE L.CompanyID=@CompanyID AND L.LocationID=@LocationID)
  )",
                    new SqlParameter[] {
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId)
                    });
                if (auth == null || auth.Rows.Count == 0)
                    throw new HttpException(403, "This account is not authorized for Inspection tenant lookup.");

                DataTable rows = br.EQueryP(@"
SELECT G.TenantID,G.TenantName
FROM dbo.THD_M_GeneralInformation G
WHERE (G.IsStoreClosed=0 OR G.DateClosed>GETDATE())
  AND EXISTS (
      SELECT 1
      FROM dbo.THD_M_AgreementInformation A
      WHERE A.CompanyID=G.CompanyID
        AND A.LocationID=G.LocationID
        AND A.TenantID=G.TenantID
        AND A.LeaseTermDate<> ''
        AND A.LeaseTermDate>=GETDATE()
  )
  AND G.CompanyID=@CompanyID
  AND G.LocationID=@LocationID
ORDER BY G.TenantName,G.TenantID",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId)
                    });
                var data = new List<Dictionary<string, object>>();
                foreach (DataRow row in rows.Rows)
                    data.Add(new Dictionary<string, object> {
                        { "TenantID", GF.GetString(row["TenantID"]) },
                        { "TenantName", GF.GetString(row["TenantName"]) },
                        { "CompanyID", companyId },
                        { "LocationID", locationId }
                    });
                return new { success = true, data = data };
            }
        }

        [WebMethod]
        public static object GetInspectionTenantSuites(string employeeId, string companyId, string locationId, string tenantId)
        {
            employeeId = GFC.RequireMenuEmployee("20021");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            tenantId = Limit(tenantId, 10).Trim();
            if (String.IsNullOrWhiteSpace(employeeId) || String.IsNullOrWhiteSpace(companyId) ||
                String.IsNullOrWhiteSpace(locationId))
                throw new HttpException(400, "Employee, company, and location are required.");

            using (var br = new WAL.BR.CF())
            {
                DataTable auth = br.EQueryP(@"
SELECT 1
FROM dbo.SysWebUser SU
WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1
  AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',@EmployeeID,'') AM WHERE AM.MenuID='20021')
  AND (
      EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
              WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                AND C.CompanyID=@CompanyID AND C.LocationID=@LocationID)
      OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip',SU.EmployeeID,'') L
                 WHERE L.CompanyID=@CompanyID AND L.LocationID=@LocationID)
  )",
                    new SqlParameter[] {
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId)
                    });
                if (auth == null || auth.Rows.Count == 0)
                    throw new HttpException(403, "This account is not authorized for Inspection suite lookup.");

                DataTable rows = br.EQueryP(@"
SELECT A.TenantID,A.SuiteNo
FROM dbo.THD_M_AgreementInformation A
JOIN dbo.THD_M_GeneralInformation G
  ON G.CompanyID=A.CompanyID AND G.LocationID=A.LocationID AND G.TenantID=A.TenantID
WHERE A.CompanyID=@CompanyID AND A.LocationID=@LocationID
  AND (@TenantID='' OR A.TenantID=@TenantID)
  AND (G.IsStoreClosed=0 OR G.DateClosed>GETDATE())
  AND A.LeaseTermDate<> ''
  AND A.LeaseTermDate>=GETDATE()
ORDER BY A.SuiteNo",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId),
                        new SqlParameter("@TenantID", tenantId)
                    });
                var data = new List<Dictionary<string, object>>();
                foreach (DataRow row in rows.Rows)
                    data.Add(new Dictionary<string, object> {
                        { "TenantID", GF.GetString(row["TenantID"]) },
                        { "SuiteNo", GF.GetString(row["SuiteNo"]) },
                        { "CompanyID", companyId },
                        { "LocationID", locationId }
                    });
                return new { success = true, data = data };
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
       I.CompanyID, I.LocationID, I.TenantID, I.SuiteNo, I.SectionID, I.InspectionTypeCode,
       I.InspectionTypeName, I.InspectionTypeDetailCode, I.InspectionTypeDetailName,
       I.ScheduledTime, I.IDTemplate, I.IDVersion, I.TemplateNo, I.TemplateName,
       I.TemplateVersion, I.InspectionDate, I.StartDateTime, I.EndDateTime,
       I.OwnerEmployeeID, ISNULL(E.Name, I.OwnerEmployeeID) TechnicianName,
       I.Status, I.IsApproved, I.ReasonVoid
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
                        new SqlParameter("@InspectionTypeCode", Limit(TokenString(record, "InspectionTypeCode"), 10)),
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
      AND Status='DRAFT' AND ISNULL(IsSubmitted,0)=0
      AND ISNULL(ReasonVoid,'')<>'';
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
            string typeCode = Limit(inspectionTypeCode, 10).ToUpperInvariant();
            string detailCode = Limit(inspectionTypeDetailCode, 20).ToUpperInvariant();
            if (typeCode == "" || detailCode == "")
                throw new HttpException(400, "Inspection Type and Detail are required.");

            using (var br = new WAL.BR.CF())
            {
                DataTable type = br.EQueryP(@"
SELECT IT.InspectionTypeCode, IT.InspectionTypeName, IT.SectionID,
       IT.InspectionMode,IT.InspectionPointMode,IT.ScheduleSelectionMode
FROM dbo.PIP_M_InspectionType IT
WHERE IT.InspectionTypeCode=@TypeCode AND IT.IsActive=1
  AND
  (
      ISNULL(IT.InspectionMode,'STANDARD')='BATCH'
      AND ISNULL(IT.InspectionPointMode,'')='MAP'
      AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='INSPECT'
  )
  AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S WHERE S.val=IT.SectionID)",
                    new SqlParameter[] {
                        new SqlParameter("@TypeCode", typeCode),
                        new SqlParameter("@SectionList", sectionList)
                    });
                if (type == null || type.Rows.Count == 0)
                    throw new HttpException(403, "Inspection Type is not configured for BATCH/MAP/INSPECT mode or not assigned to this inspector.");

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
                    if (groupId <= 0 || String.IsNullOrWhiteSpace(Convert.ToString(map["GroupName"]))) continue;
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
                return new
                {
                    success = true,
                    inspectionType = new
                    {
                        InspectionTypeCode = GF.GetString(t["InspectionTypeCode"]),
                        InspectionTypeName = GF.GetString(t["InspectionTypeName"]),
                        SectionID = GF.GetString(t["SectionID"])
                    },
                    inspectionDetail = new
                    {
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
       I.CompanyID, I.LocationID, I.TenantID, I.SuiteNo, I.SectionID, I.InspectionTypeCode,
       I.InspectionTypeName, I.InspectionTypeDetailCode, I.InspectionTypeDetailName,
       I.ScheduledTime, I.IDTemplate, I.IDVersion, I.TemplateNo, I.TemplateName,
       I.TemplateVersion, I.InspectionDate, I.StartDateTime, I.EndDateTime,
       I.OwnerEmployeeID, ISNULL(E.Name, I.OwnerEmployeeID) TechnicianName, I.Status,
       I.IsSubmitted, I.IsApproved, I.IsApproved1, I.IsApproved2,
       I.ApprovedDate, I.SyncDate, I.ReasonVoid, I.ReasonVoid1, I.ReasonVoid2,
       ISNULL(NULLIF(I.InspectionMode,''),ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')) AS InspectionMode
FROM dbo.PIP_T_Inspection I
LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=I.OwnerEmployeeID
LEFT JOIN dbo.M_HRD_Employee ES ON ES.EmployeeID=I.SubmittedBy
LEFT JOIN dbo.M_HRD_Employee EA ON EA.EmployeeID=I.ApprovedBy
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
      AND ISNULL(I.IsSubmitted,0)=0
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
            string inspectionTypeDetailCode, string templateId, string scheduleTime)
        {
            return GetInspectionApprovalQueueInternal(employeeId, companyId, locationId, approvalTab, dateFrom, dateThru, inspectionTypeCode, inspectionTypeDetailCode, templateId, scheduleTime, false, true);
        }

        private static object GetInspectionApprovalQueueInternal(string employeeId, string companyId, string locationId,
            string approvalTab, string dateFrom, string dateThru, string inspectionTypeCode,
            string inspectionTypeDetailCode, string templateId, string scheduleTime, bool countOnly, bool dispatchOutbox)
        {
            employeeId = GFC.CurrentEmployeeID();
            bool isAdministrator = IsInspectionAdministrator(employeeId);
            if (!isAdministrator) employeeId = GFC.RequireMenuEmployee("20022");
            if (dispatchOutbox)
            {
                try { DispatchInspectionEmailOutbox(10, employeeId, companyId); }
                catch (Exception dispatchError) { System.Diagnostics.Trace.TraceWarning("Inspection email outbox retry failed: {0}", dispatchError.Message); }
            }
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
LEFT JOIN dbo.M_HRD_Employee ES ON ES.EmployeeID=I.SubmittedBy
LEFT JOIN dbo.M_HRD_Employee EA ON EA.EmployeeID=I.ApprovedBy
CROSS APPLY (SELECT
 CASE WHEN EXISTS
 (
   SELECT 1 FROM dbo.SysWebCommonValue C
   WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
     AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID
     AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
 ) THEN 1 ELSE 0 END IsSPV,
 CASE WHEN ISNULL(IT.InspectionMode,'STANDARD')='BATCH'
        AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='PARAM'
        AND EXISTS
        (
          SELECT 1 FROM dbo.SysWebCommonValue C
          WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
            AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';'+dbo.fnINSPEC_ChiefRoleForSection(I.SectionID)
            AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
        ) THEN 1 ELSE 0 END IsBatchChief
) R
CROSS APPLY (SELECT
 CASE WHEN ISNULL(I.ReasonVoid,'')<>'' AND
   (ISNULL(I.ApprovedDate,CONVERT(DATETIME,'19000101',112))>CONVERT(DATETIME,'19000101',112)
    OR EXISTS
    (
      SELECT 1 FROM dbo.PIP_T_InspectionApprovalHistory H
      WHERE H.EntityType='INSPECTION' AND H.EntityID=I.InspectionID
        AND H.StageCode='SPV' AND H.ActionCode='VOIDED'
        AND NOT EXISTS
        (
          SELECT 1 FROM dbo.PIP_T_InspectionApprovalHistory X
          WHERE X.EntityType=H.EntityType AND X.EntityID=H.EntityID
            AND X.ActionCode IN ('SUBMITTED','RESUBMITTED') AND X.ActionDate>H.ActionDate
        )
    )) THEN 1 ELSE 0 END VoidSPV,
 CASE WHEN ISNULL(I.ReasonVoid1,'')<>'' AND
   EXISTS
   (
     SELECT 1 FROM dbo.PIP_T_InspectionApprovalHistory H
     WHERE H.EntityType='INSPECTION' AND H.EntityID=I.InspectionID
       AND H.StageCode=dbo.fnINSPEC_ChiefRoleForSection(I.SectionID) AND H.ActionCode='VOIDED'
       AND NOT EXISTS
       (
         SELECT 1 FROM dbo.PIP_T_InspectionApprovalHistory X
         WHERE X.EntityType=H.EntityType AND X.EntityID=H.EntityID
           AND X.ActionCode IN ('SUBMITTED','RESUBMITTED') AND X.ActionDate>H.ActionDate
       )
   ) THEN 1 ELSE 0 END VoidBatchChief
) V
WHERE I.CompanyID=@CompanyID AND I.LocationID=@LocationID AND ISNULL(I.IsActive,1)=1
 AND ISNULL(IT.InspectionMode,'STANDARD') IN ('STANDARD','BATCH')
 AND ISNULL(IT.ScheduleSelectionMode,'PARAM')<>'INSPECT'
 AND EXISTS
 (
   SELECT 1 FROM dbo.PIP_M_CheckListWOPM T
   WHERE T.IDTemplate=I.IDTemplate AND T.SectionID=I.SectionID
     AND ISNULL(T.TemplateType,'W')='I'
     AND (ISNULL(T.CompanyScope,'S')='A' OR (';'+ISNULL(T.CompanyLocationList,'')+';' LIKE '%;'+I.CompanyID+I.LocationID+';%'))
     AND (ISNULL(T.EmployeeList,'')='' OR (';'+ISNULL(T.EmployeeList,'')+';' LIKE '%;'+I.OwnerEmployeeID+';%'))
 )
 AND EXISTS
 (
   SELECT 1 FROM dbo.SysWebUser SU
   WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1
     AND (@IsAdministrator=1 OR EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',@EmployeeID,'') AM WHERE AM.MenuID='20022'))
     AND
     (
       EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
               WHERE C.UserID=SU.EmployeeID AND C.AppID='pip' AND C.CompanyID=I.CompanyID AND C.LocationID=I.LocationID)
       OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip',SU.EmployeeID,'') L
                  WHERE L.CompanyID=I.CompanyID AND L.LocationID=I.LocationID)
     )
 )
 AND
 (
   (@ApprovalTab='OUTSTANDING' AND I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=1
      AND ISNULL(I.IsApproved,0)=0 AND (@IsAdministrator=1 OR R.IsSPV=1))
   OR
   (@ApprovalTab='OUTSTANDING' AND I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=1
      AND ISNULL(IT.InspectionMode,'STANDARD')='BATCH'
      AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='PARAM'
      AND ISNULL(I.IsApproved,0)=1 AND ISNULL(I.IsApproved1,0)=0
      AND (@IsAdministrator=1 OR R.IsBatchChief=1))
   OR
   (@ApprovalTab='APPROVED' AND I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=1
      AND ISNULL(IT.InspectionMode,'STANDARD')='BATCH'
      AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='PARAM'
      AND ISNULL(I.IsApproved,0)=1 AND ISNULL(I.IsApproved1,0)=1
      AND I.Approved1Date>=@DateFrom AND I.Approved1Date<DATEADD(DAY,1,@DateThru)
      AND (@IsAdministrator=1 OR R.IsSPV=1 OR
           (R.IsBatchChief=1 AND EXISTS
             (SELECT 1 FROM dbo.PIP_T_InspectionApprovalHistory H
              WHERE H.EntityType='INSPECTION' AND H.EntityID=I.InspectionID
                AND H.StageCode=dbo.fnINSPEC_ChiefRoleForSection(I.SectionID)
                AND H.ActionCode='APPROVED' AND H.ActionDate>=@DateFrom AND H.ActionDate<DATEADD(DAY,1,@DateThru)))))
   OR
   (@ApprovalTab='APPROVED' AND I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=1
      AND NOT (ISNULL(IT.InspectionMode,'STANDARD')='BATCH' AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='PARAM')
      AND ISNULL(I.IsApproved,0)=1
      AND I.ApprovedDate>=@DateFrom AND I.ApprovedDate<DATEADD(DAY,1,@DateThru)
      AND (@IsAdministrator=1 OR R.IsSPV=1))
   OR
   (@ApprovalTab='VOID' AND I.Status='DRAFT' AND ISNULL(I.IsSubmitted,0)=0
      AND ISNULL(I.IsApproved,0)=0 AND ISNULL(I.IsApproved1,0)=0 AND ISNULL(I.IsApproved2,0)=0
      AND (ISNULL(I.ReasonVoid,'')<>'' OR ISNULL(I.ReasonVoid1,'')<>'' OR ISNULL(I.ReasonVoid2,'')<>'')
      AND
      (
        (@IsAdministrator=1 AND (V.VoidSPV=1 OR V.VoidBatchChief=1))
        OR (R.IsSPV=1 AND V.VoidSPV=1)
        OR (R.IsBatchChief=1 AND V.VoidBatchChief=1)
      ))
 )";


            SqlParameter[] filterOptionParameters = new SqlParameter[] {
                new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@IsAdministrator", isAdministrator ? 1 : 0),
                        new SqlParameter("@ApprovalTab", approvalTab),
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
       I.IDTemplate, I.TemplateNo, I.ScheduledTime" + fromWhere + @"
ORDER BY I.InspectionTypeName, I.InspectionTypeDetailName, I.TemplateNo, I.ScheduledTime",
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
       I.TenantID, I.SuiteNo, I.IDTemplate, I.IDVersion, I.ScheduledTime, I.TemplateNo, I.TemplateName, I.TemplateVersion,
       I.InspectionDate, CONVERT(VARCHAR(23), I.StartDateTime, 126) AS StartDateTime, CONVERT(VARCHAR(23), I.EndDateTime, 126) AS EndDateTime, I.Summary, I.OwnerEmployeeID,
       ISNULL(E.Name, I.OwnerEmployeeID) AS TechnicianName, I.Status,
       I.IsSubmitted,I.SubmittedBy,ISNULL(ES.Name,I.SubmittedBy) AS SubmittedByName,I.SubmittedDate,
       I.IsApproved,I.ApprovedBy,ISNULL(EA.Name,I.ApprovedBy) AS ApprovedByName,I.ApprovedDate,I.ApprovalBatchID,
       I.IsApproved1,I.Approved1By,I.Approved1Date,
       I.ApprovalRemark,I.ReasonVoid,I.ReasonVoid1,
       I.FollowUp, I.FollowUpSection, I.FollowUpRemark, I.FollowUpWONo,
       ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD') AS InspectionMode,
       ISNULL(NULLIF(IT.ScheduleSelectionMode,''),'PARAM') AS ScheduleSelectionMode,
       ISNULL(NULLIF(IT.InspectionPointMode,''),'') AS InspectionPointMode,
        CASE WHEN I.Status='DRAFT' AND (ISNULL(I.ReasonVoid,'')<>'' OR ISNULL(I.ReasonVoid1,'')<>'' OR ISNULL(I.ReasonVoid2,'')<>'') THEN 'VOID'
             WHEN ISNULL(IT.InspectionMode,'STANDARD')='BATCH' AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='PARAM' AND ISNULL(I.IsApproved1,0)=1 THEN 'ACKNOWLEDGED'
             WHEN ISNULL(I.ApprovalBatchID,0)>0 THEN 'BATCHED'
             WHEN ISNULL(IT.InspectionMode,'STANDARD')='BATCH' AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='PARAM' AND ISNULL(I.IsApproved,0)=1 THEN 'VERIFIED'
             WHEN ISNULL(I.IsApproved,0)=1 THEN 'SPV APPROVED'
             WHEN ISNULL(I.IsSubmitted,0)=1 THEN 'PENDING SPV' ELSE I.Status END AS WorkflowStatus" + fromWhere + @"
  AND (@InspectionTypeCode='' OR I.InspectionTypeCode=@InspectionTypeCode)
  AND (@InspectionTypeDetailCode='' OR I.InspectionTypeDetailCode=@InspectionTypeDetailCode)
  AND (@TemplateId='' OR CONVERT(VARCHAR(20),I.IDTemplate)=@TemplateId)
  AND (@ScheduleTime='' OR ISNULL(I.ScheduledTime,'')=@ScheduleTime)
ORDER BY I.InspectionDate DESC, I.InspectionID DESC",
                    new SqlParameter[] {
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@IsAdministrator", isAdministrator ? 1 : 0),
                        new SqlParameter("@ApprovalTab", approvalTab),
                        new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId),
                        new SqlParameter("@DateFrom", fromDate),
                        new SqlParameter("@DateThru", thruDate),
                        new SqlParameter("@InspectionTypeCode", inspectionTypeCode ?? ""),
                        new SqlParameter("@InspectionTypeDetailCode", inspectionTypeDetailCode ?? ""),
                        new SqlParameter("@TemplateId", templateId ?? ""),
                        new SqlParameter("@ScheduleTime", scheduleTime ?? "")
                    });
                if (countOnly) return rows == null ? 0 : rows.Rows.Count;

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
            employeeId = GFC.CurrentEmployeeID();
            bool isAdministrator = IsInspectionAdministrator(employeeId);
            if (!isAdministrator) employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (String.IsNullOrWhiteSpace(employeeId))
                throw new HttpException(403, "Supervisor identity is required.");
            using (var br = new WAL.BR.CF())
            {

                DataTable rows = br.EQueryP(@"
                DECLARE @Today DATETIME;
SET @Today=CONVERT(DATETIME,CONVERT(VARCHAR(10),GETDATE(),120),120);
DECLARE @Tomorrow DATETIME;
SET @Tomorrow=DATEADD(DAY,1,@Today);

;WITH ScopeInspection AS
(
    SELECT I.InspectionID,I.CompanyID,I.LocationID,I.SectionID,I.Status,
           I.ReasonVoid,I.ReasonVoid1,I.ReasonVoid2,
           IT.InspectionMode,IT.ScheduleSelectionMode,
           dbo.fnINSPEC_ChiefRoleForSection(I.SectionID) AS ChiefRole
    FROM dbo.PIP_T_Inspection I
    LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
    WHERE I.CompanyID=@CompanyID AND I.LocationID=@LocationID
      AND ISNULL(I.IsActive,1)=1
      AND EXISTS
      (
          SELECT 1 FROM dbo.PIP_M_CheckListWOPM T
          WHERE T.IDTemplate=I.IDTemplate AND T.SectionID=I.SectionID
            AND ISNULL(T.TemplateType,'W')='I'
            AND (ISNULL(T.CompanyScope,'S')='A'
                 OR (';'+ISNULL(T.CompanyLocationList,'')+';' LIKE '%;'+I.CompanyID+I.LocationID+';%'))
            AND (ISNULL(T.EmployeeList,'')=''
                 OR (';'+ISNULL(T.EmployeeList,'')+';' LIKE '%;'+I.OwnerEmployeeID+';%'))
      )
),
ApprovalEvents AS
(
    SELECT H.EntityType,H.EntityID,H.StageCode,H.ActionCode,H.ActionDate,I.Status,
           CASE
             WHEN @IsAdministrator=1 THEN 1
             WHEN H.StageCode='SPV' AND EXISTS
             (
                 SELECT 1 FROM dbo.SysWebCommonValue C
                 WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                   AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID
                   AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X
                               WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
             ) THEN 1
             WHEN H.EntityType='INSPECTION'
                  AND ISNULL(I.InspectionMode,'STANDARD')='BATCH'
                  AND ISNULL(I.ScheduleSelectionMode,'PARAM')='PARAM'
                  AND H.StageCode=I.ChiefRole
                  AND EXISTS
                  (
                      SELECT 1 FROM dbo.SysWebCommonValue C
                      WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                        AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';'+I.ChiefRole
                        AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X
                                    WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
                  ) THEN 1
             WHEN H.EntityType='LIGHTNING' AND H.StageCode IN ('CHIEF_SEC','CHIEF_ENG')
                  AND EXISTS
                  (
                      SELECT 1 FROM dbo.SysWebCommonValue C
                      WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                        AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';'+H.StageCode
                        AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X
                                    WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
                  ) THEN 1
             ELSE 0
           END AS IsVisible
    FROM dbo.PIP_T_InspectionApprovalHistory H
    JOIN ScopeInspection I ON I.InspectionID=H.EntityID
    WHERE H.EntityType IN ('INSPECTION','LIGHTNING')
      AND H.ActionCode IN ('APPROVED','VOIDED')
)
SELECT
    COUNT(DISTINCT CASE WHEN ActionCode='APPROVED' AND ActionDate>=@Today AND ActionDate<@Tomorrow
                        AND IsVisible=1
                        THEN EntityType+':'+CONVERT(VARCHAR(20),EntityID) END) AS ApprovedToday,
    CASE WHEN @IsAdministrator=1
           OR EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',@EmployeeID,'') AM WHERE AM.MenuID='20022')
         THEN 1 ELSE 0 END AS ShowApprovalCards,
    COUNT(DISTINCT CASE WHEN ActionCode='VOIDED' AND IsVisible=1 AND Status='DRAFT'
                        AND NOT EXISTS
                        (
                            SELECT 1 FROM dbo.PIP_T_InspectionApprovalHistory X
                            WHERE X.EntityType=ApprovalEvents.EntityType
                              AND X.EntityID=ApprovalEvents.EntityID
                              AND X.ActionCode IN ('SUBMITTED','RESUBMITTED')
                              AND X.ActionDate>ApprovalEvents.ActionDate
                        )
                        THEN EntityType+':'+CONVERT(VARCHAR(20),EntityID) END) AS VoidCount
FROM ApprovalEvents;",
                                new SqlParameter[]
                {
                    new SqlParameter("@EmployeeID", employeeId),
                    new SqlParameter("@IsAdministrator", isAdministrator ? 1 : 0),
                    new SqlParameter("@SectionList",
                        GFC.GetEmployeeSection(employeeId)),
                    new SqlParameter("@CompanyID", companyId),
                    new SqlParameter("@LocationID", locationId)
                });

                // Count with the same SQL scope used by both Approval OUTSTANDING queries.
                int pendingStandard = Convert.ToInt32(GetInspectionApprovalQueueInternal(
                    employeeId, companyId, locationId, "OUTSTANDING", "", "", "", "", "", "", true, false));
                int pendingLightning = Convert.ToInt32(GetLightningInspectionApprovalQueueInternal(
                    employeeId, companyId, locationId, "OUTSTANDING", "", "", "", "", "", "", true, false));
                int pendingApprovalCount = pendingStandard + pendingLightning;

                if (rows.Rows.Count == 0)
                    return new { success = true, pendingApproval = pendingApprovalCount, approvedToday = 0, voidCount = 0, showApprovalCards = false };
                DataRow row = rows.Rows[0];
                return new
                {
                    success = true,
                    pendingApproval = pendingApprovalCount,
                    approvedToday = row["ApprovedToday"] == DBNull.Value ? 0 : Convert.ToInt32(row["ApprovedToday"]),
                    showApprovalCards = row["ShowApprovalCards"] != DBNull.Value && Convert.ToInt32(row["ShowApprovalCards"]) == 1,
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
  AND I.Status='DRAFT' AND I.IsApproved=0
  AND EXISTS (
      SELECT 1 FROM dbo.SysWebUser SU

WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1 AND EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20021')
        AND EXISTS (
      SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S
      WHERE S.val=I.SectionID
  )
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
            string inspectionTypeDetailCode, string templateId, string scheduleTime)
        {
            return GetLightningInspectionApprovalQueueInternal(employeeId, companyId, locationId, approvalTab, dateFrom, dateThru, inspectionTypeCode, inspectionTypeDetailCode, templateId, scheduleTime, false, true);
        }

        private static object GetLightningInspectionApprovalQueueInternal(string employeeId, string companyId, string locationId,
            string approvalTab, string dateFrom, string dateThru, string inspectionTypeCode,
            string inspectionTypeDetailCode, string templateId, string scheduleTime, bool countOnly, bool dispatchOutbox)
        {
            employeeId = GFC.CurrentEmployeeID();
            bool isAdministrator = IsInspectionAdministrator(employeeId);
            if (!isAdministrator) employeeId = GFC.RequireMenuEmployee("20022");
            if (dispatchOutbox)
            {
                try { DispatchInspectionEmailOutbox(10, employeeId, companyId); }
                catch (Exception dispatchError) { System.Diagnostics.Trace.TraceWarning("Inspection email outbox retry failed: {0}", dispatchError.Message); }
            }
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
                Func<bool, SqlParameter[]> createParameters = includeScheduleTime => new SqlParameter[] {
                    new SqlParameter("@EmployeeID", employeeId),
                    new SqlParameter("@IsAdministrator", isAdministrator ? 1 : 0),
                    new SqlParameter("@CompanyID", companyId),
                    new SqlParameter("@LocationID", locationId),
                    new SqlParameter("@ApprovalTab", approvalTab),
                    new SqlParameter("@DateFrom", fromDate),
                    new SqlParameter("@DateThru", thruDate),
                    new SqlParameter("@InspectionTypeCode", inspectionTypeCode ?? ""),
                    new SqlParameter("@InspectionTypeDetailCode", inspectionTypeDetailCode ?? ""),
                    new SqlParameter("@TemplateId", templateId ?? ""),
                    new SqlParameter("@ScheduleTime", includeScheduleTime ? (scheduleTime ?? "") : "")
                };
                const string scope = @"
FROM dbo.PIP_T_Inspection I
LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=I.OwnerEmployeeID
LEFT JOIN dbo.M_HRD_Employee ES ON ES.EmployeeID=I.SubmittedBy
LEFT JOIN dbo.M_HRD_Employee EA ON EA.EmployeeID=I.ApprovedBy
CROSS APPLY (SELECT
 CASE WHEN EXISTS(SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID AND EXISTS(SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)) THEN 1 ELSE 0 END IsSPV,
 CASE WHEN EXISTS(SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_ENG' AND EXISTS(SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)) THEN 1 ELSE 0 END IsCE,
 CASE WHEN EXISTS(SELECT 1 FROM dbo.SysWebCommonValue C WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0 AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_SEC' AND EXISTS(SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)) THEN 1 ELSE 0 END IsCS,
 CASE WHEN EXISTS(SELECT 1 FROM dbo.PIP_M_Section S WHERE S.SectionID=I.SectionID AND UPPER(ISNULL(S.ProfitCenterNo,''))='PENG') THEN 1 ELSE 0 END IsPENG
) R
CROSS APPLY (SELECT
 CASE WHEN ISNULL(I.ReasonVoid,'')<>'' AND (ISNULL(I.ApprovedDate,CONVERT(DATETIME,'19000101',112))>CONVERT(DATETIME,'19000101',112) OR EXISTS(SELECT 1 FROM dbo.PIP_T_InspectionApprovalHistory H WHERE H.EntityType='LIGHTNING' AND H.EntityID=I.InspectionID AND H.StageCode='SPV' AND H.ActionCode='VOIDED' AND NOT EXISTS(SELECT 1 FROM dbo.PIP_T_InspectionApprovalHistory X WHERE X.EntityType=H.EntityType AND X.EntityID=H.EntityID AND X.ActionCode IN ('SUBMITTED','RESUBMITTED') AND X.ActionDate>H.ActionDate))) THEN 1 ELSE 0 END VoidSPV,
 CASE WHEN ISNULL(I.ReasonVoid1,'')<>'' AND (ISNULL(I.Approved1Date,CONVERT(DATETIME,'19000101',112))>CONVERT(DATETIME,'19000101',112) OR EXISTS(SELECT 1 FROM dbo.PIP_T_InspectionApprovalHistory H WHERE H.EntityType='LIGHTNING' AND H.EntityID=I.InspectionID AND H.StageCode='CHIEF_SEC' AND H.ActionCode='VOIDED' AND NOT EXISTS(SELECT 1 FROM dbo.PIP_T_InspectionApprovalHistory X WHERE X.EntityType=H.EntityType AND X.EntityID=H.EntityID AND X.ActionCode IN ('SUBMITTED','RESUBMITTED') AND X.ActionDate>H.ActionDate))) THEN 1 ELSE 0 END VoidCE,
 CASE WHEN ISNULL(I.ReasonVoid2,'')<>'' AND (ISNULL(I.Approved2Date,CONVERT(DATETIME,'19000101',112))>CONVERT(DATETIME,'19000101',112) OR EXISTS(SELECT 1 FROM dbo.PIP_T_InspectionApprovalHistory H WHERE H.EntityType='LIGHTNING' AND H.EntityID=I.InspectionID AND H.StageCode='CHIEF_ENG' AND H.ActionCode='VOIDED' AND NOT EXISTS(SELECT 1 FROM dbo.PIP_T_InspectionApprovalHistory X WHERE X.EntityType=H.EntityType AND X.EntityID=H.EntityID AND X.ActionCode IN ('SUBMITTED','RESUBMITTED') AND X.ActionDate>H.ActionDate))) THEN 1 ELSE 0 END VoidCS
) V
WHERE ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')='BATCH'
 AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='INSPECT'
 AND I.InspectionMode='BATCH'
 AND I.CompanyID=@CompanyID AND I.LocationID=@LocationID AND ISNULL(I.IsActive,1)=1
 AND EXISTS(SELECT 1 FROM dbo.SysWebUser SU WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1 AND (@IsAdministrator=1 OR EXISTS(SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo',@EmployeeID,'') AM WHERE AM.MenuID='20022')) AND (EXISTS(SELECT 1 FROM dbo.SysWebUserCompanyLocation C WHERE C.UserID=SU.EmployeeID AND C.AppID='pip' AND C.CompanyID=I.CompanyID AND C.LocationID=I.LocationID) OR EXISTS(SELECT 1 FROM dbo.F_SelectOneLogin('pip',SU.EmployeeID,'') L WHERE L.CompanyID=I.CompanyID AND L.LocationID=I.LocationID)))
 AND (
  (@ApprovalTab='OUTSTANDING' AND I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=1 AND (
    (@IsAdministrator=1 AND ISNULL(I.IsApproved2,0)=0)
    OR (R.IsSPV=1 AND ISNULL(I.IsApproved,0)=0)
    OR (R.IsCS=1 AND ISNULL(I.IsApproved,0)=1 AND ISNULL(I.IsApproved1,0)=0)
    OR (R.IsCE=1 AND R.IsPENG=1 AND ISNULL(I.IsApproved1,0)=1 AND ISNULL(I.IsApproved2,0)=0)
  ))
  OR
  (@ApprovalTab='APPROVED' AND I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=1 AND (
    (@IsAdministrator=1 AND (
      (ISNULL(I.IsApproved,0)=1 AND I.ApprovedDate>=@DateFrom AND I.ApprovedDate<DATEADD(DAY,1,@DateThru))
      OR (ISNULL(I.IsApproved1,0)=1 AND I.Approved1Date>=@DateFrom AND I.Approved1Date<DATEADD(DAY,1,@DateThru)
       AND EXISTS(SELECT 1 FROM dbo.PIP_T_InspectionApprovalHistory H WHERE H.EntityType='LIGHTNING' AND H.EntityID=I.InspectionID AND H.StageCode='CHIEF_SEC' AND H.ActionCode='APPROVED' AND H.ActionDate>=@DateFrom AND H.ActionDate<DATEADD(DAY,1,@DateThru)))
      OR (ISNULL(I.IsApproved2,0)=1 AND I.Approved2Date>=@DateFrom AND I.Approved2Date<DATEADD(DAY,1,@DateThru)
       AND EXISTS(SELECT 1 FROM dbo.PIP_T_InspectionApprovalHistory H WHERE H.EntityType='LIGHTNING' AND H.EntityID=I.InspectionID AND H.StageCode='CHIEF_ENG' AND H.ActionCode='APPROVED' AND H.ActionDate>=@DateFrom AND H.ActionDate<DATEADD(DAY,1,@DateThru)))
    ))
    OR (R.IsSPV=1 AND ISNULL(I.IsApproved,0)=1 AND I.ApprovedDate>=@DateFrom AND I.ApprovedDate<DATEADD(DAY,1,@DateThru))
    OR (R.IsCS=1 AND ISNULL(I.IsApproved1,0)=1 AND I.Approved1Date>=@DateFrom AND I.Approved1Date<DATEADD(DAY,1,@DateThru)
      AND EXISTS(SELECT 1 FROM dbo.PIP_T_InspectionApprovalHistory H WHERE H.EntityType='LIGHTNING' AND H.EntityID=I.InspectionID AND H.StageCode='CHIEF_SEC' AND H.ActionCode='APPROVED' AND H.ActionDate>=@DateFrom AND H.ActionDate<DATEADD(DAY,1,@DateThru)))
    OR (R.IsCE=1 AND R.IsPENG=1 AND ISNULL(I.IsApproved2,0)=1 AND I.Approved2Date>=@DateFrom AND I.Approved2Date<DATEADD(DAY,1,@DateThru)
      AND EXISTS(SELECT 1 FROM dbo.PIP_T_InspectionApprovalHistory H WHERE H.EntityType='LIGHTNING' AND H.EntityID=I.InspectionID AND H.StageCode='CHIEF_ENG' AND H.ActionCode='APPROVED' AND H.ActionDate>=@DateFrom AND H.ActionDate<DATEADD(DAY,1,@DateThru)))
  ))
  OR
  (@ApprovalTab='VOID' AND I.Status='DRAFT' AND ISNULL(I.IsSubmitted,0)=0 AND ISNULL(I.IsApproved,0)=0 AND ISNULL(I.IsApproved1,0)=0 AND ISNULL(I.IsApproved2,0)=0
    AND (ISNULL(I.ReasonVoid,'')<>'' OR ISNULL(I.ReasonVoid1,'')<>'' OR ISNULL(I.ReasonVoid2,'')<>'')
    AND ((@IsAdministrator=1 AND (V.VoidSPV=1 OR V.VoidCE=1 OR V.VoidCS=1))
      OR (R.IsSPV=1 AND V.VoidSPV=1)
      OR (R.IsCS=1 AND V.VoidCE=1)
      OR (R.IsCE=1 AND R.IsPENG=1 AND V.VoidCS=1))
  ))
 AND EXISTS(SELECT 1 FROM dbo.PIP_M_CheckListWOPM T WHERE T.IDTemplate=I.IDTemplate AND T.SectionID=I.SectionID AND ISNULL(T.TemplateType,'W')='I' AND (ISNULL(T.CompanyScope,'S')='A' OR (';'+ISNULL(T.CompanyLocationList,'')+';' LIKE '%;'+I.CompanyID+I.LocationID+';%')) AND (ISNULL(T.EmployeeList,'')='' OR (';'+ISNULL(T.EmployeeList,'')+';' LIKE '%;'+I.OwnerEmployeeID+';%')))
 AND (@InspectionTypeCode='' OR I.InspectionTypeCode=@InspectionTypeCode)
 AND (@InspectionTypeDetailCode='' OR I.InspectionTypeDetailCode=@InspectionTypeDetailCode)
 AND (@TemplateId='' OR CONVERT(VARCHAR(20),I.IDTemplate)=@TemplateId)
 AND (@ScheduleTime='' OR ISNULL(I.ScheduledTime,'')=@ScheduleTime)";

                DataTable filtersTable = br.EQueryP(@"
SELECT DISTINCT I.InspectionTypeCode,I.InspectionTypeName,I.InspectionTypeDetailCode,
       I.InspectionTypeDetailName,I.IDTemplate,I.TemplateNo,I.ScheduledTime " + scope + @"
ORDER BY I.InspectionTypeName,I.InspectionTypeDetailName,I.TemplateNo,I.ScheduledTime", createParameters(false));
                var filters = new List<Dictionary<string, object>>();
                foreach (DataRow row in filtersTable.Rows)
                {
                    var item = new Dictionary<string, object>();
                    foreach (DataColumn col in filtersTable.Columns) item[col.ColumnName] = row[col] == DBNull.Value ? null : row[col];
                    filters.Add(item);
                }
                DataTable rows = br.EQueryP(@"
SELECT I.InspectionID,I.ClientInspectionID,I.InspectionNo,I.CompanyID,I.LocationID,I.TenantID,I.SuiteNo,I.SectionID,
       I.InspectionTypeCode,I.InspectionTypeName,I.InspectionTypeDetailCode,I.InspectionTypeDetailName,
       I.IDTemplate,I.IDVersion,I.ScheduledTime,I.TemplateNo,I.TemplateName,I.TemplateVersion,
       I.InspectionDate,CONVERT(VARCHAR(23),I.StartDateTime,126) StartDateTime,
       CONVERT(VARCHAR(23),I.EndDateTime,126) EndDateTime,I.Summary,I.OwnerEmployeeID,
       ISNULL(E.Name,I.OwnerEmployeeID) TechnicianName,I.Status,
       I.IsSubmitted,I.SubmittedBy,ISNULL(ES.Name,I.SubmittedBy) SubmittedByName,I.SubmittedDate,
       I.IsApproved,I.ApprovedBy,ISNULL(EA.Name,I.ApprovedBy) ApprovedByName,I.ApprovedDate,
       I.IsApproved1,I.Approved1By,I.Approved1Date,I.IsApproved2,I.Approved2By,I.Approved2Date,I.ApprovalRemark,I.ReasonVoid,I.ReasonVoid1,I.ReasonVoid2,
       I.FollowUp,I.FollowUpSection,I.FollowUpRemark,I.FollowUpWONo,
       'BATCH' InspectionMode,ISNULL(NULLIF(IT.ScheduleSelectionMode,''),'PARAM') ScheduleSelectionMode,
       CASE WHEN I.Status='DRAFT' AND (ISNULL(I.ReasonVoid,'')<>'' OR ISNULL(I.ReasonVoid1,'')<>'' OR ISNULL(I.ReasonVoid2,'')<>'') THEN 'VOID'
            WHEN I.IsApproved2=1 THEN 'ACKNOWLEDGE 2'
            WHEN I.IsApproved1=1 THEN 'ACKNOWLEDGE 1' WHEN I.IsApproved=1 THEN 'VERIFIED' ELSE 'CHECKED' END WorkflowStatus,
       CASE WHEN I.IsApproved=0 THEN 'SPV' WHEN I.IsApproved1=0 THEN 'CHIEF_SEC' WHEN I.IsApproved2=0 THEN 'CHIEF_ENG' ELSE 'COMPLETED' END CurrentStageCode
" + scope + @"
ORDER BY I.InspectionDate DESC,I.InspectionID DESC", createParameters(true));
                if (countOnly) return rows == null ? 0 : rows.Rows.Count;

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
        public static object GetInspectionApprovalCounts(string employeeId, string companyId, string locationId,
            string dateFrom, string dateThru)
        {
            employeeId = GFC.CurrentEmployeeID();
            bool isAdministrator = IsInspectionAdministrator(employeeId);
            if (!isAdministrator) employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (String.IsNullOrWhiteSpace(employeeId))
                throw new HttpException(403, "Approver identity is required.");

            // Use the same queue queries as the dashboard, in count-only mode.
            // No email dispatch and no type/template/schedule filters are applied.
            int outstandingStandard = Convert.ToInt32(GetInspectionApprovalQueueInternal(
                employeeId, companyId, locationId, "OUTSTANDING", "", "", "", "", "", "", true, false));
            int outstandingLightning = Convert.ToInt32(GetLightningInspectionApprovalQueueInternal(
                employeeId, companyId, locationId, "OUTSTANDING", "", "", "", "", "", "", true, false));

            // Approved follows the date range shown by the Approved tab (default: today).
            int approvedStandard = Convert.ToInt32(GetInspectionApprovalQueueInternal(
                employeeId, companyId, locationId, "APPROVED", dateFrom, dateThru, "", "", "", "", true, false));
            int approvedLightning = Convert.ToInt32(GetLightningInspectionApprovalQueueInternal(
                employeeId, companyId, locationId, "APPROVED", dateFrom, dateThru, "", "", "", "", true, false));

            int voidStandard = Convert.ToInt32(GetInspectionApprovalQueueInternal(
                employeeId, companyId, locationId, "VOID", "", "", "", "", "", "", true, false));
            int voidLightning = Convert.ToInt32(GetLightningInspectionApprovalQueueInternal(
                employeeId, companyId, locationId, "VOID", "", "", "", "", "", "", true, false));

            return new
            {
                success = true,
                outstanding = outstandingStandard + outstandingLightning,
                approved = approvedStandard + approvedLightning,
                voided = voidStandard + voidLightning
            };
        }

        [WebMethod]
        public static object ProcessLightningInspectionApproval(long inspectionId, string action, string employeeId,
            string companyId, string locationId, string remark, string approvalToken)
        {
            RequireSameOriginPost();
            employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (String.IsNullOrWhiteSpace(employeeId))
                throw new HttpException(403, "Approver identity is required.");
            if (!String.Equals(action, "APPROVE", StringComparison.OrdinalIgnoreCase) &&
                !String.Equals(action, "VOID", StringComparison.OrdinalIgnoreCase))
                throw new HttpException(400, "Invalid Lightning approval action.");
            if (String.Equals(action, "VOID", StringComparison.OrdinalIgnoreCase) && String.IsNullOrWhiteSpace(remark))
                throw new HttpException(400, "Reason for void is required.");

            Guid parsedApprovalToken;
            if (!String.IsNullOrWhiteSpace(approvalToken) && !Guid.TryParse(approvalToken, out parsedApprovalToken))
                throw new HttpException(400, "Invalid approval email token.");

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
                    new SqlParameter("@p_CorrectionUrl", correctionUrl),
                    new SqlParameter("@p_ApprovalToken", String.IsNullOrWhiteSpace(approvalToken) ? (object)DBNull.Value : new Guid(approvalToken))
                }, true, true);
                object emailDispatch;
                try { emailDispatch = DispatchInspectionEmailOutbox(20, employeeId, companyId); }
                catch (Exception emailError) { emailDispatch = new { configured = false, error = emailError.Message }; }
                return new
                {
                    success = true,
                    action = action.ToUpperInvariant(),
                    inspectionId = inspectionId,
                    workflowStatus = saved != null && saved.Rows.Count > 0 ? Convert.ToString(saved.Rows[0]["WorkflowStatus"]) : "",
                    currentStageCode = saved != null && saved.Rows.Count > 0 ? Convert.ToString(saved.Rows[0]["CurrentStageCode"]) : "",
                    emailDispatch = emailDispatch
                };
            }
        }

        private static object BuildInspectionRepeatConfig(DataRow row)
        {
            if (row == null) return null;
            return new Dictionary<string, object>
            {
                { "repeatMode", GF.GetString(row["RepeatMode"]) },
                { "columnCount", Convert.ToInt32(row["ColumnCount"]) },
                { "objectLabel", GF.GetString(row["ObjectLabel"]) },
                { "countMode", GF.GetString(row["CountMode"]) },
                { "fixedCount", row["FixedCount"] == DBNull.Value ? (int?)null : Convert.ToInt32(row["FixedCount"]) },
                { "minCount", row["MinCount"] == DBNull.Value ? (int?)null : Convert.ToInt32(row["MinCount"]) },
                { "maxCount", row["MaxCount"] == DBNull.Value ? (int?)null : Convert.ToInt32(row["MaxCount"]) }
            };
        }

        private static List<Dictionary<string, object>> BuildInspectionRepeatFields(DataTable fields, int idItem)
        {
            if (fields == null) return new List<Dictionary<string, object>>();
            return fields.AsEnumerable()
                .Where(row => Convert.ToInt32(row["IDItem"]) == idItem)
                .OrderBy(row => Convert.ToInt32(row["DisplayOrder"]))
                .Select(row => new Dictionary<string, object>
                {
                    { "idRepeat", Convert.ToInt32(row["IDRepeat"]) },
                    { "fieldLabel", GF.GetString(row["FieldLabel"]) },
                    { "fieldType", GF.GetString(row["FieldType"]) },
                    { "optionList", String.IsNullOrWhiteSpace(GF.GetString(row["OptionList"])) ? new string[0] : GF.GetString(row["OptionList"]).Split(';') },
                    { "unit", GF.GetString(row["Unit"]) },
                    { "min", row["MinValue"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(row["MinValue"]) },
                    { "max", row["MaxValue"] == DBNull.Value ? (decimal?)null : Convert.ToDecimal(row["MaxValue"]) },
                    { "minInclusive", row["MinInclusive"] == DBNull.Value || Convert.ToBoolean(row["MinInclusive"]) },
                    { "maxInclusive", row["MaxInclusive"] == DBNull.Value || Convert.ToBoolean(row["MaxInclusive"]) },
                    { "isRequired", Convert.ToBoolean(row["IsRequired"]) },
                    { "groupName", GF.GetString(row["GroupName"]) },
                    { "displayOrder", Convert.ToInt32(row["DisplayOrder"]) }
                }).ToList();
        }

        [WebMethod]
        public static object GetInspectionApprovalDetail(long inspectionId, string employeeId)
        {
            employeeId = GFC.CurrentEmployeeID();
            if (!IsInspectionAdministrator(employeeId))
                employeeId = GFC.RequireMenuEmployee("20022");
            if (String.IsNullOrWhiteSpace(employeeId))
                throw new HttpException(403, "Supervisor identity is required.");
            return GetInspectionDetail(inspectionId, employeeId, false);
        }

        [WebMethod]
        public static object GetTechnicianSubmittedInspectionDetail(long inspectionId, string employeeId)
        {
            employeeId = GFC.RequireMenuEmployee("20021");
            if (String.IsNullOrWhiteSpace(employeeId))
                throw new HttpException(403, "Technician identity is required.");
            return GetInspectionDetail(inspectionId, employeeId, true);
        }

        private static object GetInspectionDetail(long inspectionId, string employeeId, bool technicianView)
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable header = br.EQueryP(@"
SELECT I.InspectionID, I.InspectionNo, I.CompanyID, I.LocationID, I.SectionID, I.Status, I.InspectionTypeName,
       I.InspectionTypeDetailName, ISNULL(NULLIF(I.InspectionMode,''),ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')) AS InspectionMode,
       CASE WHEN ISNULL(NULLIF(IT.InspectionPointMode,''),'')='DYNAMIC' THEN 'DYNAMIC_LIST'
            WHEN ISNULL(NULLIF(IT.InspectionPointMode,''),'')='MAP' THEN 'MAP' ELSE 'STANDARD' END AS InspectionLayoutCode,
       ISNULL(NULLIF(IT.InspectionPointMode,''),'') AS InspectionPointMode,
       ISNULL(NULLIF(IT.ScheduleSelectionMode,''),'PARAM') AS ScheduleSelectionMode,
       CASE WHEN I.Status='DRAFT' AND (ISNULL(I.ReasonVoid,'')<>'' OR ISNULL(I.ReasonVoid1,'')<>'' OR ISNULL(I.ReasonVoid2,'')<>'') THEN 'VOID'
            WHEN ISNULL(IT.InspectionMode,'STANDARD')='BATCH' AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='INSPECT' THEN CASE WHEN I.IsApproved2=1 THEN 'ACKNOWLEDGE 2' WHEN I.IsApproved1=1 THEN 'ACKNOWLEDGE 1' WHEN I.IsApproved=1 THEN 'VERIFIED' ELSE 'CHECKED' END
            WHEN ISNULL(IT.InspectionMode,'STANDARD')='BATCH' AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='PARAM' THEN CASE WHEN I.IsApproved1=1 THEN 'ACKNOWLEDGED' WHEN I.IsApproved=1 THEN 'VERIFIED' ELSE 'CHECKED' END
            WHEN I.IsApproved=1 THEN 'APPROVED' ELSE 'SUBMITTED' END WorkflowStatus,
       CASE WHEN ISNULL(IT.InspectionMode,'STANDARD')='BATCH' AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='INSPECT' THEN CASE WHEN I.IsApproved=0 THEN 'SPV' WHEN I.IsApproved1=0 THEN 'CHIEF_SEC' WHEN I.IsApproved2=0 THEN 'CHIEF_ENG' ELSE 'COMPLETED' END
            WHEN ISNULL(IT.InspectionMode,'STANDARD')='BATCH' AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='PARAM' THEN CASE WHEN I.IsApproved=0 THEN 'SPV' WHEN I.IsApproved1=0 THEN dbo.fnINSPEC_ChiefRoleForSection(I.SectionID) ELSE 'COMPLETED' END
            WHEN I.IsApproved=0 THEN 'SPV' ELSE 'COMPLETED' END CurrentStageCode,
       I.InspectionTypeCode, I.InspectionTypeDetailCode, I.ScheduledTime, I.IDTemplate, I.IDVersion, I.TemplateNo, I.TemplateVersion,
       I.InspectionDate, CONVERT(VARCHAR(23), I.StartDateTime, 126) AS StartDateTime, CONVERT(VARCHAR(23), I.EndDateTime, 126) AS EndDateTime, I.Summary, I.OwnerEmployeeID,
       ISNULL(ET.Name,I.OwnerEmployeeID) AS TechnicianName,
       I.IsSubmitted,I.SubmittedBy,ISNULL(ES.Name,I.SubmittedBy) AS SubmittedByName,I.SubmittedDate,
       I.IsApproved,I.ApprovedBy,ISNULL(EA.Name,I.ApprovedBy) AS ApprovedByName,I.ApprovedDate,
       I.ApprovalRemark,I.ReasonVoid,I.ReasonVoid1,I.ReasonVoid2,
       I.IsApproved1,I.Approved1By,ISNULL(EA1.Name,I.Approved1By) AS Approved1ByName,I.Approved1Date,
       I.IsApproved2,I.Approved2By,ISNULL(EA2.Name,I.Approved2By) AS Approved2ByName,I.Approved2Date,
       I.FollowUp, I.FollowUpSection, I.FollowUpRemark, I.FollowUpWONo,
       I.TenantID,I.SuiteNo,ISNULL(TG.TenantName,'') AS TenantName,
       I.GPSLatitude,I.GPSLongitude,I.GPSAccuracy,I.GPSCapturedAt
FROM dbo.PIP_T_Inspection I
LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
LEFT JOIN dbo.THD_M_GeneralInformation TG
       ON TG.CompanyID=I.CompanyID AND TG.LocationID=I.LocationID AND TG.TenantID=I.TenantID
LEFT JOIN dbo.M_HRD_Employee ET ON ET.EmployeeID=I.OwnerEmployeeID
LEFT JOIN dbo.M_HRD_Employee ES ON ES.EmployeeID=I.SubmittedBy
LEFT JOIN dbo.M_HRD_Employee EA ON EA.EmployeeID=I.ApprovedBy
LEFT JOIN dbo.M_HRD_Employee EA1 ON EA1.EmployeeID=I.Approved1By
LEFT JOIN dbo.M_HRD_Employee EA2 ON EA2.EmployeeID=I.Approved2By
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
       ((I.Status='DONE' AND ISNULL(I.IsSubmitted,0)=1)
        OR (I.Status='DRAFT' AND ISNULL(I.IsSubmitted,0)=0 AND (ISNULL(I.ReasonVoid,'')<>'' OR ISNULL(I.ReasonVoid1,'')<>'' OR ISNULL(I.ReasonVoid2,'')<>'')))
  )
  AND (
      (@TechnicianView=1
       AND I.OwnerEmployeeID=@EmployeeID
       AND I.Status='DONE'
       AND ISNULL(I.IsSubmitted,0)=1
       AND EXISTS (
           SELECT 1
           FROM dbo.SysWebUser SU
           WHERE SU.EmployeeID=@EmployeeID
             AND SU.IsActive=1
             AND (
                 EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                         WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                           AND C.CompanyID=I.CompanyID AND C.LocationID=I.LocationID)
                 OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                            WHERE L.CompanyID=I.CompanyID AND L.LocationID=I.LocationID)
             )
       )
      )
      OR
      (@TechnicianView=0
       AND EXISTS (
           SELECT 1 FROM dbo.SysWebUser SU
           WHERE SU.EmployeeID=@EmployeeID AND SU.IsActive=1
             AND (@IsAdministrator=1 OR EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') AM WHERE AM.MenuID='20022'))
             AND (@IsAdministrator=1 OR (
               ((ISNULL(IT.InspectionMode,'STANDARD')='STANDARD' OR ISNULL(NULLIF(IT.ScheduleSelectionMode,''),'PARAM')<>'INSPECT') AND EXISTS (
                   SELECT 1 FROM dbo.SysWebCommonValue C
                   WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                     AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID
                     AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
               ))
               OR (ISNULL(IT.InspectionMode,'STANDARD')='BATCH'
                   AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='PARAM'
                   AND ISNULL(IT.InspectionMode,'STANDARD')='BATCH'
                   AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='PARAM'
                   AND ISNULL(I.IsApproved,0)=1 AND ISNULL(I.IsApproved1,0)=0
                   AND EXISTS (
                       SELECT 1 FROM dbo.SysWebCommonValue C
                       WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                         AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';'+dbo.fnINSPEC_ChiefRoleForSection(I.SectionID)
                         AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
                   ))
               OR (ISNULL(IT.InspectionMode,'STANDARD')='STANDARD'
                   AND ISNULL(I.IsApproved,0)=1 AND I.ApprovalBatchID IS NOT NULL
                   AND EXISTS (
                       SELECT 1 FROM dbo.PIP_T_Inspection_ApprovalBatch B
                       WHERE B.ApprovalBatchID=I.ApprovalBatchID AND B.BatchStatus IN ('PENDING','APPROVED')
                         AND EXISTS (
                             SELECT 1 FROM dbo.SysWebCommonValue C
                             WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                               AND C.ID=CONVERT(VARCHAR(30),B.CompanyID)+CONVERT(VARCHAR(30),B.LocationID)+';'+CASE UPPER(LTRIM(RTRIM(ISNULL(B.ProfitCenterNo,'')))) WHEN 'PENG' THEN 'CHIEF_ENG' WHEN 'PSEC' THEN 'CHIEF_SEC' WHEN 'PHKP' THEN 'CHIEF_HK' ELSE '' END
                               AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
                         )
                   ))
               OR ((ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')='BATCH' AND ISNULL(NULLIF(IT.ScheduleSelectionMode,''),'PARAM')='INSPECT') AND (
                   EXISTS (
                       SELECT 1 FROM dbo.SysWebCommonValue C
                       WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                         AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
                         AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID
                   )
                   OR EXISTS (
                       SELECT 1 FROM dbo.SysWebCommonValue C
                       WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                         AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
                         AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_ENG'
                   )
                   OR EXISTS (
                       SELECT 1 FROM dbo.SysWebCommonValue C
                       WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
                         AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
                         AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';CHIEF_SEC'
                   )
               ))
             ))
             AND (
                 EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C
                         WHERE C.UserID=SU.EmployeeID AND C.AppID='pip'
                           AND C.CompanyID=I.CompanyID AND C.LocationID=I.LocationID)
                 OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', SU.EmployeeID, '') L
                            WHERE L.CompanyID=I.CompanyID AND L.LocationID=I.LocationID)
             )
       )
      )
  )",
                    new SqlParameter[] {
                        new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)),
                        new SqlParameter("@InspectionID", inspectionId),
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@TechnicianView", technicianView ? 1 : 0),
                        new SqlParameter("@IsAdministrator", !technicianView && IsInspectionAdministrator(employeeId) ? 1 : 0)
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
                string approvalScheduleMode = GF.GetString(header.Rows[0]["ScheduleSelectionMode"]).ToUpperInvariant();
                bool isLightningApproval = String.Equals(approvalInspectionMode, "BATCH", StringComparison.OrdinalIgnoreCase) && approvalScheduleMode == "INSPECT";
                if (String.Equals(approvalInspectionMode, "BATCH", StringComparison.OrdinalIgnoreCase))
                {
                    DataTable pointMasterRows = br.EQueryP(@"
SELECT TP.InspectionPointTransactionID, TP.ClientPointID, TP.InspectionPointID,
       TP.PointCode,TP.PointName,
       TP.ScheduleTime, TP.InspectionDateTime, TP.Status, TP.AbnormalRemark,
       ISNULL(P.IsNormalAbnormalRequired,0) IsNormalAbnormalRequired,
       ISNULL(NULLIF(TP.PointCode,''),P.PointCode) AS ResolvedPointCode,
       ISNULL(NULLIF(TP.PointName,''),P.PointName) AS ResolvedPointName,
       P.PointObjectType,P.PointDescription,P.MapID,P.MapX,P.MapY,
       P.ShapeType,P.SvgPathData,P.ShapeAttributes,P.StrokeWidth,
       M.MapCode,M.MapName,M.ImagePath AS MapUrl,M.MapVersion,M.MapGroupID,
       MG.GroupCode,MG.GroupName,MG.Sequence MapGroupSequence
FROM dbo.PIP_T_InspectionPoint TP
LEFT JOIN dbo.PIP_M_InspectionPoint P ON P.InspectionPointID=TP.InspectionPointID
LEFT JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
LEFT JOIN dbo.PIP_M_InspectionMapGroup MG ON MG.MapGroupID=M.MapGroupID
WHERE TP.InspectionID=@InspectionID
ORDER BY ISNULL(P.DisplayOrder,0),ISNULL(TP.PointCode,P.PointCode)",
                        new SqlParameter[] { new SqlParameter("@InspectionID", inspectionId) });

                    DataTable pointResultRows = br.EQueryP(@"
SELECT R.InspectionPointTransactionID,R.IDItem,R.ItemLabel,R.ItemType,R.Value,
       R.Remark1,R.Remark2,R.IsAnomali,R.DisplayOrder,V.ObjectIndex,V.FieldName,V.Value AS FieldValue
FROM dbo.PIP_T_InspectionResult R
LEFT JOIN dbo.PIP_T_InspectionResultValue V ON V.InspectionResultID=R.InspectionResultID
WHERE R.InspectionID=@InspectionID
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
                                        { "InspectionPointID", pointRow["InspectionPointID"] == DBNull.Value ? -(returnedPointList.Count + 1) : Convert.ToInt64(pointRow["InspectionPointID"]) },
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
                            { "MapGroupID", pointRow["MapGroupID"] == DBNull.Value ? 0 : Convert.ToInt64(pointRow["MapGroupID"]) },
                            { "GroupCode", GF.GetString(pointRow["GroupCode"]) },
                            { "GroupName", GF.GetString(pointRow["GroupName"]) },
                            { "Items", pointItems.ContainsKey(pointTransactionID) ? (object)pointItems[pointTransactionID].Values.OrderBy(x => Convert.ToInt32(x["DisplayOrder"])).ToList() : new List<Dictionary<string, object>>() }
                        };
                        batchPointRows.Add(pointData);
                        if (mapID > 0 && mapIDs.Add(mapID))
                        {
                            batchMapRows.Add(new Dictionary<string, object> {
                                { "MapID", mapID },
                                { "MapCode", GF.GetString(pointRow["MapCode"]) },
                                { "MapName", GF.GetString(pointRow["MapName"]) },
                                { "MapGroupID", pointRow["MapGroupID"] == DBNull.Value ? 0 : Convert.ToInt64(pointRow["MapGroupID"]) },
                                { "GroupCode", GF.GetString(pointRow["GroupCode"]) },
                                { "GroupName", GF.GetString(pointRow["GroupName"]) },
                                { "GroupSequence", pointRow["MapGroupSequence"] == DBNull.Value ? 0 : Convert.ToInt32(pointRow["MapGroupSequence"]) },
                                { "MapUrl", ResolveInspectionMapUrl(GF.GetString(pointRow["MapUrl"]), GF.GetString(header.Rows[0]["CompanyID"]), GF.GetString(header.Rows[0]["LocationID"])) },
                                { "MapVersion", pointRow["MapVersion"] == DBNull.Value ? 0 : Convert.ToInt32(pointRow["MapVersion"]) }
                            });
                        }
                    }

                    if (isLightningApproval)
                    {
                        DataTable scheduleRows = br.EQueryP(@"
SELECT DISTINCT D.ScheduleTime,'SUBMITTED' ScheduleStatus,I.SubmittedDate
FROM dbo.PIP_T_Inspection I
JOIN dbo.PIP_M_InspectionTypeDetail D
  ON D.InspectionTypeCode=I.InspectionTypeCode
 AND D.InspectionTypeDetailCode=I.InspectionTypeDetailCode
WHERE I.InspectionID=@InspectionID
ORDER BY D.ScheduleTime",
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
                    DataTable templateRepeatConfig = br.EQueryP(@"
SELECT R.IDItem,R.RepeatMode,R.ColumnCount,R.ObjectLabel,R.CountMode,R.FixedCount,R.MinCount,R.MaxCount
FROM dbo.PIP_M_CheckListWOPM_ItemRepeat R
JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=R.IDItem
JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
WHERE S.IDVersion=@IDVersion",
                        new SqlParameter[] { new SqlParameter("@IDVersion", Convert.ToInt32(header.Rows[0]["IDVersion"])) });
                    DataTable templateRepeatFields = br.EQueryP(@"
SELECT F.IDItem,F.IDRepeat,F.FieldLabel,F.FieldType,F.OptionList,F.Unit,F.MinValue,F.MaxValue,
       F.MinInclusive,F.MaxInclusive,F.IsRequired,F.GroupName,F.DisplayOrder
FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F
JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=F.IDItem
JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
WHERE S.IDVersion=@IDVersion
ORDER BY F.IDItem,F.DisplayOrder,F.IDRepeat",
                        new SqlParameter[] { new SqlParameter("@IDVersion", Convert.ToInt32(header.Rows[0]["IDVersion"])) });

                    var sections = templateItems.AsEnumerable()
                        .GroupBy(row => new
                        {
                            IDSection = Convert.ToInt32(row["IDSection"]),
                            SectionName = row["SectionName"].ToString(),
                            SectionOrder = Convert.ToInt32(row["SectionOrder"])
                        })
                        .OrderBy(group => group.Key.SectionOrder)
                        .Select(group => new
                        {
                            idSection = group.Key.IDSection,
                            sectionName = group.Key.SectionName,
                            items = group.Select(itemRow =>
                            {
                                string itemType = itemRow["ItemType"].ToString();
                                string optionList = itemType == "OPTION"
                                    ? (String.IsNullOrEmpty(itemRow["OptionList"].ToString())
                                        ? itemRow["StatusOption"].ToString() : itemRow["OptionList"].ToString())
                                    : "";
                                var itemGroups = templateGroups.AsEnumerable()
                                    .Where(g => g["IDItem"].ToString() == itemRow["IDItem"].ToString())
                                    .OrderBy(g => g["DisplayOrder"])
                                    .Select(g => new
                                    {
                                        groupName = g["GroupName"].ToString(),
                                        fieldList = g["FieldList"].ToString(),
                                        unit = g["Unit"].ToString()
                                    }).ToList();
                                int repeatItemId = Convert.ToInt32(itemRow["IDItem"]);
                                DataRow repeatConfigRow = templateRepeatConfig.AsEnumerable()
                                    .FirstOrDefault(row => Convert.ToInt32(row["IDItem"]) == repeatItemId);
                                var itemRepeatFields = BuildInspectionRepeatFields(templateRepeatFields, repeatItemId);
                                return new
                                {
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
                                    groups = itemGroups.Count > 0 ? itemGroups : null,
                                    repeat = itemType == "REPEAT" ? BuildInspectionRepeatConfig(repeatConfigRow) : null,
                                    repeatFields = itemType == "REPEAT" && itemRepeatFields.Count > 0 ? itemRepeatFields : null
                                };
                            }).ToList()
                        }).ToList();
                    approvalTemplateSnapshot = new
                    {
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
                return new
                {
                    success = true,
                    header = h,
                    items = itemRows,
                    photos = photos,
                    template = approvalTemplateSnapshot,
                    points = batchPointRows,
                    maps = batchMapRows,
                    schedules = batchScheduleRows
                };
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
SELECT I.InspectionID, I.ClientInspectionID, I.InspectionNo, I.CompanyID, I.LocationID,
       I.TenantID, I.SuiteNo, ISNULL(TG.TenantName,'') AS TenantName, I.SectionID,
       I.InspectionTypeCode, I.InspectionTypeName, I.InspectionTypeDetailCode,
       I.InspectionTypeDetailName, I.ScheduledTime, I.IDTemplate, I.IDVersion,
       I.TemplateNo, I.TemplateName, I.TemplateVersion,
       CONVERT(VARCHAR(10),I.InspectionDate,120) InspectionDate,
       CONVERT(VARCHAR(23),I.StartDateTime,126) StartDateTime,
       CONVERT(VARCHAR(23),I.EndDateTime,126) EndDateTime,
       I.Status, I.Summary, I.OwnerEmployeeID,
       I.FollowUp,I.FollowUpSection,I.FollowUpRemark,I.FollowUpWONo,
       I.ReasonVoid, I.ReasonVoid1, I.ReasonVoid2, I.UpdateDate,
       ISNULL(NULLIF(I.InspectionMode,''),ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')) AS InspectionMode,
       ISNULL(NULLIF(IT.InspectionPointMode,''),'') AS InspectionPointMode,
       ISNULL(NULLIF(IT.ScheduleSelectionMode,''),'PARAM') AS ScheduleSelectionMode
FROM dbo.PIP_T_Inspection I
LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
LEFT JOIN dbo.THD_M_GeneralInformation TG
       ON TG.CompanyID=I.CompanyID AND TG.LocationID=I.LocationID AND TG.TenantID=I.TenantID
WHERE I.OwnerEmployeeID=@EmployeeID AND I.CompanyID=@CompanyID AND I.LocationID=@LocationID
  AND ISNULL(I.IsActive,1)=1
  AND I.Status='DRAFT' AND I.IsApproved=0
  AND ISNULL(I.IsSubmitted,0)=0 AND (ISNULL(I.ReasonVoid,'')<>'' OR ISNULL(I.ReasonVoid1,'')<>'' OR ISNULL(I.ReasonVoid2,'')<>'')
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

                    if (String.Equals(GF.GetString(header["InspectionMode"]), "BATCH", StringComparison.OrdinalIgnoreCase))
                    {
                        DataTable returnedPoints = br.EQueryP(@"
SELECT TP.InspectionPointTransactionID,TP.ClientPointID,TP.InspectionPointID,
       TP.PointCode,TP.PointName,
       TP.ScheduleTime,TP.InspectionDateTime,TP.Status,TP.AbnormalRemark,ISNULL(P.IsNormalAbnormalRequired,0) IsNormalAbnormalRequired,
       P.PointObjectType,
       P.PointDescription,P.MapID,P.MapX,P.MapY,
       P.ShapeType,P.SvgPathData,P.ShapeAttributes,P.StrokeWidth
FROM dbo.PIP_T_InspectionPoint TP
LEFT JOIN dbo.PIP_M_InspectionPoint P ON P.InspectionPointID=TP.InspectionPointID
WHERE TP.InspectionID=@InspectionID
ORDER BY ISNULL(P.DisplayOrder,0),TP.PointCode",
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
                
                                { "InspectionPointID", pointRow["InspectionPointID"] == DBNull.Value ? -(returnedPointList.Count + 1) : Convert.ToInt64(pointRow["InspectionPointID"]) },
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
                        if (String.Equals(GF.GetString(header["ScheduleSelectionMode"]), "INSPECT", StringComparison.OrdinalIgnoreCase))
                        {
                            DataTable returnedSchedules = br.EQueryP(@"
SELECT DISTINCT D.ScheduleTime,'SUBMITTED' ScheduleStatus,I.SubmittedDate
FROM dbo.PIP_T_Inspection I
JOIN dbo.PIP_M_InspectionTypeDetail D
  ON D.InspectionTypeCode=I.InspectionTypeCode
 AND D.InspectionTypeDetailCode=I.InspectionTypeDetailCode
WHERE I.InspectionID=@InspectionID
ORDER BY D.ScheduleTime",
                                new SqlParameter[] { new SqlParameter("@InspectionID", id) });
                            record["Schedules"] = returnedSchedules.AsEnumerable().Select(row => new
                            {
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
                        DataTable templateRepeatConfig = br.EQueryP(@"
SELECT R.IDItem,R.RepeatMode,R.ColumnCount,R.ObjectLabel,R.CountMode,R.FixedCount,R.MinCount,R.MaxCount
FROM dbo.PIP_M_CheckListWOPM_ItemRepeat R
JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=R.IDItem
JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
WHERE S.IDVersion=@IDVersion",
                            new SqlParameter[] { new SqlParameter("@IDVersion", Convert.ToInt32(header["IDVersion"])) });
                        DataTable templateRepeatFields = br.EQueryP(@"
SELECT F.IDItem,F.IDRepeat,F.FieldLabel,F.FieldType,F.OptionList,F.Unit,F.MinValue,F.MaxValue,
       F.MinInclusive,F.MaxInclusive,F.IsRequired,F.GroupName,F.DisplayOrder
FROM dbo.PIP_M_CheckListWOPM_ItemRepeatField F
JOIN dbo.PIP_M_CheckListWOPM_Item I ON I.IDItem=F.IDItem
JOIN dbo.PIP_M_CheckListWOPM_Section S ON S.IDSection=I.IDSection
WHERE S.IDVersion=@IDVersion
ORDER BY F.IDItem,F.DisplayOrder,F.IDRepeat",
                            new SqlParameter[] { new SqlParameter("@IDVersion", Convert.ToInt32(header["IDVersion"])) });

                        var sections = templateItems.AsEnumerable()
                            .GroupBy(row => new
                            {
                                IDSection = Convert.ToInt32(row["IDSection"]),
                                SectionName = row["SectionName"].ToString(),
                                SectionOrder = Convert.ToInt32(row["SectionOrder"])
                            })
                            .OrderBy(group => group.Key.SectionOrder)
                            .Select(group => new
                            {
                                idSection = group.Key.IDSection,
                                sectionName = group.Key.SectionName,
                                items = group.Select(itemRow =>
                                {
                                    string itemType = itemRow["ItemType"].ToString();
                                    string optionList = itemType == "OPTION"
                                        ? (String.IsNullOrEmpty(itemRow["OptionList"].ToString())
                                            ? itemRow["StatusOption"].ToString() : itemRow["OptionList"].ToString())
                                        : "";
                                    var itemGroups = templateGroups.AsEnumerable()
                                        .Where(g => g["IDItem"].ToString() == itemRow["IDItem"].ToString())
                                        .OrderBy(g => g["DisplayOrder"])
                                        .Select(g => new
                                        {
                                            groupName = g["GroupName"].ToString(),
                                            fieldList = g["FieldList"].ToString(),
                                            unit = g["Unit"].ToString()
                                        }).ToList();
                                    int repeatItemId = Convert.ToInt32(itemRow["IDItem"]);
                                    DataRow repeatConfigRow = templateRepeatConfig.AsEnumerable()
                                        .FirstOrDefault(row => Convert.ToInt32(row["IDItem"]) == repeatItemId);
                                    var itemRepeatFields = BuildInspectionRepeatFields(templateRepeatFields, repeatItemId);
                                    return new
                                    {
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
                                        groups = itemGroups.Count > 0 ? itemGroups : null,
                                        repeat = itemType == "REPEAT" ? BuildInspectionRepeatConfig(repeatConfigRow) : null,
                                        repeatFields = itemType == "REPEAT" && itemRepeatFields.Count > 0 ? itemRepeatFields : null
                                    };
                                }).ToList()
                            }).ToList();
                        record["TemplateSnapshot"] = new
                        {
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



        private static string GetStandardBatchSnapshotFolder(long approvalBatchId)
        {
            string root = GF.Path_FolerView();
            if (String.IsNullOrWhiteSpace(root))
                throw new InvalidOperationException("Folder report INSPEC belum dikonfigurasi.");
            return Path.Combine(root, "InspectionApprovalBatch", approvalBatchId.ToString(CultureInfo.InvariantCulture));
        }

        private static string SafeBatchReportSegment(string value)
        {
            string clean = System.Text.RegularExpressions.Regex.Replace(
                (value ?? "").Trim(), @"[\\/:*?""<>|\x00-\x1F]", "_").Trim().Trim('.');
            return clean.Length == 0 ? "TYPE" : clean.Substring(0, Math.Min(40, clean.Length));
        }

        private static List<Dictionary<string, string>> GenerateStandardBatchReports(
            long approvalBatchId, string employeeId, string companyId, string locationId, bool createSnapshot)
        {
            DataTable members;
            using (var br = new WAL.BR.CF())
            {
                members = br.EQueryP(@"
SELECT I.InspectionID,I.InspectionTypeCode,I.InspectionTypeName,
       B.ReportSnapshotFolder,B.EmailStatus
FROM dbo.PIP_T_Inspection_ApprovalBatch B
JOIN dbo.PIP_T_Inspection I ON I.ApprovalBatchID=B.ApprovalBatchID
WHERE B.ApprovalBatchID=@BatchID
  AND B.CompanyID=@CompanyID AND B.LocationID=@LocationID
ORDER BY I.InspectionTypeCode,I.InspectionID",
                    new SqlParameter[] {
                        new SqlParameter("@BatchID", approvalBatchId),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId)
                    });
            }
            if (members == null || members.Rows.Count == 0)
                throw new InvalidOperationException("Batch tidak memiliki inspeksi yang dapat dibuatkan report.");

            string storedSnapshotFolder = Convert.ToString(members.Rows[0]["ReportSnapshotFolder"]);
            string snapshotFolder = String.IsNullOrWhiteSpace(storedSnapshotFolder)
                ? GetStandardBatchSnapshotFolder(approvalBatchId) : storedSnapshotFolder;
            bool emailAlreadySent = String.Equals(Convert.ToString(members.Rows[0]["EmailStatus"]), "SENT", StringComparison.OrdinalIgnoreCase);
            if (emailAlreadySent && !Directory.Exists(snapshotFolder))
                throw new InvalidOperationException("Snapshot folder untuk report yang sudah dikirim tidak ditemukan. Report tidak akan digenerate ulang agar isi lampiran tetap konsisten.");
            if (createSnapshot && !Directory.Exists(snapshotFolder))
                Directory.CreateDirectory(snapshotFolder);

            var reports = new List<Dictionary<string, string>>();
            var groups = members.AsEnumerable()
                .GroupBy(row => Convert.ToString(row["InspectionTypeCode"]).Trim(),
                    StringComparer.OrdinalIgnoreCase)
                .OrderBy(group => group.Key, StringComparer.OrdinalIgnoreCase);

            foreach (var group in groups)
            {
                string typeCode = group.Key;
                if (String.IsNullOrWhiteSpace(typeCode))
                    throw new InvalidOperationException("InspectionTypeCode kosong pada salah satu anggota batch.");

                string existingSnapshot = null;
                if (Directory.Exists(snapshotFolder))
                {
                    string prefix = "TYPE_" + SafeBatchReportSegment(typeCode) + "_";
                    existingSnapshot = Directory.GetFiles(snapshotFolder, prefix + "*.xlsx")
                        .OrderByDescending(File.GetLastWriteTimeUtc).FirstOrDefault();
                }

                string reportPath = existingSnapshot;
                string reportName = existingSnapshot == null ? "" : Path.GetFileName(existingSnapshot);

                if (String.IsNullOrWhiteSpace(reportPath))
                {
                    if (emailAlreadySent)
                        throw new InvalidOperationException("Snapshot XLSX untuk InspectionTypeCode " + typeCode + " tidak ditemukan. Report tidak akan digenerate ulang setelah email terkirim.");
                    DataTable selected = new DataTable();
                    selected.Columns.Add("InspectionID", typeof(long));
                    foreach (DataRow row in group)
                        selected.Rows.Add(Convert.ToInt64(row["InspectionID"]));

                    // R_Report uses the authenticated employee folder. Each generated
                    // file is copied immediately to a unique per-type batch snapshot path.
                    var report = R_Report.GenerateInspectionXlsx(
                        selected, companyId, locationId, employeeId);
                    if (report == null || !report.Success ||
                        String.IsNullOrWhiteSpace(report.StoragePath) || !File.Exists(report.StoragePath))
                        throw new InvalidOperationException(
                            report != null && !String.IsNullOrWhiteSpace(report.Message)
                                ? report.Message : "R_Report gagal membuat XLSX untuk InspectionTypeCode " + typeCode + ".");

                    reportName = "TYPE_" + SafeBatchReportSegment(typeCode) + "_" +
                        Path.GetFileName(report.FileName);
                    reportPath = report.StoragePath;

                    if (createSnapshot || Directory.Exists(snapshotFolder))
                    {
                        if (!Directory.Exists(snapshotFolder))
                            Directory.CreateDirectory(snapshotFolder);
                        string snapshotPath = Path.Combine(snapshotFolder, reportName);
                        File.Copy(report.StoragePath, snapshotPath, true);
                        reportPath = snapshotPath;
                    }
                }

                reports.Add(new Dictionary<string, string>
                {
                    { "InspectionTypeCode", typeCode },
                    { "FileName", reportName },
                    { "StoragePath", reportPath }
                });
            }

            if (createSnapshot)
            {
                using (var br = new WAL.BR.CF())
                {
                    br.EQueryP(@"
UPDATE dbo.PIP_T_Inspection_ApprovalBatch
SET ReportSnapshotFolder=@Folder
WHERE ApprovalBatchID=@BatchID AND CompanyID=@CompanyID AND LocationID=@LocationID",
                        new SqlParameter[] {
                            new SqlParameter("@Folder", snapshotFolder),
                            new SqlParameter("@BatchID", approvalBatchId),
                            new SqlParameter("@CompanyID", companyId),
                            new SqlParameter("@LocationID", locationId)
                        }, true, true);
                }
            }
            return reports;
        }

        private static string SendStandardBatchEmail(
            long approvalBatchId, string employeeId, string companyId, string locationId,
            DataRow batch, IList<Dictionary<string, string>> reports)
        {
            string recipients = Convert.ToString(batch["ChiefRecipients"]);
            DataTable recipientRows;
            using (var br = new WAL.BR.CF())
            {
                recipientRows = br.EQueryP(@"
SELECT DISTINCT LTRIM(RTRIM(E.emailaddress)) EmailAddress
FROM dbo.SplitStringConvertToTable(@Recipients,';') X
JOIN dbo.M_HRD_Employee E ON E.EmployeeID=LTRIM(RTRIM(X.val))
WHERE ISNULL(LTRIM(RTRIM(E.emailaddress)),'')<>''",
                    new SqlParameter[] { new SqlParameter("@Recipients", recipients ?? "") });
            }
            if (recipientRows == null || recipientRows.Rows.Count == 0)
                throw new InvalidOperationException("Alamat email CHIEF belum tersedia di M_HRD_Employee.");
            string emailTo = String.Join(";", recipientRows.AsEnumerable()
                .Select(row => Convert.ToString(row["EmailAddress"]).Trim()).ToArray());
            using (var br = new WAL.BR.CF())
            {
                br.EQueryP("UPDATE dbo.PIP_T_Inspection_ApprovalBatch SET EmailTo=@EmailTo WHERE ApprovalBatchID=@BatchID",
                    new SqlParameter[] { new SqlParameter("@EmailTo", emailTo), new SqlParameter("@BatchID", approvalBatchId) }, true, true);
            }

            string fromAddress = "";
            string fromName = employeeId;
            using (var br = new WAL.BR.CF())
            {
                DataTable sender = br.EQueryP(@"
SELECT TOP 1 ISNULL(LTRIM(RTRIM(emailaddress)),'') EmailAddress,
       ISNULL(NULLIF(LTRIM(RTRIM(Name)),''),@EmployeeID) EmployeeName
FROM dbo.M_HRD_Employee
WHERE EmployeeID=@EmployeeID AND CompanyID=@CompanyID
  AND ISNULL(TerminationDate,'')=''",
                    new SqlParameter[] {
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@CompanyID", companyId)
                    });
                if (sender != null && sender.Rows.Count > 0)
                {
                    fromAddress = Convert.ToString(sender.Rows[0]["EmailAddress"]).Trim();
                    fromName = Convert.ToString(sender.Rows[0]["EmployeeName"]).Trim();
                }
            }
            if (String.IsNullOrWhiteSpace(fromAddress))
                throw new InvalidOperationException("Email pengirim SPV tidak ditemukan di M_HRD_Employee.");

            string host = ConfigurationManager.AppSettings["smtpHost"];
            int port;
            if (String.IsNullOrWhiteSpace(host) ||
                !Int32.TryParse(ConfigurationManager.AppSettings["smtpPort"], out port) || port <= 0)
                throw new InvalidOperationException("Konfigurasi SMTP aplikasi belum lengkap.");

            string appRoot = (HttpContext.Current.Request.ApplicationPath ?? "").TrimEnd('/');
            string origin = HttpContext.Current.Request.Url.GetLeftPart(UriPartial.Authority);
            string approvalUrl = origin + appRoot + "/Secure/inspection.aspx?type=approval&view=chiefbatch";
            string sectionId = Convert.ToString(batch["SectionID"]);
            string dateText = Convert.ToDateTime(batch["InspectionDate"]).ToString("dd-MMM-yyyy", CultureInfo.InvariantCulture);

            using (var message = new MailMessage())
            {
                message.From = new MailAddress(fromAddress, fromName);
                foreach (DataRow recipient in recipientRows.Rows)
                    message.To.Add(new MailAddress(Convert.ToString(recipient["EmailAddress"]).Trim()));
                message.Subject = "INSPEC - STANDARD Inspection Approval Batch #" +
                    approvalBatchId.ToString(CultureInfo.InvariantCulture);
                var body = new StringBuilder();
                body.Append("<p>Dear CHIEF,</p>")
                    .Append("<p>STANDARD inspection approval batch menunggu pemeriksaan dan approval.</p>")
                    .Append("<p><b>Batch:</b> ").Append(approvalBatchId)
                    .Append("<br/><b>Section:</b> ").Append(HttpUtility.HtmlEncode(sectionId))
                    .Append("<br/><b>Inspection Date:</b> ").Append(HttpUtility.HtmlEncode(dateText))
                    .Append("<br/><b>Total report:</b> ").Append(reports.Count).Append("</p>")
                    .Append("<p>Silakan login ke INSPEC untuk melihat detail checklist per inspeksi, membuka report, dan melakukan approval batch:</p>")
                    .Append("<p><a href=\"").Append(HttpUtility.HtmlAttributeEncode(approvalUrl))
                    .Append("\">Open INSPEC Chief Batch Approval</a></p>")
                    .Append("<p>Approval hanya dapat dilakukan setelah login menggunakan akun CHIEF yang terdaftar pada workflow Company/Location dan ProfitCenter.</p>");
                message.Body = body.ToString();
                message.IsBodyHtml = true;

                foreach (Dictionary<string, string> report in reports)
                {
                    string attachmentPath = report["StoragePath"];
                    if (!File.Exists(attachmentPath))
                        throw new FileNotFoundException("Snapshot report tidak ditemukan.", attachmentPath);
                    message.Attachments.Add(new Attachment(attachmentPath));
                }

                using (var smtp = new SmtpClient(host, port))
                {
                    string smtpUser = ConfigurationManager.AppSettings["smtpUser"];
                    string smtpPassword = ConfigurationManager.AppSettings["smtpPassword"];
                    bool useSsl = String.Equals(ConfigurationManager.AppSettings["smtpUseSSL"], "true",
                        StringComparison.OrdinalIgnoreCase);
                    smtp.EnableSsl = useSsl;
                    smtp.DeliveryMethod = SmtpDeliveryMethod.Network;
                    smtp.Timeout = 60000;
                    if (!String.IsNullOrWhiteSpace(smtpUser))
                    {
                        smtp.UseDefaultCredentials = false;
                        smtp.Credentials = new System.Net.NetworkCredential(smtpUser, smtpPassword ?? "");
                    }
                    smtp.Send(message);
                }
            }
            return emailTo;
        }


        [WebMethod]
        public static object GetSPVApprovalSections(string employeeId, string companyId, string locationId)
        {
            employeeId = GFC.CurrentEmployeeID();
            bool isAdministrator = IsInspectionAdministrator(employeeId);
            if (!isAdministrator) employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            using (var br = new WAL.BR.CF())
            {
                DataTable rows = br.EQueryP(@"
SELECT DISTINCT S.SectionID,S.ProfitCenterNo
FROM dbo.PIP_M_Section S
WHERE S.CompanyID=@CompanyID AND S.LocationID=@LocationID
  AND (@IsAdministrator=1 OR EXISTS
  (
      SELECT 1 FROM dbo.SysWebCommonValue C
      WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
        AND C.ID=CONVERT(VARCHAR(30),S.CompanyID)+CONVERT(VARCHAR(30),S.LocationID)+';SPV;'+S.SectionID
        AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X
                    WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
  ))
ORDER BY S.SectionID",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId),
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@IsAdministrator", isAdministrator ? 1 : 0)
                    });
                var data = new List<Dictionary<string, object>>();
                foreach (DataRow row in rows.Rows)
                    data.Add(new Dictionary<string, object> {
                        { "SectionID", Convert.ToString(row["SectionID"]) },
                        { "ProfitCenterNo", Convert.ToString(row["ProfitCenterNo"]) }
                    });
                return new { success = true, data = data };
            }
        }

        [WebMethod]
        public static object GetChiefApprovalBatchSections(string employeeId, string companyId, string locationId)
        {
            employeeId = GFC.CurrentEmployeeID();
            bool isAdministrator = IsInspectionAdministrator(employeeId);
            if (!isAdministrator) employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            using (var br = new WAL.BR.CF())
            {
                DataTable rows = br.EQueryP(@"
SELECT DISTINCT S.SectionID,S.ProfitCenterNo
FROM dbo.PIP_M_Section S
WHERE S.CompanyID=@CompanyID AND S.LocationID=@LocationID
  AND (@IsAdministrator=1 OR EXISTS
  (
      SELECT 1 FROM dbo.SysWebCommonValue C
      WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
        AND C.ID=CONVERT(VARCHAR(30),S.CompanyID)+CONVERT(VARCHAR(30),S.LocationID)+';'+CASE UPPER(LTRIM(RTRIM(ISNULL(S.ProfitCenterNo,'')))) WHEN 'PENG' THEN 'CHIEF_ENG' WHEN 'PSEC' THEN 'CHIEF_SEC' WHEN 'PHKP' THEN 'CHIEF_HK' ELSE '' END
        AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X
                    WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
  ))
ORDER BY S.SectionID",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId),
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@IsAdministrator", isAdministrator ? 1 : 0)
                    });
                var data = new List<Dictionary<string, object>>();
                foreach (DataRow row in rows.Rows)
                    data.Add(new Dictionary<string, object> {
                        { "SectionID", Convert.ToString(row["SectionID"]) },
                        { "ProfitCenterNo", Convert.ToString(row["ProfitCenterNo"]) }
                    });
                return new { success = true, data = data };
            }
        }

        [WebMethod]
        public static object GetChiefApprovalBatchQueue(string employeeId, string companyId, string locationId,
            string sectionId, string dateFrom, string dateThru, string batchStatus)
        {
            employeeId = GFC.CurrentEmployeeID();
            bool isAdministrator = IsInspectionAdministrator(employeeId);
            if (!isAdministrator) employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            batchStatus = String.Equals(batchStatus, "APPROVED", StringComparison.OrdinalIgnoreCase)
                ? "APPROVED" : "PENDING";
            DateTime fromDate, thruDate;
            bool hasFrom = DateTime.TryParseExact(dateFrom, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out fromDate);
            bool hasThru = DateTime.TryParseExact(dateThru, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out thruDate);
            if (hasFrom && hasThru && fromDate > thruDate)
                throw new HttpException(400, "Tanggal From tidak boleh melewati tanggal Thru.");
            using (var br = new WAL.BR.CF())
            {
                DataTable rows = br.EQueryP(@"
SELECT B.ApprovalBatchID,B.CompanyID,B.LocationID,B.SectionID,B.InspectionDate,
       B.ProfitCenterNo,B.CreatedBy,B.CreatedDate,B.SentDate,B.BatchStatus,
       B.ApprovedBy,B.ApprovedDate,B.EmailStatus,
       ISNULL(EC.Name,B.CreatedBy) CreatedByName,
       ISNULL(EA.Name,B.ApprovedBy) ApprovedByName,
       COUNT(I.InspectionID) InspectionCount,
       COUNT(DISTINCT I.InspectionTypeCode) InspectionTypeCount
FROM dbo.PIP_T_Inspection_ApprovalBatch B
JOIN dbo.PIP_T_Inspection I ON I.ApprovalBatchID=B.ApprovalBatchID
LEFT JOIN dbo.M_HRD_Employee EC ON EC.EmployeeID=B.CreatedBy
LEFT JOIN dbo.M_HRD_Employee EA ON EA.EmployeeID=B.ApprovedBy
WHERE B.CompanyID=@CompanyID AND B.LocationID=@LocationID
  AND B.BatchStatus=@BatchStatus
  AND (@SectionID='' OR B.SectionID=@SectionID)
  AND (@HasFrom=0 OR B.InspectionDate>=@DateFrom)
  AND (@HasThru=0 OR B.InspectionDate<DATEADD(DAY,1,@DateThru))
  AND (@IsAdministrator=1 OR EXISTS
  (
      SELECT 1 FROM dbo.SysWebCommonValue C
      WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
        AND C.ID=CONVERT(VARCHAR(30),B.CompanyID)+CONVERT(VARCHAR(30),B.LocationID)+';'+CASE UPPER(LTRIM(RTRIM(ISNULL(B.ProfitCenterNo,'')))) WHEN 'PENG' THEN 'CHIEF_ENG' WHEN 'PSEC' THEN 'CHIEF_SEC' WHEN 'PHKP' THEN 'CHIEF_HK' ELSE '' END
        AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X
                    WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
  ))
GROUP BY B.ApprovalBatchID,B.CompanyID,B.LocationID,B.SectionID,B.InspectionDate,
         B.ProfitCenterNo,B.CreatedBy,B.CreatedDate,B.SentDate,B.BatchStatus,
         B.ApprovedBy,B.ApprovedDate,B.EmailStatus,EC.Name,EA.Name
ORDER BY B.InspectionDate DESC,B.ApprovalBatchID DESC",
                    new SqlParameter[] {
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId),
                        new SqlParameter("@SectionID", sectionId ?? ""),
                        new SqlParameter("@HasFrom", hasFrom ? 1 : 0),
                        new SqlParameter("@HasThru", hasThru ? 1 : 0),
                        new SqlParameter("@DateFrom", SqlDbType.DateTime) { Value = hasFrom ? (object)fromDate : DBNull.Value },
                        new SqlParameter("@DateThru", SqlDbType.DateTime) { Value = hasThru ? (object)thruDate : DBNull.Value },
                        new SqlParameter("@BatchStatus", batchStatus),
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@IsAdministrator", isAdministrator ? 1 : 0)
                    });
                var data = new List<Dictionary<string, object>>();
                foreach (DataRow row in rows.Rows)
                {
                    var item = new Dictionary<string, object>();
                    foreach (DataColumn col in rows.Columns)
                        item[col.ColumnName] = row[col] == DBNull.Value ? null : row[col];
                    data.Add(item);
                }
                return new { success = true, data = data };
            }
        }

        [WebMethod]
        public static object GetChiefApprovalBatchDetail(long approvalBatchId, string employeeId,
            string companyId, string locationId)
        {
            employeeId = GFC.CurrentEmployeeID();
            bool isAdministrator = IsInspectionAdministrator(employeeId);
            if (!isAdministrator) employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            using (var br = new WAL.BR.CF())
            {
                DataTable header = br.EQueryP(@"
SELECT B.ApprovalBatchID,B.CompanyID,B.LocationID,B.SectionID,B.InspectionDate,
       B.ProfitCenterNo,B.CreatedBy,B.CreatedDate,B.SentDate,B.BatchStatus,
       B.ApprovedBy,B.ApprovedDate,B.EmailStatus,
       CASE UPPER(LTRIM(RTRIM(ISNULL(B.ProfitCenterNo,'')))) WHEN 'PENG' THEN 'CHIEF_ENG' WHEN 'PSEC' THEN 'CHIEF_SEC' WHEN 'PHKP' THEN 'CHIEF_HK' ELSE '' END ChiefRole,
       ISNULL(EC.Name,B.CreatedBy) CreatedByName,
       ISNULL(EA.Name,B.ApprovedBy) ApprovedByName
FROM dbo.PIP_T_Inspection_ApprovalBatch B
LEFT JOIN dbo.M_HRD_Employee EC ON EC.EmployeeID=B.CreatedBy
LEFT JOIN dbo.M_HRD_Employee EA ON EA.EmployeeID=B.ApprovedBy
WHERE B.ApprovalBatchID=@BatchID
  AND B.CompanyID=@CompanyID AND B.LocationID=@LocationID
  AND (@IsAdministrator=1 OR EXISTS
  (
      SELECT 1 FROM dbo.SysWebCommonValue C
      WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
        AND C.ID=CONVERT(VARCHAR(30),B.CompanyID)+CONVERT(VARCHAR(30),B.LocationID)+';'+CASE UPPER(LTRIM(RTRIM(ISNULL(B.ProfitCenterNo,'')))) WHEN 'PENG' THEN 'CHIEF_ENG' WHEN 'PSEC' THEN 'CHIEF_SEC' WHEN 'PHKP' THEN 'CHIEF_HK' ELSE '' END
        AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X
                    WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
  ))",
                    new SqlParameter[] {
                        new SqlParameter("@BatchID", approvalBatchId),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId),
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@IsAdministrator", isAdministrator ? 1 : 0)
                    });
                if (header == null || header.Rows.Count == 0)
                    throw new HttpException(404, "Approval batch tidak ditemukan atau di luar kewenangan CHIEF.");
                DataTable members = br.EQueryP(@"
SELECT I.InspectionID,I.InspectionNo,I.SectionID,I.InspectionTypeCode,I.InspectionTypeName,
       I.InspectionTypeDetailCode,I.InspectionTypeDetailName,I.InspectionDate,
       I.TemplateNo,I.TemplateName,I.TemplateVersion,I.OwnerEmployeeID,
       ISNULL(E.Name,I.OwnerEmployeeID) TechnicianName,I.ApprovedBy,I.ApprovedDate
FROM dbo.PIP_T_Inspection I
LEFT JOIN dbo.M_HRD_Employee E ON E.EmployeeID=I.OwnerEmployeeID
WHERE I.ApprovalBatchID=@BatchID
ORDER BY I.InspectionTypeCode,I.InspectionID",
                    new SqlParameter[] { new SqlParameter("@BatchID", approvalBatchId) });
                var items = new List<Dictionary<string, object>>();
                foreach (DataRow row in members.Rows)
                {
                    var item = new Dictionary<string, object>();
                    foreach (DataColumn col in members.Columns)
                        item[col.ColumnName] = row[col] == DBNull.Value ? null : row[col];
                    items.Add(item);
                }
                var h = new Dictionary<string, object>();
                foreach (DataColumn col in header.Columns)
                    h[col.ColumnName] = header.Rows[0][col] == DBNull.Value ? null : header.Rows[0][col];
                return new { success = true, header = h, inspections = items };
            }
        }

        [WebMethod]
        public static object ApproveChiefApprovalBatch(long approvalBatchId, string employeeId,
            string companyId, string locationId)
        {
            RequireSameOriginPost();
            employeeId = GFC.CurrentEmployeeID();
            if (!IsInspectionAdministrator(employeeId))
                employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            using (var br = new WAL.BR.CF())
            {
                DataTable saved = br.EQueryP("spUTL_PIP_T_Inspection_ApprovalBatch_Approve",
                    new SqlParameter[] {
                        new SqlParameter("@p_ApprovalBatchID", approvalBatchId),
                        new SqlParameter("@p_EmployeeID", employeeId),
                        new SqlParameter("@p_CompanyID", companyId),
                        new SqlParameter("@p_LocationID", locationId)
                    }, true, true);
                return new { success = true, approvalBatchId = approvalBatchId,
                    approvedBy = employeeId,
                    inspectionCount = saved != null && saved.Rows.Count > 0
                        ? Convert.ToInt32(saved.Rows[0]["InspectionCount"]) : 0 };
            }
        }

        [WebMethod(EnableSession = true)]
        public static object GenerateChiefApprovalBatchReports(long approvalBatchId, string employeeId,
            string companyId, string locationId)
        {
            RequireSameOriginPost();
            employeeId = GFC.CurrentEmployeeID();
            if (!IsInspectionAdministrator(employeeId))
                employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            GetChiefApprovalBatchDetail(approvalBatchId, employeeId, companyId, locationId);
            try
            {
                List<Dictionary<string, string>> reports = GenerateStandardBatchReports(
                    approvalBatchId, employeeId, companyId, locationId, true);
                var links = new List<Dictionary<string, string>>();
                foreach (Dictionary<string, string> report in reports)
                {
                    string token = Guid.NewGuid().ToString("N");
                    HttpContext.Current.Session["InspectionReport_" + token] = report["StoragePath"];
                    HttpContext.Current.Session["InspectionReportName_" + token] = report["FileName"];
                    links.Add(new Dictionary<string, string> {
                        { "InspectionTypeCode", report["InspectionTypeCode"] },
                        { "FileName", report["FileName"] },
                        { "DownloadUrl", VirtualPathUtility.ToAbsolute("~/Secure/inspection.aspx?download=" + token) }
                    });
                }
                return new { success = true, reports = links };
            }
            catch (Exception ex)
            {
                System.Diagnostics.Trace.TraceError("GenerateChiefApprovalBatchReports: " + ex);
                return new { success = false, message = HttpContext.Current.IsDebuggingEnabled
                    ? ex.GetBaseException().Message : "Gagal membuat report batch CHIEF." };
            }
        }

        [WebMethod]
        public static object CreateStandardApprovalBatch(long[] inspectionIds, string employeeId,
            string companyId, string locationId)
        {
            RequireSameOriginPost();
            employeeId = GFC.CurrentEmployeeID();
            if (!IsInspectionAdministrator(employeeId))
                employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (inspectionIds == null || inspectionIds.Length == 0 || inspectionIds.Length > 200)
                throw new HttpException(400, "Pilih 1 sampai 200 inspeksi untuk dibuatkan batch.");
            long[] ids = inspectionIds.Where(id => id > 0).Distinct().ToArray();
            if (ids.Length != inspectionIds.Length)
                throw new HttpException(400, "Daftar inspeksi tidak valid atau mengandung duplikasi.");

            DataTable created;
            using (var br = new WAL.BR.CF())
            {
                created = br.EQueryP("spUTL_PIP_T_Inspection_ApprovalBatch_Create",
                    new SqlParameter[] {
                        new SqlParameter("@p_InspectionIDs", String.Join(",", ids.Select(id => id.ToString(CultureInfo.InvariantCulture)).ToArray())),
                        new SqlParameter("@p_EmployeeID", employeeId),
                        new SqlParameter("@p_CompanyID", companyId),
                        new SqlParameter("@p_LocationID", locationId)
                    }, true, true);
            }
            if (created == null || created.Rows.Count == 0)
                throw new InvalidOperationException("Batch berhasil diproses tetapi header batch tidak dikembalikan.");

            long batchId = Convert.ToInt64(created.Rows[0]["ApprovalBatchID"]);
            bool emailEnabled = created.Rows[0]["EmailEnabled"] != DBNull.Value &&
                Convert.ToBoolean(created.Rows[0]["EmailEnabled"]);
            string emailStatus = emailEnabled ? "FAILED" : "NOT_REQUIRED";
            string emailMessage = "";

            if (emailEnabled)
            {
                try
                {
                    List<Dictionary<string, string>> reports = GenerateStandardBatchReports(
                        batchId, employeeId, companyId, locationId, true);
                    string emailTo = SendStandardBatchEmail(batchId, employeeId, companyId, locationId,
                        created.Rows[0], reports);
                    emailStatus = "SENT";
                    using (var br = new WAL.BR.CF())
                    {
                        br.EQueryP(@"
UPDATE dbo.PIP_T_Inspection_ApprovalBatch
SET EmailStatus='SENT',EmailError=N'',EmailTo=@EmailTo,EmailAttemptCount=EmailAttemptCount+1,
    LastEmailAttemptDate=GETDATE(),SentDate=ISNULL(SentDate,GETDATE())
WHERE ApprovalBatchID=@BatchID",
                            new SqlParameter[] {
                                new SqlParameter("@EmailTo", emailTo),
                                new SqlParameter("@BatchID", batchId)
                            }, true, true);
                    }
                }
                catch (Exception emailError)
                {
                    emailMessage = emailError.GetBaseException().Message;
                    System.Diagnostics.Trace.TraceError("CreateStandardApprovalBatch email: " + emailError);
                    using (var br = new WAL.BR.CF())
                    {
                        br.EQueryP(@"
UPDATE dbo.PIP_T_Inspection_ApprovalBatch
SET EmailStatus='FAILED',EmailError=@Error,EmailAttemptCount=EmailAttemptCount+1,
    LastEmailAttemptDate=GETDATE(),SentDate=ISNULL(SentDate,GETDATE())
WHERE ApprovalBatchID=@BatchID",
                            new SqlParameter[] {
                                new SqlParameter("@Error", emailMessage),
                                new SqlParameter("@BatchID", batchId)
                            }, true, true);
                    }
                }
            }
            else
            {
                using (var br = new WAL.BR.CF())
                {
                    br.EQueryP("UPDATE dbo.PIP_T_Inspection_ApprovalBatch SET SentDate=GETDATE() WHERE ApprovalBatchID=@BatchID",
                        new SqlParameter[] { new SqlParameter("@BatchID", batchId) }, true, true);
                }
            }

            return new {
                success = true, approvalBatchId = batchId,
                inspectionCount = Convert.ToInt32(created.Rows[0]["InspectionCount"]),
                emailStatus = emailStatus,
                emailMessage = emailMessage
            };
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
            string employeeId = GFC.CurrentEmployeeID();
            bool isAdministrator = IsInspectionAdministrator(employeeId);
            if (!isAdministrator) employeeId = GFC.RequireMenuEmployee("20022");
            GFC.RequireCompanyLocation(employeeId, companyId, locationId);
            if (inspectionIds == null || inspectionIds.Length == 0)
                throw new HttpException(400, "Pilih minimal satu transaksi inspeksi.");
            inspectionIds = inspectionIds.Where(id => id > 0).Distinct().ToArray();
            if (inspectionIds.Length == 0 || inspectionIds.Length > 200)
                throw new HttpException(400, "Jumlah transaksi tidak valid. Maksimal 200 transaksi.");

            List<SqlParameter> parameters = new List<SqlParameter>();
            parameters.Add(new SqlParameter("@EmployeeID", employeeId));
            parameters.Add(new SqlParameter("@IsAdministrator", isAdministrator ? 1 : 0));
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
       I.OwnerEmployeeID, I.Status, I.IsApproved
FROM dbo.PIP_T_Inspection I
JOIN dbo.SysWebUser SU ON SU.EmployeeID=@EmployeeID AND SU.IsActive=1
LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
JOIN dbo.PIP_M_CheckListWOPM T ON T.IDTemplate=I.IDTemplate AND T.SectionID=I.SectionID
WHERE I.InspectionID IN (" + String.Join(",", idParameters.ToArray()) + @")
  AND I.CompanyID=@CompanyID AND I.LocationID=@LocationID
  AND ISNULL(I.IsActive,1)=1
  AND ISNULL(NULLIF(IT.ScheduleSelectionMode,''),'PARAM')<>'INSPECT'
  AND ISNULL(T.TemplateType,'W')='I'
  AND (ISNULL(T.CompanyScope,'S')='A'
       OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
  AND (ISNULL(T.EmployeeList,'')=''
       OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
  AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(@SectionList,';') S WHERE S.val=I.SectionID)
  AND (@IsAdministrator=1 OR EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') M WHERE M.MenuID='20022'))
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
            RequireSameOriginPost();
            employeeId = GFC.CurrentEmployeeID();
            bool isAdministrator = IsInspectionAdministrator(employeeId);
            if (!isAdministrator) employeeId = GFC.RequireMenuEmployee("20022");
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
            RequireSameOriginPost();
            employeeId = GFC.CurrentEmployeeID();
            bool isAdministrator = IsInspectionAdministrator(employeeId);
            if (!isAdministrator) employeeId = GFC.RequireMenuEmployee("20022");
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
  AND ISNULL(NULLIF(IT.ScheduleSelectionMode,''),'PARAM')<>'INSPECT'
  AND ISNULL(T.TemplateType,'W')='I' 
  AND (ISNULL(T.CompanyScope,'S')='A'
       OR (';' + ISNULL(T.CompanyLocationList,'') + ';' LIKE '%;' + I.CompanyID + I.LocationID + ';%'))
  AND (ISNULL(T.EmployeeList,'')=''
       OR (';' + ISNULL(T.EmployeeList,'') + ';' LIKE '%;' + I.OwnerEmployeeID + ';%'))
  AND ISNULL(I.IsSubmitted,0)=1
  AND
  (
      (ISNULL(I.IsApproved,0)=0 AND
       (@IsAdministrator=1 OR EXISTS (
          SELECT 1 FROM dbo.SysWebCommonValue C
          WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
            AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';SPV;'+I.SectionID
            AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
       )))
      OR
      (ISNULL(IT.InspectionMode,'STANDARD')='BATCH' AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='PARAM'
       AND ISNULL(I.IsApproved,0)=1 AND ISNULL(I.IsApproved1,0)=0
       AND (@IsAdministrator=1 OR EXISTS (
          SELECT 1 FROM dbo.SysWebCommonValue C
          WHERE C.AppID='INSPEC' AND C.CommonGroup='EmailApproval' AND C.IsDelete=0
            AND C.ID=CONVERT(VARCHAR(30),I.CompanyID)+CONVERT(VARCHAR(30),I.LocationID)+';'+dbo.fnINSPEC_ChiefRoleForSection(I.SectionID)
            AND EXISTS (SELECT 1 FROM dbo.SplitStringConvertToTable(C.Description,';') X WHERE LTRIM(RTRIM(X.val))=@EmployeeID)
       )))
  )
  AND (@IsAdministrator=1 OR EXISTS (SELECT 1 FROM dbo.F_SelectALLMenuAuthorization('inspecfo', @EmployeeID, '') M WHERE M.MenuID='20022'))
",
                    new SqlParameter[] {
                        new SqlParameter("@InspectionID", inspectionId),
                        new SqlParameter("@EmployeeID", employeeId),
                        new SqlParameter("@IsAdministrator", isAdministrator ? 1 : 0),
                        new SqlParameter("@SectionList", GFC.GetEmployeeSection(employeeId)),
                        new SqlParameter("@CompanyID", companyId),
                        new SqlParameter("@LocationID", locationId)
                    });
                if (authorized == null || authorized.Rows.Count == 0)
                    throw new HttpException(403, "Inspection is outside the supervisor's authorized section, template, or company/location scope.");

                string appRoot = (HttpContext.Current.Request.ApplicationPath ?? "").TrimEnd('/');
                string origin = HttpContext.Current.Request.Url.GetLeftPart(UriPartial.Authority);
                string correctionUrl = origin + appRoot + "/Secure/inspection.aspx?type=entry&inspectionId=" +
                    inspectionId.ToString(CultureInfo.InvariantCulture);
                DataTable saved = br.EQueryP("spUTL_PIP_T_Inspection_Approval_Execute", new SqlParameter[] {
                    new SqlParameter("@p_InspectionID", inspectionId),
                    new SqlParameter("@p_Action", action.ToUpperInvariant()),
                    new SqlParameter("@p_EmployeeID", employeeId),
                    new SqlParameter("@p_CompanyID", companyId),
                    new SqlParameter("@p_LocationID", locationId),
                    new SqlParameter("@p_Remark", String.IsNullOrWhiteSpace(remark) ? "" : remark),
                    new SqlParameter("@p_CorrectionUrl", correctionUrl)
                }, true, true);
                string followUpWONo = saved != null && saved.Rows.Count > 0 && saved.Columns.Contains("FollowUpWONo") && saved.Rows[0]["FollowUpWONo"] != DBNull.Value
                    ? Convert.ToString(saved.Rows[0]["FollowUpWONo"]) : "";
                object emailDispatch;
                try { emailDispatch = DispatchInspectionEmailOutbox(20, employeeId, companyId); }
                catch (Exception emailError) { emailDispatch = new { configured = false, error = emailError.Message }; }
                return new
                {
                    success = true,
                    action = action.ToUpperInvariant(),
                    inspectionId = inspectionId,
                    followUpWONo = followUpWONo,
                    emailDispatch = emailDispatch
                };
            }
        }

        private static AlternateView CreateInspectionEmailView(long inspectionId, string baseHtml)
        {
            var html = new StringBuilder();
            var linkedResources = new List<LinkedResource>();
            var linkedContentIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                using (var br = new WAL.BR.CF())
                {
                    DataTable header = br.EQueryP(@"
SELECT I.CompanyID,I.LocationID,I.InspectionDate,I.InspectionNo,I.InspectionTypeName,I.InspectionTypeDetailName,
       I.OwnerEmployeeID,I.ScheduledTime,I.Summary,ISNULL(NULLIF(I.InspectionMode,''),ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD')) InspectionMode,
       ISNULL(NULLIF(IT.ScheduleSelectionMode,''),'PARAM') ScheduleSelectionMode
FROM dbo.PIP_T_Inspection I
LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
WHERE I.InspectionID=@InspectionID",
                        new SqlParameter[] { new SqlParameter("@InspectionID", inspectionId) });
                    if (header.Rows.Count == 0)
                    {
                        html.Append(baseHtml ?? "");
                        return AlternateView.CreateAlternateViewFromString(html.ToString(), Encoding.UTF8, "text/html");
                    }
                    string companyId = GF.GetString(header.Rows[0]["CompanyID"]);
                    string locationId = GF.GetString(header.Rows[0]["LocationID"]);
                    string inspectionNo = GF.GetString(header.Rows[0]["InspectionNo"]);
                    DateTime inspectionDate = Convert.ToDateTime(header.Rows[0]["InspectionDate"]);

                    string inspectionMode = GF.GetString(header.Rows[0]["InspectionMode"]).ToUpperInvariant();
                    bool isLightning = inspectionMode == "BATCH" && String.Equals(GF.GetString(header.Rows[0]["ScheduleSelectionMode"]), "INSPECT", StringComparison.OrdinalIgnoreCase);
                    DataTable schedules;
                    if (isLightning)
                        schedules = br.EQueryP(@"
SELECT DISTINCT D.ScheduleTime FROM dbo.PIP_T_Inspection I
JOIN dbo.PIP_M_InspectionTypeDetail D ON D.InspectionTypeCode=I.InspectionTypeCode
 AND D.InspectionTypeDetailCode=I.InspectionTypeDetailCode
WHERE I.InspectionID=@InspectionID ORDER BY D.ScheduleTime",
                            new SqlParameter[] { new SqlParameter("@InspectionID", inspectionId) });
                    else
                    {
                        schedules = new DataTable();
                        schedules.Columns.Add("ScheduleTime", typeof(string));
                        schedules.Rows.Add("");
                    }
                    DataTable points = br.EQueryP(@"
SELECT TP.ScheduleTime,TP.InspectionPointTransactionID,TP.Status,TP.AbnormalRemark,
       ISNULL(NULLIF(TP.PointCode,''),P.PointCode) PointCode,
       ISNULL(NULLIF(TP.PointName,''),P.PointName) PointName,
       P.MapID,P.MapX,P.MapY,P.DisplayOrder,
       M.MapCode,M.MapName,M.ImagePath,M.MapGroupID,G.GroupName,G.Sequence GroupSequence
FROM dbo.PIP_T_InspectionPoint TP
LEFT JOIN dbo.PIP_M_InspectionPoint P ON P.InspectionPointID=TP.InspectionPointID
LEFT JOIN dbo.PIP_M_InspectionMap M ON M.MapID=P.MapID
LEFT JOIN dbo.PIP_M_InspectionMapGroup G ON G.MapGroupID=M.MapGroupID
WHERE TP.InspectionID=@InspectionID
ORDER BY TP.ScheduleTime,ISNULL(G.Sequence,0),M.MapGroupID,M.MapID,ISNULL(P.DisplayOrder,0),TP.PointCode",
                        new SqlParameter[] { new SqlParameter("@InspectionID", inspectionId) });
                    DataTable results = br.EQueryP(@"
SELECT R.InspectionResultID,R.InspectionPointTransactionID,R.ItemLabel,R.Value,R.Remark1,R.Remark2,R.IsAnomali,R.DisplayOrder
FROM dbo.PIP_T_InspectionResult R
WHERE R.InspectionID=@InspectionID
ORDER BY R.InspectionPointTransactionID,R.DisplayOrder",
                        new SqlParameter[] { new SqlParameter("@InspectionID", inspectionId) });
                    DataTable resultValues = br.EQueryP(@"
SELECT R.InspectionResultID,R.InspectionPointTransactionID,R.ItemLabel,
       V.ObjectIndex,V.FieldName,ISNULL(F.FieldLabel,V.FieldName) FieldLabel,V.Value FieldValue
FROM dbo.PIP_T_InspectionResult R
JOIN dbo.PIP_T_InspectionResultValue V ON V.InspectionResultID=R.InspectionResultID
LEFT JOIN dbo.PIP_M_CheckListWOPM_ItemRepeatField F
  ON F.IDItem=R.IDItem
 AND F.IDRepeat=CASE WHEN V.FieldName<>'' AND LEN(V.FieldName)<=10 AND V.FieldName NOT LIKE '%[^0-9]%'
                     THEN CAST(V.FieldName AS INT) ELSE 0 END
WHERE R.InspectionID=@InspectionID
ORDER BY R.InspectionResultID,V.ObjectIndex,V.FieldName",
                        new SqlParameter[] { new SqlParameter("@InspectionID", inspectionId) });
                    DataTable photos = br.EQueryP(@"
SELECT InspectionPointTransactionID,PhotoType,FileName,FileType,SeqNo
FROM dbo.PIP_T_InspectionPhoto
WHERE InspectionID=@InspectionID
ORDER BY InspectionPointTransactionID,PhotoType,SeqNo",
                        new SqlParameter[] { new SqlParameter("@InspectionID", inspectionId) });

                    html.Append(baseHtml ?? "");
                    html.Append("<hr/><h2>").Append(HttpUtility.HtmlEncode(isLightning ? "LIGHTNING DAILY INSPECTION REVIEW" :
                        (inspectionMode == "BATCH" ? "BATCH INSPECTION REVIEW" : "STANDARD INSPECTION REVIEW"))).Append("</h2>");
                    html.Append("<p><strong>").Append(HttpUtility.HtmlEncode(inspectionNo))
                        .Append("</strong> · ").Append(HttpUtility.HtmlEncode(GF.GetString(header.Rows[0]["InspectionTypeName"])))
                        .Append(" · ").Append(HttpUtility.HtmlEncode(GF.GetString(header.Rows[0]["InspectionTypeDetailName"])))
                        .Append(" · ").Append(inspectionDate.ToString("dd-MMM-yyyy", CultureInfo.InvariantCulture)).Append("</p>");

                    string inspectionSummary = GF.GetString(header.Rows[0]["Summary"]);
                    if (inspectionSummary != "")
                        html.Append("<p><strong>Summary:</strong> ").Append(HttpUtility.HtmlEncode(inspectionSummary)).Append("</p>");

                    if (inspectionMode == "STANDARD")
                    {
                        html.Append("<h3>Checklist / Findings</h3><table cellpadding='5' cellspacing='0' style='width:100%;border-collapse:collapse'>");
                        foreach (DataRow result in results.Select("InspectionPointTransactionID IS NULL"))
                        {
                            html.Append("<tr><td style='border-bottom:1px solid #eee'><strong>")
                                .Append(HttpUtility.HtmlEncode(GF.GetString(result["ItemLabel"]))).Append("</strong></td><td style='border-bottom:1px solid #eee'>")
                                .Append(HttpUtility.HtmlEncode(GF.GetString(result["Value"])));
                            long resultId = Convert.ToInt64(result["InspectionResultID"]);
                            foreach (DataRow child in resultValues.Select("InspectionResultID=" + resultId.ToString(CultureInfo.InvariantCulture)))
                                html.Append("<br/><small>").Append(HttpUtility.HtmlEncode(GF.GetString(child["FieldLabel"])))
                                    .Append(" #").Append(Convert.ToString(child["ObjectIndex"])).Append(": ")
                                    .Append(HttpUtility.HtmlEncode(GF.GetString(child["FieldValue"]))).Append("</small>");
                            string remark1 = GF.GetString(result["Remark1"]);
                            string remark2 = GF.GetString(result["Remark2"]);
                            if (remark1 != "") html.Append("<br/>").Append(HttpUtility.HtmlEncode(remark1));
                            if (remark2 != "") html.Append("<br/>").Append(HttpUtility.HtmlEncode(remark2));
                            html.Append("</td></tr>");
                        }
                        html.Append("</table>");
                        foreach (DataRow photo in photos.Select("InspectionPointTransactionID IS NULL"))
                        {
                            string fileName = GF.GetString(photo["FileName"]);
                            string fileType = GF.GetString(photo["FileType"]);
                            string photoPath = "";
                            try { photoPath = GetInspectionPhotoPath(companyId, locationId, inspectionDate, inspectionNo, fileName, fileType); }
                            catch { }
                            if (photoPath == "" || !File.Exists(photoPath)) continue;
                            string cid = "inspection-photo-standard-" + Convert.ToString(photo["PhotoType"]).ToLowerInvariant() + "-" + Convert.ToString(photo["SeqNo"]);
                            var linkedPhoto = new LinkedResource(photoPath, GetInspectionEmailMimeType(fileName + "." + fileType));
                            linkedPhoto.ContentId = cid;
                            linkedPhoto.TransferEncoding = System.Net.Mime.TransferEncoding.Base64;
                            linkedResources.Add(linkedPhoto);
                            html.Append("<br/><img src='cid:").Append(cid).Append("' alt='")
                                .Append(HttpUtility.HtmlEncode(GF.GetString(photo["PhotoType"])))
                                .Append("' style='max-width:240px;height:auto;margin:4px;border:1px solid #ddd'/>");
                        }
                    }

                    foreach (DataRow schedule in schedules.Rows)
                    {
                        string scheduleTime = GF.GetString(schedule["ScheduleTime"]);
                        string scheduleLabel = scheduleTime == "" ? GF.GetString(header.Rows[0]["ScheduledTime"]) : scheduleTime;
                        DataRow[] schedulePoints = points.Select("ScheduleTime='" + scheduleTime.Replace("'", "''") + "'");
                        if (inspectionMode == "STANDARD") continue;
                        html.Append("<section style='margin:18px 0;padding:12px;border:1px solid #ddd;border-radius:8px'>")
                            .Append("<h3>").Append(isLightning ? "Schedule " : "Batch · ")
                            .Append(HttpUtility.HtmlEncode(scheduleLabel)).Append("</h3>");

                        var mapGroups = schedulePoints.Where(row => row["MapID"] != DBNull.Value)
                            .GroupBy(row => Convert.ToInt64(row["MapID"]));
                        if (!mapGroups.Any())
                            html.Append("<p>No floor plan assigned. Point results are listed below.</p>");

                        var renderedGroupNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                        foreach (var mapGroup in mapGroups)
                        {
                            DataRow map = mapGroup.First();
                            string groupName = GF.GetString(map["GroupName"]);
                            string mapName = GF.GetString(map["MapName"]);
                            if (groupName != "" && renderedGroupNames.Add(groupName))
                                html.Append("<h4>Group Map: ").Append(HttpUtility.HtmlEncode(groupName)).Append("</h4>");
                            html.Append("<div style='margin:10px 0;padding:10px;border:1px solid #eee'>")
                                .Append("<h4>").Append(HttpUtility.HtmlEncode(GF.GetString(map["MapCode"])))
                                .Append(" - ").Append(HttpUtility.HtmlEncode(mapName)).Append("</h4>");

                            string mapPath = "";
                            string mapFile = Path.GetFileName(GF.GetString(map["ImagePath"]).Replace('/', '\\'));
                            string webRoot = (PB.Path_WebFolder1 ?? "").Trim();
                            string appPath = HttpContext.Current.Request.ApplicationPath ?? "";
                            string mapRoot = appPath.Trim('/').ToUpperInvariant().Replace("INSPEC", "PIP");
                            if (mapRoot == "") mapRoot = "PIP";
                            if (mapFile != "" && webRoot != "")
                                mapPath = Path.Combine(webRoot, mapRoot, "PIP_M_InspectionMap",
                                    SafeInspectionMapPathPart(companyId) + "_" + SafeInspectionMapPathPart(locationId), mapFile);
                            string mapCid = "lightning-map-" + Convert.ToInt64(map["MapID"]).ToString(CultureInfo.InvariantCulture);
                            html.Append("<div style='position:relative;display:block;width:100%;margin:6px 0'>");
                            if (mapPath != "" && File.Exists(mapPath))
                            {
                                if (linkedContentIds.Add(mapCid))
                                {
                                    var linkedMap = new LinkedResource(mapPath, GetInspectionEmailMimeType(mapFile));
                                    linkedMap.ContentId = mapCid;
                                    linkedMap.TransferEncoding = System.Net.Mime.TransferEncoding.Base64;
                                    linkedResources.Add(linkedMap);
                                }
                                html.Append("<img src='cid:").Append(mapCid).Append("' alt='")
                                    .Append(HttpUtility.HtmlEncode(mapName))
                                    .Append("' style='display:block;width:100%;height:auto;border:1px solid #ddd'/>");
                            }
                            else if (!String.IsNullOrWhiteSpace(GF.GetString(map["ImagePath"])))
                            {
                                string mapUrl = ResolveInspectionMapUrl(GF.GetString(map["ImagePath"]), companyId, locationId);
                                html.Append("<img src='").Append(HttpUtility.HtmlAttributeEncode(mapUrl))
                                    .Append("' alt='").Append(HttpUtility.HtmlEncode(mapName))
                                    .Append("' style='display:block;width:100%;height:auto;border:1px solid #ddd'/>");
                            }
                            foreach (DataRow markerPoint in mapGroup)
                            {
                                if (markerPoint["MapX"] == DBNull.Value || markerPoint["MapY"] == DBNull.Value) continue;
                                decimal mapX, mapY;
                                if (!Decimal.TryParse(Convert.ToString(markerPoint["MapX"]), NumberStyles.Any, CultureInfo.InvariantCulture, out mapX) ||
                                    !Decimal.TryParse(Convert.ToString(markerPoint["MapY"]), NumberStyles.Any, CultureInfo.InvariantCulture, out mapY)) continue;
                                mapX = Math.Max(0, Math.Min(100, mapX));
                                mapY = Math.Max(0, Math.Min(100, mapY));
                                html.Append("<span style='position:absolute;left:").Append(mapX.ToString(CultureInfo.InvariantCulture))
                                    .Append("%;top:").Append(mapY.ToString(CultureInfo.InvariantCulture))
                                    .Append("%;transform:translate(-50%,-50%);display:inline-block;padding:2px 5px;border-radius:10px;background:#c62828;color:#fff;font-size:10px;font-weight:bold'>")
                                    .Append(HttpUtility.HtmlEncode(GF.GetString(markerPoint["PointCode"])))
                                    .Append("</span>");
                            }
                            html.Append("</div>");

                            html.Append("<table cellpadding='5' cellspacing='0' style='width:100%;border-collapse:collapse'>")
                                .Append("<tr><th align='left' style='border-bottom:1px solid #ddd'>Point</th>")
                                .Append("<th align='left' style='border-bottom:1px solid #ddd'>Status / Finding</th></tr>");
                            foreach (DataRow point in mapGroup)
                            {
                                long pointTransactionId = Convert.ToInt64(point["InspectionPointTransactionID"]);
                                string status = GF.GetString(point["Status"]);
                                string remark = GF.GetString(point["AbnormalRemark"]);
                                html.Append("<tr><td style='border-bottom:1px solid #eee'><strong>")
                                    .Append(HttpUtility.HtmlEncode(GF.GetString(point["PointCode"]))).Append("</strong><br/>")
                                    .Append(HttpUtility.HtmlEncode(GF.GetString(point["PointName"]))).Append("</td><td style='border-bottom:1px solid #eee'>")
                                    .Append(HttpUtility.HtmlEncode(status));
                                if (remark != "") html.Append("<br/>").Append(HttpUtility.HtmlEncode(remark));

                                foreach (DataRow result in results.Select("InspectionPointTransactionID=" + pointTransactionId.ToString(CultureInfo.InvariantCulture)))
                                {
                                    string label = GF.GetString(result["ItemLabel"]);
                                    long resultId = Convert.ToInt64(result["InspectionResultID"]);
                                    foreach (DataRow child in resultValues.Select("InspectionResultID=" + resultId.ToString(CultureInfo.InvariantCulture)))
                                        html.Append("<br/><small>").Append(HttpUtility.HtmlEncode(label)).Append(" · ")
                                            .Append(HttpUtility.HtmlEncode(GF.GetString(child["FieldName"])))
                                            .Append(" #").Append(Convert.ToString(child["ObjectIndex"])).Append(": ")
                                            .Append(HttpUtility.HtmlEncode(GF.GetString(child["FieldValue"]))).Append("</small>");
                                    string value = GF.GetString(result["Value"]);
                                    string remark1 = GF.GetString(result["Remark1"]);
                                    string remark2 = GF.GetString(result["Remark2"]);
                                    if (value != "" || remark1 != "" || remark2 != "")
                                        html.Append("<br/><small>").Append(HttpUtility.HtmlEncode(label)).Append(": ")
                                            .Append(HttpUtility.HtmlEncode(value))
                                            .Append(remark1 != "" ? " · " + HttpUtility.HtmlEncode(remark1) : "")
                                            .Append(remark2 != "" ? " · " + HttpUtility.HtmlEncode(remark2) : "")
                                            .Append("</small>");
                                }

                                foreach (DataRow photo in photos.Select("InspectionPointTransactionID=" + pointTransactionId.ToString(CultureInfo.InvariantCulture)))
                                {
                                    string fileName = GF.GetString(photo["FileName"]);
                                    string fileType = GF.GetString(photo["FileType"]);
                                    string photoPath = "";
                                    try { photoPath = GetInspectionPhotoPath(companyId, locationId, inspectionDate, inspectionNo, fileName, fileType); }
                                    catch { }
                                    if (photoPath == "" || !File.Exists(photoPath)) continue;
                                    string cid = "lightning-photo-" + pointTransactionId.ToString(CultureInfo.InvariantCulture) + "-" +
                                        Convert.ToString(photo["PhotoType"]).ToLowerInvariant() + "-" +
                                        Convert.ToString(photo["SeqNo"]);
                                    var linkedPhoto = new LinkedResource(photoPath, GetInspectionEmailMimeType(fileName + "." + fileType));
                                    linkedPhoto.ContentId = cid;
                                    linkedPhoto.TransferEncoding = System.Net.Mime.TransferEncoding.Base64;
                                    linkedResources.Add(linkedPhoto);
                                    html.Append("<br/><img src='cid:").Append(cid)
                                        .Append("' alt='").Append(HttpUtility.HtmlEncode(GF.GetString(photo["PhotoType"])))
                                        .Append("' style='max-width:220px;height:auto;margin:4px;border:1px solid #ddd'/>");
                                }
                                html.Append("</td></tr>");
                            }
                            html.Append("</table></div>");
                        }
                        html.Append("</section>");
                    }
                }
                AlternateView finalView = AlternateView.CreateAlternateViewFromString(html.ToString(), Encoding.UTF8, "text/html");
                foreach (LinkedResource resource in linkedResources) finalView.LinkedResources.Add(resource);
                return finalView;
            }
            catch
            {
                foreach (LinkedResource resource in linkedResources) { try { resource.Dispose(); } catch { } }
                return AlternateView.CreateAlternateViewFromString(baseHtml ?? "", Encoding.UTF8, "text/html");
            }
        }

        private static string GetInspectionEmailMimeType(string fileName)
        {
            string extension = Path.GetExtension(fileName ?? "").ToLowerInvariant();
            switch (extension)
            {
                case ".png": return "image/png";
                case ".gif": return "image/gif";
                case ".webp": return "image/webp";
                case ".bmp": return "image/bmp";
                case ".jpg":
                case ".jpeg": return "image/jpeg";
                default: return "application/octet-stream";
            }
        }

        private static void RequireSameOriginPost()
        {
            HttpRequest request = HttpContext.Current == null ? null : HttpContext.Current.Request;
            if (request == null || !String.Equals(request.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase))
                throw new HttpException(405, "Approval actions require POST.");

            string origin = (request.Headers["Origin"] ?? "").Trim();
            Uri source = null;
            if (origin != "" && !Uri.TryCreate(origin, UriKind.Absolute, out source))
                throw new HttpException(403, "Invalid request origin.");
            if (source == null && request.UrlReferrer != null) source = request.UrlReferrer;
            if (source == null || !String.Equals(source.Scheme, request.Url.Scheme, StringComparison.OrdinalIgnoreCase) ||
                !String.Equals(source.Authority, request.Url.Authority, StringComparison.OrdinalIgnoreCase))
                throw new HttpException(403, "Cross-origin approval requests are not allowed.");
        }

        private static object DispatchInspectionEmailOutbox(int batchSize, string senderEmployeeId, string companyId)
        {
            /* Email is an optional feature. If no explicit scope switch is enabled,
               do not inspect sender details, touch old outbox rows, or report a send failure. */
            bool emailConfigured = false;
            using (var configBr = new WAL.BR.CF())
            {
                DataTable emailConfig = configBr.EQueryP(@"
SELECT TOP 1 1 AS IsEnabled
FROM dbo.PIP_T_InspectionEmailOutbox O
JOIN dbo.PIP_T_Inspection I ON I.InspectionID=O.EntityID
LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
LEFT JOIN dbo.PIP_T_InspectionApprovalHistory H ON H.ApprovalEventID=O.ApprovalEventID
WHERE O.EntityType IN ('INSPECTION','LIGHTNING')
  AND I.CompanyID=@C
  AND O.DeliveryStatus IN ('PENDING','FAILED')
  AND O.AttemptCount<5
  AND O.NextAttemptDate<=GETDATE()
  AND dbo.fnINSPEC_ApprovalEmailEnabled
  (
      I.CompanyID,I.LocationID,
      CASE WHEN O.EntityType='LIGHTNING'
                 OR (ISNULL(IT.InspectionMode,'STANDARD')='BATCH' AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='INSPECT')
           THEN 'BATCH;INSPECT'
           WHEN ISNULL(NULLIF(I.InspectionMode,''),ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD'))='STANDARD'
           THEN 'STANDARD' ELSE 'BATCH;PARAM' END,
      CASE
          WHEN O.RecipientType='APPROVER' AND CHARINDEX(':SPV:',O.NotificationKey)>0 THEN 'SPV'
          WHEN O.RecipientType='APPROVER' AND CHARINDEX(':CHIEF:',O.NotificationKey)>0 THEN 'CHIEF'
          WHEN O.RecipientType='APPROVER' AND CHARINDEX(':CHIEF_SEC:',O.NotificationKey)>0 THEN 'CHIEF_SEC'
          WHEN O.RecipientType='APPROVER' AND CHARINDEX(':CHIEF_ENG:',O.NotificationKey)>0
               THEN CASE WHEN O.EntityType='LIGHTNING' THEN 'CHIEF_ENG' ELSE 'CHIEF' END
          WHEN O.RecipientType='TECHNICIAN' AND H.StageCode IN ('TECHNICIAN','SPV') THEN 'SPV'
          WHEN O.RecipientType='TECHNICIAN' AND O.EntityType='INSPECTION' AND H.StageCode IN ('CHIEF_ENG','CHIEF_SEC','CHIEF_HK') THEN 'CHIEF'
          WHEN O.RecipientType='TECHNICIAN' THEN H.StageCode
          ELSE '' END
  )=1",
                    new SqlParameter[] { new SqlParameter("@C", companyId ?? "") });
                emailConfigured = emailConfig != null && emailConfig.Rows.Count > 0;
            }

            if (!emailConfigured)
                return new { attempted = 0, sent = 0, failed = 0, pending = 0, configured = false };

            string fromAddress = "";
            string fromName = "";
            using (var senderBr = new WAL.BR.CF())
            {
                DataTable sender = senderBr.EQueryP(@"
SELECT TOP 1 ISNULL(LTRIM(RTRIM(emailaddress)),'') AS EmailAddress, ISNULL(LTRIM(RTRIM(Name)),'') AS EmployeeName
FROM dbo.M_HRD_Employee
WHERE EmployeeID=@E AND CompanyID=@C AND ISNULL(TerminationDate,'')=''
  AND ISNULL(LTRIM(RTRIM(emailaddress)),'')<>''",
                    new SqlParameter[] {
                        new SqlParameter("@E", senderEmployeeId ?? ""),
                        new SqlParameter("@C", companyId ?? "")
                    });
                if (sender != null && sender.Rows.Count > 0)
                {
                    fromAddress = Convert.ToString(sender.Rows[0]["EmailAddress"]).Trim();
                    fromName = Convert.ToString(sender.Rows[0]["EmployeeName"]).Trim();
                }
            }

            using (var br = new WAL.BR.CF())
            {
                DataTable queue = br.EQueryP(@"
;WITH EmailQueue AS
(
    SELECT TOP (@BatchSize) *
    FROM dbo.PIP_T_InspectionEmailOutbox O WITH (UPDLOCK,READPAST,ROWLOCK)
    WHERE O.DeliveryStatus IN ('PENDING','FAILED')
      AND O.NextAttemptDate<=GETDATE()
      AND O.AttemptCount<5
      /* Re-check the specific notification stage at dispatch time. */
       AND EXISTS
       (
           SELECT 1
           FROM dbo.PIP_T_Inspection I
           LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
           LEFT JOIN dbo.PIP_T_InspectionApprovalHistory H ON H.ApprovalEventID=O.ApprovalEventID
           WHERE I.InspectionID=O.EntityID
             AND dbo.fnINSPEC_ApprovalEmailEnabled
             (
                 I.CompanyID,I.LocationID,
                 CASE WHEN O.EntityType='LIGHTNING'
                            OR (ISNULL(IT.InspectionMode,'STANDARD')='BATCH' AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='INSPECT')
                      THEN 'BATCH;INSPECT'
                      WHEN ISNULL(NULLIF(I.InspectionMode,''),ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD'))='STANDARD'
                      THEN 'STANDARD' ELSE 'BATCH;PARAM' END,
                 CASE
                     WHEN O.RecipientType='APPROVER' AND CHARINDEX(':SPV:',O.NotificationKey)>0 THEN 'SPV'
                     WHEN O.RecipientType='APPROVER' AND CHARINDEX(':CHIEF:',O.NotificationKey)>0 THEN 'CHIEF'
          WHEN O.RecipientType='APPROVER' AND CHARINDEX(':CHIEF_SEC:',O.NotificationKey)>0 THEN 'CHIEF_SEC'
                     WHEN O.RecipientType='APPROVER' AND CHARINDEX(':CHIEF_ENG:',O.NotificationKey)>0
                          THEN CASE WHEN O.EntityType='LIGHTNING' THEN 'CHIEF_ENG' ELSE 'CHIEF' END
                     WHEN O.RecipientType='TECHNICIAN' AND H.StageCode IN ('TECHNICIAN','SPV') THEN 'SPV'
                     WHEN O.RecipientType='TECHNICIAN' AND O.EntityType='INSPECTION' AND H.StageCode IN ('CHIEF_ENG','CHIEF_SEC','CHIEF_HK') THEN 'CHIEF'
                     WHEN O.RecipientType='TECHNICIAN' THEN H.StageCode
                     ELSE '' END
             )=1
       )
       ORDER BY EmailOutboxID
)
UPDATE EmailQueue
SET DeliveryStatus='SENDING',AttemptCount=AttemptCount+1,LastAttemptDate=GETDATE()
OUTPUT inserted.EmailOutboxID,inserted.EntityType,inserted.EntityID,
       inserted.RecipientEmail,inserted.EmailSubject,inserted.HtmlBody,inserted.PlainBody,inserted.AttemptCount;",
                    new SqlParameter[] { new SqlParameter("@BatchSize", Math.Max(1, Math.Min(batchSize, 50))) }, false, true);

                int sent = 0, failed = 0;
                foreach (DataRow row in queue.Rows)
                {
                    long outboxId = Convert.ToInt64(row["EmailOutboxID"]);
                    try
                    {
                        string toAddress = Convert.ToString(row["RecipientEmail"]).Trim();
                        string subject = Convert.ToString(row["EmailSubject"]);
                        string htmlBody = Convert.ToString(row["HtmlBody"]);

                        if (String.IsNullOrWhiteSpace(toAddress))
                            throw new InvalidOperationException("Recipient email is empty.");
                        if (String.IsNullOrWhiteSpace(fromAddress))
                            throw new InvalidOperationException("Email address login employee tidak ditemukan di M_HRD_Employee.");

                        if (!GF.SendEmail(
                                fromAddress,
                                fromName,
                                toAddress,
                                subject,
                                htmlBody,
                                "",
                                "",
                                "",
                                ""))
                            throw new InvalidOperationException("GF.SendEmail returned false.");

                        br.EQueryP(@"UPDATE dbo.PIP_T_InspectionEmailOutbox
SET DeliveryStatus='SENT',SentDate=GETDATE(),LastError=NULL
WHERE EmailOutboxID=@ID AND DeliveryStatus='SENDING'",
                            new SqlParameter[] { new SqlParameter("@ID", outboxId) });
                        sent++;
                    }
                    catch (Exception ex)
                    {
                        string error = ex.Message ?? "Email send failed.";
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
                            });
                        failed++;
                    }
                }

                DataTable pending = br.EQuery(@"
SELECT COUNT(1) PendingCount
FROM dbo.PIP_T_InspectionEmailOutbox O
WHERE O.DeliveryStatus IN ('PENDING','FAILED','SENDING')
  AND EXISTS
  (
      SELECT 1
      FROM dbo.PIP_T_Inspection I
      LEFT JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=I.InspectionTypeCode
      LEFT JOIN dbo.PIP_T_InspectionApprovalHistory H ON H.ApprovalEventID=O.ApprovalEventID
      WHERE I.InspectionID=O.EntityID
        AND dbo.fnINSPEC_ApprovalEmailEnabled
        (
            I.CompanyID,I.LocationID,
            CASE WHEN O.EntityType='LIGHTNING'
                       OR (ISNULL(IT.InspectionMode,'STANDARD')='BATCH' AND ISNULL(IT.ScheduleSelectionMode,'PARAM')='INSPECT')
                 THEN 'BATCH;INSPECT'
                 WHEN ISNULL(NULLIF(I.InspectionMode,''),ISNULL(NULLIF(IT.InspectionMode,''),'STANDARD'))='STANDARD'
                 THEN 'STANDARD' ELSE 'BATCH;PARAM' END,
            CASE
                WHEN O.RecipientType='APPROVER' AND CHARINDEX(':SPV:',O.NotificationKey)>0 THEN 'SPV'
                WHEN O.RecipientType='APPROVER' AND CHARINDEX(':CHIEF:',O.NotificationKey)>0 THEN 'CHIEF'
          WHEN O.RecipientType='APPROVER' AND CHARINDEX(':CHIEF_SEC:',O.NotificationKey)>0 THEN 'CHIEF_SEC'
                WHEN O.RecipientType='APPROVER' AND CHARINDEX(':CHIEF_ENG:',O.NotificationKey)>0
                     THEN CASE WHEN O.EntityType='LIGHTNING' THEN 'CHIEF_ENG' ELSE 'CHIEF' END
                WHEN O.RecipientType='TECHNICIAN' AND H.StageCode IN ('TECHNICIAN','SPV') THEN 'SPV'
                WHEN O.RecipientType='TECHNICIAN' AND O.EntityType='INSPECTION' AND H.StageCode IN ('CHIEF_ENG','CHIEF_SEC','CHIEF_HK') THEN 'CHIEF'
                WHEN O.RecipientType='TECHNICIAN' THEN H.StageCode
                ELSE '' END
        )=1
  )");
                return new
                {
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

        private static SqlParameter CreateInspectionGpsDecimalParameter(string name, string value, byte precision, byte scale)
        {
            SqlParameter parameter = new SqlParameter(name, SqlDbType.Decimal);
            parameter.Precision = precision;
            parameter.Scale = scale;
            decimal parsed;
            parameter.Value = Decimal.TryParse(value, NumberStyles.Number, CultureInfo.InvariantCulture, out parsed)
                ? (object)parsed
                : DBNull.Value;
            return parameter;
        }

        private static SqlParameter CreateInspectionGpsDateParameter(string name, string value)
        {
            SqlParameter parameter = new SqlParameter(name, SqlDbType.DateTime);
            parameter.Value = String.IsNullOrWhiteSpace(value)
                ? (object)DBNull.Value
                : ParseNullableDate(value);
            return parameter;
        }
    }
}

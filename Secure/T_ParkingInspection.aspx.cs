
using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Linq;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.UI;
using WAL;

namespace INSPEC.Secure
{
    public partial class T_ParkingInspection : WAL.PB, WAL.I_ToolBar_2
    {
        private const string _MenuID = "20024";
        private const string DateFormat = "yyyy-MM-dd";

        private string _initialJson = "{}";

        public string InitialJson
        {
            get { return _initialJson; }
        }

        public string SelectedDateIso
        {
            get
            {
                return (ViewState["ParkingDate"] as string)
                    ?? DateTime.Today.ToString(
                        DateFormat,
                        CultureInfo.InvariantCulture);
            }
        }

        private string CompanyID
        {
            get { return Master.Mn_CompanyID; }
        }

        private string LocationID
        {
            get { return Master.Mn_LocationID; }
        }

        // =========================================================
        // TOOLBAR
        // =========================================================

        public void Toolbar_Click(
            object sender,
            ToolBarEventArgs_2 e)
        {
            if (e.ToolbarItem == ToolbarItem_2.Refresh)
            {
                BindPage();
            }
        }

        private void InitToolbar()
        {
            Master.TB_VisibleToolbar(false);

            Master.TB_VisibleButton(
                ToolbarItem_2.Refresh,
                false);
        }

        // =========================================================
        // PAGE LIFECYCLE
        // =========================================================

        protected override void OnInit(EventArgs e)
        {
            if (Context.User != null &&
                Context.User.Identity != null &&
                Context.User.Identity.IsAuthenticated)
            {
                ViewStateUserKey = Context.User.Identity.Name;
            }

            base.OnInit(e);
        }

        protected void Page_Load(object sender, EventArgs e)
        {
            Page.Form.Enctype = "multipart/form-data";
            if (!String.IsNullOrEmpty(Request.QueryString["inspecPhoto"]))
            {
                ServePhotoPreview();
                return;
            }
            InitToolbar();

            DebugParkingScope("Page_Load");

            if (!IsPostBack)
            {
                LoadMenuTitle();
                BindPage();
            }
        }

        private void LoadMenuTitle()
        {
            using (WAL.BR.SysWebMenu sw =
                new WAL.BR.SysWebMenu())
            {
                sw.AppID = WAL.PB.AppID;
                sw.MenuID = _MenuID;

                DataTable menu = sw.SelectOneByMenuID();

                if (menu.Rows.Count == 0)
                {
                    throw new InvalidOperationException(
                        "Menu Parking Inspection tidak ditemukan. " +
                        "Periksa MenuID: " + _MenuID);
                }

                Master.Mn_lit_Title =
                    WAL.PB.AppID + " -> " +
                    sw.Description;
            }
        }

        // =========================================================
        // DATE
        // =========================================================

        private static DateTime ParseDate(string value)
        {
            return DateTime.ParseExact(
                value,
                DateFormat,
                CultureInfo.InvariantCulture,
                DateTimeStyles.None);
        }

        protected void btnParkingLoad_Click(
            object sender,
            EventArgs e)
        {
            DateTime inspectionDate;

            if (!DateTime.TryParseExact(
                hfParkingDate.Value,
                DateFormat,
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out inspectionDate))
            {
                Alert("Tanggal inspeksi tidak valid.");
                BindPage();
                return;
            }

            if (inspectionDate.Date > DateTime.Today)
            {
                Alert(
                    "Tanggal inspeksi tidak boleh " +
                    "melebihi hari ini.");

                BindPage();
                return;
            }

            ViewState["ParkingDate"] =
                inspectionDate.ToString(
                    DateFormat,
                    CultureInfo.InvariantCulture);

            BindPage();
        }

        // =========================================================
        // JSON HELPERS
        // =========================================================

        private static List<Dictionary<string, object>> Rows(
            DataTable table)
        {
            var result =
                new List<Dictionary<string, object>>();

            foreach (DataRow row in table.Rows)
            {
                var item =
                    new Dictionary<string, object>();

                foreach (DataColumn column in table.Columns)
                {
                    object value = row[column];

                    item[column.ColumnName] =
                        value == DBNull.Value
                            ? null
                            : value;
                }

                result.Add(item);
            }

            return result;
        }

        private static string Json(object value)
        {
            var serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = 5000000;

            return serializer.Serialize(value)
                .Replace("<", "\\u003c")
                .Replace(">", "\\u003e")
                .Replace("&", "\\u0026");
        }

        private void Alert(string message)
        {
            ClientScript.RegisterStartupScript(
                GetType(),
                "parkingAlert",
                "alert(" + Json(message) + ");",
                true);
        }

        // =========================================================
        // LOAD PARKING INSPECTION
        // =========================================================


        private void ServePhotoPreview()
        {
            long photoID;
            DateTime photoDate;
            string userID = Convert.ToString(Master.Mn_UserID).Trim();

            // WAL session context must be established by the application's login flow.
            // ASP.NET Context.User.Identity.IsAuthenticated is false in this WAL application.
            // Active Master CompanyID/LocationID can be empty on direct photo GET.
            if (String.IsNullOrWhiteSpace(userID))
                throw new HttpException(403, "Sesi pengguna WAL tidak valid.");
            if (!Int64.TryParse(Request.QueryString["inspecPhoto"], out photoID) || photoID <= 0 ||
                !DateTime.TryParseExact(Request.QueryString["photoDate"], DateFormat,
                    CultureInfo.InvariantCulture, DateTimeStyles.None, out photoDate))
                throw new HttpException(400, "Parameter preview foto tidak valid.");

            try
            {
                string mime;
                byte[] bytes;
                using (var photos = new INSPEC.BRC.T_InspectionPhotos())
                    bytes = photos.ReadPhotoForUser(PB.Path_WebFolder1, userID,
                        photoDate, "Parking", photoID, out mime);

                Response.Clear();
                Response.ContentType = mime;
                Response.AddHeader("X-Content-Type-Options", "nosniff");
                Response.Cache.SetCacheability(HttpCacheability.NoCache);
                Response.Cache.SetNoStore();
                Response.BinaryWrite(bytes);
                Context.ApplicationInstance.CompleteRequest();
            }
            catch (System.IO.FileNotFoundException ex)
            {
                System.Diagnostics.Trace.TraceWarning(
                    "[INSPEC PARKING PREVIEW] PhotoID=" + photoID + ": " + ex.Message);
                throw new HttpException(404, "Foto tidak ditemukan.");
            }
            catch (UnauthorizedAccessException ex)
            {
                System.Diagnostics.Trace.TraceWarning(
                    "[INSPEC PARKING PREVIEW] Access denied: " + ex.Message);
                throw new HttpException(403, "Akses foto tidak diizinkan.");
            }
        }

        private void BindPage()
        {
            try
            {
                string companyID = CompanyID;
                string locationID = LocationID;

                System.Diagnostics.Debug.WriteLine(
                    "[PARKING] CompanyID=[" + companyID +
                    "] LocationID=[" + locationID + "]");

                // Jangan hardcode CompanyID atau LocationID.
                // Keduanya tetap mengikuti konteks perusahaan/lokasi.
                if (String.IsNullOrWhiteSpace(companyID) ||
                    String.IsNullOrWhiteSpace(locationID))
                {
                    var emptyPayload = new Dictionary<string, object>();

                    emptyPayload["template"] = new object[0];
                    emptyPayload["items"] = new object[0];
                    emptyPayload["maps"] = new object[0];
                    emptyPayload["slots"] = new object[0];
                    emptyPayload["shapes"] = new object[0];
                    emptyPayload["scopePending"] = true;
                    emptyPayload["loadError"] = false;

                    _initialJson = Json(emptyPayload);

                    System.Diagnostics.Trace.TraceWarning(
                        "[PARKING] CompanyID/LocationID belum tersedia.");

                    return;
                }

                DateTime inspectionDate = ParseDate(SelectedDateIso);

                DataSet data;

                using (var br = new INSPEC.BRC.T_ParkingInspection())
                {
                    data = br.Get(
                        companyID,
                        locationID,
                        inspectionDate);
                }

                if (data == null)
                {
                    throw new InvalidOperationException(
                        "Stored procedure tidak mengembalikan DataSet.");
                }

                // Mendukung:
                // 3 result set: Maps, Slots, Shapes
                // 5 result set: PIP Template, PIP Items, Maps, Slots, Shapes

                int mapIndex;
                int slotIndex;
                int shapeIndex;

                if (data.Tables.Count == 3)
                {
                    mapIndex = 0;
                    slotIndex = 1;
                    shapeIndex = 2;
                }
                else if (data.Tables.Count == 5)
                {
                    mapIndex = 2;
                    slotIndex = 3;
                    shapeIndex = 4;
                }
                else
                {
                    throw new InvalidOperationException(
                        "Format result set tidak sesuai. " +
                        "Ditemukan " + data.Tables.Count +
                        " result set. Diperlukan 3 atau 5.");
                }

                // Validasi struktur result set.
                if (!data.Tables[mapIndex].Columns.Contains("MapID") ||
                    !data.Tables[mapIndex].Columns.Contains("FloorCode"))
                {
                    throw new InvalidOperationException(
                        "Result set Parking Map tidak valid.");
                }

                if (!data.Tables[slotIndex].Columns.Contains("SlotID") ||
                    !data.Tables[slotIndex].Columns.Contains("MapID"))
                {
                    throw new InvalidOperationException(
                        "Result set Parking Slot tidak valid.");
                }

                if (!data.Tables[shapeIndex].Columns.Contains("MapID") ||
                    !data.Tables[shapeIndex].Columns.Contains("SlotID"))
                {
                    throw new InvalidOperationException(
                        "Result set Parking Shape tidak valid.");
                }

                // Checklist tetap khusus Parking Inspection.
                // Tidak mengambil definisi checklist dari tabel PIP.

                var checklist = new[]
        {
            new
            {
                Code = "NoPolisi",
                Label = "No Polisi",
                Type = "TEXT",
                Required = true,
                Options = new string[0]
            },
            new
            {
                Code = "Jenis",
                Label = "Jenis",
                Type = "TEXT",
                Required = true,
                Options = new string[0]
            },
            new
            {
                Code = "Pintu",
                Label = "Pintu",
                Type = "OPTION",
                Required = false,
                Options = new[] { "Terkunci", "Tidak terkunci" }
            },
            new
            {
                Code = "Body",
                Label = "Body",
                Type = "OPTION",
                Required = false,
                Options = new[] { "Bagus", "Baret" }
            },
            new
            {
                Code = "Roda",
                Label = "Roda",
                Type = "OPTION",
                Required = false,
                Options = new[] { "Bagus", "Kempes" }
            }
        };

                var payload = new Dictionary<string, object>();

                payload["template"] = new object[0];
                payload["items"] = checklist;
                var parkingMaps = Rows(data.Tables[mapIndex]);

                foreach (Dictionary<string, object> parkingMap in parkingMaps)
                {
                    string imagePath = Convert.ToString(parkingMap["ImagePath"]);

                    parkingMap["ImagePath"] = GetParkingImageUrl(imagePath);
                }

                payload["maps"] = parkingMaps;
                payload["slots"] = Rows(data.Tables[slotIndex]);
                payload["shapes"] = Rows(data.Tables[shapeIndex]);
                using (var photos = new INSPEC.BRC.T_InspectionPhotos())
                    payload["inspectionPhotos"] = photos.ListByDate(
                        companyID, locationID, inspectionDate, "Parking");

                // PARKING-04C: read daily status, approval history, and current WAL role.
                // No approval button is authorized solely by this JSON; SQL revalidates it.
                using (var approvalBR = new INSPEC.BRC.T_ParkingInspection())
                {
                    string currentUser = Convert.ToString(Master.Mn_UserID).Trim();
                    DataSet daily = approvalBR.GetDailyApproval(companyID, locationID, inspectionDate, currentUser);
                    DataTable headers = daily.Tables[0];
                    payload["dailyWorkflow"] = headers.Rows.Count == 0 ? "NOT CREATED" :
                        Convert.ToString(headers.Rows[0]["WorkflowStatus"]);
                    payload["parkingDailyID"] = headers.Rows.Count == 0 ? null :
                        (object)Convert.ToInt64(headers.Rows[0]["ParkingDailyID"]);
                    payload["approvalRowVer"] = headers.Rows.Count == 0 ? null :
                        Convert.ToBase64String((byte[])headers.Rows[0]["RowVer"]);
                    payload["approvalHistory"] = Rows(daily.Tables[1]);
                    payload["approvalPermissions"] = Rows(daily.Tables[2]);
                    DataSet validation = approvalBR.ValidateDaily(companyID, locationID, inspectionDate);
                    if (validation.Tables.Count < 1 || validation.Tables[0].Rows.Count != 1 ||
                        !validation.Tables[0].Columns.Contains("IsReadyForChecked"))
                        throw new DataException("Result validasi Parking tidak sesuai.");
                    DataRow summary = validation.Tables[0].Rows[0];
                    payload["approvalValidation"] = Rows(validation.Tables[0])[0];
                }

                payload["scopePending"] = false;
                payload["loadError"] = false;

                _initialJson = Json(payload);

                System.Diagnostics.Debug.WriteLine(
                    "[PARKING] BindPage SUCCESS" +
                    " | Maps=" + data.Tables[mapIndex].Rows.Count +
                    " | Slots=" + data.Tables[slotIndex].Rows.Count +
                    " | Shapes=" + data.Tables[shapeIndex].Rows.Count +
                    " | Checklist=" + checklist.Length);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Trace.TraceError(
                    "[PARKING] BindPage gagal: " + ex.ToString());

                var errorPayload = new Dictionary<string, object>();

                errorPayload["template"] = new object[0];
                errorPayload["items"] = new object[0];
                errorPayload["maps"] = new object[0];
                errorPayload["slots"] = new object[0];
                errorPayload["shapes"] = new object[0];

                errorPayload["scopePending"] = false;
                errorPayload["loadError"] = true;
                errorPayload["errorMessage"] = ex.Message;

                _initialJson = Json(errorPayload);

                Alert("Load Parking Inspection gagal: " + ex.Message);
            }
        }


        private string GetParkingImageUrl(string imagePath)
        {
            if (string.IsNullOrWhiteSpace(imagePath))
                return string.Empty;

            string relativePath = imagePath.Replace("\\", "/").Trim();

            if (relativePath.StartsWith("http://",
                    StringComparison.OrdinalIgnoreCase) ||
                relativePath.StartsWith("https://",
                    StringComparison.OrdinalIgnoreCase))
            {
                return relativePath;
            }

            int imagesIndex = relativePath.IndexOf(
                "/Images/",
                StringComparison.OrdinalIgnoreCase);

            if (imagesIndex >= 0)
            {
                relativePath = relativePath.Substring(
                    imagesIndex + "/Images/".Length);
            }

            relativePath = relativePath.TrimStart('/');

            if (relativePath.StartsWith("WebFolder/",
                    StringComparison.OrdinalIgnoreCase))
            {
                relativePath = relativePath.Substring("WebFolder/".Length);
            }

            if (relativePath.StartsWith("Images/",
                    StringComparison.OrdinalIgnoreCase))
            {
                relativePath = relativePath.Substring("Images/".Length);
            }

            return "/WebFolder/Images/" + relativePath;
        }



        // PARKING-04C: same approval flow pattern as Lighting; daily status is authoritative.
        protected void btnParkingApprove_Click(object sender, EventArgs e)
        {
            try
            {
                if (hfParkingDate.Value != SelectedDateIso)
                    throw new InvalidOperationException("Tanggal berubah. Klik Load Date dahulu.");
                string actor = Convert.ToString(Master.Mn_UserID).Trim();
                if (String.IsNullOrWhiteSpace(actor) || actor.Length > 50 ||
                    String.IsNullOrWhiteSpace(CompanyID) || String.IsNullOrWhiteSpace(LocationID))
                    throw new UnauthorizedAccessException("Sesi WAL atau lokasi tidak valid.");
                DateTime date = ParseDate(SelectedDateIso);
                byte[] postedRowVer;
                try { postedRowVer = Convert.FromBase64String(hfParkingApprovalRowVer.Value); }
                catch (FormatException) { throw new InvalidOperationException("RowVer konfirmasi invalid."); }
                if (postedRowVer.Length != 8)
                    throw new InvalidOperationException("RowVer konfirmasi harus 8 byte.");
                using (var br = new INSPEC.BRC.T_ParkingInspection())
                {
                    DataSet latest = br.GetDailyApproval(CompanyID, LocationID, date, actor);
                    if (latest.Tables[0].Rows.Count != 1)
                        throw new InvalidOperationException("Header approval harian belum tersedia.");
                    DataRow header = latest.Tables[0].Rows[0];
                    byte[] currentRowVer = (byte[])header["RowVer"];
                    if (!currentRowVer.SequenceEqual(postedRowVer))
                        throw new InvalidOperationException("Data inspeksi sudah berubah. Load Date kembali.");
                    string status = Convert.ToString(header["WorkflowStatus"]);
                    string code;
                    switch (status)
                    {
                        case "DRAFT": code = "CHECKED"; break;
                        case "CHECKED": code = "VERIFIED"; break;
                        case "VERIFIED": code = "ACKNOWLEDGED"; break;
                        default: throw new InvalidOperationException("Tidak ada approval selanjutnya.");
                    }
                    // Never trust role/action from browser. Permission preview is non-authoritative.
                    // Stored procedure MUST enforce WAL membership, location, order and distinct actors.
                    br.ApproveDaily(CompanyID, LocationID, date, code, actor, currentRowVer,
                        hfParkingConfirmNoVehicles.Value == "1" && code == "CHECKED");
                }
                BindPage();
                Alert("Approval Parking berhasil.");
            }
            catch (Exception ex)
            {
                BindPage();
                Alert("Approval Parking gagal: " + ex.Message);
            }
        }

        // =========================================================
        // SAVE MODEL
        // =========================================================

        private class Entry
        {
            public int MapID { get; set; }

            public int SlotID { get; set; }

            public string NoPolisi { get; set; }

            public string Jenis { get; set; }

            public string Pintu { get; set; }

            public string Body { get; set; }

            public string Roda { get; set; }

            public string Notes { get; set; }
        }

        // =========================================================
        // SAVE PARKING INSPECTION
        // =========================================================

        protected void btnParkingSave_Click(
            object sender,
            EventArgs e)
        {
            try
            {
                if (hfParkingDate.Value != SelectedDateIso)
                {
                    throw new InvalidOperationException(
                        "Tanggal berubah. " +
                        "Klik Load Date sebelum Save.");
                }

                string companyID = CompanyID;
                string locationID = LocationID;

                if (String.IsNullOrWhiteSpace(companyID) ||
                    String.IsNullOrWhiteSpace(locationID))
                {
                    throw new InvalidOperationException(
                        "CompanyID/LocationID belum tersedia.");
                }

                string userID =
                    Convert.ToString(Master.Mn_UserID).Trim();

                if (String.IsNullOrWhiteSpace(userID))
                {
                    throw new UnauthorizedAccessException(
                        "UserID login tidak tersedia.");
                }

                var serializer =
                    new JavaScriptSerializer();

                serializer.MaxJsonLength = 5000000;

                Entry item =
                    serializer.Deserialize<Entry>(
                        hfParkingPayload.Value);

                if (item == null ||
                    item.MapID <= 0 ||
                    item.SlotID <= 0)
                {
                    throw new InvalidOperationException(
                        "MapID atau SlotID tidak valid.");
                }

                string noPolisi =
                    (item.NoPolisi ?? "").Trim().ToUpperInvariant();

                string jenis =
                    (item.Jenis ?? "").Trim().ToUpperInvariant();

                string notes =
                    (item.Notes ?? "").Trim();

                if (String.IsNullOrWhiteSpace(noPolisi) ||
                    noPolisi.Length > 40)
                {
                    throw new InvalidOperationException(
                        "No Polisi wajib diisi " +
                        "dan maksimal 40 karakter.");
                }

                if (String.IsNullOrWhiteSpace(jenis) ||
                    jenis.Length > 100)
                {
                    throw new InvalidOperationException(
                        "Jenis kendaraan wajib diisi " +
                        "dan maksimal 100 karakter.");
                }

                if (notes.Length > 2000)
                {
                    throw new InvalidOperationException(
                        "Catatan maksimal 2000 karakter.");
                }

                if (String.IsNullOrWhiteSpace(item.Pintu) ||
                    String.IsNullOrWhiteSpace(item.Body) ||
                    String.IsNullOrWhiteSpace(item.Roda))
                    throw new InvalidOperationException(
                        "Pintu, Body, dan Roda wajib diisi sebelum Save.");

                // Validasi pilihan sesuai master PIP
                // Section 204.

                ValidateOption(
                    "Pintu",
                    item.Pintu,
                    "Terkunci",
                    "Tidak terkunci");

                ValidateOption(
                    "Body",
                    item.Body,
                    "Bagus",
                    "Baret");

                ValidateOption(
                    "Roda",
                    item.Roda,
                    "Bagus",
                    "Kempes");

                DateTime inspectionDate =
                    ParseDate(SelectedDateIso);

                // PHOTO-03E: check existing evidence before modifying the transaction.
                // Photos are scoped by CompanyID+LocationID, date, MapID and SlotID.
                bool hasOverview = false;
                bool hasDamage = false;
                using (var photos = new INSPEC.BRC.T_InspectionPhotos())
                {
                    foreach (var existing in photos.ListByDate(
                        companyID, locationID, inspectionDate, "Parking"))
                    {
                        if (existing.ObjectID != item.SlotID || existing.MapID != item.MapID)
                            continue;
                        if (existing.PhotoType == "OVERVIEW") hasOverview = true;
                        if (existing.PhotoType == "DAMAGE") hasDamage = true;
                    }
                }

                bool newOverview = fuParkingPhoto.HasFile;
                bool newDamage = fuParkingDamagePhoto.HasFile;
                bool needsDamage = item.Body == "Baret" || item.Roda == "Kempes";

                // Validate both inputs BEFORE Save to avoid creating a detail without evidence.
                if (!hasOverview && !newOverview)
                    throw new InvalidOperationException(
                        "Foto kendaraan (overview) wajib dilampirkan sebelum Save.");
                if (needsDamage && !hasDamage && !newDamage)
                    throw new InvalidOperationException(
                        "Body Baret / Roda Kempes wajib memiliki foto kerusakan.");

                ValidatePendingPhoto(fuParkingPhoto, "Foto kendaraan");
                ValidatePendingPhoto(fuParkingDamagePhoto, "Foto kerusakan");

                using (var br =
                    new INSPEC.BRC.T_ParkingInspection())
                {
                    br.Save(
                        companyID,
                        locationID,
                        item.MapID,
                        inspectionDate,
                        item.SlotID,
                        noPolisi,
                        jenis,
                        item.Pintu,
                        item.Body,
                        item.Roda,
                        notes,
                        userID);
                }

                // Save detail first; Upload() needs InspectionID + SlotID to exist.
                // Both images are uploaded in the same Save click (same HTTP postback).
                // The operations are sequential, not one SQL+filesystem transaction.
                try
                {
                    if (newOverview || newDamage)
                    {
                        using (var photos = new INSPEC.BRC.T_InspectionPhotos())
                        {
                            if (newOverview)
                                photos.Upload(PB.Path_WebFolder1, companyID, locationID,
                                    "Parking", item.SlotID, inspectionDate, 0, item.MapID,
                                    "OVERVIEW", fuParkingPhoto.PostedFile, userID);
                            if (newDamage)
                                photos.Upload(PB.Path_WebFolder1, companyID, locationID,
                                    "Parking", item.SlotID, inspectionDate, 0, item.MapID,
                                    "DAMAGE", fuParkingDamagePhoto.PostedFile, userID);
                        }
                    }
                }
                catch (Exception uploadError)
                {
                    System.Diagnostics.Trace.TraceError(
                        "[INSPEC PARKING PHOTO] Save detail succeeded, upload failed: " +
                        uploadError.ToString());
                    throw new InvalidOperationException(
                        "Data kendaraan sudah tersimpan sebagai DRAFT, tetapi upload foto gagal. " +
                        "Buka kembali slot ini, pilih foto yang belum tersimpan, lalu Save lagi. " +
                        "Detail: " + uploadError.Message);
                }

                BindPage();
                Alert("Parking Inspection dan foto berhasil disimpan.");
            }
            catch (Exception ex)
            {
                BindPage();

                Alert(
                    "Save Parking Inspection gagal: " +
                    ex.Message);
            }
        }

        private static void ValidatePendingPhoto(System.Web.UI.WebControls.FileUpload control,
                                                 string label)
        {
            if (!control.HasFile) return;
            var posted = control.PostedFile;
            if (posted == null || posted.ContentLength <= 0 || posted.ContentLength > 5242880)
                throw new InvalidOperationException(label + " harus berukuran 1 byte sampai 5 MB.");
            string extension = System.IO.Path.GetExtension(posted.FileName).ToLowerInvariant();
            if (extension != ".jpg" && extension != ".jpeg" && extension != ".png")
                throw new InvalidOperationException(label + " harus berformat JPG atau PNG.");
            // The BRC Upload() performs authoritative image-content validation.
        }

        // =========================================================
        // VALIDATION
        // =========================================================

        private static void ValidateOption(
            string fieldName,
            string value,
            string allowed1,
            string allowed2)
        {
            if (String.IsNullOrWhiteSpace(value))
            {
                return;
            }

            if (!String.Equals(
                    value,
                    allowed1,
                    StringComparison.Ordinal) &&
                !String.Equals(
                    value,
                    allowed2,
                    StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "Nilai " + fieldName +
                    " tidak sesuai master checklist.");
            }
        }

        private void DebugParkingScope(string stage)
        {
            System.Diagnostics.Trace.WriteLine(
                "[PARKING][" + stage + "] " +
                "IsPostBack=" + IsPostBack +
                ", Master.CompanyID=[" +
                Convert.ToString(Master.Mn_CompanyID) + "]" +
                ", Master.LocationID=[" +
                Convert.ToString(Master.Mn_LocationID) + "]" +
                ", UserID=[" +
                Convert.ToString(Master.Mn_UserID) + "]"
            );
        }
    }
}

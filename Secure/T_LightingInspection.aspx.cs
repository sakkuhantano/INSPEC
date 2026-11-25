using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.Linq;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.UI;
using System.Web.UI.WebControls;
using WAL;

namespace INSPEC.Secure
{
    public partial class T_LightingInspection : WAL.PB, WAL.I_ToolBar_2
    {
        private const string _MenuID = "20023";
        private const string DateFormat = "yyyy-MM-dd";
        private string _initialJson = "{}";
        public string InitialJson { get { return _initialJson; } }
        public string SelectedDateIso { get { return (ViewState["LightingDate"] as string) ?? DateTime.Today.ToString(DateFormat, CultureInfo.InvariantCulture); } }

        public void Toolbar_Click(object sender, ToolBarEventArgs_2 e)
        {
            if (e.ToolbarItem == ToolbarItem_2.Refresh) BindPage();
        }
        private void InitToolbar()
        {
            Master.TB_VisibleToolbar(false);
            Master.TB_VisibleButton(ToolbarItem_2.Refresh, false);
        }
        protected override void OnInit(EventArgs e)
        {
            if (Context.User != null && Context.User.Identity != null && Context.User.Identity.IsAuthenticated)
                ViewStateUserKey = Context.User.Identity.Name;
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
            if (!IsPostBack)
            {
                using (WAL.BR.SysWebMenu sw = new WAL.BR.SysWebMenu())
                {
                    sw.AppID = PB.AppID;
                    sw.MenuID = _MenuID;
                    if (sw.SelectOneByMenuID().Rows.Count > 0)
                    {
                        Master.Mn_lit_Title = WAL.PB.AppID + " -> " + sw.Description;
                    }
                }
                BindPage();
            }
        }
        private static DateTime ParseDate(string value)
        {
            return DateTime.ParseExact(value, DateFormat, CultureInfo.InvariantCulture, DateTimeStyles.None);
        }
        private static List<Dictionary<string, object>> Rows(DataTable table)
        {
            var result = new List<Dictionary<string, object>>();
            foreach (DataRow row in table.Rows)
            {
                var item = new Dictionary<string, object>();
                foreach (DataColumn col in table.Columns)
                {
                    object v = row[col];
                    item[col.ColumnName] = v == DBNull.Value ? null : v;
                }
                result.Add(item);
            }
            return result;
        }

        private void BindPage()
        {
            try
            {
                string companyID = Master.Mn_CompanyID;
                string locationID = Master.Mn_LocationID;

                System.Diagnostics.Debug.WriteLine(
                    "[LIGHTING] CompanyID=[" + companyID +
                    "] LocationID=[" + locationID + "]"
                );

                // MASTER-01E: First GET precedes browser-side Master scope initialization.
                // The existing ASPX scopePending handler automatically posts Load Date.
                if (String.IsNullOrWhiteSpace(companyID) ||
                    String.IsNullOrWhiteSpace(locationID))
                {
                    if (!IsPostBack)
                    {
                        _initialJson = "{\"maps\":[],\"areas\":[],\"lights\":[]," +
                            "\"paths\":[],\"checklist\":[],\"scopePending\":true}";
                        return;
                    }
                    throw new InvalidOperationException(
                        "CompanyID/LocationID belum tersedia pada postback.");
                }

                DateTime inspectionDate = ParseDate(SelectedDateIso);

                DataSet checklist;
                using (var br = new INSPEC.BRC.T_LightingInspection())
                {
                    checklist = br.GetLightingChecklist(
                        companyID, locationID, inspectionDate);
                }

                string workflow = checklist.Tables[0].Rows.Count == 0
                    ? null
                    : Convert.ToString(
                        checklist.Tables[0].Rows[0]["WorkflowStatus"]);

                DataSet map = null;
                string mapWarning = null;

                try
                {
                    using (var br = new INSPEC.BRC.T_LightingInspection())
                    {
                        map = br.GetLightingInspectionMap(
                            companyID, locationID, inspectionDate);
                    }
                }
                catch (System.Data.SqlClient.SqlException ex)
                {
                    // Hanya tangani error spesifik legacy tanpa snapshot.
                    // Error database lainnya tetap dilempar.
                    if (ex.Number == 50000 &&
                        ex.Message.IndexOf(
                            "Inspeksi lama belum memiliki snapshot versi denah",
                            StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        mapWarning =
                            "Versi denah untuk inspeksi lama ini belum " +
                            "terverifikasi. Denah historis tidak ditampilkan.";
                    }
                    else
                    {
                        throw;
                    }
                }

                var payload = new Dictionary<string, object>();

                payload["maps"] = map == null
                    ? new List<Dictionary<string, object>>()
                    : Rows(map.Tables[0]);

                payload["areas"] = map == null
                    ? new List<Dictionary<string, object>>()
                    : Rows(map.Tables[1]);

                payload["lights"] = map == null
                    ? new List<Dictionary<string, object>>()
                    : Rows(map.Tables[2]);

                payload["paths"] = map == null
                    ? new List<Dictionary<string, object>>()
                    : Rows(map.Tables[3]);

                payload["checklist"] = Rows(checklist.Tables[1]);
                payload["workflow"] = workflow;
                payload["inspectionID"] = null;
                payload["rowVer"] = null;
                if (checklist.Tables[0].Rows.Count > 0)
                {
                    DataRow currentHeader = checklist.Tables[0].Rows[0];
                    payload["inspectionID"] = Convert.ToInt64(currentHeader["InspectionID"]);
                    if (currentHeader["RowVer"] != DBNull.Value)
                        payload["rowVer"] = Convert.ToBase64String((byte[])currentHeader["RowVer"]);
                }

                // Optional header fields: no schema assumption or extra SQL query.
                // Null means approval details are not returned by the current SP.
                if (checklist.Tables[0].Rows.Count > 0)
                {
                    DataRow header = checklist.Tables[0].Rows[0];
                    string[] approvalFields = new string[] {
                        "IsApproval1", "IsApproval2", "IsApproval3", "IsApproval4",
                        "UserApprove1", "UserApprove2", "UserApprove3", "UserApprove4",
                        "DateApprove1", "DateApprove2", "DateApprove3", "DateApprove4"
                    };
                    bool hasAllApprovalFields = approvalFields.All(
                        field => checklist.Tables[0].Columns.Contains(field));
                    if (hasAllApprovalFields)
                    {
                        var approval = new Dictionary<string, object>();
                        foreach (string field in approvalFields)
                        {
                            object value = header[field];
                            approval[field] = value == DBNull.Value ? null : value;
                        }
                        payload["approval"] = approval;
                    }
                }
                payload["mapWarning"] = mapWarning;
                using (var photos = new INSPEC.BRC.T_InspectionPhotos())
                    payload["inspectionPhotos"] = photos.ListByDate(
                        companyID, locationID, inspectionDate, "Lighting");

                var serializer = new JavaScriptSerializer();
                serializer.MaxJsonLength = 5000000;

                var lightingMaps =
                    (List<Dictionary<string, object>>)payload["maps"];

                foreach (Dictionary<string, object> lightingMap in lightingMaps)
                {
                    string imagePath =
                        Convert.ToString(lightingMap["ImagePath"]);

                    lightingMap["ImagePath"] =
                        GetLightingImageUrl(imagePath);
                }

                _initialJson = serializer.Serialize(payload)
                    .Replace("<", "\\u003c")
                    .Replace(">", "\\u003e")
                    .Replace("&", "\\u0026");
            }
            catch (Exception ex)
            {
                _initialJson =
                    "{\"maps\":[],\"areas\":[],\"lights\":[]," +
                    "\"paths\":[],\"checklist\":[]," +
                    "\"workflow\":\"ERROR\"}";

                ShowAlert(
                    "Gagal membaca Lighting Inspection: " + ex.Message);
            }
        }

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
                        photoDate, "Lighting", photoID, out mime);

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
                    "[INSPEC LIGHTING PREVIEW] PhotoID=" + photoID + ": " + ex.Message);
                throw new HttpException(404, "Foto tidak ditemukan.");
            }
            catch (UnauthorizedAccessException ex)
            {
                System.Diagnostics.Trace.TraceWarning(
                    "[INSPEC LIGHTING PREVIEW] Access denied: " + ex.Message);
                throw new HttpException(403, "Akses foto tidak diizinkan.");
            }
        }

        private void ShowAlert(string message)
        {
            // Script is encoded by JavaScriptSerializer, not concatenated unescaped.
            string encoded = new JavaScriptSerializer().Serialize(message);
            ClientScript.RegisterStartupScript(GetType(), "lightingMsg", "alert(" + encoded + ");", true);
        }

        protected void btnLightingLoad_Click(object sender, EventArgs e)
        {
            DateTime date;

            if (!DateTime.TryParseExact(
                hfLightingDate.Value,
                DateFormat,
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out date))
            {
                ShowAlert("Tanggal inspeksi tidak valid.");
                BindPage();
                return;
            }

            // Tidak boleh memilih tanggal setelah hari ini
            if (date.Date > DateTime.Today)
            {
                ShowAlert("Tanggal inspeksi tidak boleh melebihi hari ini.");
                BindPage();
                return;
            }

            ViewState["LightingDate"] = date.ToString(
                DateFormat,
                CultureInfo.InvariantCulture
            );

            BindPage();
        }

        // Task 05D-05B.4 — UAT: only DRAFT -> CHECKED.
        protected void btnLightingApprove_Click(object sender, EventArgs e)
        {
            try
            {
                if (hfLightingDate.Value != SelectedDateIso)
                    throw new InvalidOperationException(
                        "Tanggal berubah. Klik Load Date dahulu.");

                string actorUserID =
                    Convert.ToString(Master.Mn_UserID).Trim();

                if (String.IsNullOrWhiteSpace(actorUserID) ||
                    actorUserID.Length > 50)
                {
                    throw new UnauthorizedAccessException(
                        "UserID login tidak valid untuk approval.");
                }

                byte[] confirmedRowVer;

                try
                {
                    confirmedRowVer =
                        Convert.FromBase64String(hfApprovalRowVer.Value);
                }
                catch (FormatException)
                {
                    throw new InvalidOperationException(
                        "RowVer konfirmasi tidak valid.");
                }

                if (confirmedRowVer.Length != 8)
                    throw new InvalidOperationException(
                        "RowVer konfirmasi harus 8 byte.");

                string companyID = Master.Mn_CompanyID;
                string locationID = Master.Mn_LocationID;
                DateTime inspectionDate = ParseDate(SelectedDateIso);

                DataSet latest;

                using (var br = new INSPEC.BRC.T_LightingInspection())
                {
                    latest = br.GetLightingChecklist(
                        companyID,
                        locationID,
                        inspectionDate);
                }

                if (latest.Tables.Count < 2 ||
                    latest.Tables[0].Rows.Count != 1)
                {
                    throw new InvalidOperationException(
                        "Header inspeksi tidak ditemukan.");
                }

                DataRow header = latest.Tables[0].Rows[0];

                string currentStatus =
                    Convert.ToString(header["WorkflowStatus"]);

                string approvalCode;
                string successMessage;

                // Tentukan approval berdasarkan status database,
                // bukan berdasarkan input dari browser.
                switch (currentStatus)
                {
                    case "DRAFT":
                        approvalCode = "CHECKED";
                        successMessage =
                            "Inspeksi berhasil diselesaikan (CHECKED).";
                        break;

                    case "CHECKED":
                        approvalCode = "VERIFIED";
                        successMessage =
                            "Inspeksi berhasil diverifikasi (VERIFIED).";
                        break;

                    case "VERIFIED":
                        approvalCode = "ACKNOWLEDGED_1";
                        successMessage =
                            "Acknowledged By 1 berhasil.";
                        break;

                    case "ACKNOWLEDGED_1":
                        approvalCode = "ACKNOWLEDGED_2";
                        successMessage =
                            "Acknowledged By 2 berhasil. Inspeksi FINAL.";
                        break;

                    default:
                        throw new InvalidOperationException(
                            "Status inspeksi tidak dapat di-approve: " +
                            currentStatus);
                }

                if (header["RowVer"] == DBNull.Value)
                {
                    throw new InvalidOperationException(
                        "RowVer inspeksi tidak tersedia.");
                }

                byte[] currentRowVer =
                    (byte[])header["RowVer"];

                if (!currentRowVer.SequenceEqual(confirmedRowVer))
                {
                    throw new InvalidOperationException(
                        "Inspeksi telah berubah. Refresh halaman sebelum approval.");
                }

                long inspectionID =
                    Convert.ToInt64(header["InspectionID"]);

                if (inspectionID <= 0)
                {
                    throw new InvalidOperationException(
                        "InspectionID tidak valid.");
                }

                // Stored procedure tetap memvalidasi:
                // - User aktif dan role approval
                // - CompanyID / LocationID
                // - Urutan workflow
                // - Kelengkapan checklist untuk CHECKED
                // - RowVer dan concurrent update
                // - ACK1 dan ACK2 harus berbeda UserID
                using (var br = new INSPEC.BRC.T_LightingInspection())
                {
                    br.ApproveLightingInspection(
                        companyID,
                        locationID,
                        inspectionID,
                        approvalCode,
                        actorUserID,
                        currentRowVer,
                        null);
                }

                // LI-02: Approval has committed. Queue notification independently.
                // Email/queue failures must NEVER be shown as an approval failure.
                // LI-02: Approval sudah committed.
                // Queue dan kirim email langsung untuk inspeksi ini saja.
                // Kegagalan email tidak boleh membatalkan approval.

                if (approvalCode == "CHECKED" || approvalCode == "VERIFIED")
                {
                    bool queueSucceeded = false;

                    try
                    {
                        using (var emailQueue = new INSPEC.BRC.LightingEmailQueue())
                        {
                            emailQueue.Queue(
                                companyID,
                                locationID,
                                inspectionID,
                                approvalCode
                            );
                        }

                        queueSucceeded = true;
                    }
                    catch (Exception emailEx)
                    {
                        System.Diagnostics.Trace.TraceError(
                            "LI-02 email queue failed. InspectionID=" +
                            inspectionID + ": " + emailEx.ToString());

                        successMessage +=
                            " Email Queue Error: " + emailEx.Message;
                    }

                    if (queueSucceeded)
                    {
                        try
                        {
                            INSPEC.BRC.LightingEmailDispatchResult dispatch =
                                INSPEC.BRC.LightingEmailDispatcher.RunForInspection(
                                    companyID,
                                    locationID,
                                    inspectionID,
                                    approvalCode
                                );

                            if (dispatch.Selected == 0)
                            {
                                successMessage +=
                                    " Tidak ada email tertunda yang dapat dikirim.";
                            }
                            else if (dispatch.Failed == 0 &&
                                     dispatch.Sent == dispatch.Selected)
                            {
                                successMessage +=
                                    " Notifikasi email berhasil dikirim.";
                            }
                            else
                            {
                                successMessage +=
                                    String.Format(
                                        " Notifikasi email: {0} berhasil, {1} belum terkirim.",
                                        dispatch.Sent,
                                        dispatch.Failed
                                    );
                            }
                        }
                        catch (Exception dispatchEx)
                        {
                            System.Diagnostics.Trace.TraceError(
                                "LI-02 email dispatch failed. InspectionID=" +
                                inspectionID + ": " + dispatchEx);

                            successMessage +=
                                " Pengiriman email belum berhasil; hubungi administrator.";
                        }
                    }
                }
                BindPage();
                ShowAlert(successMessage);
            }
            catch (Exception ex)
            {
                BindPage();
                ShowAlert("Approval gagal: " + ex.Message);
            }
        }

        private class InspectionItem
        {
            public int ScheduleID { get; set; }
            public int LightID { get; set; }
            public string LightStatus { get; set; }
            public string Notes { get; set; }
        }
        protected void btnLightingSave_Click(object sender, EventArgs e)
        {
            try
            {
                // Date must be loaded through the server first; prevents saving a different date silently.
                if (hfLightingDate.Value != SelectedDateIso)
                    throw new InvalidOperationException("Tanggal berubah. Klik Load Date sebelum Save.");
                string userID = Convert.ToString(Master.Mn_UserID);
                if (String.IsNullOrWhiteSpace(userID))
                    throw new UnauthorizedAccessException("EmployeeID tidak tersedia.");
                var serializer = new JavaScriptSerializer();
                serializer.MaxJsonLength = 5000000;
                var items = serializer.Deserialize<List<InspectionItem>>(hfLightingPayload.Value);
                if (items == null || items.Count == 0 || items.Count > 183)
                    throw new InvalidOperationException("Jumlah item Save tidak valid.");
                DataSet latest;
                using (var br = new INSPEC.BRC.T_LightingInspection())
                    latest = br.GetLightingChecklist(Master.Mn_CompanyID, Master.Mn_LocationID, ParseDate(SelectedDateIso));
                if (latest.Tables[0].Rows.Count > 0 && Convert.ToString(latest.Tables[0].Rows[0]["WorkflowStatus"]) != "DRAFT")
                    throw new UnauthorizedAccessException("Inspeksi sudah terkunci.");
                var allowed = new HashSet<string>();
                foreach (DataRow r in latest.Tables[1].Rows)
                    allowed.Add(Convert.ToString(r["ScheduleID"]) + ":" + Convert.ToString(r["LightID"]));
                DataTable tvp = INSPEC.BRC.T_LightingInspection.CreateInspectionItemsTable();
                foreach (InspectionItem item in items)
                {
                    if (item == null || !allowed.Contains(item.ScheduleID + ":" + item.LightID))
                        throw new InvalidOperationException("Lampu atau jadwal tidak valid.");
                    if (item.LightStatus != "ON" && item.LightStatus != "OFF")
                        throw new InvalidOperationException("Status harus ON/OFF.");
                    tvp.Rows.Add(item.ScheduleID, item.LightID, item.LightStatus, (object)(item.Notes ?? ""));
                }
                using (var br = new INSPEC.BRC.T_LightingInspection())
                    br.SaveLightingInspection(Master.Mn_CompanyID, Master.Mn_LocationID, ParseDate(SelectedDateIso), userID, tvp);
                BindPage();
                ShowAlert("Lighting Inspection berhasil disimpan.");
            }
            catch (Exception ex)
            {
                BindPage();
                ShowAlert("Save gagal: " + ex.Message);
            }
        }

        // PHOTO-03B: Apply validates evidence on the server and saves the
        // current changes, then registers the uploaded photo when provided.
        // If file registration fails, the inspection remains DRAFT and CHECKED
        // will still reject OFF details without evidence.
        protected void btnLightingApplyWithPhoto_Click(object sender, EventArgs e)
        {
            try
            {
                if (hfLightingDate.Value != SelectedDateIso)
                    throw new InvalidOperationException("Tanggal berubah. Klik Load Date sebelum Terapkan.");
                int lightID, scheduleID;
                if (!Int32.TryParse(hfLightingPhotoLight.Value, out lightID) || lightID <= 0 ||
                    !Int32.TryParse(hfLightingPhotoSchedule.Value, out scheduleID) || scheduleID <= 0)
                    throw new InvalidOperationException("Lampu atau jadwal tidak valid.");

                string companyID = Master.Mn_CompanyID;
                string locationID = Master.Mn_LocationID;
                string userID = Convert.ToString(Master.Mn_UserID).Trim();
                if (String.IsNullOrWhiteSpace(companyID) || String.IsNullOrWhiteSpace(locationID) ||
                    String.IsNullOrWhiteSpace(userID))
                    throw new UnauthorizedAccessException("Sesi lokasi atau user tidak valid.");
                DateTime inspectionDate = ParseDate(SelectedDateIso);

                var serializer = new JavaScriptSerializer();
                serializer.MaxJsonLength = 5000000;
                var items = serializer.Deserialize<List<InspectionItem>>(hfLightingPayload.Value);
                if (items == null || items.Count == 0 || items.Count > 183)
                    throw new InvalidOperationException("Perubahan lampu tidak valid.");
                InspectionItem selectedItem = items.FirstOrDefault(x => x != null &&
                    x.ScheduleID == scheduleID && x.LightID == lightID);
                if (selectedItem == null ||
                    (selectedItem.LightStatus != "ON" && selectedItem.LightStatus != "OFF"))
                    throw new InvalidOperationException("Status lampu tidak valid.");
                if (selectedItem.LightStatus == "OFF" && !fuLightingPhoto.HasFile)
                {
                    bool alreadyHasPhoto;
                    using (var photos = new INSPEC.BRC.T_InspectionPhotos())
                        alreadyHasPhoto = photos.HasLightingEvidence(
                            companyID, locationID, inspectionDate, scheduleID, lightID);
                    if (!alreadyHasPhoto)
                        throw new InvalidOperationException(
                            "Lampu OFF wajib mempunyai foto. Pilih foto sebelum menekan Terapkan.");
                }

                DataSet latest;
                using (var br = new INSPEC.BRC.T_LightingInspection())
                    latest = br.GetLightingChecklist(companyID, locationID, inspectionDate);
                if (latest.Tables[0].Rows.Count > 0 &&
                    Convert.ToString(latest.Tables[0].Rows[0]["WorkflowStatus"]) != "DRAFT")
                    throw new UnauthorizedAccessException("Inspeksi sudah dikunci.");
                var allowed = new HashSet<string>();
                foreach (DataRow row in latest.Tables[1].Rows)
                    allowed.Add(Convert.ToString(row["ScheduleID"]) + ":" + Convert.ToString(row["LightID"]));
                DataTable tvp = INSPEC.BRC.T_LightingInspection.CreateInspectionItemsTable();
                var unique = new HashSet<string>();
                foreach (InspectionItem item in items)
                {
                    if (item == null || !allowed.Contains(item.ScheduleID + ":" + item.LightID) ||
                        !unique.Add(item.ScheduleID + ":" + item.LightID) ||
                        (item.LightStatus != "ON" && item.LightStatus != "OFF") ||
                        (item.Notes ?? "").Length > 1000)
                        throw new InvalidOperationException("Data inspeksi lampu tidak valid.");
                    tvp.Rows.Add(item.ScheduleID, item.LightID, item.LightStatus, item.Notes ?? "");
                }
                using (var br = new INSPEC.BRC.T_LightingInspection())
                    br.SaveLightingInspection(companyID, locationID, inspectionDate, userID, tvp);

                if (fuLightingPhoto.HasFile)
                {
                    using (var photos = new INSPEC.BRC.T_InspectionPhotos())
                        photos.Upload(PB.Path_WebFolder1, companyID, locationID,
                            "Lighting", lightID, inspectionDate, scheduleID, 0,
                            "EVIDENCE", fuLightingPhoto.PostedFile, userID);
                }
                BindPage();
                ShowAlert("Status lampu berhasil disimpan" +
                    (fuLightingPhoto.HasFile ? " bersama foto bukti." : "."));
            }
            catch (Exception ex)
            {
                BindPage();
                ShowAlert("Terapkan gagal: " + ex.Message);
            }
        }

        private string GetLightingImageUrl(string imagePath)
        {
            if (string.IsNullOrWhiteSpace(imagePath))
                return string.Empty;

            string relativePath = imagePath.Replace("\\", "/").Trim();

            // Jika database berisi URL lengkap, gunakan langsung.
            if (relativePath.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
                relativePath.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                return relativePath;
            }

            // Jika masih berupa path fisik, ambil bagian setelah /Images/.
            int imagesIndex = relativePath.IndexOf(
                "/Images/",
                StringComparison.OrdinalIgnoreCase
            );

            if (imagesIndex >= 0)
            {
                relativePath = relativePath.Substring(
                    imagesIndex + "/Images/".Length
                );
            }

            relativePath = relativePath.TrimStart('/');

            // Hindari duplikasi folder.
            if (relativePath.StartsWith("WebFolder/", StringComparison.OrdinalIgnoreCase))
                relativePath = relativePath.Substring("WebFolder/".Length);

            if (relativePath.StartsWith("Images/", StringComparison.OrdinalIgnoreCase))
                relativePath = relativePath.Substring("Images/".Length);

            return "/WebFolder/Images/" + relativePath;
        }

        protected void btnDispatchLightingEmail_Click(object sender, EventArgs e)
        {
            // Replace with the SAME proven admin check used by this page.
            // NEVER rely on button visibility or client-side authorization alone.
            EnsureAdministrator();
            var r = INSPEC.BRC.LightingEmailDispatcher.RunVerified(5);
            lblDispatchLightingEmail.Text = String.Format(
                "Dipilih: {0}; terkirim: {1}; gagal: {2}", r.Selected, r.Sent, r.Failed);
        }

        private void EnsureAdministrator()
        {
            if (!IsAdministrator())
                throw new HttpException(
                    403,
                    "Only INSPEC administrators can change approval routing."
                );
        }
        private bool IsAdministrator()
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable d = br.EQueryP(
                    @"SELECT CASE WHEN EXISTS(SELECT 1 FROM dbo.SysWebUserUserGroup WHERE UserID=@U AND UserGroupID='administrator') THEN 1 ELSE 0 END AS IsAdmin",
                    new SqlParameter[] { new SqlParameter("@U", Master.Mn_EmployeeID) }
                );
                return d.Rows.Count > 0 && Convert.ToInt32(d.Rows[0]["IsAdmin"]) == 1;
            }
        }
    }
}

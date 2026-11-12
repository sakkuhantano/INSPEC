using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Linq;
using System.Web.Script.Serialization;
using System.Web.UI;
using System.Web.UI.WebControls;
using WAL;

namespace INSPEC.Secure
{
    public partial class T_LightingInspection : WAL.PB, WAL.I_ToolBar_2
    {
        private const string _MenuID = "11013";
        private const string CompanyID = "I00024012";
        private const string LocationID = "R02";
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
            Master.TB_VisibleToolbar(true);
            Master.TB_VisibleButton(ToolbarItem_2.Refresh, true);
        }
        protected override void OnInit(EventArgs e)
        {
            if (Context.User != null && Context.User.Identity != null && Context.User.Identity.IsAuthenticated)
                ViewStateUserKey = Context.User.Identity.Name;
            base.OnInit(e);
        }
        protected void Page_Load(object sender, EventArgs e)
        {
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
                DataSet map;
                DataSet checklist;
                using (var br = new INSPEC.BRC.T_LightingInspection())
                    map = br.GetLightingMap(Master.Mn_CompanyID, Master.Mn_LocationID);
                using (var br = new INSPEC.BRC.T_LightingInspection())
                    checklist = br.GetLightingChecklist(Master.Mn_CompanyID, Master.Mn_LocationID, ParseDate(SelectedDateIso));
                string workflow = checklist.Tables[0].Rows.Count == 0 ? null : Convert.ToString(checklist.Tables[0].Rows[0]["WorkflowStatus"]);
                var payload = new Dictionary<string, object>();
                payload["maps"] = Rows(map.Tables[0]);
                payload["areas"] = Rows(map.Tables[1]);
                payload["lights"] = Rows(map.Tables[2]);
                payload["paths"] = Rows(map.Tables[3]);
                payload["checklist"] = Rows(checklist.Tables[1]);
                payload["workflow"] = workflow;
                var serializer = new JavaScriptSerializer();
                serializer.MaxJsonLength = 5000000;

                foreach (Dictionary<string, object> lightingMap in (List<Dictionary<string, object>>)payload["maps"])
                {
                    string imagePath = Convert.ToString(lightingMap["ImagePath"]);

                    lightingMap["ImagePath"] = GetLightingImageUrl(imagePath);
                }
                
                _initialJson = serializer.Serialize(payload).Replace("<", "\\u003c").Replace(">", "\\u003e").Replace("&", "\\u0026");
            }
            catch (Exception ex)
            {
                _initialJson = "{\"maps\":[],\"areas\":[],\"lights\":[],\"paths\":[],\"checklist\":[],\"workflow\":\"ERROR\"}";
                ShowAlert("Gagal membaca Lighting Inspection: " + ex.Message);
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
            if (!DateTime.TryParseExact(hfLightingDate.Value, DateFormat, CultureInfo.InvariantCulture, DateTimeStyles.None, out date))
            {
                ShowAlert("Tanggal inspeksi tidak valid.");
                BindPage();
                return;
            }
            ViewState["LightingDate"] = date.ToString(DateFormat, CultureInfo.InvariantCulture);
            BindPage();
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
                string userID = Convert.ToString(Master.Mn_EmployeeID);
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
    }
}

using System;
using System.Collections.Generic;
using System.Data;
using System.Web.Script.Serialization;
using System.Web.UI;
using System.Web.UI.WebControls;
using WAL;

namespace INSPEC.Secure
{
    public partial class M_LightingMapEditor : WAL.PB, WAL.I_ToolBar_2
    {
        private const string _MenuID = "11013";

        private string _initialJson = "{}";
        public string InitialJson { get { return _initialJson; } }
        public void Toolbar_Click(object sender, ToolBarEventArgs_2 e)
        {
            if (e.ToolbarItem == ToolbarItem_2.Refresh) BindPage();
        }
        protected override void OnInit(EventArgs e)
        {
            if (Context.User != null && Context.User.Identity != null && Context.User.Identity.IsAuthenticated)
                ViewStateUserKey = Context.User.Identity.Name;
            base.OnInit(e);
        }
        protected void Page_Load(object sender, EventArgs e)
        {
            Master.TB_VisibleToolbar(true);
            Master.TB_VisibleButton(ToolbarItem_2.Refresh, true);
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
        // SECURITY: Replace or connect this with the ERP's actual menu-permission check.
        // Until the role is assigned by the existing authentication system, writes are denied.
        private bool CanEdit()
        {
            return Context.User != null && Context.User.Identity != null &&
                   Context.User.Identity.IsAuthenticated && Context.User.IsInRole("INSPEC_LightingMapEditor");
        }
        private static List<Dictionary<string, object>> Rows(DataTable table)
        {
            var list = new List<Dictionary<string, object>>();
            foreach (DataRow row in table.Rows)
            {
                var obj = new Dictionary<string, object>();
                foreach (DataColumn col in table.Columns)
                    obj[col.ColumnName] = row[col] == DBNull.Value ? null : row[col];
                list.Add(obj);
            }
            return list;
        }
        private static string ImageUrl(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return "";
            string p = path.Replace('\\', '/').Trim();
            if (p.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || p.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) return p;
            int at = p.IndexOf("/Images/", StringComparison.OrdinalIgnoreCase);
            if (at >= 0) p = p.Substring(at + 8);
            p = p.TrimStart('/');
            if (p.StartsWith("WebFolder/", StringComparison.OrdinalIgnoreCase)) p = p.Substring(10);
            if (p.StartsWith("Images/", StringComparison.OrdinalIgnoreCase)) p = p.Substring(7);
            return "/WebFolder/Images/" + p;
        }
        private void BindPage()
        {
            try
            {
                DataSet ds;
                using (var br = new INSPEC.BRC.M_LightingMapEditor())
                    ds = br.GetLightingMapEditor(Master.Mn_CompanyID, Master.Mn_LocationID);
                if (ds.Tables.Count < 2) throw new InvalidOperationException("Editor SP harus mengembalikan 2 result set.");
                var maps = Rows(ds.Tables[0]);
                foreach (var m in maps) m["ImagePath"] = ImageUrl(Convert.ToString(m["ImagePath"]));
                var payload = new Dictionary<string, object>();
                payload["maps"] = maps;
                payload["paths"] = Rows(ds.Tables[1]);
                payload["canEdit"] = CanEdit();
                var serializer = new JavaScriptSerializer();
                serializer.MaxJsonLength = 5000000;
                _initialJson = serializer.Serialize(payload).Replace("<", "\\u003c").Replace(">", "\\u003e").Replace("&", "\\u0026");
            }
            catch (Exception ex)
            {
                _initialJson = "{\"maps\":[],\"paths\":[],\"canEdit\":false}";
                Alert("Gagal membaca map editor: " + ex.Message);
            }
        }
        private void Alert(string message)
        {
            ClientScript.RegisterStartupScript(GetType(), "mapEditorAlert", "alert(" + new JavaScriptSerializer().Serialize(message) + ");", true);
        }
        private sealed class EditAction
        {
            public int MapID { get; set; }
            public int MapPathID { get; set; }
            public string ActionType { get; set; }
        }
        protected void btnEditorSave_Click(object sender, EventArgs e)
        {
            if (!CanEdit())
            {
                Response.StatusCode = 403;
                Alert("Tidak memiliki izin untuk mengedit mapping.");
                BindPage();
                return;
            }
            try
            {
                string raw = hfEditorChanges.Value ?? "";
                if (raw.Length > 100000) throw new InvalidOperationException("Payload terlalu besar.");
                var actions = new JavaScriptSerializer().Deserialize<List<EditAction>>(raw);
                if (actions == null || actions.Count == 0 || actions.Count > 250)
                    throw new InvalidOperationException("Jumlah operasi tidak valid.");
                string company = Master.Mn_CompanyID, location = Master.Mn_LocationID;
                string user = Convert.ToString(Master.Mn_EmployeeID);
                if (string.IsNullOrWhiteSpace(user)) throw new InvalidOperationException("Identitas pengguna tidak tersedia.");
                // Each call is atomic in its own SP. A batch of multiple calls is NOT atomic.
                using (var br = new INSPEC.BRC.M_LightingMapEditor())
                {
                    foreach (EditAction a in actions)
                    {
                        if (a == null || a.MapID <= 0 || a.MapPathID <= 0 ||
                            (a.ActionType != "HIDE" && a.ActionType != "SHOW" &&
                             a.ActionType != "DELETE" && a.ActionType != "RESTORE"))
                            throw new InvalidOperationException("Operasi mapping tidak valid.");
                        br.SaveLightingMapEditor(company, location, a.MapID, a.MapPathID,
                            a.ActionType, user, "Lighting Map Editor UI");
                    }
                }
                Alert("Perubahan mapping berhasil disimpan.");
            }
            catch (Exception ex)
            {
                Alert("Penyimpanan gagal. Sebagian operasi mungkin sudah tersimpan; halaman akan dimuat ulang. Detail: " + ex.Message);
            }
            BindPage();
        }
    }
}

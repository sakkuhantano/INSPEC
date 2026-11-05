using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;
using WAL;

namespace INSPEC.MasterPages
{
    public partial class Site1 : System.Web.UI.MasterPage
    {
        protected void Page_Init(object sender, EventArgs e)
        {
            ucToolbar.ToolbarClick += UC_ToolbarClick;
        }

        private void UC_ToolbarClick(object sender, ToolBarEventArgs_2 e)
        {
            I_ToolBar_2 page = Page as I_ToolBar_2;
            if (page != null)
            {
                page.Toolbar_Click(sender, e);
            }
        }

        public void TB_VisibleToolbar(bool value)
        {
            GF.ShowPanel(ref pnl_TB, value);
        }

        public void TB_IsConfirmMessage(ToolbarItem_2 item, bool value)
        {
            ucToolbar.IsConfirmMessage(item, value);
        }

        public void TB_SetConfirmMessage(ToolbarItem_2 item, string value)
        {
            ucToolbar.SetConfirmMessage(item, value);
        }

        public void TB_SetConfirmMessage(ToolbarItem_2 item, bool isConfirmMessage, string value)
        {
            ucToolbar.SetConfirmMessage(item, isConfirmMessage, value);
        }

        public void TB_SetIcon(ToolbarItem_2 item, string value)
        {
            ucToolbar.SetIcon(item, value);
        }

        public void TB_SetText(ToolbarItem_2 item, string value)
        {
            ucToolbar.SetText(item, value);
        }

        public void TB_SetWidth(ToolbarItem_2 item, string value)
        {
            ucToolbar.SetWidth(item, value);
        }

        public void TB_EnableButton(ToolbarItem_2 item, bool value)
        {
            ucToolbar.EnableButton(item, value);
        }

        public bool TB_EnableButton(ToolbarItem_2 item)
        {
            return ucToolbar.EnableButton(item);
        }

        public void TB_VisibleButton(ToolbarItem_2 item, bool value)
        {
            ucToolbar.VisibleButton(item, value);
        }

        public bool TB_VisibleButton(ToolbarItem_2 item)
        {
            return ucToolbar.VisibleButton(item);
        }

        public void TB_VisibleButton(ToolbarItem_2 item, bool value, string p_Text = "", string p_Icon = "", string p_Width = "")
        {
            ucToolbar.VisibleButton(item, value, p_Text, p_Icon, p_Width);
        }


        // BS5 Master compatibility properties.
        // Profile values are loaded once from the same PIP login function used by BS5.
        private System.Data.DataRow _legacyUserRow;

        private System.Data.DataRow LegacyUserRow
        {
            get
            {
                if (_legacyUserRow == null)
                {
                    string employeeID = GFC.CurrentEmployeeID();
                    if (!String.IsNullOrEmpty(employeeID))
                    {
                        using (var br = new WAL.BR.CF())
                        {
                            System.Data.DataTable dt = br.EQuery(
                                @"SELECT TOP 1
                                      A.EmployeeID, A.UserID, A.UserName, A.UserGroupID,
                                      A.IsAllowExportReport, A.CompanyID, A.CompanyName,
                                      A.BussinessID, A.LocationID, A.LocationName,
                                      A.HomeCurrencyID, A.HomeDecimal, A.ForeignCurrencyID,
                                      A.ForeignDecimal, A.BuildingType, A.CompanyID_Asli,
                                      A.LocationID_Asli, A.ParentEmployeeID, A.ParentePDR,
                                      A.ProfitCenterNo, A.ProfitCenterName, A.CCEmailPC,
                                      A.JobTitleID, A.JobTitleName, A.EmailAddress, A.CCEmail
                                  FROM dbo.F_SelectOneLogin('PIP', @EmployeeID, '') A",
                                "@EmployeeID=" + employeeID);
                            if (dt.Rows.Count > 0)
                                _legacyUserRow = dt.Rows[0];
                        }
                    }
                }
                return _legacyUserRow;
            }
        }

        private string LegacyValue(string column)
        {
            System.Data.DataRow row = LegacyUserRow;
            return row == null || row[column] == System.DBNull.Value
                ? String.Empty : Convert.ToString(row[column]).Trim();
        }

        private int LegacyIntValue(string column)
        {
            int value;
            return Int32.TryParse(LegacyValue(column), out value) ? value : 0;
        }

        private bool LegacyBoolValue(string column)
        {
            bool value;
            return Boolean.TryParse(LegacyValue(column), out value) && value;
        }

        public string Mn_hf_MP_Position
        {
            get { return Request.Form[hfMnMPPosition.UniqueID] ?? hfMnMPPosition.Value; }
            set { hfMnMPPosition.Value = value ?? String.Empty; }
        }
        public bool Mn_IsByPassLogonUser
        {
            get
            {
                string value = Request.Form[hfMnIsByPassLogonUser.UniqueID] ?? hfMnIsByPassLogonUser.Value;
                return String.Equals(value, "true", StringComparison.OrdinalIgnoreCase) || value == "1";
            }
            set { hfMnIsByPassLogonUser.Value = value ? "true" : "false"; }
        }
        public string Mn_lit_Title
        {
            get { return lit_Title.Text.Trim(); }
            set { lit_Title.Text = value ?? String.Empty; }
        }
        public string Mn_EmployeeID
        {
            get
            {
                string value = Request.Form[hfMnEmployeeID.UniqueID] ?? hfMnEmployeeID.Value;
                return String.IsNullOrWhiteSpace(value) ? GFC.CurrentEmployeeID() : value.Trim();
            }
        }
        public string Mn_UserID { get { return LegacyValue("UserID"); } }
        public string Mn_UserName { get { return LegacyValue("UserName"); } }
        public string Mn_UserGroupID { get { return LegacyValue("UserGroupID"); } }
        public string Mn_CompanyID
        {
            get { return Request.Form[hfMnCompanyID.UniqueID] ?? hfMnCompanyID.Value; }
            set { hfMnCompanyID.Value = value ?? String.Empty; }
        }
        public string Mn_CompanyName
        {
            get { return Request.Form[hfMnCompanyName.UniqueID] ?? hfMnCompanyName.Value; }
            set { hfMnCompanyName.Value = value ?? String.Empty; }
        }
        public string Mn_BussinessID { get { return LegacyValue("BussinessID"); } }
        public string Mn_LocationID
        {
            get { return Request.Form[hfMnLocationID.UniqueID] ?? hfMnLocationID.Value; }
            set { hfMnLocationID.Value = value ?? String.Empty; }
        }
        public string Mn_LocationName { get { return LegacyValue("LocationName"); } }
        public string Mn_HomeCurrencyID { get { return LegacyValue("HomeCurrencyID"); } }
        public string Mn_HomeDecimal { get { return LegacyValue("HomeDecimal"); } }
        public string Mn_ForeignCurrencyID { get { return LegacyValue("ForeignCurrencyID"); } }
        public string Mn_ForeignDecimal { get { return LegacyValue("ForeignDecimal"); } }
        public string Mn_BuildingType { get { return LegacyValue("BuildingType"); } }
        public string Mn_ActivePeriod { get; set; }
        public string Mn_CompanyID_Asli { get { return LegacyValue("CompanyID_Asli"); } }
        public string Mn_LocationID_Asli { get { return LegacyValue("LocationID_Asli"); } }
        public bool Mn_IsAllowExportReport { get { return LegacyBoolValue("IsAllowExportReport"); } }
        public string Mn_ParentEmployeeID { get { return LegacyValue("ParentEmployeeID"); } }
        public string Mn_ParentePDR { get { return LegacyValue("ParentePDR"); } }
        public string Mn_ProfitCenterNo { get { return LegacyValue("ProfitCenterNo"); } }
        public string Mn_ProfitCenterName { get { return LegacyValue("ProfitCenterName"); } }
        public int Mn_CCEmailPC { get { return LegacyIntValue("CCEmailPC"); } }
        public string Mn_JobTitleID { get { return LegacyValue("JobTitleID"); } }
        public string Mn_JobTitleName { get { return LegacyValue("JobTitleName"); } }
        public string Mn_EmailAddress { get { return LegacyValue("EmailAddress"); } }
        public int Mn_CCEmail { get { return LegacyIntValue("CCEmail"); } }

        protected void Page_Load(object sender, EventArgs e)
        {

        }
    }
}
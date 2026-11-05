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


        // BS5 Master compatibility properties. INSPEC does not currently load
        // several legacy profile fields, so those properties return safe defaults.
        private System.Data.DataRow _legacyUserRow;

        private System.Data.DataRow LegacyUserRow
        {
            get
            {
                if (_legacyUserRow == null)
                {
                    string employeeID = GFC.CurrentEmployeeID();
                    using (var br = new WAL.BR.CF())
                    {
                        System.Data.DataTable dt = br.EQuery(
                            @"SELECT TOP 1 U.UserID, U.UserName, A.UserName AS DisplayName,
                                     A.JobTitleName, A.EmailAddress, A.ProfitCenterNo
                              FROM dbo.SysWebUser U
                              CROSS APPLY dbo.F_SelectOneLogin('pip', U.EmployeeID, '') A
                              WHERE U.EmployeeID=@EmployeeID AND U.IsActive=1",
                            "@EmployeeID=" + employeeID);
                        if (dt.Rows.Count > 0)
                            _legacyUserRow = dt.Rows[0];
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

        public string Mn_hf_MP_Position { get; set; }
        public bool Mn_IsByPassLogonUser { get; set; }
        public string Mn_lit_Title
        {
            get { return Page.Title; }
            set { Page.Title = value; }
        }
        public string Mn_EmployeeID { get { return GFC.CurrentEmployeeID(); } }
        public string Mn_UserID { get { return LegacyValue("UserID"); } }
        public string Mn_UserName { get { return LegacyValue("DisplayName"); } }
        public string Mn_UserGroupID { get { return String.Empty; } }
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
        public string Mn_BussinessID { get; set; }
        public string Mn_LocationID
        {
            get { return Request.Form[hfMnLocationID.UniqueID] ?? hfMnLocationID.Value; }
            set { hfMnLocationID.Value = value ?? String.Empty; }
        }
        public string Mn_LocationName { get; set; }
        public string Mn_HomeCurrencyID { get; set; }
        public string Mn_HomeDecimal { get; set; }
        public string Mn_ForeignCurrencyID { get; set; }
        public string Mn_ForeignDecimal { get; set; }
        public string Mn_BuildingType { get; set; }
        public string Mn_ActivePeriod { get; set; }
        public string Mn_CompanyID_Asli { get { return String.Empty; } }
        public string Mn_LocationID_Asli { get { return String.Empty; } }
        public bool Mn_IsAllowExportReport { get { return false; } }
        public string Mn_ParentEmployeeID { get { return String.Empty; } }
        public string Mn_ParentePDR { get { return String.Empty; } }
        public string Mn_ProfitCenterNo { get { return LegacyValue("ProfitCenterNo"); } }
        public string Mn_ProfitCenterName { get { return String.Empty; } }
        public int Mn_CCEmailPC { get { return 0; } }
        public string Mn_JobTitleID { get { return String.Empty; } }
        public string Mn_JobTitleName { get { return LegacyValue("JobTitleName"); } }
        public string Mn_EmailAddress { get { return LegacyValue("EmailAddress"); } }
        public int Mn_CCEmail { get { return 0; } }

        protected void Page_Load(object sender, EventArgs e)
        {

        }
    }
}
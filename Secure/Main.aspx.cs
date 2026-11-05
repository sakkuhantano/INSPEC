using System;
using System.Collections.Generic;
using System.Data;
using System.Linq;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;
using WAL;

namespace INSPEC.Secure
{
    public partial class Main : WAL.PB
    {
        private const string _MenuID = "0";
        protected void Page_Load(object sender, EventArgs e)
        {
            if (!IsPostBack)
            {
                // 0 : cache null   1 : otorisasi menu (true)   2 : otorisasi menu (false)
                if (base.AllowRead(_MenuID) == 2)
                {
                    throw new Exception(WAL.GF.MSG_ACCESS_DENIED);
                    return;
                }
                Master.Mn_lit_Title = WAL.PB.AppID + " -> " + ((DataSet)Session[GF.Key_CacheLoggedOnUser]).Tables["UserGroupMenu"].Select("MenuID='" + _MenuID + "'")[0]["Description"];
                
                //Master.Visible_pnlCompany(false);
                //Master.Visible_pnlMuliaGroup(true);

                //lblDestination.Text = "";
                
            }
        }

        
    }
}
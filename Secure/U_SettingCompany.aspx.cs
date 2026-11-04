using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;
using WAL;

using System.Collections;
using System.Diagnostics;
using System.Data;

namespace INSPEC.Secure
{
    public partial class U_SettingCompany : WAL.PB, WAL.I_ToolBar_2
    {
        private const string _MenuID = "113";

        #region Control Event
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
                using (WAL.BR.SysWebMenu sw = new WAL.BR.SysWebMenu())
                {
                    sw.AppID = PB.AppID;
                    sw.MenuID = _MenuID;
                    if (sw.SelectOneByMenuID().Rows.Count > 0)
                    {
                        Master.Mn_lit_Title = WAL.PB.AppID + " -> " + sw.Description;
                    }
                }

                InitToolbar();
                PrepareScreen();

                Master.TB_EnableButton(ToolbarItem_2.New, false);

                GF.Focus(this, txtCompanyID.ClientID);
            }
        }

        protected void lbtn_PreRender(object sender, EventArgs e)
        {
            GF.AddAttdisabled_2(sender);
        }

        public void Toolbar_Click(object sender, ToolBarEventArgs_2 e)
        {
            switch (e.ToolbarItem)
            {
                case ToolbarItem_2.New:
                    PrepareScreen();
                    break;
                case ToolbarItem_2.Save:
                    _Save();
                    break;
                case ToolbarItem_2.Refresh:
                    break;
            }
            GF.Focus(this, txtCompanyID.ClientID);
        }
        protected void txtCompanyID_TextChanged(object sender, EventArgs e)
        {
            _OpenCompany();
            GF.Focus(this, txtLocationID.ClientID);
        }
        protected void txtLocationID_TextChanged(object sender, EventArgs e)
        {
            _OpenLocation();
            GF.Focus(this, txtLocationID.ClientID);
        }
        #endregion

        #region Main Functions
        private void PrepareScreen()
        {
            lbtnCompanyID.Attributes.Add("onClick", GF.JSOpenSearchList_2("28", "Master Company", txtCompanyID.ClientID, false, Master.Mn_EmployeeID + GF.Str));
            txtCompanyID.Attributes.Add("onKeyDown", GF.JSOpenSearchList_2("28", "Master Company", txtCompanyID.ClientID, true, Master.Mn_EmployeeID + GF.Str));

            lbtnLocationID.Attributes.Add("onClick", GF.JSOpenSearchList_2("29", "Master Location", txtLocationID.ClientID, false, Master.Mn_EmployeeID + GF.Str + ";" + txtCompanyID.ClientID));
            txtLocationID.Attributes.Add("onKeyDown", GF.JSOpenSearchList_2("29", "Master Location", txtLocationID.ClientID, true, Master.Mn_EmployeeID + GF.Str + ";" + txtCompanyID.ClientID));

            txtCompanyID.Text = "";
            txtCompanyName.Text = "";
            txtLocationID.Text = "";
            txtLocationName.Text = "";
        }
        private void _OpenCompany(RecStatus recStatus = RecStatus.Current)
        {
            using (WAL.BR.CF br = new WAL.BR.CF())
            {
                DataTable V_dt = br.EQuery("SELECT DISTINCT top 1 " +
                                           "mc.CompanyID, c.CompanyName " +
                                           "FROM dbo.F_SysWebUserCompanyLocation(@AppID, @EmployeeID, '') mc " +
                                           "INNER JOIN SysWebCompany c on c.CompanyID = mc.CompanyID " +
                                           "WHERE mc.CompanyID = @CompanyID " +
                                           "AND c.IsActive = 1",
                                           "@AppID=" + PB.AppID +
                                           GF.Str2 +
                                           "@EmployeeID=" + Master.Mn_EmployeeID +
                                           GF.Str2 +
                                           "@CompanyID=" + txtCompanyID.Text.Trim() +
                                           "");

                if (V_dt.Rows.Count > 0)
                {
                    txtCompanyID.Text = Convert.ToString(V_dt.Rows[0]["CompanyID"]);
                    txtCompanyName.Text = Convert.ToString(V_dt.Rows[0]["CompanyName"]);

                    V_dt = br.EQuery("SELECT TOP 1 " +
                                     "mc.LocationID " +
                                     "FROM dbo.F_SysWebUserCompanyLocation(@AppID, @EmployeeID, '') mc " +
                                     "WHERE mc.CompanyID = @CompanyID " +
                                     "ORDER BY mc.LocationID ",
                                     "@AppID=" + PB.AppID +
                                     GF.Str2 +
                                     "@EmployeeID=" + Master.Mn_EmployeeID +
                                     GF.Str2 +
                                     "@CompanyID=" + txtCompanyID.Text.Trim() +
                                     "");

                    if (V_dt.Rows.Count > 0)
                    {
                        txtLocationID.Text = Convert.ToString(V_dt.Rows[0]["LocationID"]);
                    }

                    _OpenLocation();
                }
                else
                {
                    PrepareScreen();
                }
            }
        }
        private void _OpenLocation()
        {
            using (WAL.BR.CF br = new WAL.BR.CF())
            {
                DataTable V_dt = br.EQuery("SELECT TOP 1 " +
                                           "mc.LocationID, c.LocationName " +
                                           "FROM dbo.F_SysWebUserCompanyLocation(@AppID, @EmployeeID, '') mc " +
                                           "INNER JOIN SysWebLocation c on c.CompanyID = mc.CompanyID " +
                                           "                               AND c.LocationID = mc.LocationID " +
                                           "WHERE mc.CompanyID = @CompanyID " +
                                           "And mc.LocationID = @LocationID " +
                                           "And c.IsActive = 1 ",
                                           "@AppID=" + PB.AppID +
                                           GF.Str2 +
                                           "@EmployeeID=" + Master.Mn_EmployeeID +
                                           GF.Str2 +
                                           "@CompanyID=" + txtCompanyID.Text.Trim() +
                                           GF.Str2 +
                                           "@LocationID=" + txtLocationID.Text.Trim() +
                                           "");

                if (V_dt.Rows.Count > 0)
                {
                    txtLocationID.Text = Convert.ToString(V_dt.Rows[0]["LocationID"]);
                    txtLocationName.Text = Convert.ToString(V_dt.Rows[0]["LocationName"]);
                }
                else
                {
                    txtLocationID.Text = "";
                    txtLocationName.Text = "";
                }
            }
        }
        private bool _ValidateSave()
        {
            string _strmsg = string.Empty;

            if (txtCompanyID.Text.Trim() == string.Empty)
            {
                _strmsg = "Company ID cannot empty";
            }
            else if (txtLocationID.Text.Trim() == string.Empty)
            {
                _strmsg = "Location ID cannot empty";
            }

            if (_strmsg.Trim() != string.Empty)
            {
                GF.MsgBox_2(this, _strmsg);
            }

            return _strmsg.Trim() == string.Empty;
        }
        private bool _Save()
        {
            if (_ValidateSave() == false)
            {
                return false;
            }

            SaveComLocDllToCache(Master.Mn_EmployeeID,
                                 txtCompanyID.Text,
                                 txtLocationID.Text,
                                 PB.AppID);

            Master.Mn_RefreshVarMenu();

            //Master.Mn_CompanyID = base.CompanyID;
            //Master.Mn_CompanyName = base.CompanyName;
            //Master.Mn_LocationID = base.LocationID;
            //Master.Mn_LocationName = base.LocationName;
            //Master.Mn_HomeCurrencyID = base.HomeCurrencyID;
            //Master.Mn_HomeDecimal = Convert.ToString(base.HomeDecimal);
            //Master.Mn_ForeignCurrencyID = base.ForeignCurrencyID;
            //Master.Mn_ForeignDecimal = Convert.ToString(base.ForeignDecimal);
            //Master.Mn_BuildingType = base.BuildingType;

            DestinationPath();
            return true;
        }
        #endregion

        #region Private Functions
        public void SaveComLocDllToCache(string p_EmployeeID,
                                         string p_CompanyID,
                                         string p_LocationID,
                                         string p_AppID)
        {
            DataView odv;
            using (WAL.BR.CF ocf = new WAL.BR.CF())
            {
                odv = ocf.EQuery("SELECT " +
                                 "x.*, " +
                                 "ISNULL(swc.CompanyName, '') AS CompanyName, " +
                                 "ISNULL(swl.LocationName, '') AS LocationName " +
                                 "FROM dbo.F_SysWebUserCompanyLocation(@AppID, @EmployeeID, '') x " +
                                 "LEFT JOIN SysWebCompany swc ON swc.CompanyID = x.CompanyID " +
                                 "LEFT JOIN SysWebLocation swl ON swl.CompanyID = x.CompanyID AND swl.LocationID = x.LocationID " +
                                 "WHERE swl.CompanyID = @CompanyID " +
                                 "AND swl.LocationID = @LocationID " +
                                 "",
                                 "@AppID=" + p_AppID +
                                 GF.Str2 +
                                 "@EmployeeID=" + p_EmployeeID +
                                 GF.Str2 +
                                 "@CompanyID=" + p_CompanyID +
                                 GF.Str2 +
                                 "@LocationID=" + p_LocationID +
                                 "").DefaultView;
            }

            if (odv.Count > 0)
            {
                using (PB opb = new PB())
                {
                    opb.CompanyID = Convert.ToString(odv[0]["CompanyID"]);
                    opb.CompanyName = Convert.ToString(odv[0]["CompanyName"]);
                    opb.LocationID = Convert.ToString(odv[0]["LocationID"]);
                    opb.LocationName = Convert.ToString(odv[0]["LocationName"]);
                    opb.HomeCurrencyID = Convert.ToString(odv[0]["HomeCurrencyID"]);
                    opb.HomeDecimal = Convert.ToString(odv[0]["HomeDecimal"]);
                    opb.ForeignCurrencyID = Convert.ToString(odv[0]["ForeignCurrencyID"]);
                    opb.ForeignDecimal = Convert.ToString(odv[0]["ForeignDecimal"]);
                    opb.BuildingType = Convert.ToString(odv[0]["BuildingType"]);
                }
            }


            //base.CompanyID = txtCompanyID.Text.Trim();
            //base.CompanyName = lblCompanyName.Text.Trim();
            //base.LocationID = txtLocationID.Text.Trim();
            //base.LocationName = lblLocationName.Text.Trim();

            //using (WAL.BR.SysWebLocation obr = new WAL.BR.SysWebLocation())
            //{
            //    obr.CompanyID = txtCompanyID.Text.Trim();
            //    obr.LocationID = txtLocationID.Text.Trim();
            //    if (obr.SelectOne().Rows.Count > 0)
            //    {
            //        base.HomeCurrencyID = obr.HomeCurrencyID;
            //        base.HomeDecimal = obr.HomeDecimal + "";
            //        base.ForeignCurrencyID = obr.ForeignCurrencyID;
            //        base.ForeignDecimal = obr.ForeignDecimal + "";
            //        base.BuildingType = obr.BuildingType;
            //    }
            //}

            //Master.Mn_CompanyID = txtCompanyID.Text.Trim();
            //Master.Mn_CompanyName = lblCompanyName.Text.Trim();
            //Master.Mn_LocationID = txtLocationID.Text.Trim();
            //Master.Mn_LocationName = lblLocationName.Text.Trim();
        }

        private void InitToolbar()
        {
            Master.TB_VisibleToolbar(true);
            Master.TB_VisibleButton(WAL.ToolbarItem_2.New, true);
            Master.TB_VisibleButton(WAL.ToolbarItem_2.Save, true);
        }
        private void DestinationPath()
        {
            if (Request.QueryString[GF.QUERYSTRING_RETURNURL] != null)
            {
                Response.Redirect(Request.QueryString[GF.QUERYSTRING_RETURNURL]);
            }
        }
        #endregion
    }
}


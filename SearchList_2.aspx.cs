using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;
using System.Data;
using WAL;

namespace INSPEC
{
    public partial class SearchList_2 : PB, I_SearchList
    {

        #region Control Events
            protected void Page_Load(object sender, EventArgs e)
            {
                if (!IsPostBack)
                {
                    if (ReadQueryString())
                    {
                        PrepareScreen();
                    }

                    GF.Focus(this.Page, lbtnSearch.ClientID);
                }

                //switch (Convert.ToString(Request.QueryString["cd"].Trim()))
                //{
                //    case "139":
                //        Page.ClientScript.RegisterStartupScript(Page.GetType(), "__ScriptOnLoad",
                //        "<script > " +
                //        "if(screen.availWidth < 850) " +
                //        "{  " +
                //        "   document.getElementById(\"tbl_SeachList_2\").style.width = \"850px\"; " +
                //        //"   document.getElementById(\"grdListItem\").style.width = \"850px\"; " +
                //        "} " +    
                //        "</script > ");

                //        break;
                //}
            }
            protected void ucfsl_FilterSearchListClick(object sender, FilterSearchListEventArgs e)
            {
                switch (e.FilterSearchListItem)
                {
                    case FilterSearchListItem.Ok:
                        UpdateViewGridSearchList(grdListItem_DataSource(grdListItem.ClientID));

                        //GF.Focus(this.Page, ucfsl.txtFilterValueFirstClientID);
                        GF.Focus(this.Page, ucfsl.txt_Current_Value_ClientID_Text);
                        //ucfsl.ResultFilterSearch();
                        break;
                    case FilterSearchListItem.Clear:
                        Bind_grdListItem();
                        ucfsl.ClearFilterValue();

                        GF.Focus(this.Page, ucfsl.txt_First_Value_ClientID_Text);
                        break;
                    case FilterSearchListItem.Close:
                        lbtnSearch.Visible = true;
                        pnlSearch.Style.Add("display", "none");
                        Bind_grdListItem();

                        GF.Focus(this.Page, lbtnSearch.ClientID);
                        break;
                }
            }
            
            protected void txtMaxRecord_TextChanged(object sender, EventArgs e)
            {
                txtMaxRecord.Text = (GF.IsNumeric(txtMaxRecord.Text.Trim()) && Convert.ToInt32(txtMaxRecord.Text.Trim()) > 0 ? txtMaxRecord.Text : "50");
                UpdateViewGridSearchList(grdListItem_DataSource(grdListItem.ClientID));

                GF.Focus(this.Page, txtMaxRecord.ClientID);
            }
            protected void lbtnSearch_Click(object sender, EventArgs e)
            {
                pnlSearch.Style.Add("display", "");
                lbtnSearch.Visible = false;
                Bind_grdListItem();

                GF.Focus(this.Page, ucfsl.txt_First_Value_ClientID_Text);
            }
        #endregion

        #region Main Functions
        protected void grdListItem_ItemDataBound(object sender, DataGridItemEventArgs e)
        {
            switch (e.Item.ItemType)
            {
                case ListItemType.Header:
                    //kolom mulai dr 1
                    switch (Convert.ToString(Request.QueryString["cd"].Trim()))
                    {
                        case "13":
                            e.Item.Cells[6].Attributes.Add("style", "display:none;");
                            break;
                        case "16":
                            e.Item.Cells[3].Attributes.Add("style", "text-align:right;");
                            break;
                        case "33":
                            e.Item.Cells[6].Attributes.Add("style", "text-align:right;");
                            break;
                        case "154":
                            e.Item.Cells[4].Attributes.Add("style", "display:none;");
                            e.Item.Cells[5].Attributes.Add("style", "display:none;");
                            break;
                    }
                    break;
                case ListItemType.Item:
                case ListItemType.AlternatingItem:
                    DataRowView _drv = (DataRowView)e.Item.DataItem;
                    if (_drv == null)
                        return;

                    //kolom mulai dr 1
                    switch (Convert.ToString(Request.QueryString["cd"].Trim()))
                    {
                        case "10":
                            e.Item.Cells[2].Text = (Convert.ToDateTime(e.Item.Cells[2].Text)).ToString(GF.FormatDate);
                            e.Item.Cells[4].Text = Convert.ToDecimal(e.Item.Cells[4].Text).ToString(GF.FormatCurrency2);
                            break;
                        case "11":
                            e.Item.Cells[2].Text = (Convert.ToDateTime(e.Item.Cells[2].Text)).ToString(GF.FormatDate);
                            e.Item.Cells[4].Text = Convert.ToDecimal(e.Item.Cells[4].Text).ToString(GF.FormatCurrency2);
                            e.Item.Cells[6].Text = Convert.ToDecimal(e.Item.Cells[6].Text).ToString(GF.FormatCurrency2);
                            e.Item.Cells[10].Text = Convert.ToDecimal(e.Item.Cells[10].Text).ToString(GF.FormatCurrency2);
                            break;
                        case "13":
                            e.Item.Cells[3].Text = (Convert.ToDateTime(e.Item.Cells[3].Text)).ToString(GF.FormatDate);
                            e.Item.Cells[6].Attributes.Add("style", "display:none;");
                            break;
                        case "16":
                            e.Item.Cells[3].Attributes.Add("style", "text-align:right;");
                            e.Item.Cells[3].Text = Convert.ToDecimal(e.Item.Cells[3].Text).ToString(GF.FormatCurrency2);
                            break;
                        case "30":
                            e.Item.Cells[2].Text = (Convert.ToDateTime(e.Item.Cells[2].Text)).ToString(GF.FormatDate);
                            break;
                        case "33":
                            e.Item.Cells[6].Attributes.Add("style", "text-align:right;");
                            break;

                        case "57":
                            e.Item.Cells[12].Attributes.Add("style", "text-align:right;");
                            e.Item.Cells[13].Attributes.Add("style", "text-align:right;");
                            e.Item.Cells[14].Attributes.Add("style", "text-align:right;");
                            e.Item.Cells[12].Text = Convert.ToDecimal(e.Item.Cells[12].Text).ToString(GF.FormatCurrency2);
                            e.Item.Cells[13].Text = Convert.ToDecimal(e.Item.Cells[13].Text).ToString(GF.FormatCurrency2);
                            e.Item.Cells[14].Text = Convert.ToDecimal(e.Item.Cells[14].Text).ToString(GF.FormatCurrency2);

                            if (Convert.ToDateTime(e.Item.Cells[2].Text) == GF.MinDate())
                            {
                                e.Item.Cells[2].Text = "";
                            }
                            else
                            {
                                e.Item.Cells[2].Text = (Convert.ToDateTime(e.Item.Cells[2].Text)).ToString(GF.FormatDate);
                            }

                            if (Convert.ToDateTime(e.Item.Cells[7].Text) == GF.MinDate())
                            {
                                e.Item.Cells[7].Text = "";
                            }
                            else
                            {
                                e.Item.Cells[7].Text = (Convert.ToDateTime(e.Item.Cells[7].Text)).ToString(GF.FormatDate);
                            }
                        
                            if (Convert.ToDateTime(e.Item.Cells[10].Text) == GF.MinDate())
                            {
                                e.Item.Cells[10].Text = "";
                            }
                            else
                            {
                                e.Item.Cells[10].Text = (Convert.ToDateTime(e.Item.Cells[10].Text)).ToString(GF.FormatDate);
                            }
                            break;
                        case "58":
                            e.Item.Cells[2].Text = (Convert.ToDateTime(e.Item.Cells[2].Text)).ToString(GF.FormatDate);
                            break;
                        case "154":
                            e.Item.Cells[4].Attributes.Add("style", "display:none;");
                            e.Item.Cells[5].Attributes.Add("style", "display:none;");
                            break;
                        case "59":
                            e.Item.Cells[16].Attributes.Add("style", "text-align:right;");
                            e.Item.Cells[17].Attributes.Add("style", "text-align:right;");
                            e.Item.Cells[16].Text = Convert.ToDecimal(e.Item.Cells[16].Text).ToString(GF.FormatCurrency0);
                            e.Item.Cells[17].Text = Convert.ToDecimal(e.Item.Cells[17].Text).ToString(GF.FormatCurrency0);

                            if (Convert.ToDateTime(e.Item.Cells[2].Text) == GF.MinDate())
                            {
                                e.Item.Cells[2].Text = "";
                            }
                            else
                            {
                                e.Item.Cells[2].Text = (Convert.ToDateTime(e.Item.Cells[2].Text)).ToString(GF.FormatDate);
                            }

                            if (Convert.ToDateTime(e.Item.Cells[5].Text) == GF.MinDate())
                            {
                                e.Item.Cells[5].Text = "";
                            }
                            else
                            {
                                e.Item.Cells[5].Text = (Convert.ToDateTime(e.Item.Cells[5].Text)).ToString(GF.FormatDate);
                            }

                            if (Convert.ToDateTime(e.Item.Cells[8].Text) == GF.MinDate())
                            {
                                e.Item.Cells[8].Text = "";
                            }
                            else
                            {
                                e.Item.Cells[8].Text = (Convert.ToDateTime(e.Item.Cells[8].Text)).ToString(GF.FormatDate);
                            }

                            if (Convert.ToDateTime(e.Item.Cells[11].Text) == GF.MinDate())
                            {
                                e.Item.Cells[11].Text = "";
                            }
                            else
                            {
                                e.Item.Cells[11].Text = (Convert.ToDateTime(e.Item.Cells[11].Text)).ToString(GF.FormatDate);
                            }

                            if (Convert.ToDateTime(e.Item.Cells[14].Text) == GF.MinDate())
                            {
                                e.Item.Cells[14].Text = "";
                            }
                            else
                            {
                                e.Item.Cells[14].Text = (Convert.ToDateTime(e.Item.Cells[14].Text)).ToString(GF.FormatDate);
                            }

                            break;
                    }
                    break;
                case ListItemType.Footer:
                    for (int i = 0; i < e.Item.Cells.Count; i++)
                    {
                        if (i == 0)
                        {
                            e.Item.Cells[i].ColumnSpan = e.Item.Cells.Count;
                            e.Item.Cells[i].Text = "<span style=\"font-weight:normal;color:grey;\">No Record Found .....</span>";

                            //e.Item.Cells[i].ColumnSpan = e.Item.Cells.Count;
                            //e.Item.Cells[i].Text = "<div class=\"row mt-2 \" style=\"margin:auto;\" > " +
                            //                       "    <div class=\"col text-center \" style=\"font-weight:bold;color:grey;\" > " +
                            //                       "        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"23\" height=\"23\" fill=\"currentColor\" class=\"bi bi-search\" viewBox=\"0 0 16 16\"> " +
                            //                       "            <path d=\"M11.742 10.344a6.5 6.5 0 1 0-1.397 1.398h-.001c.03.04.062.078.098.115l3.85 3.85a1 1 0 0 0 1.415-1.414l-3.85-3.85a1.007 1.007 0 0 0-.115-.1zM12 6.5a5.5 5.5 0 1 1-11 0 5.5 5.5 0 0 1 11 0z\"/> " +
                            //                       "        </svg> " +
                            //                       "    </div> " +
                            //                       "</div> " +
                            //                       "<div class=\"row mt-1 mb-2 \" style=\"margin:auto;\" > " +
                            //                       "    <div class=\"col text-center \" style=\"font-weight:bold;color:grey;\" > " +
                            //                       "        <span class=\"mt-2\" >..... No Record .....</span> " +
                            //                       "    </div> " +
                            //                       "</div> ";

                            //e.Item.Cells[i].Text = "<div class=\"row mt-3 \" > " +
                            //                       "    <div class=\"col text-center \" > " + 
                            //                       "        <svg xmlns=\"http://www.w3.org/2000/svg\" width=\"42\" height=\"42\" fill=\"currentColor\" class=\"bi bi-clipboard-x\" viewBox=\"0 0 16 16\"> " +
                            //                       "            <path fill-rule=\"evenodd\" d=\"M6.146 7.146a.5.5 0 0 1 .708 0L8 8.293l1.146-1.147a.5.5 0 1 1 .708.708L8.707 9l1.147 1.146a.5.5 0 0 1-.708.708L8 9.707l-1.146 1.147a.5.5 0 0 1-.708-.708L7.293 9 6.146 7.854a.5.5 0 0 1 0-.708z\"/> " +
                            //                       "            <path d=\"M4 1.5H3a2 2 0 0 0-2 2V14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V3.5a2 2 0 0 0-2-2h-1v1h1a1 1 0 0 1 1 1V14a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V3.5a1 1 0 0 1 1-1h1v-1z\"/> " +
                            //                       "            <path d=\"M9.5 1a.5.5 0 0 1 .5.5v1a.5.5 0 0 1-.5.5h-3a.5.5 0 0 1-.5-.5v-1a.5.5 0 0 1 .5-.5h3zm-3-1A1.5 1.5 0 0 0 5 1.5v1A1.5 1.5 0 0 0 6.5 4h3A1.5 1.5 0 0 0 11 2.5v-1A1.5 1.5 0 0 0 9.5 0h-3z\"/> " +
                            //                       "        </svg> " +
                            //                       "    </div> " +
                            //                       "</div> " +
                            //                       "<div class=\"row mt-1 mb-3 \" > " +
                            //                       "    <div class=\"col text-center \" > " +
                            //                       "        <span class=\"mt-2\" style=\"font-weight:normal;color:grey;\">No Data</span> </div> " +
                            //                       "    </div> " +
                            //                       "</div> ";

                            //e.Item.Cells[i].Text = "<div class=\"row mt-2 \" > " +
                            //                       "    <div class=\"col text-center \" > " +
                            //                       "        <img src=\"../../WebFolder/Images/empty-box_512x512.png\" width=\"64\" height=\"64\" alt=\"\" /> " +
                            //                       "    </div> " +
                            //                       "</div> " +
                            //                       "<div class=\"row mt-1 mb-2 \" > " +
                            //                       "    <div class=\"col text-center \" > " +
                            //                       "        <span class=\"mt-2\" style=\"font-weight:Bold;color:grey;\"> No Data </span> </div> " +
                            //                       "    </div> " +
                            //                       "</div> ";
                            //

                            //e.Item.Cells[i].Text = "<div class=\"row\" > " +
                            //                       "    <div class=\"col text-center \" > " +
                            //                       "        <span class=\"mt-2\" style=\"font-weight:normal;color:grey;\"> ..... No Data .....</span> </div> " +
                            //                       "    </div> " +
                            //                       "</div> ";
                        }
                        else
                        {
                            e.Item.Cells[i].Visible = false;
                        }
                    }
                    break;
            }
        }
        private void ListFieldTextAndValue()
        {
            string[] _retval = new string[2];

            switch (Convert.ToString(Request.QueryString["cd"].Trim()))
            {
                case "-1":
                    _retval[0] = "Title; Description";
                    _retval[1] = "hp.Title; hp.[Description]";
                    break;
                case "0":
                    _retval[0] = "ID; Name";
                    _retval[1] = "x.ID; x.Name";
                    break;
                case "1":
                    _retval[0] = "Company ID; Company Name";
                    _retval[1] = "ttgi.CompanyID; c.CompanyName";
                    break;
                case "2":
                    _retval[0] = "Location ID; Location Name";
                    _retval[1] = "ttgi.LocationID; c.LocationName";
                    break;
                case "8":
                    _retval[0] = "Company ID; Company Name";
                    _retval[1] = "mc.CompanyID; c.CompanyName";
                    break;
                case "15":
                    _retval[0] = "ProfitCenter No; Description";
                    _retval[1] = "CT; Description";
                    break;
                case "20":
                    _retval[0] = "Account; Description";
                    _retval[1] = "Account; [Description]";
                    break;
                case "28":
                    _retval[0] = "Company ID; Company Name";
                    _retval[1] = "mc.CompanyID; c.CompanyName";
                    break;
                case "29":
                    _retval[0] = "Location ID; Location Name";
                    _retval[1] = "mc.LocationID; c.LocationName";
                    break;
                case "330":
                    _retval[0] = "EmployeeID; Name ";
                    _retval[1] = "x.EmployeeID; x.Name ";
                    break;
                case "49":
                    _retval[0] = "Company ID; Company Name";
                    _retval[1] = "ttgi.CompanyID; m.CompanyName";
                    break;
                case "50":
                    _retval[0] = "CurrencyID; Description";
                    _retval[1] = "CurrencyID; Description";
                    break;
                case "51":
                    _retval[0] = "Company ID; Company Name";
                    _retval[1] = "a.companyId; b.companyName";
                    break;
                case "52":
                    _retval[0] = "Type ID; Description";
                    _retval[1] = "Type; Description";
                    break;
                case "53":
                    _retval[0] = "Account; Description";
                    _retval[1] = "Account; [Description]";
                    break;
                case "54":
                    _retval[0] = "Vendor ID; Vendor Name";
                    _retval[1] = "VendorID; VendorName";
                    break;
                case "32":
                    _retval[0] = "SectionID; Description";
                    _retval[1] = "SectionID; [Description]";
                    break;
                case "154":
                    _retval[0] = "InspectionTypeCode;InspectionTypeName";
                    _retval[1] = "InspectionTypeCode;InspectionTypeName";
                    break;
                case "155":
                    _retval[0] = "MapCode;MapName;Version";
                    _retval[1] = "M.MapCode;M.MapName;M.MapVersion";
                    break;            }

            ucfsl.ListFieldText = _retval[0];
            ucfsl.ListFieldValue = _retval[1];
        }
        private string GetListColNotReturnValue()
        {
            string _retval = "";

            switch (Convert.ToString(Request.QueryString["cd"].Trim()))
            {
                case "0":
                    _retval = "[3],[4]";
                    break;
                case "30":
                    _retval = "[3]";
                    break;
            }


            return _retval;
        }
        public DataView grdListItem_DataSource(string UC_ClientID)
        {
            DataView _retval = new DataView();
            //switch (UC_ClientID)
            //{
            //    case "ucgsl":
                    string MaxRecord = txtMaxRecord.Text;
                    string Condition = ucfsl.ResultFilterSearchList();
                    switch (Convert.ToString(Request.QueryString["cd"].Trim()))
                    {
                        case "-1":
                            using (WAL.BR.CF ocom = new WAL.BR.CF())
                            {
                                _retval = ocom.ExecuteSQL("SELECT TOP " + MaxRecord + " (Case When hp.ID = 1 then hp.Title else '' end) As Title, Replace(hp.[Description],char(10),'<Br/>') as [Description] " + "FROM THD_Help hp " + "where 1 = 1 " + (Condition.Trim() != string.Empty ? " And " + Condition.Trim() : "") + " Order By hp.GroupTitle Desc, hp.ID ").DefaultView;
                            }
                            break;
                        case "0":
                            using (WAL.BR.CF ocm = new WAL.BR.CF())
                            {
                                _retval = ocm.ExecuteSQL("SELECT TOP " + MaxRecord + " x.ID, x.Name, " +
                                                         "'<a id=\"' + '1' + x.ID + '\" onclick=\"javascript:openWindow(''' + '" + PB.Url_WebFolder1 + "Images/" + "' + x.Img + ''',''' + '2' + x.ID + ''',752,450,''no'',''yes'');\" title=\"' + x.ID + '\"> ' + x.Img + '</a>' as Img,  " +
                                                         "'<a id=\"' + '3' + x.ID + '\" onclick=\"javascript:openWindow(''" + "SearchList.aspx?cd=0&cdn=Test&ctrlID=txt&srv=true&rvc=0&fvalue=" + "'',''' + '4' + x.ID + ''',752,450,''no'',''yes'');\" title=\"' + x.ID + '\"> ' + x.Img + '</a>' as Img  " +
                                                         "FROM  " +
                                                         "( " +
                                                         "     SELECT 'HCM001' AS ID, 'test1' AS NAME, 'HCM001.jpg' AS img " +
                                                         "     UNION ALL " +
                                                         "     SELECT 'HCM010' AS ID, 'test2' AS NAME, 'HCM010.jpg' AS img  " +
                                                         ") x " +
                                                         ((Condition == "") ? "" : "WHERE " + Condition)
                                                         ).DefaultView;
                            }
                            break;
                        case "28":
                            using (WAL.BR.SysWebUserCompanyLocation ocom = new WAL.BR.SysWebUserCompanyLocation())
                            {
                                ocom.UserID = Request.QueryString["0"].Trim();
                                _retval = ocom.SelectSLCompany(MaxRecord, Condition).DefaultView;
                            }
                            break;
                        case "29":
                            using (WAL.BR.SysWebUserCompanyLocation ocom = new WAL.BR.SysWebUserCompanyLocation())
                            {
                                ocom.UserID = Request.QueryString["0"].Trim();
                                ocom.CompanyID = Request.QueryString["1"].Trim();
                                _retval = ocom.SelectSLLocation(MaxRecord, Condition).DefaultView;
                            }
                            break;
                        case "330":
                            using (WAL.BR.CF ocom = new WAL.BR.CF())
                            {
                                _retval = ocom.EQuery("SELECT top " + MaxRecord + " " +
                                                      "x.EmployeeID, x.Name " +
                                                      "FROM M_HRD_Employee x " +
                                                      (Condition.Trim() != "" ? "WHERE " + Condition.Trim() : " ") +
                                                      "Order By x.EmployeeID " +
                                                      "").DefaultView;
                            }
                            break;
                        case "51":
                            using (WAL.BR.CF ocm = new WAL.BR.CF())
                            {
                                _retval = ocm.ExecuteSQL(" SELECT TOP " + MaxRecord +
                                                           " a.CompanyID, " +
                                                           " b.Name AS CompanyName, " +
                                                           " a.LocationID " +
                                                        "FROM SysWebAppCompanyLocation a " +
                                                        "INNER JOIN GL_M_Company b ON a.CompanyID = b.CompanyID " +
                                                        "WHERE a.appId = 'GL'  " +
                                                        ((Condition == "") ? "" : "AND " + Condition) +
                                                        "Order By a.CompanyID").DefaultView;
                            }
                            break;
                        case "52":
                            using (WAL.BR.CF ocm = new WAL.BR.CF())
                            {
                                _retval = ocm.ExecuteSQL(" SELECT TOP " + MaxRecord +
                                                            "* "+
                                                         "FROM type "+
                                                        ((Condition == "") ? "" : "WHERE " + Condition)).DefaultView;
                            }
                            break;
                        case "53":
                            using (WAL.BR.CF ocm = new WAL.BR.CF())
                            {
                                _retval = ocm.ExecuteSQL(" SELECT TOP " + MaxRecord +
                                                            " Account,[Description] " +
                                                         "FROM Account WHERE post_flag = 1 and monetaryF = 1 ORDER BY Account").DefaultView;
                            }
                            break;
                        case "54":
                            using (WAL.BR.CF ocm = new WAL.BR.CF())
                            {
                                if (Request.QueryString["2"] == string.Empty)
                                    Condition += ((Condition != string.Empty ? " and " : "") + "a.pkpno<>''");
                                else 
                                    Condition += ((Condition != string.Empty ? " and " : "") +
                                    "((exists (select * from syswebcommonvalue b where b.appid='tax' and b.commongroup='VendorForVatINManual' and b.[description]=a.vendorid and b.isdelete=0)" +
                                    " and not exists (select * from syswebcommonvalue b where b.appid='tax' and b.commongroup='CompanyForVatINManual' and b.isdelete=0 and b.[description]='" + Request.QueryString["0"] + Request.QueryString["1"] + "'))" +
                                    " or exists (select * from syswebcommonvalue b where b.appid='tax' and b.commongroup='CompanyForVatINManual' and b.isdelete=0 and b.[description]='" + Request.QueryString["0"] + Request.QueryString["1"] + "'))");
                                _retval = ocm.ExecuteSQL(" SELECT TOP " + MaxRecord +
                                                            " a.VendorID, a.VendorName " +
                                                         "FROM PIP_M_Vendor a WHERE a.isdelete=0 " +
                                                         ((Condition == "") ? "" : "AND " + Condition) +
                                                         " ORDER BY a.VendorID").DefaultView;
                            }
                            break;
                        case "32":
                            using (var ocom = new BRC.PIP_M_Section())
                            {
                                if (Request.QueryString["2"] != string.Empty)
                                    Condition = "profitcenterno='" + Request.QueryString["2"] + "'";
                                _retval = ocom.SelectSLSection(MaxRecord, Condition).DefaultView;
                            }
                            break;
                        case "154":
                            _retval = INSPEC.Secure.M_InspectionType.F_SelectSLInspectionType(
                                                            "",
                                                            MaxRecord,
                                                            Condition);
                            break;
                        case "155":
                            using (WAL.BR.CF br = new WAL.BR.CF())
                            {
                                _retval = br.EQueryP(@"
SELECT TOP " + MaxRecord + @" M.MapCode, M.MapName, M.MapVersion
FROM dbo.PIP_M_InspectionMap M
WHERE M.CompanyID=@CompanyID AND M.LocationID=@LocationID AND M.IsCurrentVersion=1
AND (EXISTS (SELECT 1 FROM dbo.syswebuserusergroup U
             WHERE U.usergroupid='administrator' AND U.userid=@EmployeeID)
 OR EXISTS (SELECT 1 FROM dbo.PIP_M_InspectionPoint P
            INNER JOIN dbo.PIP_M_InspectionType IT ON IT.InspectionTypeCode=P.InspectionTypeCode
            INNER JOIN dbo.PIP_M_Section S ON S.SectionID=IT.SectionID
            WHERE P.MapID=M.MapID AND S.ProfitCenterNo=@ProfitCenterNo))
ORDER BY M.MapCode",
                                    new System.Data.SqlClient.SqlParameter[] {
                                        new System.Data.SqlClient.SqlParameter("@CompanyID", Request.QueryString["0"] ?? ""),
                                        new System.Data.SqlClient.SqlParameter("@LocationID", Request.QueryString["1"] ?? ""),
                                        new System.Data.SqlClient.SqlParameter("@ProfitCenterNo", Request.QueryString["2"] ?? ""),
                                        new System.Data.SqlClient.SqlParameter("@EmployeeID", Request.QueryString["3"] ?? "")
                                    }).DefaultView;
                            }
                            break;

                    }
                //    break;
                //default:
                //    GF.MsgBox(this.Page, "Invalid UC_ClientID (" + UC_ClientID + ") grdListItem_DataSource");
                //    break;
            //}
            return _retval;
        }
        public string SearchListID(string UC_ClientID)
        {
            string _retval = "";
            //switch (UC_ClientID)
            //{
            //    case "ucgsl":
            _retval = Request.QueryString["cd"].Trim();
            //        break;
            //    default:
            //        GF.MsgBox(this.Page, "Invalid UC_ClientID (" + UC_ClientID + ") SearchListID");
            //        break;
            //}
            return _retval;
        }
        #endregion

        #region Private Functions
        private void PrepareScreen()
        {
            litSearchList.Text = PB.AppID + " SL -> " + Request.QueryString["cdn"];

            lblShowReturnValue.Text = (Request.QueryString["srv"] == string.Empty ? "true" : Request.QueryString["srv"]);
            lblReturnValueCol.Text = (Request.QueryString["rvc"] == string.Empty ? "0" : Request.QueryString["rvc"]);

            pnlSearch.Style.Add("display", "none");
            lbtnSearch.Visible = true;

            ListFieldTextAndValue();
            ucfsl.UpdateViewGridFilterSearchList();

            lblListColNotReturnValue.Text = GetListColNotReturnValue();
            UpdateViewGridSearchList(grdListItem_DataSource(grdListItem.ClientID));

        }
        private bool ReadQueryString()
        {
            bool b = Request.QueryString["cd"].Trim().Length > 0 & Request.QueryString["ctrlID"].Trim().Length > 0;
            return b;
        }
        private void BindDataGrid(string sortExpression)
        {
            DataView dv = (DataView)Session[GetSessionID()];
            if ((sortExpression.Length > 0))
            {
                dv.Sort = sortExpression;
                Session[GetSessionID()] = dv;
            }
            grdListItem.DataSource = dv;
            grdListItem.DataBind();
        }
        private string GetSessionID()
        {
            string _retval = GF.Key_CacheSLDictatedDV;
            I_SearchList isl = Page as I_SearchList;
            if (isl != null)
            {
                _retval = _retval + isl.SearchListID(UC_GetClientID());
            }
            isl = null;
            return _retval;
        }
        private string GetSortExpressionID()
        {
            string _retval = GF.Key_CacheSLSortExpression;
            I_SearchList isl = Page as I_SearchList;
            if (isl != null)
            {
                _retval = _retval + isl.SearchListID(UC_GetClientID());
            }
            isl = null;
            return _retval;
        }
        private string GetSortDirectionID()
        {
            string _retval = GF.Key_CacheSLSortDirection;
            I_SearchList isl = Page as I_SearchList;
            if (isl != null)
            {
                _retval = _retval + isl.SearchListID(UC_GetClientID());
            }
            isl = null;
            return _retval;
        }
        private string UC_GetClientID()
        {
            string[] cid = grdListItem.ClientID.Split('_');
            return cid[0];
        }
        #endregion

        #region DataGrid Command Center
            protected void grdListItem_ItemCreated(object sender, DataGridItemEventArgs e)
            {
                switch (e.Item.ItemType)
                {
                    case ListItemType.Header:
                        if (
                                !Convert.ToBoolean(lblShowReturnValue.Text)
                                && GF.IsNumeric(lblReturnValueCol.Text)
                                && (Convert.ToInt32(lblReturnValueCol.Text) + 1) >= 0
                                && (Convert.ToInt32(lblReturnValueCol.Text) + 1) <= (e.Item.Cells.Count - 1)
                           )
                        {
                            e.Item.Cells[(Convert.ToInt32(lblReturnValueCol.Text) + 1)].Attributes.Add("style", "display:none;");
                        }
                        break;
                    case ListItemType.Item:
                    case ListItemType.AlternatingItem:
                        DataRowView _drv = (DataRowView)e.Item.DataItem;
                        if (_drv == null)
                            return;

                        if (
                                !Convert.ToBoolean(lblShowReturnValue.Text)
                                && GF.IsNumeric(lblReturnValueCol.Text)
                                && (Convert.ToInt32(lblReturnValueCol.Text) + 1) >= 0
                                && (Convert.ToInt32(lblReturnValueCol.Text) + 1) <= (e.Item.Cells.Count - 1)
                           )
                        {
                            e.Item.Cells[(Convert.ToInt32(lblReturnValueCol.Text) + 1)].Attributes.Add("style", "display:none;");
                        }


                        string s1 = Convert.ToString(_drv.Row[0]).Trim();
                        if (
                                GF.IsNumeric(lblReturnValueCol.Text)
                                && Convert.ToInt32(lblReturnValueCol.Text) >= 0
                                && Convert.ToInt32(lblReturnValueCol.Text) <= (e.Item.Cells.Count - 1)
                           )
                        {
                            s1 = Convert.ToString(_drv.Row[Convert.ToInt32(lblReturnValueCol.Text)]).Trim();
                        }

                        //Dim a As String = "'"

                        s1 = s1.Replace("'", " ");
                        s1 = s1.Replace("\"", " ");


                        if (Request.QueryString["cd"].Trim() != "-1")
                        {
                            //e.Item.Attributes.Add("onmouseover", "javascript:this.style.backgroundColor='lightgray';this.focus;this.style.cursor='pointer';");
                            e.Item.Attributes.Add("onmouseover", "javascript:this.style.backgroundColor='#e5e6e7';this.focus;this.style.cursor='pointer';");

                            //e.Item.Attributes.Add("onmouseout", "javascript:this.style.removeAttribute('backgroundColor');") 'transparent
                            //this.removeAttribute('style'); 'for IE,Mozilla
                            //this.setAttribute('style',''); 'for Chrome, safari
                            //this.style.removeProperty ("background-color");
                            e.Item.Attributes.Add("onmouseout", "javascript:this.style.backgroundColor='transparent';");

                            LinkButton _lbtnok = (LinkButton)e.Item.FindControl("_lbtnok");
                            //_lbtnok.Attributes.Add("onfocus", "javascript:this.style.backgroundColor='#696969';")
                            //_lbtnok.Attributes.Add("onblur", "javascript:this.style.backgroundColor='transparent';")
                            _lbtnok.Attributes.Add("onfocus", "javascript:this.parentNode.parentNode.style.backgroundColor = 'lightgray';");
                            _lbtnok.Attributes.Add("onblur", "javascript:this.parentNode.parentNode.style.backgroundColor = 'transparent';");

                            //If e.Item.ItemType = ListItemType.Item Then
                            // e.Item.Attributes.Add("onmouseout", "javascript:this.style.backgroundColor='white'")
                            //ElseIf e.Item.ItemType = ListItemType.AlternatingItem Then
                            // e.Item.Attributes.Add("onmouseout", "javascript:this.style.backgroundColor='WhiteSmoke'")
                            //End If


                            if (string.IsNullOrEmpty(lblListColNotReturnValue.Text))
                            {
                                e.Item.Attributes.Add("onclick", "closeWindowPostBackReturnValue('" + s1 + "', '" + (Request.QueryString["ctrlID"]).Trim() + "')");
                            }
                            else
                            {
                                if (lblListColNotReturnValue.Text != "[*]")
                                {
                                    for (int i = 0; i <= e.Item.Cells.Count - 1; i++)
                                    {
                                        if (!lblListColNotReturnValue.Text.Contains("[" + i + "]"))
                                        {
                                            e.Item.Cells[i].Attributes.Add("onclick", "closeWindowPostBackReturnValue('" + s1 + "', '" + (Request.QueryString["ctrlID"]).Trim() + "')");
                                        }
                                    }
                                }
                            }
                        }
                        break;
                }
            }
            protected void grdListItem_SortCommand(object source, DataGridSortCommandEventArgs e)
            {
                if (grdListItem.Items.Count > 0)
                {
                    string sortExpression = Convert.ToString(ViewState[GetSortExpressionID()]);
                    string sortDirection = Convert.ToString(ViewState[GetSortDirectionID()]);
                    if ((sortExpression != e.SortExpression))
                    {
                        sortExpression = e.SortExpression;
                        sortDirection = "asc";
                    }
                    else
                    {
                        if ((sortDirection == "asc"))
                        {
                            sortDirection = "desc";
                        }
                        else
                        {
                            sortDirection = "asc";
                        }
                    }

                    ViewState[GetSortExpressionID()] = sortExpression;
                    ViewState[GetSortDirectionID()] = sortDirection;

                    BindDataGrid(sortExpression + " " + sortDirection);
                }
            }
            public void Bind_grdListItem()
            {
                if (grdListItem.Items.Count > 0)
                {
                    DataView dv = (DataView)Session[GetSessionID()];
                    if (dv == null)
                    {
                        I_SearchList isl = Page as I_SearchList;
                        if (isl != null)
                        {
                            UpdateViewGridSearchList(isl.grdListItem_DataSource(UC_GetClientID()));
                        }
                        isl = null;
                        //throw new Exception("Session is expired");
                    }
                    else
                    {
                        grdListItem.DataSource = dv;
                        grdListItem.DataBind();
                    }
                }
            }
            public void UpdateViewGridSearchList(DataView p_grdListItemDataSource)
            {
                grdListItem.DataSource = p_grdListItemDataSource;
                grdListItem.DataBind();
                //grdListItem.ShowFooter = (grid_S2_M_GA.Items.Count == 0) ? true : false;

                //// display record count
                lblSearchResults.Text = grdListItem.Items.Count.ToString().Trim();
                if (grdListItem.Items.Count > 0)
                {
                    grdListItem.ShowFooter = false;
                    Session[GetSessionID()] = (DataView)grdListItem.DataSource;
                }
                else
                {
                    grdListItem.ShowFooter = true;
                }
            }

        #endregion
    }
}
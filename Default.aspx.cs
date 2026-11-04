
using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;

using System.Collections;
using System.Data;
using System.Diagnostics;

using WAL;
using System.Web.UI.HtmlControls;

using System.Data.SqlClient;
using System.Net;

namespace Web
{
    public partial class _Default : WAL.PB
    {
        #region Control Event
        protected void Page_Load(object sender, System.EventArgs e)
        {
            if (!IsPostBack)
            {
                using (var ocf = new WAL.BR.CF())
                {
                    if (ocf.EQuery("SELECT * FROM SysWebCommonValue v WHERE v.AppID = 'ALL' AND v.ID = '" + Context.Request.Url.Host + "' AND v.CommonGroup = 'DomainNonWWW' ").Rows.Count > 0)
                    {
                        Response.Redirect(HttpContext.Current.Request.Url.AbsoluteUri.Replace("://", "://www."));
                    }
                }

                litTitle.Text = WAL.PB.AppID + " -> Login";

                _PrepareScreen();
                
                if (F_InfoID() != "")
                {
                    using (var osi = new WAL.BR.SysWebInfo())
                    {
                        osi.ID = F_InfoID();
                        if (osi.IsExpiredDateByID())
                        {
                            txt_Login_UserID.Text = osi.Description1;
                            F_lbtn_Login(txt_Login_UserID.Text, osi.Description2);
                        }
                        else
                        {
                            //throw new Exception("YOU ARE NOT AUTHORIZED TO VIEW CONTENTS OF THIS PAGE.");
                        }
                    }
                }
                else if (F_UserID() != "")
                {
                    txt_Login_UserID.Text = Request.QueryString["1"];
                    F_lbtn_Login(txt_Login_UserID.Text, Request.QueryString["2"]);
                }

                WAL.GF.Focus(this.Page, txt_Login_UserID.ClientID);
            }

            //if (!Page.ClientScript.IsClientScriptBlockRegistered("openfullscreen"))
            //{
            //    Page.ClientScript.RegisterClientScriptBlock(Page.GetType(),
            //                                                "openfullscreen",
            //                                                "<script language=JavaScript> function fullscreen() " +
            //                                                "{ " +
            //                                                "   var hwnd = window.open('Default.aspx', '_FullWindow', 'status=yes,toolbar=no,menubar=no,location=no,resizable=yes,scrollbars=yes'); " +
            //                                                "} " +
            //                                                "</script>");
            //}
        }

        protected void lbtn_Login_Click(object sender, EventArgs e)
        {
            string V_HPwd;
            using (var oCF = new WAL.BR.CF())
            {
                V_HPwd = oCF.GetHashStringSQL(txt_Login_Password.Text);
                oCF.Dispose();
            }

            F_lbtn_Login(txt_Login_UserID.Text, V_HPwd);

            GF.Focus(this, txt_Login_UserID.ClientID);
        }

        #endregion

        #region Main Functions
        private void _PrepareScreen()
        {
            //txt_Login_UserID.Attributes.Add("onkeypress", "javascript:PostBackCtrlID_Enter(event.keyCode,'" + lbtn_Login.ClientID + "');if(event.keyCode == 13){" + lbtn_Login.ClientID + ".style.display='none';document.getElementById('lbtn_LoginLoading').style.display = '';}");
            //txt_Login_Password.Attributes.Add("onkeypress", "javascript:PostBackCtrlID_Enter(event.keyCode,'" + lbtn_Login.ClientID + "');if(event.keyCode == 13){" + lbtn_Login.ClientID + ".style.display='none';document.getElementById('lbtn_LoginLoading').style.display = '';}");

            txt_Login_UserID.Text = "";
            txt_Login_UserID.Text = "";

            //body1.Attributes.Add("onkeypress", "javascript:PostBackCtrlID_Enter(event.keyCode,'lbtnLogon');");

            //string s = "";
            //s += "Browser Capabilities" + Environment.NewLine;
            //s += "Type = " + Request.Browser.Type + ", " + Environment.NewLine;
            //s += "Name = " + Request.Browser.Browser + ", " + Environment.NewLine;
            //s += "Version = " + Request.Browser.Version + ", " + Environment.NewLine;
            //s += "Major Version = " + Request.Browser.MajorVersion + ", " + Environment.NewLine;
            //s += "Minor Version = " + Request.Browser.MinorVersion + ", " + Environment.NewLine;
            //s += "Platform = " + Request.Browser.Platform + ", " + Environment.NewLine;
            //s += "Is Beta = " + Request.Browser.Beta + ", " + Environment.NewLine;
            //s += "Is Crawler = " + Request.Browser.Crawler + ", " + Environment.NewLine;
            //s += "Is AOL = " + Request.Browser.AOL + ", " + Environment.NewLine;
            //s += "Is Win16 = " + Request.Browser.Win16 + ", " + Environment.NewLine;
            //s += "Is Win32 = " + Request.Browser.Win32 + ", " + Environment.NewLine;
            //s += "Supports Frames = " + Request.Browser.Frames + ", " + Environment.NewLine;
            //s += "Supports Tables = " + Request.Browser.Tables + ", " + Environment.NewLine;
            //s += "Supports Cookies = " + Request.Browser.Cookies + ", " + Environment.NewLine;
            //s += "Supports VBScript = " + Request.Browser.VBScript + ", " + Environment.NewLine;
            //s += "Supports JavaScript = " + Request.Browser.EcmaScriptVersion.ToString() + ", " + Environment.NewLine;
            //s += "Supports Java Applets = " + Request.Browser.JavaApplets + ", " + Environment.NewLine;
            //s += "Supports ActiveX Controls = " + Request.Browser.ActiveXControls + ", " + Environment.NewLine;
            //s += "Supports JavaScript Version = " + Request.Browser["JavaScriptVersion"] + Environment.NewLine;
            //lblinfo.ToolTip = s;
            //lblinfo.Text = Request.Browser.Browser + " " + Request.Browser.Version;
        }
        #endregion

        #region Private Functions
        private void LoginPath()
        {
            if (Request.QueryString[WAL.GF.QUERYSTRING_RETURNURL] == null)
            {
                Response.Redirect("Secure/Main.aspx");
            }
            else
            {
                Response.Redirect("Secure/" + Request.QueryString[WAL.GF.QUERYSTRING_RETURNURL]);
            }
        }

        private void F_lbtn_Login(string p_LogonUserID, string p_HPwd)
        {
            using (WAL.BR.CF oCF = new WAL.BR.CF())
            {
                if (base.CreateCacheLoggedOnUser(2, true, p_LogonUserID, p_HPwd))
                {
                    //pb.CacheLoggedOnUser.Tables["User"].Rows[0]["UserGroupMenuResult"] = pb.CacheLoggedOnUser.Tables["User"].Rows[0]["UserGroupMenuResult"].ToString().Replace("<li ><a   > <span > <img src=\"../../WebFolder/images/13x13_Utility.png\" alt=\"\" border=\"0\" align=\"absmiddle\"/>&nbsp;Utility </span> </a><div> <ul><li > <a  href=\"U_SettingCompany.aspx\"> <span > <img src=\"../../WebFolder/images/12x14_NoImage.png\" alt=\"\" border=\"0\" align=\"absmiddle\"/>&nbsp;Setting Company </span > </a></li></ul> </div></li>", "");
                    LoginPath();
                }
                else
                {
                    lbl_Login_Invalid.Text = "Invalid User Name Or Password. Please try again.";
                }
            }
        }


        private string F_UserID()
        {
            string V_retval = "";

            try
            {
                V_retval = Request.QueryString["1"];
            }
            catch (Exception e)
            {
            }

            V_retval = (V_retval == null ? "" : V_retval);

            return V_retval;
        }
        private string F_InfoID()
        {
            string V_retval = "";

            try
            {
                V_retval = Request.QueryString["InfoID"];
            }
            catch (Exception e)
            {
            }

            V_retval = (V_retval == null ? "" : V_retval);

            return V_retval;
        }
        #endregion
    }
}
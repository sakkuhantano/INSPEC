using System;
using System.Data;
using System.Web.Services;
using System.Web.UI;
using WAL;

namespace INSPECFO.Secure
{
    public partial class profilesetting : System.Web.UI.Page
    {
        protected void Page_Load(object sender, EventArgs e) { }

        [WebMethod]
        public static object SaveSetting(string p_userid, string p_oldpassword, string p_newpassword, string p_theme)
        {
            using (var oUser = new WAL.BR.CF())
            {
                string oldHash = oUser.GetHashStringSQL(p_oldpassword);
                DataTable dt = oUser.EQuery(
                    "SELECT UserID, Password FROM SysWebUser WHERE UserID=@UserID AND IsActive=1",
                    "@UserID=" + p_userid);
                if (dt.Rows.Count == 0) return new { message = "User Not found" };
                if (p_newpassword != "" && Convert.ToString(dt.Rows[0]["Password"]).Trim() != oldHash.Trim())
                    return new { message = "Wrong password" };
                if (p_newpassword != "")
                    oUser.EQuery("UPDATE SysWebUser SET Password=@Password WHERE UserID=@UserID",
                        "@UserID=" + p_userid + GF.Str2 + "@Password=" + oUser.GetHashStringSQL(p_newpassword));
                oUser.EQuery("UPDATE UTL_User SET Theme=@Theme WHERE UserID=@UserID",
                    "@UserID=" + p_userid + GF.Str2 + "@Theme=" + p_theme);
                return new { message = "ok" };
            }
        }
    }
}
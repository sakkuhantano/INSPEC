using System;
using System.Data;
using System.Web.Services;
using System.Web.UI;
using WAL;

namespace INSPECFO.Secure
{
    public partial class profilesetting : System.Web.UI.Page
    {
        protected void Page_Load(object sender, EventArgs e)
        {
            INSPECFO.AppAuthorization.CurrentEmployeeID();
        }

        [WebMethod]
        public static object SaveSetting(string p_userid, string p_oldpassword, string p_newpassword, string p_theme)
        {
            string employeeID = INSPECFO.AppAuthorization.CurrentEmployeeID();
            using (var oUser = new WAL.BR.CF())
            {
                DataTable dt = oUser.EQuery(
                    "SELECT UserID, Password FROM SysWebUser WHERE employeeid=@EmployeeID AND IsActive=1",
                    "@EmployeeID=" + employeeID);
                if (dt.Rows.Count != 1) throw new HttpException(401, "The authenticated INSPEC user could not be resolved.");

                string userID = Convert.ToString(dt.Rows[0]["UserID"]).Trim();
                string oldHash = oUser.GetHashStringSQL(p_oldpassword ?? "");
                if (!String.IsNullOrEmpty(p_newpassword) &&
                    Convert.ToString(dt.Rows[0]["Password"]).Trim() != oldHash.Trim())
                    return new { message = "Wrong password" };

                if (!String.IsNullOrEmpty(p_newpassword))
                    oUser.EQuery("UPDATE SysWebUser SET Password=@Password WHERE UserID=@UserID",
                        "@UserID=" + userID + GF.Str2 + "@Password=" + oUser.GetHashStringSQL(p_newpassword));

                oUser.EQuery("UPDATE UTL_User SET Theme=@Theme WHERE UserID=@UserID",
                    "@UserID=" + userID + GF.Str2 + "@Theme=" + (p_theme ?? ""));
                return new { message = "ok" };
            }
        }
    }
}
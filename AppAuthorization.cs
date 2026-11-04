using System;
using System.Data;
using System.Web;
using WAL;

namespace INSPECFO
{
    public static class AppAuthorization
    {
        public const string CookieName = "INSPEC_AUTH";
        public static void SetCookie(string token)
        {
            HttpContext c = HttpContext.Current;
            if (c == null || c.Response == null) return;
            HttpCookie k = new HttpCookie(CookieName, token ?? "");
            k.HttpOnly = true; k.Secure = c.Request.IsSecureConnection;
            k.Path = String.IsNullOrEmpty(c.Request.ApplicationPath) ? "/" : c.Request.ApplicationPath.TrimEnd('/') + "/";
            k.Expires = DateTime.Now.AddDays(2); c.Response.Cookies.Add(k);
        }
        public static void ClearCookie()
        {
            HttpContext c = HttpContext.Current;
            if (c == null || c.Response == null) return;
            HttpCookie k = new HttpCookie(CookieName, "");
            k.HttpOnly = true; k.Secure = c.Request.IsSecureConnection;
            k.Path = String.IsNullOrEmpty(c.Request.ApplicationPath) ? "/" : c.Request.ApplicationPath.TrimEnd('/') + "/";
            k.Expires = DateTime.Now.AddDays(-1); c.Response.Cookies.Add(k);
        }
        public static string CurrentEmployeeID()
        {
            HttpContext c = HttpContext.Current;
            HttpCookie k = c == null ? null : c.Request.Cookies[CookieName];
            string token = k == null ? "" : Convert.ToString(k.Value).Trim();
            Guid parsedToken;
            if (String.IsNullOrEmpty(token) || !Guid.TryParse(token, out parsedToken))
                throw new HttpException(401, "Authentication is required.");
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQuery(@"SELECT TOP 1 U.employeeid FROM dbo.UserSession S
                    INNER JOIN dbo.SysWebUser U ON U.UserID=S.UserID
                    WHERE S.Token=@Token AND S.IsActive=1 AND S.ExpireTime>GETDATE() AND U.IsActive=1",
                    "@Token=" + token);
                if (dt.Rows.Count != 1) throw new HttpException(401, "Login session is invalid or expired.");
                return Convert.ToString(dt.Rows[0]["employeeid"]).Trim();
            }
        }
        public static bool HasMenu(string employeeID, string menuID)
        {
            if (String.IsNullOrWhiteSpace(employeeID) || String.IsNullOrWhiteSpace(menuID)) return false;
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQuery(@"SELECT TOP 1 1 FROM dbo.F_SelectALLMenuAuthorization('INSPECFO', @EmployeeID, '') M WHERE M.MenuID=@MenuID",
                    "@EmployeeID=" + employeeID + GF.Str2 + "@MenuID=" + menuID);
                return dt.Rows.Count > 0;
            }
        }
        public static void RequireCompanyLocation(string employeeID, string companyID, string locationID)
        {
            if (String.IsNullOrWhiteSpace(employeeID) || String.IsNullOrWhiteSpace(companyID) || String.IsNullOrWhiteSpace(locationID))
                throw new HttpException(400, "Company and location are required.");
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQuery(@"SELECT TOP 1 1 FROM dbo.SysWebUser U
                    WHERE U.employeeid=@EmployeeID AND U.IsActive=1 AND (
                        EXISTS (SELECT 1 FROM dbo.SysWebUserCompanyLocation C WHERE C.UserID=@EmployeeID AND C.AppID='pip' AND C.CompanyID=@CompanyID AND C.LocationID=@LocationID)
                        OR EXISTS (SELECT 1 FROM dbo.F_SelectOneLogin('pip', @EmployeeID, '') L WHERE L.CompanyID=@CompanyID AND L.LocationID=@LocationID))",
                    "@EmployeeID=" + employeeID + GF.Str2 + "@CompanyID=" + companyID + GF.Str2 + "@LocationID=" + locationID);
                if (dt.Rows.Count == 0) throw new HttpException(403, "Company/location is not authorized for this account.");
            }
        }
        public static string GetEmployeeSection(string employeeID)
        {
            using (var br = new WAL.BR.CF())
            {
                DataTable dt = br.EQuery("SELECT TOP 1 ISNULL(Section,'') Section FROM dbo.UTL_User WHERE EmployeeID=@EmployeeID", "@EmployeeID=" + employeeID);
                return dt.Rows.Count == 0 ? "" : Convert.ToString(dt.Rows[0]["Section"]);
            }
        }
        public static string RequireMenuEmployee(string menuID)
        {
            string id = CurrentEmployeeID();
            if (!HasMenu(id, menuID)) throw new HttpException(403, "You are not authorized to access this function.");
            return id;
        }
        public static string RequireAnyMenuEmployee(params string[] menuIDs)
        {
            string id = CurrentEmployeeID();
            foreach (string menuID in menuIDs) if (HasMenu(id, menuID)) return id;
            throw new HttpException(403, "You are not authorized to access this function.");
        }
    }
}
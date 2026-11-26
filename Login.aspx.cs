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
using System.Web.Services;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

namespace INSPEC
{
    public partial class Login : WAL.PB
    {
        #region Control Event
        protected void Page_Load(object sender, System.EventArgs e)
        {
            if (String.Equals((Request.QueryString["task"] ?? String.Empty).Trim(), "scheduledChiefBatch", StringComparison.OrdinalIgnoreCase))
            {
                HandleScheduledChiefBatchRequest();
                return;
            }
            if (!IsPostBack)
            {
                using (var ocf = new WAL.BR.CF())
                {
                    if (ocf.EQuery("SELECT * FROM SysWebCommonValue v WHERE v.AppID = 'ALL' AND v.ID = '" + Context.Request.Url.Host + "' AND v.CommonGroup = 'DomainNonWWW' ").Rows.Count > 0)
                    {
                        Response.Redirect(HttpContext.Current.Request.Url.AbsoluteUri.Replace("://", "://www."));
                    }
                }

                //lit_Title.Text = WAL.PB.AppID + " -> Login";

                _PrepareScreen();

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

        private void HandleScheduledChiefBatchRequest()
        {
            HttpContext context = HttpContext.Current;
            HttpResponse response = context.Response;
            response.Clear();
            response.ContentType = "application/json";
            response.ContentEncoding = Encoding.UTF8;
            response.TrySkipIisCustomErrors = true;
            int statusCode = 200;
            object payload;
            try
            {
                ValidateScheduledChiefBatchRequest();
                payload = new { success = true, result = Secure.inspection.RunScheduledChiefBatch() };
            }
            catch (HttpException ex)
            {
                statusCode = ex.GetHttpCode();
                payload = new { success = false, message = ex.Message };
            }
            catch (Exception ex)
            {
                System.Diagnostics.Trace.TraceError("INSPEC scheduled Chief batch gateway: " + ex);
                statusCode = 500;
                payload = new { success = false, message = context.IsDebuggingEnabled ? ex.GetBaseException().Message : "Scheduled Chief Batch gagal. Periksa log aplikasi." };
            }
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = Int32.MaxValue;
            response.StatusCode = statusCode;
            response.Write(serializer.Serialize(payload));
            response.Flush();
            response.SuppressContent = true;
            context.ApplicationInstance.CompleteRequest();
        }

        private void ValidateScheduledChiefBatchRequest()
        {
            HttpRequest request = HttpContext.Current.Request;
            if (!String.Equals(request.HttpMethod, "POST", StringComparison.OrdinalIgnoreCase))
                throw new HttpException(405, "Scheduler endpoint hanya menerima HTTP POST.");
            if (!request.IsSecureConnection)
                throw new HttpException(403, "Scheduler endpoint wajib dipanggil melalui HTTPS.");
            if (request.QueryString.Count != 1 || !String.Equals(request.QueryString["task"], "scheduledChiefBatch", StringComparison.Ordinal))
                throw new HttpException(400, "Scheduler request tidak valid.");

            string allowedIps = ConfigurationManager.AppSettings["INSPECSchedulerAllowedIPs"] ?? String.Empty;
            if (!String.IsNullOrWhiteSpace(allowedIps))
            {
                string remoteIp = (request.UserHostAddress ?? String.Empty).Trim();
                bool allowed = allowedIps.Split(new char[] { ',', ';' }, StringSplitOptions.RemoveEmptyEntries)
                    .Select(value => value.Trim()).Any(value => String.Equals(value, remoteIp, StringComparison.OrdinalIgnoreCase));
                if (!allowed) throw new HttpException(403, "IP server scheduler tidak diizinkan.");
            }

            string secret = (ConfigurationManager.AppSettings["INSPECSchedulerHmacSecret"] ?? String.Empty).Trim();
            if (secret.Length < 32) throw new HttpException(503, "Secret scheduler belum dikonfigurasi pada aplikasi INSPEC.");
            string timestampText = (request.Headers["X-INSPEC-Timestamp"] ?? String.Empty).Trim();
            string nonce = (request.Headers["X-INSPEC-Nonce"] ?? String.Empty).Trim();
            string signature = (request.Headers["X-INSPEC-Signature"] ?? String.Empty).Trim();
            long timestamp;
            if (!Int64.TryParse(timestampText, NumberStyles.None, CultureInfo.InvariantCulture, out timestamp) ||
                nonce.Length != 32 || !nonce.All(Uri.IsHexDigit) || signature.Length != 64 || !signature.All(Uri.IsHexDigit))
                throw new HttpException(401, "Scheduler signature tidak valid.");

            DateTime epoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
            long now = (long)(DateTime.UtcNow - epoch).TotalSeconds;
            if (Math.Abs(now - timestamp) > 300) throw new HttpException(401, "Timestamp scheduler sudah kedaluwarsa.");
            string canonical = "POST\n" + request.Url.AbsolutePath + "?task=scheduledChiefBatch\n" + timestampText + "\n" + nonce.ToLowerInvariant();
            string expected;
            using (HMACSHA256 hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret)))
                expected = BitConverter.ToString(hmac.ComputeHash(Encoding.UTF8.GetBytes(canonical))).Replace("-", "").ToLowerInvariant();
            if (!FixedTimeEquals(expected, signature.ToLowerInvariant())) throw new HttpException(401, "Scheduler signature tidak valid.");

            using (var br = new WAL.BR.CF())
            {
                DataTable registered = br.EQueryP("spUTL_INSPEC_Scheduler_RegisterNonce",
                    new SqlParameter[] { new SqlParameter("@p_Nonce", nonce.ToLowerInvariant()) }, true, true);
                if (registered == null || registered.Rows.Count == 0 || !Convert.ToBoolean(registered.Rows[0]["Accepted"]))
                    throw new HttpException(401, "Scheduler request sudah pernah digunakan (replay ditolak).");
            }
        }

        private static bool FixedTimeEquals(string left, string right)
        {
            if (left == null || right == null || left.Length != right.Length) return false;
            int difference = 0;
            for (int i = 0; i < left.Length; i++) difference |= left[i] ^ right[i];
            return difference == 0;
        }

        #endregion

        #region Main Functions
        private void _PrepareScreen()
        {
            //txt_Login_UserID.Attributes.Add("onkeypress", "javascript:PostBackCtrlID_Enter(event.keyCode,'" + lbtn_Login.ClientID + "');if(event.keyCode == 13){" + lbtn_Login.ClientID + ".style.display='none';document.getElementById('lbtn_LoginLoading').style.display = '';}");
            //txt_Login_Password.Attributes.Add("onkeypress", "javascript:PostBackCtrlID_Enter(event.keyCode,'" + lbtn_Login.ClientID + "');if(event.keyCode == 13){" + lbtn_Login.ClientID + ".style.display='none';document.getElementById('lbtn_LoginLoading').style.display = '';}");


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

        [WebMethod]
        public static bool ValidateSession(
            string browserGuid,
            string serverGuid,
            string token)
        {
            using (var br = new WAL.BR.CF())
            {
                bool valid = br.EQuery(@"SELECT TOP 1 S.UserID
                    FROM UserSession S
                    INNER JOIN SysWebUser U ON U.EmployeeID = S.UserID
                    WHERE S.BrowserGuid = @BrowserGuid
                      AND S.ServerGuid = @ServerGuid
                      AND S.Token = @Token
                      AND S.IsActive = 1
                      AND S.ExpireTime > GETDATE()
                      AND U.IsActive = 1",
                    "@BrowserGuid=" + browserGuid + GF.Str2 +
                    "@ServerGuid=" + serverGuid + GF.Str2 +
                    "@Token=" + token).Rows.Count > 0;
                if (!valid)
                    return false;

                // The browser may still have a valid UserSession in localStorage
                // while the HttpOnly cookie was lost (for example after browser
                // cookie cleanup). Restore it only when absent. Never overwrite a
                // different cookie here: it may belong to a newer login in another tab.
                HttpContext context = HttpContext.Current;
                if (context != null)
                {
                    HttpCookie authCookie = context.Request.Cookies[GFC.CookieName];
                    string requestToken = authCookie == null
                        ? String.Empty : Convert.ToString(authCookie.Value).Trim();

                    if (String.IsNullOrEmpty(requestToken))
                    {
                        GFC.SetCookie(token);
                    }
                    else if (!String.Equals(requestToken, token, StringComparison.Ordinal))
                    {
                        // A different cookie is present; do not create a redirect
                        // loop by claiming this browser session is ready to enter.
                        return false;
                    }
                }

                return true;
            }

        }
        [WebMethod]
        public static bool ConfirmSessionCookie(string token)
        {
            HttpContext context = HttpContext.Current;
            if (context == null || String.IsNullOrWhiteSpace(token))
                return false;

            HttpCookie authCookie = context.Request.Cookies[GFC.CookieName];
            string requestToken = authCookie == null
                ? String.Empty : Convert.ToString(authCookie.Value).Trim();

            if (!String.Equals(requestToken, token, StringComparison.Ordinal))
                return false;

            using (var br = new WAL.BR.CF())
            {
                return br.EQuery(@"SELECT TOP 1 S.UserID
                    FROM UserSession S
                    INNER JOIN SysWebUser U ON U.EmployeeID = S.UserID
                    WHERE S.Token = @Token
                      AND S.IsActive = 1
                      AND S.ExpireTime > GETDATE()
                      AND U.IsActive = 1",
                    "@Token=" + token).Rows.Count > 0;
            }
        }

        [WebMethod]
        public static bool F_Logout(string browserGuid, string serverGuid, string token)
        {
            using (var br = new WAL.BR.CF())
            {
                br.EQuery(
                    @"UPDATE UserSession
                      SET IsActive = 0
                      WHERE BrowserGuid = @BrowserGuid
                        AND ServerGuid = @ServerGuid
                        AND Token = @Token
                        AND IsActive = 1",
                    "@BrowserGuid=" + browserGuid + GF.Str2 +
                    "@ServerGuid=" + serverGuid + GF.Str2 +
                    "@Token=" + token);
                GFC.ClearCookie();
                return true;
            }
        }

        [WebMethod]
        public static object F_Login(string p_userid, string p_password, string p_browserGuid, string p_deviceName)
        {
            string passwordHash;
            using (var oUser = new WAL.BR.CF())
            {
                passwordHash = oUser.GetHashStringSQL(p_password);
            }
            return F_LoginWithHash(p_userid, passwordHash, p_browserGuid, p_deviceName);
        }

        [WebMethod]
        public static object F_LoginByInfoID(string infoID, string p_browserGuid, string p_deviceName)
        {
            if (String.IsNullOrWhiteSpace(infoID) || infoID.Length > 100)
                return new { success = false, message = "Invalid portal login ticket." };

            try
            {
                using (var oUser = new WAL.BR.CF())
                {
                    // Consume the short-lived portal ticket atomically to prevent replay.
                    DataTable dtTicket = oUser.EQuery(
                        @"UPDATE SysWebInfo
                          SET ExpiredDate = GETDATE(), UpdateDate = GETDATE()
                          OUTPUT deleted.Description1 AS EmployeeID,
                                 deleted.Description2 AS PasswordHash
                          WHERE ID = @InfoID
                            AND Type = 'LinkApp'
                            AND AppID = 'WebApp'
                            AND ExpiredDate > GETDATE()",
                        "@InfoID=" + infoID);

                    if (dtTicket.Rows.Count != 1)
                        return new { success = false, message = "Portal login ticket is invalid, expired, or already used." };

                    string employeeID = Convert.ToString(dtTicket.Rows[0]["EmployeeID"]).Trim();
                    string passwordHash = Convert.ToString(dtTicket.Rows[0]["PasswordHash"]).Trim();
                    if (String.IsNullOrWhiteSpace(employeeID) || String.IsNullOrWhiteSpace(passwordHash))
                        return new { success = false, message = "Portal login ticket does not contain valid user credentials." };

                    DataTable dtUser = oUser.EQuery(
                        @"SELECT TOP 2 UserID
                          FROM SysWebUser
                          WHERE employeeid = @EmployeeID
                            AND [Password] = @Password
                            AND IsActive = 1",
                        "@EmployeeID=" + employeeID + GF.Str2 +
                        "@Password=" + passwordHash);

                    if (dtUser.Rows.Count != 1)
                        return new { success = false, message = "INSPEC account not found or inactive." };

                    string userID = Convert.ToString(dtUser.Rows[0]["UserID"]).Trim();
                    return F_LoginWithHash(employeeID, passwordHash, p_browserGuid, p_deviceName);
                }
            }
            catch (Exception ex)
            {
                return new { success = false, message = "Portal login could not be completed." };
            }
        }

        public static object F_LoginFromLegacySession(string employeeID, string passwordHash, string browserGuid, string deviceName)
        {
            if (String.IsNullOrWhiteSpace(employeeID) ||
                String.IsNullOrWhiteSpace(passwordHash) ||
                String.IsNullOrWhiteSpace(browserGuid))
                return new { success = false, message = "Legacy INSPEC session is invalid." };

            return F_LoginWithHash(employeeID, passwordHash, browserGuid, deviceName);
        }

        [WebMethod]
        private static object F_LoginWithHash(string p_employeeid, string V_Pwd, string p_browserGuid, string p_deviceName)
        {
            using (var oUser = new WAL.BR.CF())
            {
                DataTable dt = oUser.EQuery(
                    @"SELECT U.UserID, U.UserName, U.employeeid AS EmployeeID, U.Password,
                             ISNULL(L.SectionList, '') AS Section,
                             ISNULL(NULLIF(L.Theme, ''), 'L') AS Theme,
                             a.JobTitleName, a.EmailAddress, a.ProfitCenterNo,
                             ISNULL(us.LastSyncMaster, CAST('' AS SMALLDATETIME)) AS LastSyncMaster,
                             a.UserName AS UserName1,
                             ISNULL(us.LastSyncWO, CAST('' AS SMALLDATETIME)) AS LastSyncWO
                      FROM SysWebUser U
                      LEFT JOIN INSPEC_User L ON L.UserID = U.employeeid
                      OUTER APPLY
                      (
                          SELECT TOP 1 LastSyncMaster, LastSyncWO
                          FROM UserSession
                          WHERE UserID = U.EmployeeID AND BrowserGuid = @BrowserGuid
                          ORDER BY LoginTime DESC, ID DESC
                      ) us
                      CROSS APPLY dbo.F_SelectOneLogin('pip', U.employeeid, '') a
                      WHERE U.employeeid = @EmployeeID AND U.IsActive = 1",
                    "@EmployeeID=" + p_employeeid + GF.Str2 +
                     "@BrowserGuid=" + p_browserGuid);
                var _arrList = new ArrayList();
                if (dt.Rows.Count == 0) return new { success = false, message = "user not found..." };
                if (Convert.ToString(dt.Rows[0]["Password"]).Trim() != V_Pwd.Trim())
                    return new { success = false, message = "wrong password..." };
                string v_currcompany = "", v_currcompanyname = "";
                string v_serverguid = Guid.NewGuid().ToString(), v_token = Guid.NewGuid().ToString();
                string v_username = Convert.ToString(dt.Rows[0]["UserName1"]);
                string V_EmpID = Convert.ToString(dt.Rows[0]["EmployeeID"]).Trim();
                string v_section = GFC.GetEmployeeSection(V_EmpID);
                string v_jobtitle = Convert.ToString(dt.Rows[0]["JobTitleName"]);
                string v_email = Convert.ToString(dt.Rows[0]["EmailAddress"]);
                string v_profitcenter = Convert.ToString(dt.Rows[0]["ProfitCenterNo"]);
                string v_theme = String.IsNullOrWhiteSpace(Convert.ToString(dt.Rows[0]["Theme"])) ? "L" : Convert.ToString(dt.Rows[0]["Theme"]);
                string V_UserID = Convert.ToString(dt.Rows[0]["UserID"]).Trim();
                 bool v_isInspectionAdministrator = oUser.EQuery(
                     @"SELECT TOP 1 1
                       FROM dbo.SysWebUser SU
                       JOIN dbo.SysWebUserUserGroup UG ON UG.UserID=SU.UserID
                       WHERE SU.EmployeeID=@EmployeeID
                         AND SU.IsActive=1
                         AND UG.UserGroupID='administrator'",
                     "@EmployeeID=" + V_EmpID).Rows.Count > 0;

                // Load the authorized INSPEC front-end menu from SysWeb2.
                // EmployeeID is the NIK used by SysWebUserUserGroup and the authorization function.
                DataTable dtMenus = oUser.EQuery(
                    @"SELECT MenuID, ParentMenuID, Caption, URL, AppID, IsReport,
                             [COUNTER], Line, ImageUrl, [DESCRIPTION], isActive, HeaderDetail
                      FROM dbo.F_SelectALLMenuAuthorization(@AppID, @EmployeeID, '')
                      ORDER BY [COUNTER], MenuID",
                    "@AppID=inspecfo" + GF.Str2 +
                    "@EmployeeID=" + V_EmpID);

                // Match the same authorized child-menu set required by dashboard.aspx.
                // Parent menus or unrelated INSPEC menus alone must not create a session.
                string[] allowedMenuIDs = { "20011", "20012", "20021", "20022", "20031", "20041", "20042", "20043" };
                bool hasAllowedMenu = dtMenus.AsEnumerable().Any(row =>
                    allowedMenuIDs.Contains(Convert.ToString(row["MenuID"]).Trim()));

                if (!hasAllowedMenu)
                    return new { success = false, message = "You are not authorized to access INSPEC." };

                var menus = new List<Dictionary<string, object>>();
                foreach (DataRow menuRow in dtMenus.Rows)
                {
                    var menu = new Dictionary<string, object>();
                    menu["MenuID"] = menuRow["MenuID"];
                    menu["ParentMenuID"] = menuRow["ParentMenuID"];
                    menu["Caption"] = menuRow["Caption"];
                    menu["URL"] = menuRow["URL"];
                    menu["AppID"] = menuRow["AppID"];
                    menu["IsReport"] = menuRow["IsReport"];
                    menu["COUNTER"] = menuRow["COUNTER"];
                    menu["Line"] = menuRow["Line"];
                    menu["ImageUrl"] = menuRow["ImageUrl"];
                    menu["DESCRIPTION"] = menuRow["DESCRIPTION"];
                    menu["isActive"] = menuRow["isActive"];
                    menu["HeaderDetail"] = menuRow["HeaderDetail"];
                    menus.Add(menu);
                }
                foreach (DataRow row in oUser.EQuery(
                    "select companylocation, companyname from (" +
                    "select companylocation, companyname, sourcepriority, ROW_NUMBER() OVER (PARTITION BY companylocation ORDER BY sourcepriority) rn from (" +
                    "SELECT a.companyid+';'+a.locationid companylocation, a.alias companyname, 0 sourcepriority FROM dbo.F_SelectOneLogin('pip', @userid, '') a " +
                    "union all select a.companyid+';'+a.locationid, b.alias, 1 from syswebusercompanylocation a join syswebcompany b on a.companyid=b.companyid where a.userid=@userid and a.appid='pip' " +
                    ") sources ) ranked where rn=1 order by sourcepriority, companylocation",
                    "@userid=" + V_EmpID).Rows)
                {
                    Dictionary<string, object> dict = new Dictionary<string, object>();
                    dict["companylocation"] = row["companylocation"]; dict["companyname"] = row["companyname"];
                    if (_arrList.Count == 0) { v_currcompany = row["companylocation"] + ""; v_currcompanyname = row["companyname"] + ""; }
                    _arrList.Add(dict);
                }
                try
                {
                    oUser.EQuery(
@"SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @NewID INT;
DECLARE @SessionID INT;
-- Serialize session cleanup and ID allocation with concurrent logins.
SELECT @NewID = ISNULL(MAX(ID), 0) FROM UserSession WITH (TABLOCKX, HOLDLOCK);

-- Clean stale sessions on every successful login, regardless of the logging-in user.
-- Expired rows are removed even when IsActive is still 1 (e.g. abandoned incognito sessions).
DELETE FROM UserSession
WHERE ISNULL(IsActive, 0) = 0
   OR ExpireTime <= GETDATE();

-- Find this browser's reusable session only after stale rows have been removed.
SELECT TOP 1 @SessionID = ID
FROM UserSession
WHERE UserID = @EmployeeID AND BrowserGuid = @BrowserGuid
ORDER BY LoginTime DESC, ID DESC;

-- A login refreshes only this browser's session. Other devices remain active.
UPDATE UserSession
SET IsActive = 0
WHERE UserID = @EmployeeID AND BrowserGuid = @BrowserGuid AND IsActive = 1;

IF @SessionID IS NULL
BEGIN
    -- New browser/device: do not inherit another device's sync watermark.
    SELECT @NewID = ISNULL(MAX(ID), 0) + 1 FROM UserSession;

    INSERT UserSession (ID, UserID, BrowserGuid, ServerGuid, Token, LoginTime, ExpireTime, IsActive, DeviceName, LastSyncMaster, LastSyncWO)
    VALUES (@NewID, @EmployeeID, @BrowserGuid, @ServerGuid, @Token, GETDATE(), DATEADD(DAY,2,GETDATE()),1,@DeviceName,'','');
END
ELSE
BEGIN
    -- Reuse this device's row so its own sync watermarks survive re-login.
    UPDATE UserSession
    SET ServerGuid = @ServerGuid,
        Token = @Token,
        LoginTime = GETDATE(),
        ExpireTime = DATEADD(DAY,2,GETDATE()),
        IsActive = 1,
        DeviceName = @DeviceName
    WHERE ID = @SessionID;
END
COMMIT TRANSACTION;",
                    "@EmployeeID=" + V_EmpID + GF.Str2 + "@BrowserGuid=" + p_browserGuid + GF.Str2 +
                    "@ServerGuid=" + v_serverguid + GF.Str2 + "@Token=" + v_token + GF.Str2 + "@DeviceName=" + p_deviceName);
                    GFC.SetCookie(v_token);
                    return new
                    {
                        success = true,
                        message = "ok",
                        token = v_token,
                        serverguid = v_serverguid,
                        companylist = _arrList,
                        menus = menus,
                        userid = V_UserID,
                        username = v_username,
                        curcompany = v_currcompany,
                        curcompanyname = v_currcompanyname,
                        employeeid = V_EmpID,
                        isInspectionAdministrator = v_isInspectionAdministrator,
                        jobtitle = v_jobtitle,
                        email = v_email,
                        profitcenter = v_profitcenter,
                        theme = v_theme,
                        section = v_section,
                        lastsyncm = Convert.ToDateTime(dt.Rows[0]["LastSyncMaster"]).ToString(GF.FormatDate2),
                        lastsyncw = Convert.ToDateTime(dt.Rows[0]["LastSyncWO"]).ToString(GF.FormatDate2)
                    };
                }
                catch (Exception ex) { return new { success = false, message = ex.Message }; }
            }
        }
        #endregion
    }
}

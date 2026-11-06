using OfficeOpenXml;
using OfficeOpenXml.Style;
using System;
using System.Data;
using System.Drawing;
using System.Web;
using System.Web.UI;

namespace INSPEC.Secure
{
    public partial class R_Reports : Page
    {
        protected void Page_Load(object sender, EventArgs e)
        {
            GFC.RequireMenuEmployee("20022");
            string token = Convert.ToString(Request.QueryString["token"]);
            if (String.IsNullOrWhiteSpace(token) || token.Length != 32)
                throw new HttpException(400, "Report token tidak valid.");

            string key = "InspectionReport_" + token;
            long[] ids = Session[key] as long[];
            string companyId = Convert.ToString(Session["InspectionReportCompany_" + token]);
            string locationId = Convert.ToString(Session["InspectionReportLocation_" + token]);
            if (ids == null || ids.Length == 0 ||
                String.IsNullOrWhiteSpace(companyId) || String.IsNullOrWhiteSpace(locationId))
                throw new HttpException(403, "Sesi report sudah berakhir. Silakan Preview kembali.");

            Session.Remove(key);
            Session.Remove("InspectionReportCompany_" + token);
            Session.Remove("InspectionReportLocation_" + token);

            DataTable data = inspection.GetAuthorizedInspectionSelection(ids, companyId, locationId);
            if (data.Rows.Count != ids.Length)
                throw new HttpException(403, "Data report tidak lagi sesuai dengan pilihan transaksi.");

            using (ExcelPackage package = new ExcelPackage())
            {
                ExcelWorksheet sheet = package.Workbook.Worksheets.Add("Inspection Report");
                sheet.Cells["A1"].Value = "INSPECTION REPORT";
                sheet.Cells["A1"].Style.Font.Bold = true;
                sheet.Cells["A1"].Style.Font.Size = 14;
                DataTable export = data.DefaultView.ToTable(false,
                    "InspectionNo", "InspectionTypeCode", "InspectionTypeName",
                    "InspectionTypeDetailCode", "InspectionTypeDetailName",
                    "InspectionDate", "TemplateNo", "TemplateName",
                    "OwnerEmployeeID", "Status", "IsApprove");
                sheet.Cells["A3"].LoadFromDataTable(export, true);
                using (var header = sheet.Cells[3, 1, 3, export.Columns.Count])
                {
                    header.Style.Font.Bold = true;
                    header.Style.Fill.PatternType = ExcelFillStyle.Solid;
                    header.Style.Fill.BackgroundColor.SetColor(Color.LightSteelBlue);
                    header.Style.WrapText = true;
                }
                sheet.View.FreezePanes(4, 1);
                sheet.Cells[sheet.Dimension.Address].AutoFitColumns();
                byte[] file = package.GetAsByteArray();
                Response.Clear();
                Response.Buffer = true;
                Response.ContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
                Response.AddHeader("Content-Disposition", "attachment; filename=Inspection_Report.xlsx");
                Response.BinaryWrite(file);
                Response.Flush();
                Response.SuppressContent = true;
                HttpContext.Current.ApplicationInstance.CompleteRequest();
            }
        }
    }
}
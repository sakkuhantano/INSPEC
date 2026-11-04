using OfficeOpenXml;
using OfficeOpenXml.Style;
using System;
using System.Collections.Generic;
using System.Data;
using System.Drawing;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;
using WAL;

namespace INSPEC.Secure
{
    public partial class R_Report : WAL.PB, WAL.I_ToolBar_2
    {
        protected void Page_Load(object sender, EventArgs e)
        {

        }

        public void Toolbar_Click(object sender, ToolBarEventArgs_2 e)
        {
            switch (e.ToolbarItem)
            {
                case ToolbarItem_2.Refresh:
                    //PrepareScreen();
                    break;
                case ToolbarItem_2.Print:
                    //_printReport();
                    break;
            }
        }

        //// Pilihan bersumber dari checkbox Inspection Approval, bukan input manual.
        //// canAccessInspectionNo HARUS memeriksa izin pengguna per nomor di server.
        //public static byte[] Create(IEnumerable<string> inspectionNos, string connectionString,
        //    string companyId, string locationId, Func<string, bool> canAccessInspectionNo)
        //{
        //    if (inspectionNos == null) throw new ArgumentNullException("inspectionNos");
        //    if (String.IsNullOrWhiteSpace(companyId) || String.IsNullOrWhiteSpace(locationId))
        //        throw new ArgumentException("CompanyID/LocationID login tidak tersedia.");
        //    if (canAccessInspectionNo == null)
        //        throw new ArgumentNullException("canAccessInspectionNo", "Validasi akses setiap inspeksi wajib dilakukan.");

        //    List<string> selected = inspectionNos.Select(x => (x ?? String.Empty).Trim())
        //        .Where(x => x.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        //    if (selected.Count == 0) throw new ArgumentException("Pilih minimal satu InspectionNo.");
        //    if (selected.Count > 500) throw new ArgumentException("Maksimal 500 transaksi per export.");
        //    foreach (string no in selected)
        //    {
        //        if (no.Length > 100 || no.IndexOf(',') >= 0 ||
        //            no.IndexOf('\r') >= 0 || no.IndexOf('\n') >= 0)
        //            throw new ArgumentException("Format InspectionNo tidak valid: " + no);
        //        if (!canAccessInspectionNo(no))
        //            throw new UnauthorizedAccessException("Tidak berhak mengakses transaksi: " + no);
        //    }
        //    string inspectionNosCsv = String.Join(",", selected.ToArray());

        //    DataSet ds = new DataSet();
        //    using (SqlConnection conn = new SqlConnection(connectionString))
        //    using (SqlCommand cmd = new SqlCommand("dbo.usp_PIP_InspectionReportPreview", conn))
        //    using (SqlDataAdapter adapter = new SqlDataAdapter(cmd))
        //    {
        //        cmd.CommandType = CommandType.StoredProcedure;
        //        cmd.CommandTimeout = 120;
        //        cmd.Parameters.Add("@InspectionNos", SqlDbType.NVarChar, -1).Value = inspectionNosCsv;
        //        cmd.Parameters.Add("@CompanyID", SqlDbType.NVarChar, 100).Value = companyId;
        //        cmd.Parameters.Add("@LocationID", SqlDbType.NVarChar, 100).Value = locationId;
        //        adapter.Fill(ds);
        //    }

        //    if (ds.Tables.Count < 2 || ds.Tables[0].Rows.Count == 0)
        //        throw new InvalidOperationException("Data transaksi inspeksi tidak ditemukan.");

        //    DataTable headers = ds.Tables[0];
        //    DataTable results = ds.Tables[1];

        //    // Defense in depth: SQL SP sudah memvalidasi; C# juga wajib menolak
        //    // gabungan jenis inspeksi yang berbeda (tidak boleh partial export).
        //    List<DataRow> allHeaders = headers.AsEnumerable().ToList();
        //    if (allHeaders.Count != selected.Count ||
        //        allHeaders.Select(h => V(h, "InspectionNo"))
        //            .Distinct(StringComparer.OrdinalIgnoreCase).Count() != selected.Count)
        //        throw new InvalidOperationException(
        //            "Jumlah inspeksi dari database berbeda dari checkbox terpilih. Export dibatalkan.");
        //    var distinctTypes = allHeaders
        //        .Select(h => V(h, "InspectionTypeCode").Trim())
        //        .Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        //    if (distinctTypes.Count != 1 || String.IsNullOrWhiteSpace(distinctTypes[0]))
        //        throw new InvalidOperationException(
        //            "Inspection Type berbeda. Pilih transaksi dengan InspectionTypeCode yang sama.");

        //    if (allHeaders.Any(h => String.IsNullOrWhiteSpace(V(h, "InspectionTypeDetailCode")) ||
        //                            String.IsNullOrWhiteSpace(V(h, "InspectionTypeDetailName"))))
        //        throw new InvalidOperationException(
        //            "Inspection Type Detail Code dan Name harus tersedia pada setiap transaksi.");

        //    bool conflictingDetailName = allHeaders.GroupBy(h => String.Join("\u001f", new string[] {
        //            V(h, "CompanyID"), V(h, "LocationID"), V(h, "InspectionTypeCode"),
        //            V(h, "InspectionTypeDetailCode")
        //        }), StringComparer.OrdinalIgnoreCase)
        //        .Any(g => g.Select(h => V(h, "InspectionTypeDetailName").Trim())
        //            .Distinct(StringComparer.OrdinalIgnoreCase).Count() > 1);
        //    if (conflictingDetailName)
        //        throw new InvalidOperationException(
        //            "Inspection Type Detail Code sama tetapi Detail Name berbeda. Periksa data transaksi.");

        //    Dictionary<string, List<DataRow>> resultLookup = results.AsEnumerable()
        //        .GroupBy(r => V(r, "InspectionID"))
        //        .ToDictionary(g => g.Key, g => g.ToList());

        //    // Satu tipe inspeksi saja. DetailCode BERBEDA => sheet berbeda.
        //    // Item dan transaksi dengan DetailCode sama => satu sheet, selama
        //    // template/version/tanggal/layout dan scope lainnya juga sama.
        //    var groups = allHeaders.GroupBy(h => String.Join("\u001f", new string[] {
        //        V(h, "CompanyID"), V(h, "LocationID"), V(h, "InspectionTypeCode"),
        //        V(h, "InspectionTypeDetailCode"), V(h, "InspectionTypeDetailName"),
        //        V(h, "IDTemplate"), V(h, "IDVersion"), V(h, "TemplateName"), DateKey(h),
        //        V(h, "ReportLayout").Trim().ToUpperInvariant()
        //    }), StringComparer.OrdinalIgnoreCase).ToList();

        //    using (ExcelPackage book = new ExcelPackage())
        //    {
        //        HashSet<string> sheetNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        //        foreach (var group in groups)
        //        {
        //            List<DataRow> hrows = group.ToList();
        //            string layout = V(hrows[0], "ReportLayout").Trim().ToUpperInvariant();
        //            if (layout != "H" && layout != "V")
        //                throw new InvalidOperationException("ReportLayout harus H atau V.");

        //            List<ItemDef> items = CollectItems(hrows, resultLookup);
        //            if (items.Count == 0)
        //                throw new InvalidOperationException("Tidak ada item checklist untuk kelompok inspeksi ini.");
        //            // Judul A1 tetap TemplateName. Nama TAB memakai DetailName
        //            // (mis. Lift 1, Lift 2); kode ditambahkan jika nama tab bentrok.
        //            string title = V(hrows[0], "TemplateName");
        //            if (String.IsNullOrWhiteSpace(title))
        //                throw new InvalidOperationException("TemplateName pada PIP_T_Inspection wajib terisi untuk judul Excel.");
        //            string detailName = UnitName(hrows[0]);
        //            string proposedTab = SafeSheetName(detailName);
        //            if (sheetNames.Contains(proposedTab))
        //                proposedTab = detailName + " (" + V(hrows[0], "InspectionTypeDetailCode") + ")";
        //            ExcelWorksheet ws = book.Workbook.Worksheets.Add(UniqueSheetName(proposedTab, sheetNames));
        //            if (layout == "H") WriteHorizontal(ws, hrows, items, resultLookup);
        //            else WriteVertical(ws, hrows, items, resultLookup);
        //        }
        //        return book.GetAsByteArray();
        //    }
        //}

        //private static List<ItemDef> CollectItems(List<DataRow> headers,
        //    Dictionary<string, List<DataRow>> lookup)
        //{
        //    Dictionary<string, ItemDef> itemMap = new Dictionary<string, ItemDef>();
        //    foreach (DataRow h in headers)
        //    {
        //        List<DataRow> detail;
        //        if (!lookup.TryGetValue(V(h, "InspectionID"), out detail)) continue;
        //        foreach (DataRow r in detail)
        //        {
        //            string id = V(r, "IDItem");
        //            if (String.IsNullOrEmpty(id)) continue;
        //            if (!itemMap.ContainsKey(id)) itemMap.Add(id, new ItemDef
        //            {
        //                Id = id,
        //                Label = V(r, "ItemLabel"),
        //                Order = Order(r)
        //            });
        //            else if (!String.Equals(itemMap[id].Label.Trim(), V(r, "ItemLabel").Trim(),
        //                              StringComparison.OrdinalIgnoreCase))
        //                throw new InvalidOperationException("Label checklist tidak konsisten untuk IDItem " + id);

        //        }
        //    }
        //    return itemMap.Values.OrderBy(i => i.Order).ThenBy(i => i.Id).ToList();
        //}

        //private static Dictionary<string, DataRow> ValuesFor(DataRow header,
        //    Dictionary<string, List<DataRow>> lookup)
        //{
        //    Dictionary<string, DataRow> map = new Dictionary<string, DataRow>();
        //    List<DataRow> detail;
        //    if (!lookup.TryGetValue(V(header, "InspectionID"), out detail)) return map;
        //    foreach (DataRow r in detail)
        //    {
        //        string id = V(r, "IDItem");
        //        if (String.IsNullOrEmpty(id)) continue;
        //        if (map.ContainsKey(id))
        //            throw new InvalidOperationException("IDItem " + id +
        //                " memiliki lebih dari satu result dalam InspectionID " + V(header, "InspectionID") +
        //                ". Tentukan aturan agregasi sebelum ekspor.");
        //        map.Add(id, r);
        //    }
        //    return map;
        //}

        //private static void WriteHorizontal(ExcelWorksheet ws, List<DataRow> headers,
        //    List<ItemDef> items, Dictionary<string, List<DataRow>> lookup)
        //{
        //    if (items.Count + 6 > 16384)
        //        throw new InvalidOperationException("Jumlah kolom checklist melebihi batas Excel.");
        //    int notesCol = 4 + items.Count;
        //    int ownerCol = notesCol + 1;
        //    int approveCol = notesCol + 2;
        //    Head(ws, headers[0], approveCol, "HORIZONTAL");

        //    ws.Cells[6, 1].Value = "DATE";
        //    ws.Cells[6, 2].Value = "TIME";
        //    ws.Cells[6, 3].Value = "FLOOR / UNIT";
        //    for (int i = 0; i < items.Count; i++)
        //        Put(ws.Cells[6, i + 4], items[i].Label);
        //    ws.Cells[6, notesCol].Value = "KETERANGAN";
        //    ws.Cells[6, ownerCol].Value = "INSPECTED BY";
        //    ws.Cells[6, approveCol].Value = "APPROVED BY";

        //    ws.Column(1).Width = 13;
        //    ws.Column(2).Width = 9;
        //    ws.Column(3).Width = 17;
        //    for (int i = 0; i < items.Count; i++) ws.Column(4 + i).Width = 12;
        //    ws.Column(notesCol).Width = 30;
        //    ws.Column(ownerCol).Width = 18;
        //    ws.Column(approveCol).Width = 18;

        //    List<DataRow> ordered = headers.OrderBy(h => DateKey(h))
        //        .ThenBy(h => TimeOf(h)).ThenBy(h => V(h, "InspectionTypeDetailName"))
        //        .ThenBy(h => V(h, "InspectionNo")).ToList();
        //    int row = 7;
        //    foreach (DataRow h in ordered)
        //    {
        //        Put(ws.Cells[row, 1], DateOf(h));
        //        Put(ws.Cells[row, 2], TimeOf(h));
        //        Put(ws.Cells[row, 3], UnitName(h));
        //        Dictionary<string, DataRow> detail = ValuesFor(h, lookup);
        //        for (int i = 0; i < items.Count; i++)
        //        {
        //            DataRow r;
        //            if (detail.TryGetValue(items[i].Id, out r))
        //                Put(ws.Cells[row, i + 4], CheckValue(V(r, "Value")));
        //        }
        //        Put(ws.Cells[row, notesCol], Notes(h, lookup));
        //        Put(ws.Cells[row, ownerCol], V(h, "OwnerEmployeeID"));
        //        Put(ws.Cells[row, approveCol], V(h, "ApprovedBy"));
        //        row++;
        //    }
        //    BodyStyle(ws, row - 1, approveCol, false);
        //    Footer(ws, row + 2, approveCol);
        //}

        //private static void WriteVertical(ExcelWorksheet ws, List<DataRow> headers,
        //    List<ItemDef> items, Dictionary<string, List<DataRow>> lookup)
        //{
        //    List<DataRow> ordered = headers.OrderBy(h => V(h, "InspectionTypeDetailCode"))
        //        .ThenBy(h => TimeOf(h)).ThenBy(h => V(h, "InspectionNo")).ToList();
        //    int lastCol = Math.Max(2, ordered.Count + 1);
        //    if (lastCol > 16384)
        //        throw new InvalidOperationException("Jumlah transaksi melebihi batas kolom Excel.");
        //    Head(ws, headers[0], lastCol, "VERTICAL");
        //    ws.Cells[6, 1].Value = "INSPECTED ITEM";
        //    List<Dictionary<string, DataRow>> maps = ordered.Select(h => ValuesFor(h, lookup)).ToList();

        //    for (int j = 0; j < ordered.Count; j++)
        //    {
        //        DataRow h = ordered[j];
        //        string unit = UnitName(h);
        //        // Data per InspectionNo tidak boleh saling menimpa dalam layout V.
        //        // Tanggal+jam+nomor memudahkan identifikasi meski unit sama.
        //        unit += " (" + DateOf(h) + " " + TimeOf(h) + " / " + V(h, "InspectionNo") + ")";
        //        Put(ws.Cells[6, j + 2], unit);
        //        ws.Column(j + 2).Width = 23;
        //    }
        //    ws.Column(1).Width = 45;
        //    for (int i = 0; i < items.Count; i++)
        //    {
        //        int r = i + 7;
        //        Put(ws.Cells[r, 1], items[i].Label);
        //        for (int j = 0; j < ordered.Count; j++)
        //        {
        //            DataRow result;
        //            if (maps[j].TryGetValue(items[i].Id, out result))
        //                Put(ws.Cells[r, j + 2], CheckValue(V(result, "Value")));
        //        }
        //    }
        //    int endRow = 6 + Math.Max(1, items.Count);
        //    BodyStyle(ws, endRow, lastCol, true);
        //    int notesRow = endRow + 3;
        //    MergeText(ws, notesRow, lastCol, "KETERANGAN / FOLLOW UP");
        //    int nr = notesRow + 1;
        //    foreach (DataRow h in ordered)
        //    {
        //        string note = Notes(h, lookup);
        //        if (String.IsNullOrWhiteSpace(note)) continue;
        //        MergeText(ws, nr, lastCol, UnitName(h) + " / " + V(h, "InspectionNo") + ": " + note);
        //        ws.Row(nr).Height = 24;
        //        nr++;
        //    }
        //    Footer(ws, nr + 1, lastCol);
        //}

        //private static readonly Color HeaderColor = Color.FromArgb(232, 238, 242);
        //private static readonly Color AlternatingColor = Color.FromArgb(247, 249, 250);
        //private static readonly Color BorderColor = Color.FromArgb(164, 175, 184);

        //private static void Head(ExcelWorksheet ws, DataRow header, int lastCol, string orientation)
        //{
        //    // Judul utama harus persis TemplateName pada PIP_T_Inspection.
        //    string reportTitle = V(header, "TemplateName");
        //    if (String.IsNullOrWhiteSpace(reportTitle))
        //        throw new InvalidOperationException("TemplateName pada PIP_T_Inspection tidak boleh kosong.");

        //    MergeText(ws, 1, lastCol, reportTitle);
        //    ws.Row(1).Height = 34;
        //    ExcelRange titleRange = ws.Cells[1, 1, 1, lastCol];
        //    titleRange.Style.Font.Bold = true;
        //    titleRange.Style.Font.Size = 15;
        //    titleRange.Style.Fill.PatternType = ExcelFillStyle.Solid;
        //    titleRange.Style.Fill.BackgroundColor.SetColor(HeaderColor);
        //    titleRange.Style.HorizontalAlignment = ExcelHorizontalAlignment.Center;

        //    MergeText(ws, 2, lastCol, "DATE: " + DateOf(header) +
        //        "     |     REPORT LAYOUT: " + orientation);
        //    MergeText(ws, 3, lastCol, "COMPANY: " + V(header, "CompanyID") +
        //        "     LOCATION: " + V(header, "LocationID") +
        //        "     VERSION: " + V(header, "TemplateVersion"));
        //    MergeText(ws, 4, lastCol,
        //        "âœ“ = Bersih / Memuaskan     X = Tidak memuaskan     |     Nilai lain mengikuti data transaksi");
        //    ws.Row(4).Height = 22;
        //    ws.Row(5).Height = 10;
        //    ws.PrinterSettings.Orientation = eOrientation.Landscape;
        //    ws.PrinterSettings.PaperSize = ePaperSize.A3;
        //    ws.PrinterSettings.FitToPage = true;
        //    ws.PrinterSettings.FitToWidth = 1;
        //    ws.PrinterSettings.FitToHeight = 0;
        //}

        //private static void BodyStyle(ExcelWorksheet ws, int endRow, int lastCol, bool vertical)
        //{
        //    ExcelRange range = ws.Cells[6, 1, Math.Max(6, endRow), lastCol];
        //    range.Style.Border.Top.Style = ExcelBorderStyle.Thin;
        //    range.Style.Border.Left.Style = ExcelBorderStyle.Thin;
        //    range.Style.Border.Bottom.Style = ExcelBorderStyle.Thin;
        //    range.Style.Border.Right.Style = ExcelBorderStyle.Thin;
        //    range.Style.Border.Top.Color.SetColor(BorderColor);
        //    range.Style.Border.Left.Color.SetColor(BorderColor);
        //    range.Style.Border.Bottom.Color.SetColor(BorderColor);
        //    range.Style.Border.Right.Color.SetColor(BorderColor);
        //    range.Style.VerticalAlignment = ExcelVerticalAlignment.Center;
        //    range.Style.WrapText = true;

        //    ws.Row(6).Height = vertical ? 46 : 76;
        //    ExcelRange heading = ws.Cells[6, 1, 6, lastCol];
        //    heading.Style.Fill.PatternType = ExcelFillStyle.Solid;
        //    heading.Style.Fill.BackgroundColor.SetColor(HeaderColor);
        //    heading.Style.Font.Bold = true;
        //    heading.Style.Font.Size = 9;
        //    heading.Style.HorizontalAlignment = ExcelHorizontalAlignment.Center;

        //    for (int row = 7; row <= endRow; row++)
        //    {
        //        ws.Row(row).Height = 23;
        //        if (row % 2 == 0)
        //        {
        //            ExcelRange alternate = ws.Cells[row, 1, row, lastCol];
        //            alternate.Style.Fill.PatternType = ExcelFillStyle.Solid;
        //            alternate.Style.Fill.BackgroundColor.SetColor(AlternatingColor);
        //        }
        //        int firstChecklistCol = vertical ? 2 : 4;
        //        int lastChecklistCol = vertical ? lastCol : lastCol - 3;
        //        if (firstChecklistCol <= lastChecklistCol)
        //            ws.Cells[row, firstChecklistCol, row, lastChecklistCol]
        //                .Style.HorizontalAlignment = ExcelHorizontalAlignment.Center;
        //    }

        //    // Freeze 6 header rows. EPPlus 4: the first unfrozen row is 7.
        //    ws.View.FreezePanes(7, 1);
        //}

        //private static void Footer(ExcelWorksheet ws, int row, int lastCol)
        //{
        //    MergeText(ws, row, lastCol, "NOTE: Items marked X require corrective action.");
        //    MergeText(ws, row + 2, lastCol,
        //        "INSPECTED BY: ______________________      APPROVED BY: ______________________      DATE: ______________");

        //    // Area cetak mengikuti panjang checklist / banyak transaksi secara dinamis.
        //    ws.PrinterSettings.PrintArea = ws.Cells[1, 1, row + 2, lastCol];
        //}

        //private static void MergeText(ExcelWorksheet ws, int row, int lastCol, string value)
        //{
        //    if (lastCol > 1) ws.Cells[row, 1, row, lastCol].Merge = true;
        //    Put(ws.Cells[row, 1], value);
        //    ws.Cells[row, 1].Style.VerticalAlignment = ExcelVerticalAlignment.Center;
        //}

        //private static string Notes(DataRow h, Dictionary<string, List<DataRow>> lookup)
        //{
        //    List<string> remarks = new List<string>();
        //    if (!String.IsNullOrWhiteSpace(V(h, "Summary"))) remarks.Add(V(h, "Summary"));
        //    if (!String.IsNullOrWhiteSpace(V(h, "FollowUpRemark")))
        //        remarks.Add("Follow-up: " + V(h, "FollowUpRemark"));
        //    List<DataRow> details;
        //    if (lookup.TryGetValue(V(h, "InspectionID"), out details))
        //        foreach (DataRow r in details)
        //        {
        //            string note = String.Join(" / ", new string[] { V(r, "Remark1"), V(r, "Remark2") }
        //                .Where(x => !String.IsNullOrWhiteSpace(x)).ToArray());
        //            if (!String.IsNullOrWhiteSpace(note))
        //                remarks.Add(V(r, "ItemLabel") + ": " + note);
        //        }
        //    return String.Join(" | ", remarks.ToArray());
        //}

        //private static string CheckValue(string value)
        //{
        //    string clean = (value ?? String.Empty).Trim();
        //    if (String.Equals(clean, "V", StringComparison.OrdinalIgnoreCase)) return "âœ“";
        //    if (String.Equals(clean, "X", StringComparison.OrdinalIgnoreCase)) return "X";
        //    return value ?? String.Empty;
        //}

        //private static string UnitName(DataRow row)
        //{
        //    string name = V(row, "InspectionTypeDetailName");
        //    return String.IsNullOrWhiteSpace(name) ? V(row, "InspectionTypeDetailCode") : name;
        //}

        //private static void Put(ExcelRange cell, string value)
        //{
        //    if (value == null) value = String.Empty;
        //    // Tulis sebagai TEXT (jangan pernah menetapkan cell.Formula dari data transaksi).
        //    // Pertahankan pengamanan terhadap formula injection dari input pengguna.
        //    if (value.Length > 0 && "=+-@".IndexOf(value[0]) >= 0)
        //        value = "'" + value;
        //    if (value.Length > 32000) value = value.Substring(0, 32000);
        //    cell.Style.Numberformat.Format = "@";
        //    cell.Value = value;
        //}

        //private static string DateKey(DataRow r)
        //{
        //    object obj = r["InspectionDate"];
        //    if (obj is DateTime) return ((DateTime)obj).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        //    return V(r, "InspectionDate");
        //}

        //private static string DateOf(DataRow r)
        //{
        //    object obj = r["InspectionDate"];
        //    if (obj is DateTime) return ((DateTime)obj).ToString("dd/MM/yyyy", CultureInfo.InvariantCulture);
        //    return V(r, "InspectionDate");
        //}

        //private static string TimeOf(DataRow r)
        //{
        //    object obj = r["ScheduledTime"];
        //    if (obj == DBNull.Value || obj == null) return String.Empty;
        //    if (obj is TimeSpan) return ((TimeSpan)obj).ToString(@"hh\:mm", CultureInfo.InvariantCulture);
        //    if (obj is DateTime) return ((DateTime)obj).ToString("HH:mm", CultureInfo.InvariantCulture);
        //    TimeSpan ts;
        //    return TimeSpan.TryParse(V(r, "ScheduledTime"), out ts) ?
        //        ts.ToString(@"hh\:mm", CultureInfo.InvariantCulture) : V(r, "ScheduledTime");
        //}

        //private static string V(DataRow r, string name)
        //{
        //    object v = r[name];
        //    return v == null || v == DBNull.Value ? String.Empty : Convert.ToString(v, CultureInfo.InvariantCulture);
        //}

        //private static int Order(DataRow r)
        //{
        //    int n;
        //    return Int32.TryParse(V(r, "DisplayOrder"), out n) ? n : Int32.MaxValue;
        //}

        //private static string SafeSheetName(string source)
        //{
        //    string clean = Regex.Replace(source ?? String.Empty, @"[\\/\:\*\?\[\]]", " ").Trim().Trim('\'');
        //    return clean.Length <= 31 ? clean : clean.Substring(0, 31);
        //}

        //private static string UniqueSheetName(string source, HashSet<string> existing)
        //{
        //    string clean = Regex.Replace(source, @"[\\/\:\*\?\[\]]", " ").Trim().Trim('\'');
        //    if (clean.Length == 0) clean = "Inspection";
        //    string baseName = clean.Substring(0, Math.Min(31, clean.Length));
        //    string name = baseName;
        //    int n = 2;
        //    while (!existing.Add(name))
        //    {
        //        string suffix = " (" + n.ToString(CultureInfo.InvariantCulture) + ")";
        //        name = baseName.Substring(0, Math.Min(31 - suffix.Length, baseName.Length)) + suffix;
        //        n++;
        //    }
        //    return name;
        //}

        //private void _printReport()
        //{
        //    lblError.Text = String.Empty;
        //    try
        //    {
        //        // IMPORTANT: validate current user's access to CompanyID/LocationID
        //        // and requested InspectionNo server-side BEFORE calling exporter.
        //        // This sample assumes your existing authorization layer handles it.
        //        string cs = ConfigurationManager.ConnectionStrings["PIPConnection"].ConnectionString;
        //        byte[] data = InspectionExcelExporter.Create(txtInspectionNos.Text, cs);
        //        Response.Clear();
        //        Response.ContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
        //        Response.AddHeader("Content-Disposition", "attachment; filename=Inspection_Report.xlsx");
        //        Response.BinaryWrite(data);
        //        Response.Flush();
        //        Context.    .CompleteRequest();
        //    }
        //    catch (Exception ex)
        //    {
        //        lblError.Text = Server.HtmlEncode(ex.Message);
        //    }
        //}
    }
}
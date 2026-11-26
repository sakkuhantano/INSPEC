using OfficeOpenXml;
using OfficeOpenXml.Style;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.UI;
using System.Web.UI.WebControls;
using WAL;

namespace INSPEC.Secure
{
    using Rpt = INSPEC.BRC.Report;
    using ReportData = INSPEC.BRC.Report.ReportData;
    public partial class R_Report : WAL.PB, WAL.I_ToolBar_2
    {
        private const string _MenuID = "12011";
        protected void Page_Load(object sender, EventArgs e)
        {
            if (!IsPostBack)
            {
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
                PreapareScreen();
            }

        }

        private void PreapareScreen()
        {
            F_Close_pnl_Search();
            UpdateViewGridReport();
        }

        // Satu IDItem bisa menjadi beberapa kolom H jika master menyimpan
        // ItemType=OPTION dan OptionList, misalnya "ON;OFF".
        // Semuanya tetap menunjuk IDItem yang sama untuk membaca Value aktual.
        private sealed class HorizontalChoiceColumn
        {
            public Rpt.ItemDef Item;
            public string Choice; // null = kolom standar; non-null = kolom opsi.
        }

        private sealed class HorizontalItemRange
        {
            public Rpt.ItemDef Item;
            public int FirstCol;
            public int LastCol;
            public bool HasChoices;
        }

        private static List<HorizontalChoiceColumn> BuildHorizontalColumns(
            List<Rpt.ItemDef> items, string headerMode)
        {
            List<HorizontalChoiceColumn> columns = new List<HorizontalChoiceColumn>();
            foreach (Rpt.ItemDef item in items)
            {
                // Mode NONE: selalu satu kolom per Item; hasil lama tidak berubah.
                bool canExpand = headerMode != "NONE" && String.Equals(
                    item.ItemType, "OPTION", StringComparison.OrdinalIgnoreCase);
                string[] options = canExpand && !String.IsNullOrWhiteSpace(item.OptionList)
                    ? item.OptionList.Split(';').Select(s => s.Trim())
                        .Where(s => s.Length > 0).ToArray()
                    : new string[0];

                if (options.Length > 1)
                {
                    if (options.Distinct(StringComparer.OrdinalIgnoreCase).Count() != options.Length)
                        throw new InvalidOperationException(
                            "OptionList mengandung pilihan duplikat: " + item.Label);
                    foreach (string choice in options)
                        columns.Add(new HorizontalChoiceColumn { Item = item, Choice = choice });
                }
                else
                    columns.Add(new HorizontalChoiceColumn { Item = item, Choice = null });
            }
            return columns;
        }

        private static List<HorizontalItemRange> GetHorizontalRanges(
            List<HorizontalChoiceColumn> columns)
        {
            List<HorizontalItemRange> ranges = new List<HorizontalItemRange>();
            int i = 0;
            while (i < columns.Count)
            {
                Rpt.ItemDef item = columns[i].Item;
                int end = i + 1;
                while (end < columns.Count && Object.ReferenceEquals(columns[end].Item, item))
                    end++;
                ranges.Add(new HorizontalItemRange
                {
                    Item = item,
                    FirstCol = 4 + i,
                    LastCol = 3 + end,
                    HasChoices = columns[i].Choice != null
                });
                i = end;
            }
            return ranges;
        }

        private static void PutHeaderMerged(ExcelWorksheet ws, int row1, int col1,
            int row2, int col2, string title)
        {
            if (row1 != row2 || col1 != col2)
                ws.Cells[row1, col1, row2, col2].Merge = true;
            Put(ws.Cells[row1, col1], title);
        }

        // Digunakan H saat OPTION mempunyai lebih dari satu pilihan.
        // Struktur AUTO: Section -> [SubSection] -> Item -> Choice.
        // Struktur SECTION: Section -> Item -> Choice.
        // Item tanpa pilihan/anak di-merge vertikal sampai tingkat paling bawah.
        private static void WriteHorizontalOptionHeaders(ExcelWorksheet ws,
            int headerRow, List<HorizontalChoiceColumn> columns, bool hasSubSections)
        {
            List<HorizontalItemRange> ranges = GetHorizontalRanges(columns);
            int leafRow = headerRow + (hasSubSections ? 3 : 2);
            int i = 0;
            while (i < ranges.Count)
            {
                int sectionEnd = i + 1;
                while (sectionEnd < ranges.Count && String.Equals(
                    ranges[sectionEnd].Item.SectionKey, ranges[i].Item.SectionKey,
                    StringComparison.OrdinalIgnoreCase))
                    sectionEnd++;

                PutHeaderMerged(ws, headerRow, ranges[i].FirstCol,
                    headerRow, ranges[sectionEnd - 1].LastCol,
                    ranges[i].Item.SectionName);

                int k = i;
                while (k < sectionEnd)
                {
                    HorizontalItemRange current = ranges[k];
                    string subKey = hasSubSections
                        ? (current.Item.SubSectionKey ?? String.Empty) : String.Empty;
                    if (subKey.Length == 0)
                    {
                        int itemRow = headerRow + 1;
                        int itemEnd = current.HasChoices ? leafRow - 1 : leafRow;
                        PutHeaderMerged(ws, itemRow, current.FirstCol,
                            itemEnd, current.LastCol, current.Item.Label);
                        if (current.HasChoices)
                            for (int col = current.FirstCol; col <= current.LastCol; col++)
                                Put(ws.Cells[leafRow, col], columns[col - 4].Choice);
                        k++;
                        continue;
                    }

                    int subEnd = k + 1;
                    while (subEnd < sectionEnd && String.Equals(
                        ranges[subEnd].Item.SubSectionKey, subKey,
                        StringComparison.OrdinalIgnoreCase))
                        subEnd++;
                    string subTitle = current.Item.SubSectionName;
                    // Satu Item berjudul sama dengan SubSection: jangan ulang judul.
                    bool duplicateName = subEnd == k + 1 &&
                        String.Equals(subTitle.Trim(), current.Item.Label.Trim(),
                            StringComparison.OrdinalIgnoreCase);
                    if (duplicateName)
                        PutHeaderMerged(ws, headerRow + 1, current.FirstCol,
                            current.HasChoices ? headerRow + 2 : leafRow,
                            current.LastCol, subTitle);
                    else
                        PutHeaderMerged(ws, headerRow + 1, current.FirstCol,
                            headerRow + 1, ranges[subEnd - 1].LastCol, subTitle);

                    for (int p = k; p < subEnd; p++)
                    {
                        HorizontalItemRange itemRange = ranges[p];
                        if (!duplicateName)
                        {
                            int itemRow = headerRow + 2;
                            // Jika ada opsi: label di atas pilihan.
                            // Jika tidak: ItemLabel menempati baris item + pilihan.
                            int itemEnd = itemRange.HasChoices ? itemRow : leafRow;
                            PutHeaderMerged(ws, itemRow, itemRange.FirstCol,
                                itemEnd, itemRange.LastCol, itemRange.Item.Label);
                        }
                        if (itemRange.HasChoices)
                            for (int col = itemRange.FirstCol; col <= itemRange.LastCol; col++)
                                Put(ws.Cells[leafRow, col], columns[col - 4].Choice);
                    }
                    k = subEnd;
                }
                i = sectionEnd;
            }
        }

        private static void WriteHorizontalValue(ExcelWorksheet ws, int row,
            int col, HorizontalChoiceColumn column, DataRow result)
        {
            string rawValue = BRC.Report.GetValue(result, "Value");
            if (column.Choice == null)
            {
                // Nilai dikirim persis seperti pada PIP_T_InspectionResult.Value.
                // Termasuk angka berkoma, nol di depan, serta huruf V/X.
                PutResultValue(ws.Cells[row, col], rawValue);
                return;
            }
            string value = rawValue.Trim();
            // Hindari hilangnya nilai jika OptionList master tidak cocok dengan snapshot.
            // Misal Value=ON tetapi OptionList hanya YES; hentikan, jangan kosongkan.
            string[] options = (column.Item.OptionList ?? String.Empty).Split(';');
            bool found = options.Any(choice => String.Equals(choice.Trim(), value,
                StringComparison.OrdinalIgnoreCase));
            if (value.Length > 0 && !found)
                throw new InvalidOperationException(
                    "Value '" + value + "' tidak ditemukan pada OptionList IDItem " +
                    column.Item.Id.Split('\u001f')[0] + " (" + column.Item.Label + ").");
            if (value.Length > 0 && String.Equals(value, column.Choice,
                StringComparison.OrdinalIgnoreCase))
                // Jika Value = ON, tulis "ON" pada kolom ON (bukan tanda centang).
                // Nilai lain juga tidak diubah menjadi simbol.
                PutResultValue(ws.Cells[row, col], rawValue);
        }

        // Semua pembuatan Excel sengaja dalam satu method agar mirip Closing Report.
        private static void _CreateXLSXFile(ReportData report, FileInfo newFile)
        {
            if (newFile == null) throw new ArgumentNullException("newFile");
            // Pola standar Closing Report: ExcelPackage berbasis file, lalu Save().
            using (ExcelPackage pck = new ExcelPackage(newFile))
            {
                foreach (var group in report.Groups)
                {
                    // DetailName sudah disusun berdasarkan GroupingBy di Report.cs.
                    string sheetName = NewSheetName(group.DetailName);
                    ExcelWorksheet ws = pck.Workbook.Worksheets.Add(sheetName);
                    List<DataRow> headers = group.Headers.OrderBy(h => BRC.Report.DateKey(h))
                                            .ThenBy(h => BRC.Report.TimeOf(h))
                                            .ThenBy(h => BRC.Report.GetValue(h, "InspectionNo")).ToList();
                    // T memakai renderer sendiri agar kolom STATUS/Remark dari VERSION
                    // tidak mengubah bentuk H maupun V yang sudah berjalan.
                    if (group.Layout == "T")
                    {
                        WriteChecklistTemplate(ws, group, report, headers);
                        continue;
                    }
                    // Matriks V khusus Operator Log Sheet (Section / SubSection / Unit / Jam).
                    if (group.Layout == "V" && group.VerticalMode == "TIME_MATRIX")
                    {
                        WriteVerticalTimeMatrix(ws, group, report, headers);
                        continue;
                    }
                    // V STANDARD: setiap lokasi toilet/unit menjadi subjudul,
                    // lalu setiap transaksi/jam menjadi kolom, bukan nama unit.
                    // Mode H dan T tidak mengalami perubahan.
                    if (group.Layout == "V")
                    {
                        WriteVerticalStandardByTime(ws, group, report, headers);
                        continue;
                    }
                    var items = group.Items;  // ItemDef tetap di Report.cs
                    var units = group.Units;  // SELURUH unit master (termasuk yang kosong)
                    string layout = group.Layout;
                    string headerMode = group.ChecklistHeaderMode ?? "NONE";
                    List<HorizontalChoiceColumn> horizontalColumns = layout == "H"
                        ? BuildHorizontalColumns(items, headerMode)
                        : new List<HorizontalChoiceColumn>();
                    int horizontalColumnCount = horizontalColumns.Count;
                    int lastCol = layout == "H" ? horizontalColumnCount + 6 : units.Count + 1;
                    int lastRow;

                    if ((layout != "H" && layout != "V") || lastCol > 16384 || lastCol < 2)
                        throw new InvalidOperationException("Layout atau jumlah kolom tidak valid.");

                    // Judul selalu dari transaksi: PIP_T_Inspection.InspectionTypeName.
                    ws.Cells[1, 1, 1, lastCol].Merge = true;
                    Put(ws.Cells[1, 1], group.Title);
                    ws.Cells[1, 1, 1, lastCol].Style.Font.Bold = true;
                    ws.Cells[1, 1, 1, lastCol].Style.Font.UnderLine = true;
                    ws.Cells[1, 1, 1, lastCol].Style.Font.Size = 18;
                    ws.Cells[1, 1, 1, lastCol].Style.HorizontalAlignment = ExcelHorizontalAlignment.Center;
                    ws.Row(1).Height = 32;

                    ws.Cells[2, 1, 2, lastCol].Merge = true;
                    // Tanggal transaksi bisa berbeda; jangan beri label hanya tanggal pertama.
                    var dates = headers.Select(h => BRC.Report.DateOf(h)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
                    string periodLabel = dates.Count == 1 ? dates[0] : "MULTI DATE";
                    Put(ws.Cells[2, 1], "PERIODE " + periodLabel + "  |  " + group.GroupLabel);
                    ws.Cells[2, 1, 2, lastCol].Style.HorizontalAlignment = ExcelHorizontalAlignment.Center;
                    ws.Cells[2, 1, 2, lastCol].Style.Font.Size = 12;

                    int headerRow = 4;
                    // H: header bertingkat di atas kolom ItemLabel.
                    // V: Section/SubSection menjadi baris band di antara item,
                    //    tanpa menggeser nilai dari kolom unit masing-masing.
                    bool groupedHeader = layout == "H" && headerMode != "NONE";
                    bool groupedVerticalRows = layout == "V" && headerMode != "NONE";
                    bool hasSubSections = headerMode == "AUTO" && items.Any(i =>
                        !String.IsNullOrEmpty(i.SubSectionKey));
                    bool hasChoiceColumns = groupedHeader && horizontalColumnCount > items.Count;
                    int headerDepth = groupedHeader
                        ? (hasSubSections ? 3 : 2) + (hasChoiceColumns ? 1 : 0)
                        : 1;
                    int firstRow = headerRow + headerDepth;
                    int currentRow = firstRow;

                    if (layout == "H")
                    {
                        // HORIZONTAL: satu InspectionNo = satu baris, ItemLabel jadi kolom.
                        string[] fixedHeaders = { "DATE", "TIME", "FLOOR / UNIT" };
                        for (int i = 0; i < fixedHeaders.Length; i++)
                        {
                            if (groupedHeader)
                                ws.Cells[headerRow, i + 1, firstRow - 1, i + 1].Merge = true;
                            Put(ws.Cells[headerRow, i + 1], fixedHeaders[i]);
                        }
                        if (hasChoiceColumns)
                            WriteHorizontalOptionHeaders(ws, headerRow, horizontalColumns, hasSubSections);
                        else if (groupedHeader)
                            WriteHierarchicalChecklistHeaders(ws, headerRow, items, headerMode, headerDepth);
                        else
                            for (int i = 0; i < items.Count; i++)
                                Put(ws.Cells[headerRow, i + 4], items[i].Label);
                        string[] trailing = { "KETERANGAN / FOLLOW UP", "INSPECTED BY", "APPROVED BY" };
                        for (int j = 0; j < trailing.Length; j++)
                        {
                            int col = horizontalColumnCount + 4 + j;
                            if (groupedHeader)
                                ws.Cells[headerRow, col, firstRow - 1, col].Merge = true;
                            Put(ws.Cells[headerRow, col], trailing[j]);
                        }

                        // GROUPING LAMA (DINONAKTIFKAN): hanya baris transaksi terpilih.
                        // foreach (DataRow h in headers) { ... }

                        // GROUPING BARU (AKTIF): setiap unit master wajib muncul.
                        // Jika ada beberapa transaksi untuk unit yang sama, tampilkan
                        // semua baris transaksi tersebut; jika belum ada, satu baris kosong.
                        foreach (var unit in units)
                        {
                            List<DataRow> unitHeaders = headers.Where(h =>
                                String.Equals(BRC.Report.GetValue(h, "InspectionTypeDetailCode").Trim(),
                                    unit.Code, StringComparison.OrdinalIgnoreCase)).ToList();

                            if (unitHeaders.Count == 0)
                            {
                                Put(ws.Cells[currentRow, 3], unit.Name);
                                currentRow++;
                                continue;
                            }

                            foreach (DataRow h in unitHeaders)
                            {
                                Put(ws.Cells[currentRow, 1], BRC.Report.DateOf(h));
                                Put(ws.Cells[currentRow, 2], BRC.Report.TimeOf(h));
                                Put(ws.Cells[currentRow, 3], unit.Name);
                                var values = headerMode == "NONE" && group.HorizontalNoneAliases != null
                                    ? BRC.Report.ValuesForHorizontalNone(h, report.ResultLookup,
                                        group.HorizontalNoneAliases)
                                    : BRC.Report.ValuesFor(h, report.ResultLookup);
                                for (int i = 0; i < horizontalColumns.Count; i++)
                                {
                                    DataRow result;
                                    if (values.TryGetValue(horizontalColumns[i].Item.Id, out result))
                                        WriteHorizontalValue(ws, currentRow, i + 4,
                                            horizontalColumns[i], result);
                                }
                                Put(ws.Cells[currentRow, horizontalColumnCount + 4],
                                    BRC.Report.Notes(h, report.ResultLookup));
                                Put(ws.Cells[currentRow, horizontalColumnCount + 5],
                                    BRC.Report.GetValue(h, "InspectedByName"));
                                Put(ws.Cells[currentRow, horizontalColumnCount + 6],
                                    BRC.Report.GetValue(h, "ApprovedByName"));
                                currentRow++;
                            }
                        }
                        lastRow = currentRow - 1;
                    }
                    else
                    {
                        // VERTICAL: ItemLabel menjadi baris; SEMUA unit MASTER
                        // menjadi kolom (tidak tergantung jumlah InspectionNo).
                        Put(ws.Cells[headerRow, 1], "INSPECTED ITEM");
                        var rowsByUnit = units.Select(unit => headers.Where(h =>
                            String.Equals(BRC.Report.GetValue(h, "InspectionTypeDetailCode").Trim(),
                                unit.Code, StringComparison.OrdinalIgnoreCase)).ToList()).ToList();
                        var valuesByUnit = rowsByUnit.Select(groupHeaders => groupHeaders.Select(h =>
                            BRC.Report.ValuesFor(h, report.ResultLookup)).ToList()).ToList();

                        for (int j = 0; j < units.Count; j++)
                            Put(ws.Cells[headerRow, j + 2], units[j].Name);

                        // Jika mode NONE, tidak ada tambahan baris sehingga output
                        // V sama seperti sebelumnya. Jika SECTION/AUTO, kelompok
                        // hanya menambah baris label, BUKAN kolom nilai.
                        string lastSectionKey = null;
                        string lastSubSectionKey = null;
                        foreach (var item in items)
                        {
                            if (groupedVerticalRows)
                            {
                                if (!String.Equals(lastSectionKey, item.SectionKey,
                                    StringComparison.OrdinalIgnoreCase))
                                {
                                    WriteVerticalHierarchyBand(ws, currentRow, lastCol,
                                        item.SectionName, true);
                                    currentRow++;
                                    lastSectionKey = item.SectionKey;
                                    lastSubSectionKey = null;
                                }

                                // AUTO: hanya buat baris SubSection jika item punya
                                // SubSection. Item tanpa SubSection tetap di Section.
                                string subKey = headerMode == "AUTO"
                                    ? (item.SubSectionKey ?? String.Empty) : String.Empty;
                                if (subKey.Length > 0 && !String.Equals(
                                    lastSubSectionKey, subKey, StringComparison.OrdinalIgnoreCase))
                                {
                                    WriteVerticalHierarchyBand(ws, currentRow, lastCol,
                                        item.SubSectionName, false);
                                    currentRow++;
                                }
                                lastSubSectionKey = subKey;
                            }

                            Put(ws.Cells[currentRow, 1], item.Label);
                            for (int j = 0; j < units.Count; j++)
                            {
                                List<string> matches = new List<string>();
                                for (int k = 0; k < rowsByUnit[j].Count; k++)
                                {
                                    DataRow result;
                                    if (!valuesByUnit[j][k].TryGetValue(item.Id, out result))
                                        continue;
                                    string value = BRC.Report.GetValue(result, "Value");
                                    if (String.IsNullOrWhiteSpace(value)) continue;
                                    // Per satu unit, beberapa transaksi tidak boleh saling menimpa.
                                    matches.Add(value);
                                }
                                if (matches.Count == 1)
                                    PutResultValue(ws.Cells[currentRow, j + 2], matches[0]);
                                else if (matches.Count > 1)
                                {
                                    List<string> valueLines = new List<string>();
                                    for (int k = 0; k < rowsByUnit[j].Count; k++)
                                    {
                                        DataRow r;
                                        if (!valuesByUnit[j][k].TryGetValue(item.Id, out r)) continue;
                                        string val = BRC.Report.GetValue(r, "Value");
                                        if (String.IsNullOrWhiteSpace(val)) continue;
                                        DataRow h = rowsByUnit[j][k];
                                        valueLines.Add(BRC.Report.DateOf(h) + " " +
                                            BRC.Report.TimeOf(h) + " [" +
                                            BRC.Report.GetValue(h, "InspectionNo") + "]: " + val);
                                    }
                                    PutResultValue(ws.Cells[currentRow, j + 2], String.Join("\n", valueLines.ToArray()));
                                    ws.Row(currentRow).Height = Math.Min(90, Math.Max(24, valueLines.Count * 15));
                                }
                            }
                            currentRow++;
                        }
                        // KETERANGAN BARU: satu baris tepat setelah checklist terakhir
                        // (contoh: AC Vent). Tidak di-merge agar posisi tiap note
                        // sejajar dengan kolom Lift/Floor dari master.
                        Put(ws.Cells[currentRow, 1], "KETERANGAN / FOLLOW UP");
                        ws.Cells[currentRow, 1].Style.Font.Bold = true;
                        ws.Cells[currentRow, 1].Style.WrapText = true;

                        int maxNoteLines = 1;
                        for (int j = 0; j < units.Count; j++)
                        {
                            List<string> notes = new List<string>();
                            foreach (DataRow h in rowsByUnit[j])
                            {
                                string note = BRC.Report.Notes(h, report.ResultLookup);
                                if (String.IsNullOrWhiteSpace(note)) continue;

                                // Satu transaksi pada Lift tersebut: tulis catatan saja.
                                // Banyak transaksi: tampilkan nomor agar tidak tertukar.
                                if (rowsByUnit[j].Count > 1)
                                    note = BRC.Report.GetValue(h, "InspectionNo") + ": " + note;

                                notes.Add(note);
                            }

                            // Belum ada inspeksi/keterangan: biarkan cell kosong.
                            if (notes.Count == 0) continue;

                            Put(ws.Cells[currentRow, j + 2], String.Join("\n", notes.ToArray()));
                            ws.Cells[currentRow, j + 2].Style.WrapText = true;
                            maxNoteLines = Math.Max(maxNoteLines, notes.Count);
                        }

                        ws.Row(currentRow).Height = Math.Min(120, Math.Max(32, maxNoteLines * 20));
                        lastRow = currentRow; // Masukkan baris keterangan ke border dan print area.

                        // LOGIKA LAMA (dinonaktifkan): keterangan digabung
                        // menjadi beberapa baris penuh di bawah checklist.
                        // ws.Cells[currentRow, 1, currentRow, lastCol].Merge = true;
                        // foreach (DataRow h in headers) { ... }
                    }

                    if (lastRow > 1048576)
                        throw new InvalidOperationException("Jumlah baris laporan melebihi batas Excel.");

                    // Format tabel sederhana seperti Closing Report kantor.
                    ExcelRange table = ws.Cells[headerRow, 1, Math.Max(headerRow, lastRow), lastCol];
                    table.Style.Border.Top.Style = ExcelBorderStyle.Thin;
                    table.Style.Border.Bottom.Style = ExcelBorderStyle.Thin;
                    table.Style.Border.Left.Style = ExcelBorderStyle.Thin;
                    table.Style.Border.Right.Style = ExcelBorderStyle.Thin;
                    table.Style.WrapText = true;
                    table.Style.VerticalAlignment = ExcelVerticalAlignment.Center;
                    ExcelRange headerRange = ws.Cells[headerRow, 1, firstRow - 1, lastCol];
                    headerRange.Style.Font.Bold = true;
                    headerRange.Style.Fill.PatternType = ExcelFillStyle.Solid;
                    headerRange.Style.Fill.BackgroundColor.SetColor(Color.FromArgb(232, 238, 242));
                    headerRange.Style.HorizontalAlignment = ExcelHorizontalAlignment.Center;
                    ws.Row(headerRow).Height = groupedHeader ? 26 : (layout == "H" ? 55 : 40);
                    if (groupedHeader)
                    {
                        for (int offset = 1; offset < headerDepth; offset++)
                            ws.Row(headerRow + offset).Height = offset == headerDepth - 1 ? 40 : 30;
                    }
                    ws.View.FreezePanes(firstRow, layout == "H" ? 4 : 2);

                    ConfigurePageSetup(ws, layout);
                    ws.PrinterSettings.PrintArea = ws.Cells[1, 1, Math.Max(lastRow, currentRow), lastCol];
                }
                pck.Save();
            }
        }

        // V STANDARD: lokasi (InspectionTypeDetailName) adalah SUBJUDUL BLOK,
        // bukan kepala kolom. INSPECTED ITEM berada di A, sementara TIME
        // menaungi satu atau lebih kolom ScheduledTime transaksi (B, C, dst).
        // Contoh: Toilet Inspection / Male Toilet B1 / 07:00 dan 09:00.
        // GroupingBy dari Report.Prepare tetap menentukan worksheet.
        private static void WriteVerticalStandardByTime(
            ExcelWorksheet ws, Rpt.ReportGroup group, ReportData report,
            List<DataRow> headers)
        {
            List<Rpt.UnitDef> units = group.Units;
            if (units == null || units.Count == 0)
                throw new InvalidOperationException(
                    "V STANDARD memerlukan master InspectionTypeDetail.");

            int lastCol = 2;
            foreach (Rpt.UnitDef unit in units)
            {
                int count = headers.Count(h => String.Equals(
                    BRC.Report.GetValue(h, "InspectionTypeDetailCode").Trim(),
                    unit.Code, StringComparison.OrdinalIgnoreCase));
                lastCol = Math.Max(lastCol, 1 + Math.Max(1, count));
            }
            if (lastCol > 16384)
                throw new InvalidOperationException("Jumlah kolom waktu melebihi batas Excel.");

            ws.Cells[1, 1, 1, lastCol].Merge = true;
            Put(ws.Cells[1, 1], group.Title);
            ws.Cells[1, 1, 1, lastCol].Style.Font.Bold = true;
            ws.Cells[1, 1, 1, lastCol].Style.Font.Size = 18;
            ws.Cells[1, 1, 1, lastCol].Style.HorizontalAlignment =
                ExcelHorizontalAlignment.Center;
            ws.Row(1).Height = 31;

            List<string> dates = headers.Select(BRC.Report.DateOf)
                .Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            string period = dates.Count == 1 ? dates[0] : "MULTI DATE";
            // Satu toilet per worksheet: nama toilet persis di bawah judul.
            if (units.Count == 1)
            {
                ws.Cells[2, 1, 2, lastCol].Merge = true;
                Put(ws.Cells[2, 1], units[0].Name);
                ws.Cells[2, 1, 2, lastCol].Style.Font.Bold = true;
                ws.Cells[2, 1, 2, lastCol].Style.Font.Size = 13;
                ws.Cells[2, 1, 2, lastCol].Style.HorizontalAlignment =
                    ExcelHorizontalAlignment.Center;
                ws.Cells[3, 1, 3, lastCol].Merge = true;
                Put(ws.Cells[3, 1], "PERIODE " + period);
                ws.Cells[3, 1, 3, lastCol].Style.HorizontalAlignment =
                    ExcelHorizontalAlignment.Center;
            }
            else
            {
                ws.Cells[2, 1, 2, lastCol].Merge = true;
                Put(ws.Cells[2, 1], "PERIODE " + period);
                ws.Cells[2, 1, 2, lastCol].Style.HorizontalAlignment =
                    ExcelHorizontalAlignment.Center;
            }

            string headerMode = (group.ChecklistHeaderMode ?? "NONE").ToUpperInvariant();
            int currentRow = 4;
            int firstHeaderRow = 0;
            foreach (Rpt.UnitDef unit in units)
            {
                List<DataRow> unitHeaders = headers.Where(h => String.Equals(
                    BRC.Report.GetValue(h, "InspectionTypeDetailCode").Trim(),
                    unit.Code, StringComparison.OrdinalIgnoreCase))
                    .OrderBy(h => BRC.Report.DateKey(h))
                    .ThenBy(h => BRC.Report.TimeOf(h))
                    .ThenBy(h => BRC.Report.GetValue(h, "InspectionNo"))
                    .ToList();
                int width = 1 + Math.Max(1, unitHeaders.Count);
                List<Dictionary<string, DataRow>> values = unitHeaders.Select(h =>
                    BRC.Report.ValuesFor(h, report.ResultLookup)).ToList();

                // Multi-lokasi: setiap toilet menjadi blok tersendiri di dalam
                // sheet yang sama. Single-lokasi sudah ada di baris 2.
                if (units.Count > 1)
                {
                    ws.Cells[currentRow, 1, currentRow, lastCol].Merge = true;
                    Put(ws.Cells[currentRow, 1], unit.Name);
                    ExcelRange locationBand = ws.Cells[currentRow, 1, currentRow, lastCol];
                    locationBand.Style.Font.Bold = true;
                    locationBand.Style.Font.Size = 12;
                    locationBand.Style.Fill.PatternType = ExcelFillStyle.Solid;
                    locationBand.Style.Fill.BackgroundColor.SetColor(
                        Color.FromArgb(216, 228, 238));
                    currentRow++;
                }
                int headerRow = currentRow;
                if (firstHeaderRow == 0) firstHeaderRow = headerRow;
                ws.Cells[headerRow, 1, headerRow + 1, 1].Merge = true;
                Put(ws.Cells[headerRow, 1], "INSPECTED ITEM");
                if (width > 2)
                    ws.Cells[headerRow, 2, headerRow, width].Merge = true;
                Put(ws.Cells[headerRow, 2], "TIME");

                bool multipleDates = unitHeaders.Select(BRC.Report.DateKey)
                    .Distinct(StringComparer.OrdinalIgnoreCase).Count() > 1;
                for (int i = 0; i < unitHeaders.Count; i++)
                {
                    DataRow h = unitHeaders[i];
                    string clock = BRC.Report.TimeOf(h);
                    string label = multipleDates
                        ? BRC.Report.DateOf(h) + " " + clock : clock;
                    // Waktu sama pada lebih dari satu inspeksi: bedakan dengan nomor
                    // transaksi agar hasil tidak tertimpa diam-diam.
                    int occurrences = unitHeaders.Count(other =>
                        BRC.Report.DateKey(other) == BRC.Report.DateKey(h) &&
                        String.Equals(BRC.Report.TimeOf(other), clock,
                            StringComparison.OrdinalIgnoreCase));
                    if (occurrences > 1)
                        label += " [" + BRC.Report.GetValue(h, "InspectionNo") + "]";
                    Put(ws.Cells[headerRow + 1, i + 2], label);
                }
                if (unitHeaders.Count == 0)
                    Put(ws.Cells[headerRow + 1, 2], "-");
                ExcelRange timeHeader = ws.Cells[headerRow, 1, headerRow + 1, width];
                timeHeader.Style.Font.Bold = true;
                timeHeader.Style.Fill.PatternType = ExcelFillStyle.Solid;
                timeHeader.Style.Fill.BackgroundColor.SetColor(
                    Color.FromArgb(232, 238, 242));
                timeHeader.Style.HorizontalAlignment = ExcelHorizontalAlignment.Center;
                timeHeader.Style.VerticalAlignment = ExcelVerticalAlignment.Center;
                timeHeader.Style.WrapText = true;
                ws.Row(headerRow).Height = 24;
                ws.Row(headerRow + 1).Height = multipleDates ? 34 : 26;
                currentRow += 2;

                string lastSectionKey = null;
                string lastSubSectionKey = null;
                foreach (Rpt.ItemDef item in group.Items)
                {
                    if (headerMode != "NONE")
                    {
                        if (!String.Equals(lastSectionKey, item.SectionKey,
                            StringComparison.OrdinalIgnoreCase))
                        {
                            WriteVerticalHierarchyBand(ws, currentRow, width,
                                item.SectionName, true);
                            currentRow++;
                            lastSectionKey = item.SectionKey;
                            lastSubSectionKey = null;
                        }
                        string subKey = headerMode == "AUTO"
                            ? (item.SubSectionKey ?? String.Empty) : String.Empty;
                        if (subKey.Length > 0 && !String.Equals(lastSubSectionKey,
                            subKey, StringComparison.OrdinalIgnoreCase))
                        {
                            WriteVerticalHierarchyBand(ws, currentRow, width,
                                item.SubSectionName, false);
                            currentRow++;
                        }
                        lastSubSectionKey = subKey;
                    }
                    Put(ws.Cells[currentRow, 1], item.Label);
                    for (int i = 0; i < values.Count; i++)
                    {
                        DataRow result;
                        if (values[i].TryGetValue(item.Id, out result))
                            PutResultValue(ws.Cells[currentRow, i + 2],
                                BRC.Report.GetValue(result, "Value"));
                    }
                    currentRow++;
                }

                Put(ws.Cells[currentRow, 1], "KETERANGAN / FOLLOW UP");
                ws.Cells[currentRow, 1].Style.Font.Bold = true;
                int maxLines = 1;
                for (int i = 0; i < unitHeaders.Count; i++)
                {
                    string note = BRC.Report.Notes(unitHeaders[i], report.ResultLookup);
                    if (String.IsNullOrWhiteSpace(note)) continue;
                    Put(ws.Cells[currentRow, i + 2], note);
                    ws.Cells[currentRow, i + 2].Style.WrapText = true;
                    maxLines = Math.Max(maxLines, ApproximateLines(note, 28));
                }
                ws.Row(currentRow).Height = Math.Min(105, Math.Max(28, maxLines * 16));

                // V STANDARD: satu Inspected By dan satu Approved By untuk
                // seluruh blok lokasi ini, BUKAN nama pada setiap kolom jam.
                // Jika transaksi berbeda menyimpan penanggung jawab berbeda,
                // jangan memilih salah satu secara diam-diam.
                List<string> inspectedNames = unitHeaders
                    .Select(h => BRC.Report.GetValue(h, "InspectedByName").Trim())
                    .Where(name => name.Length > 0)
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .ToList();
                List<string> approvedNames = unitHeaders
                    .Select(h => BRC.Report.GetValue(h, "ApprovedByName").Trim())
                    .Where(name => name.Length > 0)
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .ToList();

                if (inspectedNames.Count > 1)
                    throw new InvalidOperationException(
                        "V STANDARD: Inspected By berbeda untuk lokasi '" +
                        unit.Name + "'. Periksa OwnerEmployeeID dari InspectionID yang dipilih.");
                if (approvedNames.Count > 1)
                    throw new InvalidOperationException(
                        "V STANDARD: Approved By berbeda untuk lokasi '" +
                        unit.Name + "'. Periksa ApprovedBy dari InspectionID yang dipilih.");

                currentRow++;
                Put(ws.Cells[currentRow, 1], "INSPECTED BY");
                ws.Cells[currentRow, 1].Style.Font.Bold = true;
                if (width > 2)
                    ws.Cells[currentRow, 2, currentRow, width].Merge = true;
                ExcelRange inspectedCell = ws.Cells[currentRow, 2];
                Put(inspectedCell, inspectedNames.Count == 1 ? inspectedNames[0] : String.Empty);
                inspectedCell.Style.WrapText = true;
                ws.Row(currentRow).Height = 28;

                currentRow++;
                Put(ws.Cells[currentRow, 1], "APPROVED BY");
                ws.Cells[currentRow, 1].Style.Font.Bold = true;
                if (width > 2)
                    ws.Cells[currentRow, 2, currentRow, width].Merge = true;
                ExcelRange approvedCell = ws.Cells[currentRow, 2];
                Put(approvedCell, approvedNames.Count == 1 ? approvedNames[0] : String.Empty);
                approvedCell.Style.WrapText = true;
                ws.Row(currentRow).Height = 28;

                ExcelRange table = ws.Cells[headerRow, 1, currentRow, width];
                table.Style.Border.Top.Style = ExcelBorderStyle.Thin;
                table.Style.Border.Bottom.Style = ExcelBorderStyle.Thin;
                table.Style.Border.Left.Style = ExcelBorderStyle.Thin;
                table.Style.Border.Right.Style = ExcelBorderStyle.Thin;
                table.Style.WrapText = true;
                table.Style.VerticalAlignment = ExcelVerticalAlignment.Center;
                currentRow += 2;
            }

            if (currentRow > 1048576)
                throw new InvalidOperationException("Jumlah baris V STANDARD melebihi batas Excel.");
            if (firstHeaderRow > 0)
                ws.View.FreezePanes(firstHeaderRow + 2, 2);
            ConfigurePageSetup(ws, "V");
            ws.PrinterSettings.FitToPage = true;
            ws.PrinterSettings.FitToWidth = lastCol > 20 ? 2 : 1;
            ws.PrinterSettings.FitToHeight = 0;
            ws.PrinterSettings.PrintArea = ws.Cells[1, 1, currentRow - 2, lastCol];
        }

        // TIME_MATRIX: struktur meniru Operator Log Sheet fisik:
        // [Section + jam pada SATU baris], lalu
        // [SubSection (merge vertikal)] [Item] [Unit] [Value per jam].
        // Item tanpa SubSection memakai kolom pertama langsung. Tidak ada
        // header generik 'GROUP / SUBSECTION', 'INSPECTED ITEM', atau 'UNIT'.
        // H, V STANDARD dan T tidak dipengaruhi oleh perubahan ini.
        private static void WriteVerticalTimeMatrix(ExcelWorksheet ws,
            Rpt.ReportGroup group, ReportData report, List<DataRow> headers)
        {
            if (group.Items == null || group.Items.Count == 0 || headers.Count == 0)
                throw new InvalidOperationException("Data TIME_MATRIX kosong.");

            // Judul tetap menggunakan InspectionTypeName transaksi.
            Put(ws.Cells[1, 1], group.Title);
            ws.Row(1).Height = 32;
            Put(ws.Cells[2, 1], "PERIODE OPERASIONAL  |  " + group.GroupLabel +
                "  |  Mulai " + group.OperationalStartLabel);
            ws.Row(2).Height = 24;

            // Khusus V + AUTO + TIME_MATRIX: bila satu worksheet memiliki
            // beberapa InspectionTypeDetail, tampilkan seluruh jam sebagai
            // kolom pada SATU tabel per Section (mis. 00:00 lalu 08:00).
            // Mode lain tetap memakai pemisahan detail seperti versi V8.11.
            // Jika dua detail memiliki Value pada item dan timestamp sama,
            // validasi duplikat di bawah tetap menolak, tidak menimpa data.
            bool combineAutoMatrixDetails =
                String.Equals(group.ChecklistHeaderMode, "AUTO",
                    StringComparison.OrdinalIgnoreCase) &&
                headers.Select(h => BRC.Report.GetValue(h,
                    "InspectionTypeDetailCode").Trim())
                    .Distinct(StringComparer.OrdinalIgnoreCase).Count() > 1;
            var unitGroups = headers.GroupBy(h =>
                combineAutoMatrixDetails ? String.Empty :
                    BRC.Report.GetValue(h, "InspectionTypeDetailCode").Trim(),
                StringComparer.OrdinalIgnoreCase).ToList();
            Dictionary<DataRow, Dictionary<string, DataRow>> valuesByHeader =
                new Dictionary<DataRow, Dictionary<string, DataRow>>();
            foreach (DataRow h in headers)
                valuesByHeader.Add(h, BRC.Report.ValuesFor(h, report.ResultLookup));

            var sectionGroups = group.Items.GroupBy(i => i.SectionKey,
                StringComparer.OrdinalIgnoreCase).ToList();
            int currentRow = 4;
            int maxColumn = 4;
            foreach (var sec in sectionGroups)
            {
                List<Rpt.ItemDef> sectionItems = sec.ToList();
                foreach (var unitGroup in unitGroups)
                {
                    List<DataRow> unitHeaders = unitGroup.ToList();
                    List<DataRow> activeHeaders = unitHeaders.Where(h =>
                        sectionItems.Any(i => valuesByHeader[h].ContainsKey(i.Id))).ToList();
                    if (activeHeaders.Count == 0)
                        activeHeaders = unitHeaders;
                    if (activeHeaders.Count == 0) continue;

                    var slots = activeHeaders.GroupBy(h =>
                        BRC.Report.InspectionTimestamp(h)).OrderBy(g => g.Key).ToList();
                    int lastCol = 3 + slots.Count;
                    if (lastCol > 16384)
                        throw new InvalidOperationException(
                            "TIME_MATRIX melebihi batas 16384 kolom Excel.");
                    maxColumn = Math.Max(maxColumn, lastCol);

                    string unitName = BRC.Report.UnitName(unitHeaders[0]);
                    string sectionTitle = sectionItems[0].SectionName;
                    if (unitGroups.Count > 1 && !String.IsNullOrWhiteSpace(unitName))
                        sectionTitle += "  |  " + unitName;
                    if (!combineAutoMatrixDetails &&
                        group.OperationalStartLabel == "berbeda per unit")
                        sectionTitle += "  |  Mulai " +
                            TimeSpan.Parse(BRC.Report.GetValue(unitHeaders[0],
                                "OperationalStartTime"), CultureInfo.InvariantCulture)
                                .ToString(@"hh\:mm", CultureInfo.InvariantCulture);

                    // Foto: FIRE EQUIPMENT | 10:00 | 12:00 | ...
                    // Tidak ada baris header kedua berisi nama kolom generik.
                    int tableStart = currentRow;
                    ExcelRange sectionRow = ws.Cells[currentRow, 1, currentRow, lastCol];
                    StyleChecklistBand(sectionRow, true);
                    ws.Cells[currentRow, 1, currentRow, 3].Merge = true;
                    Put(ws.Cells[currentRow, 1], sectionTitle);
                    for (int j = 0; j < slots.Count; j++)
                    {
                        ExcelRange clockCell = ws.Cells[currentRow, j + 4];
                        Put(clockCell, slots[j].Key.ToString("HH:mm",
                            CultureInfo.InvariantCulture));
                        clockCell.Style.HorizontalAlignment = ExcelHorizontalAlignment.Center;
                    }
                    ws.Row(currentRow).Height = 28;
                    currentRow++;

                    // Foto: HYDRANT WATER menjadi sel gabungan vertikal pada
                    // kolom pertama; PUMP #1 dan PUMP #2 di kolom kedua.
                    // Item tanpa SubSection tampil pada kolom pertama.
                    int itemIndex = 0;
                    while (itemIndex < sectionItems.Count)
                    {
                        Rpt.ItemDef firstItem = sectionItems[itemIndex];
                        string subKey = group.ChecklistHeaderMode == "AUTO"
                            ? (firstItem.SubSectionKey ?? String.Empty) : String.Empty;
                        int endIndex = itemIndex + 1;
                        if (subKey.Length > 0)
                        {
                            while (endIndex < sectionItems.Count &&
                                String.Equals(sectionItems[endIndex].SubSectionKey,
                                    subKey, StringComparison.OrdinalIgnoreCase))
                                endIndex++;

                            int span = endIndex - itemIndex;
                            if (span > 1)
                                ws.Cells[currentRow, 1, currentRow + span - 1, 1].Merge = true;
                            Put(ws.Cells[currentRow, 1], firstItem.SubSectionName);
                            ws.Cells[currentRow, 1].Style.Font.Bold = true;
                            ws.Cells[currentRow, 1].Style.VerticalAlignment =
                                ExcelVerticalAlignment.Center;
                            ws.Cells[currentRow, 1].Style.WrapText = true;
                        }

                        for (int k = itemIndex; k < endIndex; k++)
                        {
                            Rpt.ItemDef item = sectionItems[k];
                            if (subKey.Length == 0)
                            {
                                Put(ws.Cells[currentRow, 1], item.Label);
                            }
                            else
                            {
                                // Hindari nama sama di dua kolom untuk subsection
                                // yang hanya memiliki satu item bernama identik.
                                bool sameName = endIndex == itemIndex + 1 &&
                                    String.Equals(item.SubSectionName.Trim(),
                                        item.Label.Trim(), StringComparison.OrdinalIgnoreCase);
                                if (!sameName)
                                    Put(ws.Cells[currentRow, 2], item.Label);
                            }
                            Put(ws.Cells[currentRow, 3], item.Unit ?? String.Empty);
                            ws.Row(currentRow).Height = 23;

                            for (int j = 0; j < slots.Count; j++)
                            {
                                DataRow match = null;
                                foreach (DataRow h in slots[j])
                                {
                                    DataRow candidate;
                                    if (!valuesByHeader[h].TryGetValue(item.Id, out candidate))
                                        continue;
                                    if (match != null)
                                        throw new InvalidOperationException(
                                            "TIME_MATRIX duplikat untuk Section '" +
                                            sectionTitle + "', item '" + item.Label +
                                            "', waktu " + slots[j].Key.ToString(
                                                "dd-MM-yyyy HH:mm", CultureInfo.InvariantCulture) + ".");
                                    match = candidate;
                                }
                                if (match != null)
                                    PutResultValue(ws.Cells[currentRow, j + 4],
                                        BRC.Report.GetValue(match, "Value"));
                            }
                            currentRow++;
                        }
                        itemIndex = endIndex;
                    }

                    ExcelRange table = ws.Cells[tableStart, 1, currentRow - 1, lastCol];
                    table.Style.Border.Top.Style = ExcelBorderStyle.Thin;
                    table.Style.Border.Bottom.Style = ExcelBorderStyle.Thin;
                    table.Style.Border.Left.Style = ExcelBorderStyle.Thin;
                    table.Style.Border.Right.Style = ExcelBorderStyle.Thin;
                    table.Style.VerticalAlignment = ExcelVerticalAlignment.Center;
                    table.Style.WrapText = true;
                    currentRow += 2;
                }
            }
            if (currentRow <= 4)
                throw new InvalidOperationException("Tidak ada tabel TIME_MATRIX untuk inspeksi terpilih.");
            if (currentRow > 1048576)
                throw new InvalidOperationException("TIME_MATRIX melebihi batas baris Excel.");
            ws.Cells[1, 1, 1, maxColumn].Merge = true;
            ws.Cells[2, 1, 2, maxColumn].Merge = true;
            ws.Cells[1, 1, 1, maxColumn].Style.Font.Bold = true;
            ws.Cells[1, 1, 1, maxColumn].Style.Font.Size = 17;
            ws.Cells[1, 1, 1, maxColumn].Style.HorizontalAlignment =
                ExcelHorizontalAlignment.Center;
            ws.Cells[2, 1, 2, maxColumn].Style.HorizontalAlignment =
                ExcelHorizontalAlignment.Center;
            ws.View.FreezePanes(3, 4);
            ConfigurePageSetup(ws, "V_MATRIX");
            ws.PrinterSettings.FitToPage = true;
            ws.PrinterSettings.FitToWidth = maxColumn > 15 ? 2 : 1;
            ws.PrinterSettings.FitToHeight = 0;
            ws.PrinterSettings.PrintArea = ws.Cells[1, 1, currentRow - 3, maxColumn];
        }

        // T: tabel ITEMS / STATUS / Remark1 / Remark2, 1 blok per InspectionID.
        // Beberapa IDVersion boleh dalam satu sheet; judul remark mengikuti
        // VERSION masing-masing, bukan memakai versi transaksi pertama.
        // Tidak ada tanda tangan, hanya label dan nama seperti laporan H.
        private static void WriteChecklistTemplate(ExcelWorksheet ws,
            Rpt.ReportGroup group, ReportData report, List<DataRow> headers)
        {
            if (report.MasterItems == null)
                throw new InvalidOperationException("Master checklist untuk layout T tidak tersedia.");
            int maxCols = 3;
            foreach (DataRow h in headers)
            {
                if (BRC.Report.GetValue(h, "VersionCount") != "1")
                    throw new InvalidOperationException("IDVersion/IDTemplate checklist T tidak valid.");
                int count = 3;
                if (BRC.Report.GetValue(h, "VersionRemark1Required") == "1") count++;
                if (BRC.Report.GetValue(h, "VersionRemark2Required") == "1") count++;
                maxCols = Math.Max(maxCols, count);
            }

            ws.Cells[1, 1, 1, maxCols].Merge = true;
            Put(ws.Cells[1, 1], group.Title);
            ws.Cells[1, 1, 1, maxCols].Style.Font.Bold = true;
            ws.Cells[1, 1, 1, maxCols].Style.Font.Size = 16;
            ws.Cells[1, 1, 1, maxCols].Style.HorizontalAlignment =
                ExcelHorizontalAlignment.Center;
            ws.Row(1).Height = 34;

            ws.Cells[2, 1, 2, maxCols].Merge = true;
            Put(ws.Cells[2, 1], group.GroupLabel);
            ws.Cells[2, 1, 2, maxCols].Style.HorizontalAlignment =
                ExcelHorizontalAlignment.Center;

            int currentRow = 4;
            foreach (DataRow h in headers)
            {
                bool hasRemark1 = BRC.Report.GetValue(h, "VersionRemark1Required") == "1";
                bool hasRemark2 = BRC.Report.GetValue(h, "VersionRemark2Required") == "1";
                string remark1Title = BRC.Report.GetValue(h, "VersionRemark1Text").Trim();
                string remark2Title = BRC.Report.GetValue(h, "VersionRemark2Text").Trim();
                if ((hasRemark1 && remark1Title.Length == 0) ||
                    (hasRemark2 && remark2Title.Length == 0))
                    throw new InvalidOperationException("Judul Remark pada VERSION wajib terisi bila flag = 1.");

                int blockLastCol = 3 + (hasRemark1 ? 1 : 0) + (hasRemark2 ? 1 : 0);
                string headerMode = group.ChecklistHeaderMode ?? "NONE";
                List<Rpt.ItemDef> items = BRC.Report.ItemsForInspection(
                    h, report.ResultLookup, report.MasterItems, headerMode);
                if (items.Count == 0)
                    throw new InvalidOperationException("Checklist T kosong untuk InspectionID " +
                        BRC.Report.GetValue(h, "InspectionID"));
                Dictionary<string, DataRow> values = BRC.Report.ValuesFor(h, report.ResultLookup);

                // Metadata transaksi; InspectionNo, unit, dan tanggal dari database.
                ExcelRange metadata = ws.Cells[currentRow, 1, currentRow, blockLastCol];
                metadata.Merge = true;
                Put(ws.Cells[currentRow, 1], "INSPECTION NO: " +
                    BRC.Report.GetValue(h, "InspectionNo") + "  |  DATE: " +
                    BRC.Report.DateOf(h) + "  |  UNIT: " +
                    BRC.Report.GetValue(h, "InspectionTypeDetailName"));
                metadata.Style.Font.Bold = true;
                metadata.Style.Fill.PatternType = ExcelFillStyle.Solid;
                metadata.Style.Fill.BackgroundColor.SetColor(Color.FromArgb(222, 232, 240));
                metadata.Style.WrapText = true;
                ws.Row(currentRow).Height = 30;
                currentRow++;

                int tableStart = currentRow;
                Put(ws.Cells[currentRow, 1], "NO");
                Put(ws.Cells[currentRow, 2], "ITEMS");
                Put(ws.Cells[currentRow, 3], "STATUS");
                int c = 4;
                if (hasRemark1) Put(ws.Cells[currentRow, c++], remark1Title);
                if (hasRemark2) Put(ws.Cells[currentRow, c++], remark2Title);
                ExcelRange columnHeader = ws.Cells[currentRow, 1, currentRow, blockLastCol];
                columnHeader.Style.Font.Bold = true;
                columnHeader.Style.Fill.PatternType = ExcelFillStyle.Solid;
                columnHeader.Style.Fill.BackgroundColor.SetColor(Color.FromArgb(208, 222, 234));
                columnHeader.Style.HorizontalAlignment = ExcelHorizontalAlignment.Center;
                columnHeader.Style.WrapText = true;
                ws.Row(currentRow).Height = 42;
                currentRow++;

                int sectionNo = 0;
                int subNo = 0;
                string lastSection = null;
                string lastSub = null;
                foreach (Rpt.ItemDef item in items)
                {
                    if (headerMode != "NONE" && !String.Equals(lastSection,
                        item.SectionKey, StringComparison.OrdinalIgnoreCase))
                    {
                        sectionNo++;
                        subNo = 0;
                        Put(ws.Cells[currentRow, 1], sectionNo.ToString(CultureInfo.InvariantCulture));
                        ExcelRange band = ws.Cells[currentRow, 2, currentRow, blockLastCol];
                        band.Merge = true;
                        Put(ws.Cells[currentRow, 2], item.SectionName);
                        StyleChecklistBand(band, true);
                        ws.Row(currentRow).Height = 24;
                        currentRow++;
                        lastSection = item.SectionKey;
                        lastSub = null;
                    }
                    string sub = headerMode == "AUTO" ? (item.SubSectionKey ?? String.Empty)
                        : String.Empty;
                    if (sub.Length > 0 && !String.Equals(sub, lastSub,
                        StringComparison.OrdinalIgnoreCase))
                    {
                        subNo++;
                        Put(ws.Cells[currentRow, 1], sectionNo.ToString(CultureInfo.InvariantCulture)
                            + "." + subNo.ToString(CultureInfo.InvariantCulture));
                        ExcelRange subBand = ws.Cells[currentRow, 2, currentRow, blockLastCol];
                        subBand.Merge = true;
                        Put(ws.Cells[currentRow, 2], item.SubSectionName);
                        StyleChecklistBand(subBand, false);
                        ws.Row(currentRow).Height = 23;
                        currentRow++;
                    }
                    lastSub = sub;

                    Put(ws.Cells[currentRow, 2], item.Label);
                    int estimatedLines = ApproximateLines(item.Label, 39);
                    DataRow result;
                    if (values.TryGetValue(item.Id, out result))
                    {
                        string status = BRC.Report.GetValue(result, "Value");
                        PutResultValue(ws.Cells[currentRow, 3], status);
                        estimatedLines = Math.Max(estimatedLines, ApproximateLines(status, 15));
                        c = 4;
                        if (hasRemark1)
                        {
                            string note1 = BRC.Report.GetValue(result, "Remark1");
                            Put(ws.Cells[currentRow, c++], note1);
                            estimatedLines = Math.Max(estimatedLines, ApproximateLines(note1, 32));
                        }
                        if (hasRemark2)
                        {
                            string note2 = BRC.Report.GetValue(result, "Remark2");
                            Put(ws.Cells[currentRow, c++], note2);
                            estimatedLines = Math.Max(estimatedLines, ApproximateLines(note2, 32));
                        }
                    }
                    ws.Row(currentRow).Height = Math.Min(180, Math.Max(22, estimatedLines * 16));
                    currentRow++;
                }

                // Border mencakup satu blok tabel checklist, termasuk baris kelompok.
                ExcelRange table = ws.Cells[tableStart, 1, currentRow - 1, blockLastCol];
                table.Style.Border.Top.Style = ExcelBorderStyle.Thin;
                table.Style.Border.Bottom.Style = ExcelBorderStyle.Thin;
                table.Style.Border.Left.Style = ExcelBorderStyle.Thin;
                table.Style.Border.Right.Style = ExcelBorderStyle.Thin;
                table.Style.WrapText = true;
                table.Style.VerticalAlignment = ExcelVerticalAlignment.Center;

                // Tidak ada area tanda tangan/approval elektronik.
                // Tampilkan nama penanggung jawab seperti laporan H.
                WriteChecklistPersonRow(ws, currentRow++, blockLastCol,
                    "INSPECTED BY", BRC.Report.GetValue(h, "InspectedByName"));
                WriteChecklistPersonRow(ws, currentRow++, blockLastCol,
                    "APPROVED BY", BRC.Report.GetValue(h, "ApprovedByName"));
                currentRow += 2;
            }

            if (currentRow > 1048576)
                throw new InvalidOperationException("Jumlah baris layout T melebihi batas Excel.");
            // T tidak menggunakan FreezePanes. Lebar seluruh kolom
            // disesuaikan lewat AutoFit yang juga dipakai layout H dan V.
            ConfigurePageSetup(ws, "T");
            // Portrait dengan satu halaman lebar; panjang otomatis mengikuti data.
            ws.PrinterSettings.FitToPage = true;
            ws.PrinterSettings.FitToWidth = 1;
            ws.PrinterSettings.FitToHeight = 0;
            ws.PrinterSettings.Orientation = eOrientation.Portrait;
            ws.PrinterSettings.PaperSize = ePaperSize.A3;
            ws.PrinterSettings.PrintArea = ws.Cells[1, 1, currentRow - 1, maxCols];
        }

        // Perkiraan tinggi baris untuk item/remark panjang supaya tidak terpotong
        // saat dibaca maupun dicetak (tanpa menggunakan AutoFit pada merged cell).
        private static int ApproximateLines(string text, int charactersPerLine)
        {
            if (String.IsNullOrEmpty(text)) return 1;
            int lines = 0;
            foreach (string part in text.Replace("\r", "").Split('\n'))
                lines += Math.Max(1, (part.Length + charactersPerLine - 1) / charactersPerLine);
            return lines;
        }

        private static void StyleChecklistBand(ExcelRange band, bool section)
        {
            band.Style.Font.Bold = true;
            band.Style.Fill.PatternType = ExcelFillStyle.Solid;
            band.Style.Fill.BackgroundColor.SetColor(section
                ? Color.FromArgb(216, 228, 238) : Color.FromArgb(239, 245, 248));
            band.Style.VerticalAlignment = ExcelVerticalAlignment.Center;
            band.Style.WrapText = true;
        }

        private static void WriteChecklistPersonRow(ExcelWorksheet ws, int row,
            int lastCol, string label, string name)
        {
            Put(ws.Cells[row, 1], label);
            ExcelRange cell = ws.Cells[row, 2, row, lastCol];
            cell.Merge = true;
            Put(ws.Cells[row, 2], name);
            cell.Style.Font.Bold = true;
            cell.Style.WrapText = true;
            ws.Row(row).Height = 24;
        }

        // V ONLY: Section dan SubSection menjadi baris kelompok penuh.
        // Nilai pada baris item tidak dipindah dari kolom unit asalnya.
        private static void WriteVerticalHierarchyBand(
            ExcelWorksheet ws, int row, int lastCol, string label, bool isSection)
        {
            if (String.IsNullOrWhiteSpace(label))
                throw new InvalidOperationException(
                    "Nama Section/SubSection kosong pada header bertingkat V.");

            ExcelRange band = ws.Cells[row, 1, row, lastCol];
            band.Merge = true;
            Put(ws.Cells[row, 1], label);
            band.Style.Font.Bold = true;
            band.Style.Fill.PatternType = ExcelFillStyle.Solid;
            band.Style.Fill.BackgroundColor.SetColor(isSection
                ? Color.FromArgb(216, 228, 238)
                : Color.FromArgb(237, 243, 247));
            band.Style.HorizontalAlignment = ExcelHorizontalAlignment.Left;
            band.Style.VerticalAlignment = ExcelVerticalAlignment.Center;
            band.Style.Indent = isSection ? 0 : 1;
            band.Style.WrapText = true;
            ws.Row(row).Height = isSection ? 27 : 23;
        }

        // H ONLY: Section dan SubSection adalah BARIS HEADER; ItemLabel tetap kolom
        // berdampingan seperti I inc | I out. Nilai tetap pada kolom IDItem yang sama.
        private static void WriteHierarchicalChecklistHeaders(
            ExcelWorksheet ws, int headerRow, List<Rpt.ItemDef> items,
            string mode, int headerDepth)
        {
            const int firstItemCol = 4;
            int itemHeaderRow = headerRow + headerDepth - 1;
            int index = 0;
            while (index < items.Count)
            {
                int sectionEnd = index + 1;
                while (sectionEnd < items.Count && String.Equals(
                    items[sectionEnd].SectionKey, items[index].SectionKey,
                    StringComparison.OrdinalIgnoreCase))
                    sectionEnd++;

                int sectionFrom = firstItemCol + index;
                int sectionTo = firstItemCol + sectionEnd - 1;
                if (sectionTo > sectionFrom)
                    ws.Cells[headerRow, sectionFrom, headerRow, sectionTo].Merge = true;
                Put(ws.Cells[headerRow, sectionFrom], items[index].SectionName);

                // SECTION dan AUTO tanpa SubSection: dua baris, Section > ItemLabel.
                if (headerDepth == 2)
                {
                    for (int k = index; k < sectionEnd; k++)
                        Put(ws.Cells[itemHeaderRow, firstItemCol + k], items[k].Label);
                }
                else
                {
                    // AUTO dengan SubSection: tiga baris Section > SubSection > Item.
                    // Untuk item tanpa SubSection, ItemLabel di-merge vertikal.
                    int k = index;
                    while (k < sectionEnd)
                    {
                        if (String.IsNullOrEmpty(items[k].SubSectionKey))
                        {
                            int col = firstItemCol + k;
                            ws.Cells[headerRow + 1, col, itemHeaderRow, col].Merge = true;
                            Put(ws.Cells[headerRow + 1, col], items[k].Label);
                            k++;
                            continue;
                        }
                        int end = k + 1;
                        while (end < sectionEnd && String.Equals(
                            items[end].SubSectionKey, items[k].SubSectionKey,
                            StringComparison.OrdinalIgnoreCase))
                            end++;
                        int colFrom = firstItemCol + k;
                        int colTo = firstItemCol + end - 1;
                        if (colTo > colFrom)
                            ws.Cells[headerRow + 1, colFrom, headerRow + 1, colTo].Merge = true;
                        Put(ws.Cells[headerRow + 1, colFrom], items[k].SubSectionName);
                        for (int x = k; x < end; x++)
                            Put(ws.Cells[itemHeaderRow, firstItemCol + x], items[x].Label);
                        k = end;
                    }
                }
                index = sectionEnd;
            }
        }

        // API publik utama yang digunakan oleh halaman Preview/Print supervisor.
        // DataTable hanya berisi InspectionID; CompanyID, LocationID, dan UserID
        // berasal dari konteks halaman pemanggil. InspectionNo dibaca dari database.
        // PENTING: halaman pemanggil wajib memvalidasi hak akses Print/Preview SPV
        // dan mengambil companyId/locationId/userId dari konteks login server,
        // bukan dari nilai input pengguna.
        public static ReportFileResult GenerateInspectionXlsx(
            DataTable selectedInspections,
            string companyId,
            string locationId,
            string userId)
        {
            try
            {
                if (selectedInspections == null)
                    throw new ArgumentNullException("selectedInspections");
                if (!selectedInspections.Columns.Contains("InspectionID"))
                    throw new ArgumentException("DataTable harus memiliki kolom InspectionID.");
                if (selectedInspections.Rows.Count == 0 || selectedInspections.Rows.Count > 500)
                    throw new InvalidOperationException("Pilih 1 sampai 500 baris inspeksi.");
                if (String.IsNullOrWhiteSpace(companyId) || String.IsNullOrWhiteSpace(locationId))
                    throw new ArgumentException("CompanyID/LocationID wajib diisi.");
                if (String.IsNullOrWhiteSpace(userId))
                    throw new ArgumentException("UserID folder export wajib diisi.", "userId");

                List<string> ids = new List<string>();
                HashSet<long> knownIds = new HashSet<long>();
                for (int i = 0; i < selectedInspections.Rows.Count; i++)
                {
                    DataRow row = selectedInspections.Rows[i];
                    if (row.RowState == DataRowState.Deleted) continue;

                    long id;
                    string rawId = Convert.ToString(row["InspectionID"], CultureInfo.InvariantCulture).Trim();
                    if (!Int64.TryParse(rawId, NumberStyles.None, CultureInfo.InvariantCulture, out id) || id <= 0)
                        throw new ArgumentException("InspectionID tidak valid pada baris " + (i + 1) + ".");
                    if (knownIds.Add(id))
                        ids.Add(id.ToString(CultureInfo.InvariantCulture));
                }

                if (ids.Count == 0)
                    throw new InvalidOperationException("Tidak ada InspectionID aktif yang dipilih.");

                Rpt.InspectionScope scope = Rpt.GetInspectionScope(ids);
                if (!String.Equals(scope.CompanyID, companyId, StringComparison.OrdinalIgnoreCase) ||
                    !String.Equals(scope.LocationID, locationId, StringComparison.OrdinalIgnoreCase))
                    throw new UnauthorizedAccessException("InspectionID tidak sesuai scope CompanyID/LocationID yang telah diotorisasi.");

                return GenerateInspectionXlsxCore(ids, companyId, locationId, userId);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Trace.TraceError("GenerateInspectionXlsx(DataTable, scope): " + ex);
                bool isDebug = HttpContext.Current != null && HttpContext.Current.IsDebuggingEnabled;
                string friendly = ex is ArgumentException || ex is InvalidOperationException ||
                                  ex is UnauthorizedAccessException ? ex.Message : "Gagal memproses DataTable inspeksi. Periksa log server.";
                return new ReportFileResult
                {
                    Success = false,
                    Status = "FAILED",
                    FileName = String.Empty,
                    StoragePath = String.Empty,
                    Message = isDebug ? ex.GetBaseException().Message : friendly
                };
            }
        }

        // Hanya untuk pengujian tombol Print halaman R_Report ini.
        // Preview/Print halaman supervisor lain mengirim parameter langsung,
        // setelah otorisasi SPV dicek oleh backend halaman pemanggil.
        private static string GetMasterLoginValue(MasterPage master, string memberName)
        {
            for (MasterPage current = master; current != null; current = current.Master)
            {
                Type type = current.GetType();
                PropertyInfo property = type.GetProperty(memberName,
                    BindingFlags.Instance | BindingFlags.Public);
                if (property != null && property.GetIndexParameters().Length == 0)
                    return (Convert.ToString(property.GetValue(current, null)) ?? String.Empty).Trim();

                FieldInfo field = type.GetField(memberName,
                    BindingFlags.Instance | BindingFlags.Public);
                if (field != null)
                    return (Convert.ToString(field.GetValue(current)) ?? String.Empty).Trim();
            }

            throw new UnauthorizedAccessException(
                "MasterPage tidak menyediakan data login: " + memberName);
        }

        // Dipanggil oleh overload DataTable empat parameter setelah scope transaksi
        // cocok dengan companyId/locationId yang diterima dari halaman terotorisasi.
        private static ReportFileResult GenerateInspectionXlsxCore(
            IEnumerable<string> inspectionIds,
            string companyId,
            string locationId,
            string userId)
        {
            string storagePath = null;
            string exportFolder = null;
            string stage = "VALIDASI INPUT";
            try
            {
                if (inspectionIds == null)
                    throw new ArgumentNullException("inspectionIds");
                if (String.IsNullOrWhiteSpace(companyId) || String.IsNullOrWhiteSpace(locationId))
                    throw new ArgumentException("CompanyID/LocationID login tidak boleh kosong.");
                if (String.IsNullOrWhiteSpace(userId))
                    throw new ArgumentException("UserID untuk nama folder export wajib diisi.");

                List<string> selected = Rpt.NormalizeInspectionIds(inspectionIds)
                    .Select(id => id.ToString(CultureInfo.InvariantCulture)).ToList();

                if (selected.Count == 0)
                    throw new InvalidOperationException("Pilih minimal satu InspectionID.");
                if (selected.Count > 500)
                    throw new InvalidOperationException("Maksimal 500 InspectionID per export.");

                stage = "BACA DATABASE / REPORT.CS";
                // Sumber data, GroupingBy (;), IDVersion, semua Lift master,
                // checklist, serta layout H/V tetap menggunakan kode existing.
                ReportData report = Rpt.Prepare(selected, companyId, locationId);
                if (report == null || report.Groups == null || report.Groups.Count == 0)
                    throw new InvalidOperationException("Tidak ada worksheet yang dapat dibuat.");

                stage = "BUAT NAMA DAN FOLDER";
                string V_FileType = "xlsx";
                string V_Path_FolerView = GF.Path_FolerView();
                string V_FileName = Path.GetFileNameWithoutExtension(SafeExcelFileName(report.Title));
                string V_FileNameType = V_FileName + "_" + GF.DBSDatetime().ToString(GF.FormatDateTime2) + "." + V_FileType;

                if (String.IsNullOrWhiteSpace(V_Path_FolerView))
                    throw new InvalidOperationException("GF.Path_FolerView() belum dikonfigurasi.");
                if (!Directory.Exists(V_Path_FolerView))
                    Directory.CreateDirectory(V_Path_FolerView);

                string folderName = SafeFolderSegment(userId);
                exportFolder = Path.Combine(V_Path_FolerView, folderName);
                Directory.CreateDirectory(exportFolder);
                storagePath = Path.Combine(exportFolder, V_FileNameType);

                //stage = "BUAT NAMA DAN FOLDER";
                //// Format kantor: Path_FolerView, DBSDatetime dan ExcelPackage.Save().
                //// FileName tetap identik dengan InspectionTypeName (kecuali karakter
                //// yang tidak diperbolehkan oleh filesystem).
                //string V_FileType = "xlsx";
                //string V_Path_FolerView = GF.Path_FolerView();
                //string V_FileName = Path.GetFileNameWithoutExtension(SafeExcelFileName(report.Title));
                //string V_FileNameType = V_FileName + "." + V_FileType;

                //if (String.IsNullOrWhiteSpace(V_Path_FolerView))
                //    throw new InvalidOperationException("GF.Path_FolerView() belum dikonfigurasi.");
                //if (!Directory.Exists(V_Path_FolerView))
                //    Directory.CreateDirectory(V_Path_FolerView);

                //// UserID dan waktu di nama subfolder agar nama file Excel
                //// tidak perlu diberi prefix/suffix dan tetap sama dengan judul.
                //// GUID di sini hanya menghindari bentrok antar-request, BUKAN token login.
                //string folderName = "[" + SafeFolderSegment(userId) + "]" +
                //    SafeFolderSegment(GF.DBSDatetime().ToString(GF.FormatDateTime2)) +
                //    "_" + Guid.NewGuid().ToString("N").Substring(0, 8);
                //exportFolder = Path.Combine(V_Path_FolerView, folderName);
                //Directory.CreateDirectory(exportFolder);
                //storagePath = Path.Combine(exportFolder, V_FileNameType);

                stage = "GENERATE XLSX / EPPLUS";
                // _CreateXLSXFile melakukan new ExcelPackage(newFile),
                // menulis worksheet H/V, kemudian pck.Save().
                _CreateXLSXFile(report, new FileInfo(storagePath));

                stage = "UJI FILE HASIL SAVE";
                FileInfo created = new FileInfo(storagePath);
                if (!created.Exists || created.Length == 0)
                    throw new IOException("File Excel tidak tersimpan atau kosong.");

                // Self-test yang bisa dijalankan langsung di halaman kita.
                // File dibuka lagi dari DISK menggunakan EPPlus, bukan byte[] HTTP.
                int actualSheets = 0;
                using (ExcelPackage check = new ExcelPackage(new FileInfo(storagePath)))
                {
                    foreach (ExcelWorksheet sheet in check.Workbook.Worksheets)
                    {
                        actualSheets++;
                        if (sheet.Dimension == null)
                            throw new InvalidOperationException("Worksheet '" + sheet.Name + "' kosong.");
                        if (!String.Equals(sheet.Cells[1, 1].Text.Trim(),
                                report.Title.Trim(), StringComparison.Ordinal))
                            throw new InvalidOperationException(
                                "Judul worksheet '" + sheet.Name + "' tidak cocok dengan InspectionTypeName.");
                    }
                }
                if (actualSheets != report.Groups.Count)
                    throw new InvalidOperationException("Jumlah worksheet hasil save tidak cocok dengan GroupingBy.");

                System.Diagnostics.Trace.TraceInformation(
                    "InspectionReport SUCCESS; InspectionCount={0}; Sheets={1}; Bytes={2}",
                    selected.Count, actualSheets, created.Length);

                return new ReportFileResult
                {
                    Success = true,
                    Status = "SUCCESS",
                    FileName = V_FileNameType,
                    StoragePath = storagePath,
                    Message = "Excel berhasil dibuat dan lolos pemeriksaan EPPlus."
                };
            }
            catch (Exception ex)
            {
                // Informasi lengkap disimpan di Trace, tidak dikirim ke browser publik.
                System.Diagnostics.Trace.TraceError(
                    "GenerateInspectionXlsx FAILED at " + stage + ": " + ex.ToString());
                if (!String.IsNullOrWhiteSpace(storagePath))
                {
                    try { if (File.Exists(storagePath)) File.Delete(storagePath); }
                    catch (Exception cleanupEx)
                    { System.Diagnostics.Trace.TraceWarning(cleanupEx.ToString()); }
                }
                if (!String.IsNullOrWhiteSpace(exportFolder))
                {
                    try
                    {
                        if (Directory.Exists(exportFolder) &&
                            Directory.GetFileSystemEntries(exportFolder).Length == 0)
                            Directory.Delete(exportFolder);
                    }
                    catch (Exception cleanupEx)
                    { System.Diagnostics.Trace.TraceWarning(cleanupEx.ToString()); }
                }
                // Saat Web.config compilation debug=true, tampilkan tahap dan
                // pesan asli agar mudah ditelusuri pada halaman kita sendiri.
                bool isDebug = HttpContext.Current != null && HttpContext.Current.IsDebuggingEnabled;
                string friendly = ex is ArgumentException || ex is InvalidOperationException ||
                                  ex is UnauthorizedAccessException
                    ? ex.Message : "Gagal membuat Excel. Periksa log server.";
                return new ReportFileResult
                {
                    Success = false,
                    Status = "FAILED",
                    FileName = String.Empty,
                    StoragePath = String.Empty,
                    Message = isDebug ? "[DEBUG " + stage + "] " + ex.GetBaseException().Message : friendly
                };
            }
        }

        // Folder hanya menggunakan karakter yang aman untuk filesystem dan URL.
        private static string SafeFolderSegment(string value)
        {
            string clean = Regex.Replace((value ?? "").Trim(),
                @"[\\/:*?""<>|\x00-\x1F]", "_").Trim().Trim('.');
            if (clean.Length == 0) clean = "USER";
            return clean.Substring(0, Math.Min(40, clean.Length));
        }

        // Dipakai oleh tombol Print halaman ini dan tombol Preview halaman lain.
        // URL dibentuk dari StoragePath; tidak perlu property FileUrl.
        // Folder GF.Url_FolerView() harus dilindungi otorisasi server.
        public static string GetInspectionFileUrl(ReportFileResult result)
        {
            if (result == null || !result.Success || String.IsNullOrWhiteSpace(result.StoragePath))
                throw new ArgumentException("Hasil generate Excel tidak valid.");

            string rootPath = Path.GetFullPath(GF.Path_FolerView())
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                + Path.DirectorySeparatorChar;
            string physicalPath = Path.GetFullPath(result.StoragePath);
            if (!physicalPath.StartsWith(rootPath, StringComparison.OrdinalIgnoreCase) ||
                !File.Exists(physicalPath))
                throw new InvalidOperationException("File Excel tidak ditemukan dalam folder laporan.");

            // Karena project .NET 4.5 belum mempunyai Path.GetRelativePath().
            string relativePath = physicalPath.Substring(rootPath.Length);
            string[] parts = relativePath.Split(new char[] {
                Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar
            }, StringSplitOptions.RemoveEmptyEntries);
            string baseUrl = GF.Url_FolerView();
            if (String.IsNullOrWhiteSpace(baseUrl))
                throw new InvalidOperationException("GF.Url_FolerView() belum dikonfigurasi.");
            baseUrl = baseUrl.TrimEnd('/');
            if (baseUrl.StartsWith("~/", StringComparison.Ordinal))
                baseUrl = VirtualPathUtility.ToAbsolute(baseUrl);
            else if (!baseUrl.StartsWith("/", StringComparison.Ordinal) &&
                     !Uri.IsWellFormedUriString(baseUrl, UriKind.Absolute))
                baseUrl = VirtualPathUtility.ToAbsolute("~/" + baseUrl.TrimStart('/'));

            return baseUrl + "/" + String.Join("/",
                parts.Select(HttpUtility.UrlPathEncode).ToArray());
        }

        // AutoFit berlaku untuk H, V, dan T. Batas minimum menjaga kolom
        // tetap terbaca ketika sebagian header di-merge (AutoFit tidak dapat
        // mengukur ukuran teks dalam merged cells secara akurat).
        // Batas maksimum mencegah satu Remark/ItemLabel panjang membuat
        // halaman Excel sangat lebar. WrapText dan tinggi baris tetap berlaku.
        private static void AutoFitReportColumns(ExcelWorksheet ws, string layout)
        {
            if (ws.Dimension == null) return;
            ws.Cells[ws.Dimension.Address].AutoFitColumns();

            int columnCount = ws.Dimension.End.Column;
            for (int i = 1; i <= columnCount; i++)
            {
                double minWidth = 12;
                double maxWidth = 42;

                if (layout == "T")
                {
                    if (i == 1) { minWidth = 9; maxWidth = 12; } // NO
                    else if (i == 2) { minWidth = 32; maxWidth = 50; } // ITEMS
                    else if (i == 3) { minWidth = 14; maxWidth = 24; } // STATUS
                    else { minWidth = 25; maxWidth = 48; } // Remark1/Remark2
                }
                else if (layout == "H")
                {
                    if (i == 1) minWidth = 12; // DATE
                    if (i == 2) minWidth = 10; // TIME
                    if (i == 3) minWidth = 18; // FLOOR / UNIT
                }
                else if (layout == "V")
                {
                    if (i == 1) minWidth = 28; // INSPECTED ITEM
                    else minWidth = 16;        // kolom unit master
                }
                else if (layout == "V_MATRIX")
                {
                    if (i == 1) { minWidth = 20; maxWidth = 34; }
                    else if (i == 2) { minWidth = 30; maxWidth = 48; }
                    else if (i == 3) { minWidth = 12; maxWidth = 20; }
                    else { minWidth = 12; maxWidth = 18; }
                }

                double fittedWidth = ws.Column(i).Width;
                ws.Column(i).Width = Math.Max(minWidth,
                    Math.Min(maxWidth, fittedWidth));
            }
        }

        private static void ConfigurePageSetup(ExcelWorksheet ws, string layout)
        {
            AutoFitReportColumns(ws, layout);
            ws.PrinterSettings.FitToPage = false;
            ws.PrinterSettings.Scale = 63;
            ws.PrinterSettings.TopMargin = 0.15M;
            ws.PrinterSettings.LeftMargin = 0.15M;
            ws.PrinterSettings.RightMargin = 0.15M;
            ws.PrinterSettings.BottomMargin = 0.15M;
            ws.PrinterSettings.Orientation = eOrientation.Landscape;
            ws.PrinterSettings.PaperSize = ePaperSize.A3;
        }

        private static string NewSheetName(string name)
        {
            // DetailName sudah diisi dari GroupingBy oleh Report.cs.
            string clean = Regex.Replace((name ?? "").Trim(),
                @"[\\/:*?\[\]\x00-\x1F]", " ").Trim('\'');

            if (String.IsNullOrWhiteSpace(clean)) clean = "Inspection";

            // Batas nama worksheet Excel maksimal 31 karakter.
            return clean.Substring(0, Math.Min(31, clean.Length))
                .TrimEnd(' ', '\'');
        }

        // InspectionTypeName menentukan nama file download (bukan nama tab).
        // Hanya karakter invalid path yang dibersihkan, judul dalam Excel tetap asli.
        private static string SafeExcelFileName(string title)
        {
            string name = Regex.Replace((title ?? "").Trim(),
                @"[\\/:*?""<>|\x00-\x1F]", " ").Trim().TrimEnd('.');
            if (name.Length > 120) name = name.Substring(0, 120).Trim().TrimEnd('.');
            if (String.IsNullOrWhiteSpace(name))
                throw new InvalidOperationException("InspectionTypeName tidak valid untuk nama file Excel.");
            // Nama device Windows tidak dapat dipakai sebagai nama file.
            string upper = name.ToUpperInvariant();
            string deviceName = upper.Split('.')[0];
            if (deviceName == "CON" || deviceName == "PRN" || deviceName == "AUX" ||
                deviceName == "NUL" || Regex.IsMatch(deviceName, @"^(COM|LPT)[1-9]$"))
                name = "Report_" + name;
            return name + ".xlsx";
        }

        private static void Put(ExcelRange cell, string text)
        {
            text = text ?? "";
            //Mencegah Excel Injection
            if (text.Length > 0 && "=+-@".IndexOf(text[0]) >= 0) text = "'" + text;
            //Length Excelnya
            if (text.Length > 32000) text = text.Substring(0, 32000);
            cell.Style.Numberformat.Format = "@";
            cell.Value = text;
        }

        // H/V/T: tulis Value sebagai STRING Excel, bukan angka atau formula.
        // Contoh yang dipertahankan: "0,5", "01,20", "-0,75", "+1,5", "V", "ON".
        // EPPlus menulis cell.Value bertipe string; tidak mengisi cell.Formula.
        private static void PutResultValue(ExcelRange cell, string value)
        {
            string text = value ?? String.Empty;
            if (text.Length > 32000)
                text = text.Substring(0, 32000);
            cell.Style.Numberformat.Format = "@";
            cell.Value = text;
        }

        public void Toolbar_Click(object sender, ToolBarEventArgs_2 e)
        {
            switch (e.ToolbarItem)
            {
                case ToolbarItem_2.Refresh:
                    //PrepareScreen();
                    break;
                case ToolbarItem_2.Print:
                    _printReport();
                    break;
            }
        }

        private void InitToolbar()
        {
            Master.TB_VisibleToolbar(true);
            Master.TB_VisibleButton(ToolbarItem_2.Refresh, true);
            Master.TB_VisibleButton(ToolbarItem_2.Print, true);
        }

        // DEBUG LOKAL: tombol Print pada halaman MasterPage B memanggil
        // method publik yang SAMA dengan Preview milik rekan (MasterPage A).
        private void _printReport()
        {
            lblError.Text = String.Empty;
            try
            {
                DataTable selectedInspections = new DataTable();
                selectedInspections.Columns.Add("InspectionID", typeof(long));
                foreach (DataGridItem item in gridAppReport.Items)
                {
                    CheckBox chk = item.FindControl("_chkboxupdateGridH") as CheckBox;
                    Label lbl = item.FindControl("_lblInspectionID") as Label;
                    if (chk == null || lbl == null)
                        throw new InvalidOperationException("Checkbox/InspectionID tidak ditemukan pada DataGrid.");
                    if (chk.Checked && !String.IsNullOrWhiteSpace(lbl.Text))
                        selectedInspections.Rows.Add(
                            Int64.Parse(lbl.Text.Trim(), CultureInfo.InvariantCulture));
                }

                // Uji API empat parameter yang sama dengan halaman Preview supervisor.
                // Company/Location diambil dari login halaman ini, bukan dari DataTable.
                string companyId = GetMasterLoginValue(Master, "Mn_CompanyID");
                string locationId = GetMasterLoginValue(Master, "Mn_LocationID");
                ReportFileResult result = GenerateInspectionXlsx(
                    selectedInspections, companyId, locationId, Master.Mn_UserID);
                if (!result.Success)
                {
                    lblError.ForeColor = Color.Red;
                    lblError.Text = Server.HtmlEncode(result.Message);
                    return;
                }

                // Preview sederhana; ukuran dan jumlah worksheet hanya dicatat di Trace.
                // Link manual tetap ada kalau browser memblokir popup.
                string fileUrl = GetInspectionFileUrl(result);
                string safeUrlHtml = HttpUtility.HtmlAttributeEncode(fileUrl);
                lblError.ForeColor = Color.Green;
                lblError.Text = "DEBUG OK - " +
                    selectedInspections.Rows.Count +
                    " InspectionID (DataTable). <a href=\"" + safeUrlHtml +
                    "\" target=\"_blank\" rel=\"noopener\">Buka / Download Excel</a>";

                string jsUrl = HttpUtility.JavaScriptStringEncode(fileUrl);
                string script = "if (typeof openWindow === 'function') { " +
                    "openWindow('" + jsUrl + "', '_blank',800,600,'yes','yes'); " +
                    "} else { window.open('" + jsUrl + "', '_blank'); }";
                // UpdatePanel: ClientScript biasa tidak selalu dijalankan setelah async postback.
                if (ScriptManager.GetCurrent(Page) != null)
                    ScriptManager.RegisterStartupScript(Page, Page.GetType(),
                        "InspectionExcelOpen", script, true);
                else
                    ClientScript.RegisterStartupScript(GetType(),
                        "InspectionExcelOpen", script, true);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Trace.TraceError("_printReport: " + ex);
                lblError.ForeColor = Color.Red;
                lblError.Text = "Gagal membuat Excel: " +
                    Server.HtmlEncode(ex.GetBaseException().Message);
            }
        }

        private void UpdateViewGridReport()
        {
            txtMaxRecord.Text = (GF.IsNumeric(txtMaxRecord.Text.Trim()) && Convert.ToInt16(txtMaxRecord.Text.Trim()) > 0 ? Convert.ToString(Convert.ToInt16(txtMaxRecord.Text.Trim())) : "50");

            using (WAL.BR.CF ocf = new WAL.BR.CF())
            {
                DataTable V_gd = (ocf.EQuery(
                                "SELECT " +
                                "    InspectionID, ClientInspectionID,  " +
                                "    InspectionNo,  " +
                                "    CompanyID,  " +
                                "    LocationID,  " +
                                "    SectionID, InspectionTypeCode, InspectionTypeName, InspectionTypeDetailCode,  " +
                                "    InspectionTypeDetailName, InspectionDate, TemplateNo, InspectionTypeName, TemplateName, [Status] " +
                                "FROM PIP_T_Inspection "
                               ));
                gridAppReport.DataSource = V_gd;
                gridAppReport.DataBind();
                gridAppReport.ShowFooter = (gridAppReport.Items.Count == 0) ? true : false;

            }

            lblSearchResults.Text = "Count : " + gridAppReport.Items.Count.ToString();

        }

        protected void grdListItem_SortCommand(object source, System.Web.UI.WebControls.DataGridSortCommandEventArgs e)
        {
            if (gridAppReport.Items.Count > 0)
            {
                string sortExpression = Convert.ToString(ViewState[GF.Key_CacheSLSortExpression]);
                string sortDirection = Convert.ToString(ViewState[GF.Key_CacheSLSortExpression]);

                if (sortExpression != e.SortExpression)
                {
                    sortExpression = e.SortExpression;
                    sortDirection = "asc";
                }
                else
                {
                    if (sortDirection == "asc")
                    {
                        sortDirection = "desc";
                    }
                    else
                    {
                        sortDirection = "asc";
                    }

                }

                ViewState[GF.Key_CacheSLSortExpression] = sortExpression;
                ViewState[GF.Key_CacheSLSortExpression] = sortDirection;
                BindDataGrid(sortExpression + " " + sortDirection);
            }
        }

        protected void lbtn_Search_Click(object sender, EventArgs e)
        {
            F_Open_pnl_Search();
            GF.Focus(this.Page, txt_InspectionNo.ClientID);
        }

        protected void lBtn_S_Apply_Click(object sender, EventArgs e)
        {
            UpdateViewGridReport();
            GF.Focus(this.Page, txt_InspectionNo.ClientID);
        }
        protected void lbtn_S_Reset_Click(object sender, EventArgs e)
        {
            GF.Focus(this.Page, txt_InspectionNo.ClientID);
        }
        protected void lbtn_S_Close_Click(object sender, EventArgs e)
        {
            F_Close_pnl_Search();
            GF.Focus(this.Page, lbtn_Search.ClientID);
        }

        private void F_Open_pnl_Search()
        {
            lbtn_Search.Visible = false;
            GF.ShowPanel(ref pnl_Search, true);
        }
        private void F_Close_pnl_Search()
        {
            lbtn_Search.Visible = true;
            GF.ShowPanel(ref pnl_Search, false);
        }

        protected void lbtn_PreRender(object sender, EventArgs e)
        {
            GF.AddAttdisabled_2(sender);
        }

        private void BindDataGrid(string sortExpression)
        {
            DataView dv = (DataView)Session[GF.Key_CacheSLDictatedDV];

            if (sortExpression.Length > 0)
            {
                dv.Sort = sortExpression;
                Session[GF.Key_CacheSLDictatedDV] = dv;
            }

            gridAppReport.DataSource = dv;
            gridAppReport.DataBind();

        }

        protected void TextBox_TextChanged(object sender, System.EventArgs e)
        {
            TextBox a = (TextBox)sender;
            switch (a.ID)
            {
                case "txtMaxRecord":
                    UpdateViewGridReport();
                    GF.Focus(this.Page, txtMaxRecord.ClientID);
                    break;
            }
        }
    }

    public sealed class ReportFileResult
    {
        public bool Success { get; set; }
        public string Status { get; set; }
        public string FileName { get; set; }
        public string StoragePath { get; set; }
        public string Message { get; set; }
    }
}

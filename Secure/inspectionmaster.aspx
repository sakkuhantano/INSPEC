<%@ Page Title="" Language="C#" MasterPageFile="~/MasterPages/Site_BS_5.Master" AutoEventWireup="true" CodeBehind="inspectionmaster.aspx.cs" Inherits="INSPEC.Secure.inspectionmaster" %>
<%@ MasterType VirtualPath="~/MasterPages/Site_BS_5.Master" %>
<%@ Register Src="~/UserControls/UC_FilterSearchList_2.ascx" TagPrefix="uc1" TagName="UC_FilterSearchList_2" %>
<asp:Content ID="Content1" ContentPlaceHolderID="head" runat="server">
    <link href="../CSSCus/inspectionmaster.css" rel="stylesheet" />
    <script src="../JSCus/pdf.min.js"></script>
    <script src="../JSCus/inspectionmaster.js"></script>
</asp:Content>
<asp:Content ID="Content2" ContentPlaceHolderID="ContentPlaceHolder1" runat="server">
    <asp:HiddenField ID="hidActiveTab" runat="server" ClientIDMode="Static" Value="#tab-map" />
    <asp:HiddenField ID="hidMapID" runat="server" ClientIDMode="Static" />
    <asp:HiddenField ID="hidMapIsDraft" runat="server" ClientIDMode="Static" Value="0" />
    <asp:HiddenField ID="hidPointID" runat="server" />
    <asp:HiddenField ID="hidElementID" runat="server" />
    <div class="d-none">
        <asp:DropDownList ID="ddlPointObjectType" runat="server"><asp:ListItem Value="GENERAL" Selected="True">General</asp:ListItem></asp:DropDownList>
        <asp:DropDownList ID="ddlPointMap" runat="server" />
        <asp:DropDownList ID="ddlEditorMap" runat="server" />
    </div>
    <asp:Panel ID="pnlMessage" runat="server" Visible="false" CssClass="alert alert-info alert-dismissible fade show mb-3">
        <asp:Literal ID="litMessage" runat="server" />
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </asp:Panel>

    <table border="0" cellspacing="0" cellpadding="0" style="width:100%;">
        <tr><td>
            <div class="row border rounded shadow-sm" style="margin:auto;">
                <div class="col">
                    <div class="row my-1">
                        <div class="col-sm-6 mb-1">
                            <div class="row mt-1">
                                <div class="col-sm-4 d-flex align-items-center">
                                    <asp:LinkButton ID="lBtnMapCode" runat="server" Text="Map Code" OnPreRender="lbtn_PreRender" CssClass="CUS-lbtn-1" />
                                </div>
                                <div class="col-sm-8">
                                    <asp:TextBox ID="txtMapCode" runat="server" ClientIDMode="Static" MaxLength="50" AutoPostBack="true" OnTextChanged="txtMapCode_TextChanged" CssClass="form-control form-control-sm rounded fz-custom1" />
                                </div>
                            </div>
                            <div class="row mt-1">
                                <div class="col-sm-4 d-flex align-items-center">Map Name</div>
                                <div class="col-sm-8">
                                    <asp:TextBox ID="txtMapName" runat="server" MaxLength="200" CssClass="form-control form-control-sm rounded fz-custom1" />
                                </div>
                            </div>
                            <div class="row mt-1">
                                <div class="col-sm-4 d-flex align-items-center">Map Description <i class="fas fa-info-circle text-muted ms-1" data-bs-toggle="tooltip" data-bs-placement="top" title="Keterangan tambahan tentang cakupan atau lokasi denah. Contoh: Denah area parkir basement lantai P1. Tidak perlu mengulang Map Name." aria-label="Panduan Map Description"></i></div>
                                <div class="col-sm-8">
                                    <asp:TextBox ID="txtMapDescription" runat="server" MaxLength="500" CssClass="form-control form-control-sm rounded fz-custom1" />
                                </div>
                            </div>
                                        <div class="row mt-1">
                                            <div class="col-sm-4 d-flex align-items-center">
                                                <asp:LinkButton ID="lBtnInspectionType" runat="server" Text="Inspection Type" OnPreRender="lbtn_PreRender" CssClass="CUS-lbtn-1" />
                                            </div>
                                            <div class="col-sm-8">
                                                <asp:DropDownList ID="ddlInspectionType" runat="server" CssClass="form-select form-select-sm rounded fz-custom1" AutoPostBack="true" OnSelectedIndexChanged="ddlInspectionType_SelectedIndexChanged" />
                                            </div>
                                        </div>
                                        <div class="row mt-1">
                                            <div class="col-sm-4 d-flex align-items-center">Inspection Detail</div>
                                            <div class="col-sm-8">
                                                <asp:DropDownList ID="ddlInspectionDetail" runat="server" CssClass="form-select form-select-sm rounded fz-custom1" />
                                            </div>
                                        </div>
                            <div class="row mt-1">
                                <div class="col-sm-4 d-flex align-items-center">Inspection Coverage</div>
                                <div class="col-sm-8">
                                    <asp:CheckBox ID="chkRequireAllPoints" runat="server" Text=" Semua titik wajib diinspeksi" Checked="true" />
                                    <div class="form-text small">Centang untuk lampu dan objek yang seluruhnya harus dites. Kosongkan untuk car park: hanya titik yang ada kendaraan perlu diinspeksi.</div>
                                </div>
                            </div>
                        </div>
                        <div class="col-sm-6 mb-1">
                            <div class="row mt-1">
                                <div class="col-sm-4 d-flex align-items-center">Floor Plan (PDF / JPG) <span class="text-muted small">(optional)</span></div>
                                <div class="col-sm-8">
                                    <asp:FileUpload ID="fuMapPdf" runat="server" ClientIDMode="Static" CssClass="form-control form-control-sm rounded fz-custom1" accept=".pdf,.jpg,.jpeg,application/pdf,image/jpeg" />
                                    <asp:LinkButton ID="btnClearMapFile" runat="server" CssClass="btn btn-sm btn-outline-secondary mt-1" OnClick="btnClearMapFile_Click" CausesValidation="false"><i class="fas fa-eraser"></i> Clear Floor Plan</asp:LinkButton>
                                </div>
                            </div>
                            <div class="row mt-1">
                                <div class="col-sm-4 d-flex align-items-center">Version</div>
                                <div class="col-sm-8 d-flex align-items-center">
                                    <asp:Label ID="lblMapVersion" runat="server" CssClass="small text-muted" />
                                </div>
                            </div>
                        </div>
                    </div>



                    <asp:Panel ID="pnlPointEditor" runat="server" Visible="false" CssClass="modal fade" ClientIDMode="Static" role="dialog" aria-labelledby="inspectionPointModalTitle" tabindex="-1">
                        <div class="modal-dialog modal-xl modal-dialog-centered modal-dialog-scrollable inspection-point-dialog" role="document">
                            <div class="modal-content inspection-point-modal-content">
                                <div class="modal-header py-2">
                                    <div>
                                        <h5 class="modal-title fs-6 mb-0" id="inspectionPointModalTitle">Inspection Point</h5>
                                        <div class="small text-muted">Isi data point. Koordinat hanya perlu diisi jika point akan diplot pada denah.</div>
                                    </div>
                                    <asp:LinkButton ID="btnNewPoint" runat="server" CssClass="btn-close" OnClick="btnClosePoint_Click" CausesValidation="false" ToolTip="Close" />
                                </div>
                                <div class="modal-body inspection-point-modal-body">
                                <div class="row my-1">
                                    <div class="col-sm-6 mb-1">
                                        <div class="row mt-1">
                                            <div class="col-sm-4 d-flex align-items-center">Point Code</div>
                                            <div class="col-sm-8"><asp:TextBox ID="txtPointCode" runat="server" MaxLength="50" CssClass="form-control form-control-sm rounded fz-custom1" /></div>
                                        </div>
                                        <div class="row mt-1">
                                            <div class="col-sm-4 d-flex align-items-center">Point Name</div>
                                            <div class="col-sm-8"><asp:TextBox ID="txtPointName" runat="server" MaxLength="200" CssClass="form-control form-control-sm rounded fz-custom1" /></div>
                                        </div>
                                    </div>
                                    <div class="col-sm-6 mb-1">
                                        <div class="row mt-1">
                                            <div class="col-sm-4 d-flex align-items-center">Object Reference <i class="fas fa-info-circle text-muted ms-1" data-bs-toggle="tooltip" data-bs-placement="top" title="Kode referensi aset atau objek fisik jika tersedia, misalnya nomor aset, tag equipment, atau kode lampu. Opsional; boleh dikosongkan jika tidak ada." aria-label="Panduan Object Reference"></i></div>
                                            <div class="col-sm-8"><asp:TextBox ID="txtObjectReferenceCode" runat="server" MaxLength="100" CssClass="form-control form-control-sm rounded fz-custom1" /></div>
                                        </div>
                                        <div class="row mt-1">
                                            <div class="col-sm-4 d-flex align-items-center">Point Description <i class="fas fa-info-circle text-muted ms-1" data-bs-toggle="tooltip" data-bs-placement="top" title="Keterangan spesifik untuk titik inspeksi ini, misalnya posisi detail, ciri lokasi, atau instruksi identifikasi. Contoh: Lampu di atas pintu masuk basement. Tidak perlu mengulang Point Name. Opsional." aria-label="Panduan Point Description"></i></div>
                                            <div class="col-sm-8"><asp:TextBox ID="txtPointDescription" runat="server" MaxLength="500" TextMode="MultiLine" Rows="2" CssClass="form-control form-control-sm rounded fz-custom1" /></div>
                                        </div>
                                        <div class="row mt-1">
                                            <div class="col-sm-4 d-flex align-items-center">Display Order</div>
                                            <div class="col-sm-8"><asp:TextBox ID="txtPointOrder" runat="server" Text="0" CssClass="form-control form-control-sm rounded fz-custom1" /></div>
                                        </div>
                                        <div class="row mt-1">
                                            <div class="col-sm-4"></div>
                                            <div class="col-sm-8"><asp:CheckBox ID="chkNormalAbnormalRequired" runat="server" Text=" Require Normal / Abnormal selection" Checked="false" /></div>
                                        </div>
                                    </div>
                                </div>
                                <asp:HiddenField ID="hidSwapPointID" runat="server" ClientIDMode="Static" />
                                <asp:Panel ID="pnlEditor" runat="server" Visible="false" CssClass="mt-2">
                                    <div class="border rounded p-2">
                                        <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-2">
                                            <div class="fw-bold small">Map Coordinate <span class="text-muted fw-normal">(optional)</span> <asp:Label ID="lblPointMapCode" runat="server" CssClass="text-muted fw-normal" /></div>
                                            <div class="inspection-map-toolbar d-flex align-items-center gap-1">
                                                <button type="button" class="btn btn-sm btn-outline-secondary" id="btnMapZoomOut" title="Zoom out"><i class="bi bi-zoom-out"></i></button>
                                                <button type="button" class="btn btn-sm btn-outline-secondary" id="btnMapZoomIn" title="Zoom in"><i class="bi bi-zoom-in"></i></button>
                                                <button type="button" class="btn btn-sm btn-outline-secondary" id="btnMapZoomFit">Fit</button>
                                                <span class="small text-muted" id="lblMapZoom">100%</span>
                                                <asp:HyperLink ID="lnkEditorPdf" runat="server" Target="_blank" CssClass="CUS-lbtn-1" Visible="false">Open PDF</asp:HyperLink>
                                            </div>
                                        </div>
                                        <div class="inspection-coordinate-board" id="inspectionCoordinateBoard" title="Klik bidang denah untuk menentukan koordinat Inspection Point aktif">
                                            <div class="inspection-coordinate-content" id="inspectionCoordinateContent">
                                                <asp:Literal ID="litEditorPdfBackground" runat="server" />
                                                <div class="inspection-coordinate-grid"></div>
                                                <asp:Repeater ID="rptMapElements" runat="server">
                                                    <ItemTemplate>
                                                        <button type="button" class='inspection-coordinate-marker <%# Convert.ToString(Eval("InspectionPointID")) == hidPointID.Value ? "inspection-coordinate-marker-current" : "" %>'
                                                            style='left:<%# Eval("XPercent") %>%;top:<%# Eval("YPercent") %>%;'
                                                            data-point-id='<%# Eval("InspectionPointID") %>' data-can-swap='<%# Eval("CanSwap") %>'
                                                            title='<%# Eval("PointCode") + " - " + Eval("PointName") %>'>
                                                            <%# Eval("MarkerLabel") %>
                                                        </button>
                                                    </ItemTemplate>
                                                </asp:Repeater>
                                            </div>
                                        </div>
                                        <div class="inspection-coordinate-hint" role="note">
                                            <span><i class="fas fa-circle text-primary"></i> Point lain</span>
                                            <span><i class="fas fa-circle text-warning"></i> Point aktif</span>
                                            <span><i class="fas fa-circle text-success"></i> Posisi baru</span>
                                            <span class="inspection-coordinate-hint-action">Klik marker lain untuk Swap</span>
                                        </div>
                                        <div class="row g-2 mt-2 align-items-end">
                                            <div class="col-6 col-md-2"><label class="small">X (%)</label><asp:TextBox ID="txtMarkerX" runat="server" ClientIDMode="Static" CssClass="form-control form-control-sm" /></div>
                                            <div class="col-6 col-md-2"><label class="small">Y (%)</label><asp:TextBox ID="txtMarkerY" runat="server" ClientIDMode="Static" CssClass="form-control form-control-sm" /></div>
                                            <div class="col-12 col-md d-flex flex-wrap align-items-center gap-2">
                                                <button type="button" id="btnClearCoordinate" class="btn btn-sm btn-outline-secondary"><i class="fas fa-eraser"></i> Clear Coordinate</button>
                                                <asp:LinkButton ID="btnSwapPosition" runat="server" CssClass="btn btn-sm btn-outline-warning" OnClick="btnSwapPosition_Click" CausesValidation="false"><i class="fas fa-exchange-alt"></i> Swap with selected marker</asp:LinkButton>
                                                <span id="lblSwapTarget" class="small text-muted">Klik marker lain untuk memilih target swap.</span>
                                            </div>
                                        </div>
                                    </div>
                                </asp:Panel>
                                </div>
                                <div class="modal-footer py-2 inspection-point-modal-footer">
                                    <span class="small text-muted me-auto">Koordinat tersimpan setelah tombol Save ditekan.</span>
                                    <asp:LinkButton ID="btnSavePoint" runat="server" CssClass="btn btn-primary btn-sm px-4" OnClick="btnSavePoint_Click"><i class="fas fa-save"></i> Save Inspection Point</asp:LinkButton>
                                </div>
                            </div>
                        </div>
                    </asp:Panel>

                    <div class="row my-1">
                        <div class="col border rounded shadow-sm">
                            <div class="row font-weight-bold bg-custom20" style="height:30px;border-bottom:1px solid #dee2e6;">
                                <div class="col-sm-5 d-flex align-items-center">Inspection Points</div>
                                <div class="col-sm-7 d-flex justify-content-end align-items-center">
                                    <div class="input-group input-group-sm" style="width:250px;">
                                        <asp:TextBox ID="txtPointSearch" runat="server" CssClass="form-control form-control-sm fz-custom1" MaxLength="50" placeholder="Search Point Code" />
                                        <asp:LinkButton ID="btnSearchPoint" runat="server" CssClass="btn btn-sm CUS-btn-outline-PColor-1" OnClick="btnSearchPoint_Click" CausesValidation="false"><i class="fas fa-search"></i></asp:LinkButton>
                                    </div>
                                    <asp:DropDownList ID="ddlPointPageSize" runat="server" CssClass="form-select form-select-sm ms-1" Width="75px" AutoPostBack="true" OnSelectedIndexChanged="ddlPointPageSize_SelectedIndexChanged">
                                        <asp:ListItem Value="10">10</asp:ListItem>
                                        <asp:ListItem Value="20" Selected="True">20</asp:ListItem>
                                        <asp:ListItem Value="50">50</asp:ListItem>
                                        <asp:ListItem Value="100">100</asp:ListItem>
                                    </asp:DropDownList>
                                    <asp:LinkButton ID="btnNewPointGrid" runat="server" CssClass="btn btn-sm CUS-btn-outline-PColor-1 ms-1 py-1 px-3 CUS-fz-5 CUS-BorRad-4" OnClick="btnNewPointGrid_Click" CausesValidation="false"><i class="fas fa-plus-circle"></i> Add Point</asp:LinkButton>
                                </div>
                            </div>
                            <div class="row">
                                <div class="col">
                                    <asp:GridView ID="gvPoints" runat="server" AutoGenerateColumns="false" BorderColor="#394376" BorderWidth="0" GridLines="None" CssClass="table-sm table-borderless mb-0 w-100" OnRowCommand="gvPoints_RowCommand" EmptyDataText="No Inspection Point">
                                        <HeaderStyle HorizontalAlign="left" CssClass="CUS-fz-5 dtgrdhd-custom1 CUS-bg-Color-1" />
                                        <RowStyle HorizontalAlign="left" VerticalAlign="Top" CssClass="CUS-fz-5 dtgrddt-custom1" />
                                        <AlternatingRowStyle HorizontalAlign="left" VerticalAlign="Top" CssClass="CUS-fz-5 dtgrddtalt-custom1" />
                                        <Columns>
                                            <asp:TemplateField HeaderText="" HeaderStyle-Width="1%" ItemStyle-Width="1%">
                                                <ItemTemplate>
                                                    <asp:LinkButton ID="btnEditPointRow" runat="server" CssClass="CUS-lbtn-1" ToolTip="Edit Inspection Point" CommandName="EditPoint" CommandArgument='<%# Eval("InspectionPointID") %>' CausesValidation="false"><i class="far fa-edit"></i></asp:LinkButton>
                                                </ItemTemplate>
                                            </asp:TemplateField>
                                            <asp:TemplateField HeaderText="" HeaderStyle-Width="1%" ItemStyle-Width="1%">
                                                <ItemTemplate>
                                                    <asp:LinkButton ID="btnDeletePointRow" runat="server" CssClass="text-danger" ToolTip="Nonaktifkan Inspection Point" CommandName="DeletePoint" CommandArgument='<%# Eval("InspectionPointID") %>' CausesValidation="false" OnClientClick="return confirm('Nonaktifkan Inspection Point ini?');"><i class="far fa-trash-alt"></i></asp:LinkButton>
                                                </ItemTemplate>
                                            </asp:TemplateField>
                                            <asp:BoundField DataField="PointCode" HeaderText="Point Code" />
                                            <asp:BoundField DataField="PointName" HeaderText="Point Name" />
                                            <asp:BoundField DataField="ObjectReferenceCode" HeaderText="Object Reference" />
                                            <asp:BoundField DataField="DisplayOrder" HeaderText="Order" />
                                            <asp:TemplateField HeaderText="N/Abn" HeaderStyle-Width="6%" ItemStyle-HorizontalAlign="Center">
                                                <ItemTemplate><%# Convert.ToBoolean(Eval("IsNormalAbnormalRequired")) ? "Yes" : "-" %></ItemTemplate>
                                            </asp:TemplateField>
                                        </Columns>
                                    </asp:GridView>
                                </div>
                            </div>
                            <div class="row my-1">
                                <div class="col-sm-5 small text-muted d-flex align-items-center">
                                    <asp:Label ID="lblPointPageInfo" runat="server" />
                                </div>
                                <div class="col-sm-7 d-flex justify-content-end align-items-center">
                                    <asp:Panel ID="pnlPointPager" runat="server" CssClass="inspection-point-pager d-flex align-items-center gap-2">
                                        <div class="btn-group btn-group-sm" role="group" aria-label="Inspection point pages">
                                            <asp:LinkButton ID="btnPointFirst" runat="server" CssClass="btn btn-outline-secondary" OnClick="btnPointFirst_Click" CausesValidation="false" ToolTip="First page"><i class="fas fa-angle-double-left"></i></asp:LinkButton>
                                            <asp:LinkButton ID="btnPointPrevious" runat="server" CssClass="btn btn-outline-secondary" OnClick="btnPointPrevious_Click" CausesValidation="false" ToolTip="Previous page"><i class="fas fa-angle-left"></i></asp:LinkButton>
                                            <asp:LinkButton ID="btnPointNext" runat="server" CssClass="btn btn-outline-secondary" OnClick="btnPointNext_Click" CausesValidation="false" ToolTip="Next page"><i class="fas fa-angle-right"></i></asp:LinkButton>
                                            <asp:LinkButton ID="btnPointLast" runat="server" CssClass="btn btn-outline-secondary" OnClick="btnPointLast_Click" CausesValidation="false" ToolTip="Last page"><i class="fas fa-angle-double-right"></i></asp:LinkButton>
                                        </div>
                                        <div class="input-group input-group-sm inspection-point-goto">
                                            <span class="input-group-text">Page</span>
                                            <asp:TextBox ID="txtPointGoToPage" runat="server" CssClass="form-control text-center" Text="1" />
                                            <asp:LinkButton ID="btnPointGoToPage" runat="server" CssClass="btn btn-primary" OnClick="btnPointGoToPage_Click" CausesValidation="false">Go</asp:LinkButton>
                                        </div>
                                        <asp:Label ID="lblPointPageTotal" runat="server" CssClass="small text-muted text-nowrap" />
                                    </asp:Panel>
                                </div>
                            </div>
                        </div>
                    </div>

                    <asp:Panel ID="pnlMapPreview" runat="server" Visible="false">
                        <div class="row my-1">
                            <div class="col border rounded shadow-sm">
                                <div class="row font-weight-bold bg-custom20" style="height:30px;border-bottom:1px solid #dee2e6;">
                                    <div class="col d-flex align-items-center">
                                        <asp:Label ID="lblMapPreviewTitle" runat="server" />
                                    </div>
                                    <div class="col-auto d-flex align-items-center">
                                        <asp:HyperLink ID="lnkMapPdf" runat="server" Target="_blank" CssClass="CUS-lbtn-1">Open PDF</asp:HyperLink>
                                    </div>
                                </div>
                                <div class="p-2">
                                    <asp:Literal ID="litMapPreview" runat="server" />
                                </div>
                            </div>
                        </div>
                    </asp:Panel>

                </div>
            </div>
        </td></tr>
    </table>
</asp:Content>

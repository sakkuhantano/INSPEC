<%@ Page Title="" Language="C#" MasterPageFile="~/MasterPages/Site_BS_5.Master" AutoEventWireup="true" CodeBehind="inspectionmaster.aspx.cs" Inherits="INSPEC.Secure.inspectionmaster" %>
<%@ MasterType VirtualPath="~/MasterPages/Site_BS_5.Master" %>
<asp:Content ID="Content1" ContentPlaceHolderID="head" runat="server">
    <link href="../CSSCus/inspectionmaster.css" rel="stylesheet" />
    <script src="../JSCus/pdf.min.js"></script>
    <script src="../JSCus/inspectionmaster.js"></script>
</asp:Content>
<asp:Content ID="Content2" ContentPlaceHolderID="ContentPlaceHolder1" runat="server">
    <asp:HiddenField ID="hidActiveTab" runat="server" ClientIDMode="Static" Value="#tab-map" />
    <asp:HiddenField ID="hidMapID" runat="server" />
    <asp:HiddenField ID="hidPointID" runat="server" />
    <asp:HiddenField ID="hidElementID" runat="server" />
    <asp:Panel ID="pnlMessage" runat="server" Visible="false" CssClass="alert alert-info alert-dismissible fade show mb-3">
        <asp:Literal ID="litMessage" runat="server" />
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    </asp:Panel>

    <div class="inspection-master-heading mb-3">
        <div>
            <div class="text-muted small">INSPECTION CONFIGURATION</div>
            <h4 class="mb-1">Inspection Setup</h4>
            <div class="text-muted small">Kelola denah, titik inspeksi, dan posisi titik pada denah.</div>
        </div>
        <span class="badge text-bg-light border"><i class="bi bi-diagram-3 me-1"></i> Master Data</span>
    </div>

    <ul class="nav nav-tabs inspection-master-tabs" id="inspectionMasterTabs" role="tablist">
        <li class="nav-item" role="presentation">
            <button class="nav-link active" id="tab-map-link" data-bs-toggle="tab" data-bs-target="#tab-map" type="button" role="tab">
                <i class="bi bi-file-earmark-pdf me-1"></i> Map PDF
            </button>
        </li>
        <li class="nav-item" role="presentation">
            <button class="nav-link" id="tab-point-link" data-bs-toggle="tab" data-bs-target="#tab-point" type="button" role="tab">
                <i class="bi bi-geo-alt me-1"></i> Inspection Point
            </button>
        </li>
        <li class="nav-item" role="presentation">
            <button class="nav-link" id="tab-editor-link" data-bs-toggle="tab" data-bs-target="#tab-editor" type="button" role="tab">
                <i class="bi bi-pin-map me-1"></i> Map Editor
            </button>
        </li>
    </ul>

    <div class="tab-content inspection-master-content">
        <div class="tab-pane fade show active" id="tab-map" role="tabpanel">
            <div class="row g-3">
                <div class="col-xl-5">
                    <div class="card border-0 shadow-sm h-100">
                        <div class="card-header bg-white fw-semibold">Map Information</div>
                        <div class="card-body">
                            <div class="mb-3">
                                <label class="form-label">Map Code</label>
                                <asp:TextBox ID="txtMapCode" runat="server" CssClass="form-control" MaxLength="50" />
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Map Name</label>
                                <asp:TextBox ID="txtMapName" runat="server" CssClass="form-control" MaxLength="200" />
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Description</label>
                                <asp:TextBox ID="txtMapDescription" runat="server" CssClass="form-control" TextMode="MultiLine" Rows="3" MaxLength="500" />
                            </div>
                            <div class="mb-3">
                                <label class="form-label">PDF Floor Plan</label>
                                <asp:FileUpload ID="fuMapPdf" runat="server" CssClass="form-control" accept=".pdf,application/pdf" />
                                <div class="form-text">PDF maksimal 50 MB. Upload PDF baru pada map yang sudah ada akan membuat versi baru.</div>
                            </div>
                            <div class="d-flex flex-wrap gap-2">
                                <asp:LinkButton ID="btnSaveMap" runat="server" CssClass="btn btn-primary" OnClick="btnSaveMap_Click"><i class="bi bi-save me-1"></i> Save Map</asp:LinkButton>
                                <asp:LinkButton ID="btnNewMap" runat="server" CssClass="btn btn-outline-secondary" OnClick="btnNewMap_Click"><i class="bi bi-plus-lg me-1"></i> New</asp:LinkButton>
                            </div>
                            <asp:Label ID="lblMapVersion" runat="server" CssClass="small text-muted d-block mt-3" />
                        </div>
                    </div>
                </div>
                <div class="col-xl-7">
                    <div class="card border-0 shadow-sm h-100">
                        <div class="card-header bg-white d-flex justify-content-between align-items-center">
                            <span class="fw-semibold">Registered Maps</span>
                            <asp:LinkButton ID="btnRefreshMap" runat="server" CssClass="btn btn-sm btn-outline-secondary" OnClick="btnRefreshMap_Click"><i class="bi bi-arrow-clockwise"></i> Refresh</asp:LinkButton>
                        </div>
                        <div class="card-body p-0">
                            <div class="table-responsive">
                                <asp:GridView ID="gvMaps" runat="server" AutoGenerateColumns="false" CssClass="table table-hover align-middle mb-0 inspection-master-grid"
                                    GridLines="None" EmptyDataText="Belum ada denah.">
                                    <Columns>
                                        <asp:BoundField DataField="MapCode" HeaderText="Code" />
                                        <asp:BoundField DataField="MapName" HeaderText="Map Name" />
                                        <asp:BoundField DataField="MapVersion" HeaderText="Version" />
                                        <asp:TemplateField HeaderText="Status">
                                            <ItemTemplate><span class="badge <%# Convert.ToBoolean(Eval("IsActive")) ? "text-bg-success" : "text-bg-secondary" %>"><%# Convert.ToBoolean(Eval("IsActive")) ? "Active" : "Inactive" %></span></ItemTemplate>
                                        </asp:TemplateField>
                                        <asp:TemplateField HeaderText="" ItemStyle-CssClass="text-end text-nowrap">
                                            <ItemTemplate>
                                                <asp:LinkButton ID="btnEditMapRow" runat="server" CssClass="btn btn-sm btn-outline-primary" CommandArgument='<%# Eval("MapID") %>' CausesValidation="false" OnCommand="btnEditMapRow_Command"><i class="bi bi-pencil"></i></asp:LinkButton>
                                                <asp:LinkButton ID="btnOpenMapRow" runat="server" CssClass="btn btn-sm btn-outline-secondary" CommandArgument='<%# Eval("MapID") %>' CausesValidation="false" OnCommand="btnOpenMapRow_Command"><i class="bi bi-eye"></i></asp:LinkButton>
                                            </ItemTemplate>
                                        </asp:TemplateField>
                                    </Columns>
                                </asp:GridView>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            <asp:Panel ID="pnlMapPreview" runat="server" Visible="false" CssClass="card border-0 shadow-sm mt-3">
                <div class="card-header bg-white d-flex justify-content-between align-items-center">
                    <asp:Label ID="lblMapPreviewTitle" runat="server" CssClass="fw-semibold" />
                    <asp:HyperLink ID="lnkMapPdf" runat="server" Target="_blank" CssClass="btn btn-sm btn-outline-primary">Open PDF <i class="bi bi-box-arrow-up-right ms-1"></i></asp:HyperLink>
                </div>
                <div class="card-body p-2">
                    <asp:Literal ID="litMapPreview" runat="server" />
                </div>
            </asp:Panel>
        </div>

        <div class="tab-pane fade" id="tab-point" role="tabpanel">
            <div class="row g-3">
                <div class="col-xl-4">
                    <div class="card border-0 shadow-sm">
                        <div class="card-header bg-white fw-semibold">Inspection Point Information</div>
                        <div class="card-body">
                            <div class="mb-3">
                                <label class="form-label">Inspection Type</label>
                                <asp:DropDownList ID="ddlInspectionType" runat="server" CssClass="form-select" AutoPostBack="true" OnSelectedIndexChanged="ddlInspectionType_SelectedIndexChanged" />
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Inspection Detail</label>
                                <asp:DropDownList ID="ddlInspectionDetail" runat="server" CssClass="form-select" />
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Point Code</label>
                                <asp:TextBox ID="txtPointCode" runat="server" CssClass="form-control" MaxLength="50" />
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Point Name</label>
                                <asp:TextBox ID="txtPointName" runat="server" CssClass="form-control" MaxLength="200" />
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Object Type</label>
                                <asp:DropDownList ID="ddlPointObjectType" runat="server" CssClass="form-select">
                                    <asp:ListItem Value="GENERAL">General / Area</asp:ListItem>
                                    <asp:ListItem Value="LIGHTING">Lighting</asp:ListItem>
                                    <asp:ListItem Value="PARKING_BAY">Parking Bay</asp:ListItem>
                                    <asp:ListItem Value="EQUIPMENT">Equipment</asp:ListItem>
                                    <asp:ListItem Value="OTHER">Other</asp:ListItem>
                                </asp:DropDownList>
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Linked Map</label>
                                <asp:DropDownList ID="ddlPointMap" runat="server" CssClass="form-select" />
                                <div class="form-text">Opsional. Point tanpa map tetap dapat dipakai untuk inspeksi gaya lama.</div>
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Object Reference Code</label>
                                <asp:TextBox ID="txtObjectReferenceCode" runat="server" CssClass="form-control" MaxLength="100" />
                            </div>
                            <div class="mb-3">
                                <label class="form-label">Description</label>
                                <asp:TextBox ID="txtPointDescription" runat="server" CssClass="form-control" TextMode="MultiLine" Rows="2" MaxLength="500" />
                            </div>
                            <div class="row g-2">
                                <div class="col-6">
                                    <label class="form-label">Display Order</label>
                                    <asp:TextBox ID="txtPointOrder" runat="server" CssClass="form-control" Text="0" />
                                </div>
                                <div class="col-6 d-flex align-items-end pb-2">
                                    <asp:CheckBox ID="chkPointActive" runat="server" Text=" Active" Checked="true" />
                                </div>
                            </div>
                            <div class="d-flex flex-wrap gap-2 mt-3">
                                <asp:LinkButton ID="btnSavePoint" runat="server" CssClass="btn btn-primary" OnClick="btnSavePoint_Click"><i class="bi bi-save me-1"></i> Save Point</asp:LinkButton>
                                <asp:LinkButton ID="btnNewPoint" runat="server" CssClass="btn btn-outline-secondary" OnClick="btnNewPoint_Click"><i class="bi bi-plus-lg me-1"></i> New</asp:LinkButton>
                            </div>
                        </div>
                    </div>
                </div>
                <div class="col-xl-8">
                    <div class="card border-0 shadow-sm">
                        <div class="card-header bg-white fw-semibold">Inspection Points</div>
                        <div class="card-body p-0">
                            <div class="table-responsive">
                                <asp:GridView ID="gvPoints" runat="server" AutoGenerateColumns="false" CssClass="table table-hover align-middle mb-0 inspection-master-grid"
                                    GridLines="None" EmptyDataText="Belum ada inspection point." OnRowCommand="gvPoints_RowCommand">
                                    <Columns>
                                        <asp:BoundField DataField="PointCode" HeaderText="Code" />
                                        <asp:BoundField DataField="PointName" HeaderText="Point Name" />
                                        <asp:BoundField DataField="InspectionTypeCode" HeaderText="Type" />
                                        <asp:BoundField DataField="InspectionTypeDetailCode" HeaderText="Detail" />
                                        <asp:BoundField DataField="PointObjectType" HeaderText="Object" />
                                        <asp:TemplateField HeaderText="Status">
                                            <ItemTemplate><span class="badge <%# Convert.ToBoolean(Eval("IsActive")) ? "text-bg-success" : "text-bg-secondary" %>"><%# Convert.ToBoolean(Eval("IsActive")) ? "Active" : "Inactive" %></span></ItemTemplate>
                                        </asp:TemplateField>
                                        <asp:TemplateField HeaderText="" ItemStyle-CssClass="text-end text-nowrap">
                                            <ItemTemplate>
                                                <asp:LinkButton ID="btnEditPointRow" runat="server" CssClass="btn btn-sm btn-outline-primary" CommandName="EditPoint" CommandArgument='<%# Eval("InspectionPointID") %>'><i class="bi bi-pencil"></i></asp:LinkButton>
                                            </ItemTemplate>
                                        </asp:TemplateField>
                                    </Columns>
                                </asp:GridView>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <div class="tab-pane fade" id="tab-editor" role="tabpanel">
            <div class="card border-0 shadow-sm">
                <div class="card-header bg-white">
                    <div class="d-flex flex-wrap justify-content-between align-items-center gap-2"><div class="fw-semibold">Map Point Editor</div><asp:HyperLink ID="lnkEditorPdf" runat="server" Target="_blank" CssClass="btn btn-sm btn-outline-primary" Visible="false">Open selected PDF <i class="bi bi-box-arrow-up-right ms-1"></i></asp:HyperLink></div>
                    <div class="small text-muted">Pilih denah dan inspection point, lalu tentukan posisi marker pada bidang koordinat denah.</div>
                </div>
                <div class="card-body">
                    <div class="row g-3 align-items-end">
                        <div class="col-md-5">
                            <label class="form-label">Map</label>
                            <asp:DropDownList ID="ddlEditorMap" runat="server" CssClass="form-select" AutoPostBack="true" OnSelectedIndexChanged="ddlEditorMap_SelectedIndexChanged" />
                        </div>
                        <div class="col-md-5">
                            <label class="form-label">Inspection Point</label>
                            <asp:DropDownList ID="ddlEditorPoint" runat="server" CssClass="form-select" />
                        </div>
                        <div class="col-md-2">
                            <asp:LinkButton ID="btnLoadEditor" runat="server" CssClass="btn btn-outline-primary w-100" OnClick="btnLoadEditor_Click"><i class="bi bi-arrow-clockwise me-1"></i> Load</asp:LinkButton>
                        </div>
                    </div>
                    <asp:Panel ID="pnlEditor" runat="server" Visible="false" CssClass="mt-3">
                        <div class="row g-3">
                            <div class="col-lg-8">
                                <div class="inspection-map-toolbar d-flex flex-wrap align-items-center gap-2 mb-2">
                                    <button type="button" class="btn btn-sm btn-outline-secondary" id="btnMapZoomOut" title="Zoom out"><i class="bi bi-zoom-out"></i></button>
                                    <button type="button" class="btn btn-sm btn-outline-secondary" id="btnMapZoomIn" title="Zoom in"><i class="bi bi-zoom-in"></i></button>
                                    <button type="button" class="btn btn-sm btn-outline-secondary" id="btnMapZoomFit"><i class="bi bi-arrows-angle-contract me-1"></i> Fit</button>
                                    <span class="small text-muted" id="lblMapZoom">100%</span>
                                    <span class="small text-muted ms-auto">Saat zoom, drag denah untuk menggeser.</span>
                                </div>
                                <div class="inspection-coordinate-board" id="inspectionCoordinateBoard" title="Klik untuk menentukan koordinat marker">
                                    <div class="inspection-coordinate-content" id="inspectionCoordinateContent">
                                        <asp:Literal ID="litEditorPdfBackground" runat="server" />
                                        <div class="inspection-coordinate-grid"></div>
                                        <asp:Repeater ID="rptMapElements" runat="server">
                                            <ItemTemplate>
                                                <span class="inspection-coordinate-marker" style='left:<%# Eval("XPercent") %>%;top:<%# Eval("YPercent") %>%;' title='<%# Eval("PointName") %>'><%# Eval("DisplayOrder") %></span>
                                            </ItemTemplate>
                                        </asp:Repeater>
                                        <div class="inspection-coordinate-hint">Klik bidang untuk mengisi koordinat · 0–100%</div>
                                    </div>
                                </div>
                            </div>
                            <div class="col-lg-4">
                                <div class="border rounded-3 p-3">
                                    <div class="fw-semibold mb-2">Place / Update Marker</div>
                                    <div class="mb-3">
                                        <label class="form-label">X Position (%)</label>
                                        <asp:TextBox ID="txtMarkerX" runat="server" ClientIDMode="Static" CssClass="form-control" Text="50" />
                                    </div>
                                    <div class="mb-3">
                                        <label class="form-label">Y Position (%)</label>
                                        <asp:TextBox ID="txtMarkerY" runat="server" ClientIDMode="Static" CssClass="form-control" Text="50" />
                                    </div>
                                    <div class="form-text mb-3">Isi posisi relatif terhadap lebar dan tinggi denah (0 sampai 100). Marker akan tersimpan sebagai koordinat relatif sehingga tetap proporsional saat tampilan diperbesar atau diperkecil.</div>
                                    <asp:LinkButton ID="btnSaveMarker" runat="server" CssClass="btn btn-primary w-100" OnClick="btnSaveMarker_Click"><i class="bi bi-pin-angle me-1"></i> Save Marker</asp:LinkButton>
                                </div>
                            </div>
                        </div>
                        <div class="table-responsive mt-3">
                            <asp:GridView ID="gvMapElements" runat="server" AutoGenerateColumns="false" CssClass="table table-sm table-hover align-middle"
                                GridLines="None" EmptyDataText="Belum ada marker pada map ini." OnRowCommand="gvMapElements_RowCommand">
                                <Columns>
                                    <asp:BoundField DataField="PointCode" HeaderText="Point Code" />
                                    <asp:BoundField DataField="PointName" HeaderText="Point Name" />
                                    <asp:BoundField DataField="XPercent" HeaderText="X %" DataFormatString="{0:0.00}" />
                                    <asp:BoundField DataField="YPercent" HeaderText="Y %" DataFormatString="{0:0.00}" />
                                    <asp:TemplateField HeaderText="">
                                        <ItemTemplate><asp:LinkButton ID="btnEditMarker" runat="server" CssClass="btn btn-sm btn-outline-primary" CommandName="EditMarker" CommandArgument='<%# Eval("MapElementID") %>'><i class="bi bi-pencil"></i> Edit</asp:LinkButton></ItemTemplate>
                                    </asp:TemplateField>
                                </Columns>
                            </asp:GridView>
                        </div>
                    </asp:Panel>
                </div>
            </div>
        </div>
    </div>
</asp:Content>

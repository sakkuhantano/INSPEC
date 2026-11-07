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
                                <div class="col-sm-4 d-flex align-items-center">Description</div>
                                <div class="col-sm-8">
                                    <asp:TextBox ID="txtMapDescription" runat="server" MaxLength="500" CssClass="form-control form-control-sm rounded fz-custom1" />
                                </div>
                            </div>
                        </div>
                        <div class="col-sm-6 mb-1">
                            <div class="row mt-1">
                                <div class="col-sm-4 d-flex align-items-center">PDF Floor Plan</div>
                                <div class="col-sm-8">
                                    <asp:FileUpload ID="fuMapPdf" runat="server" CssClass="form-control form-control-sm rounded fz-custom1" accept=".pdf,application/pdf" />
                                </div>
                            </div>
                            <div class="row mt-1">
                                <div class="col-sm-4 d-flex align-items-center">Version</div>
                                <div class="col-sm-8 d-flex align-items-center">
                                    <asp:Label ID="lblMapVersion" runat="server" CssClass="small text-muted" />
                                </div>
                            </div>
                            <div class="row mt-1">
                                <div class="col-sm-4"></div>
                                <div class="col-sm-8">
                                    <asp:LinkButton ID="btnRefreshMap" runat="server" CssClass="btn btn-sm CUS-btn-outline-PColor-1 py-1 px-3 CUS-fz-5 CUS-BorRad-4" OnClick="btnRefreshMap_Click"><i class="fas fa-sync-alt"></i> Refresh</asp:LinkButton>
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

                    <asp:Panel ID="pnlPointEditor" runat="server" Visible="false">
                        <div class="row my-1">
                            <div class="col border rounded shadow-sm">
                                <div class="row font-weight-bold bg-custom20" style="height:30px;border-bottom:1px solid #dee2e6;">
                                    <div class="col d-flex align-items-center">Inspection Point</div>
                                    <div class="col-auto d-flex align-items-center">
                                        <asp:LinkButton ID="btnNewPoint" runat="server" CssClass="CUS-lbtn-1" OnClick="btnNewPoint_Click" CausesValidation="false"><i class="fas fa-times"></i></asp:LinkButton>
                                    </div>
                                </div>
                                <div class="row my-1">
                                    <div class="col-sm-6 mb-1">
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
                                            <div class="col-sm-4 d-flex align-items-center">Object Reference</div>
                                            <div class="col-sm-8"><asp:TextBox ID="txtObjectReferenceCode" runat="server" MaxLength="100" CssClass="form-control form-control-sm rounded fz-custom1" /></div>
                                        </div>
                                        <div class="row mt-1">
                                            <div class="col-sm-4 d-flex align-items-center">Description</div>
                                            <div class="col-sm-8"><asp:TextBox ID="txtPointDescription" runat="server" MaxLength="500" TextMode="MultiLine" Rows="2" CssClass="form-control form-control-sm rounded fz-custom1" /></div>
                                        </div>
                                        <div class="row mt-1">
                                            <div class="col-sm-4 d-flex align-items-center">Display Order</div>
                                            <div class="col-sm-8"><asp:TextBox ID="txtPointOrder" runat="server" Text="0" CssClass="form-control form-control-sm rounded fz-custom1" /></div>
                                        </div>
                                        <div class="row mt-1">
                                            <div class="col-sm-4"></div>
                                            <div class="col-sm-8"><asp:CheckBox ID="chkPointActive" runat="server" Text=" Active" Checked="true" /></div>
                                        </div>
                                    </div>
                                </div>
                                <div class="row my-1">
                                    <div class="col-sm-6"></div>
                                    <div class="col-sm-6 d-flex justify-content-end">
                                        <asp:LinkButton ID="btnSavePoint" runat="server" CssClass="btn btn-sm CUS-btn-outline-PColor-1 py-1 px-3 CUS-fz-5 CUS-BorRad-4" OnClick="btnSavePoint_Click"><i class="fas fa-save"></i> Save Point</asp:LinkButton>
                                    </div>
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
                                        <PagerStyle Mode="NumericPages" HorizontalAlign="right" />
                                        <Columns>
                                            <asp:TemplateField HeaderText="" HeaderStyle-Width="1%" ItemStyle-Width="1%">
                                                <ItemTemplate>
                                                    <asp:LinkButton ID="btnEditPointRow" runat="server" CssClass="CUS-lbtn-1" ToolTip="Edit Inspection Point" CommandName="EditPoint" CommandArgument='<%# Eval("InspectionPointID") %>' CausesValidation="false"><i class="far fa-edit"></i></asp:LinkButton>
                                                </ItemTemplate>
                                            </asp:TemplateField>
                                            <asp:TemplateField HeaderText="" HeaderStyle-Width="1%" ItemStyle-Width="1%">
                                                <ItemTemplate>
                                                    <asp:LinkButton ID="btnMapPointRow" runat="server" CssClass="CUS-lbtn-1" ToolTip="Open Map Editor" CommandName="MapEditor" CommandArgument='<%# Eval("InspectionPointID") %>' CausesValidation="false"><i class="fas fa-map-marker-alt"></i></asp:LinkButton>
                                                </ItemTemplate>
                                            </asp:TemplateField>
                                            <asp:BoundField DataField="PointCode" HeaderText="Point Code" />
                                            <asp:BoundField DataField="PointName" HeaderText="Point Name" />
                                            <asp:BoundField DataField="InspectionTypeCode" HeaderText="Type" />
                                            <asp:BoundField DataField="InspectionTypeDetailCode" HeaderText="Detail" />
                                            <asp:BoundField DataField="DisplayOrder" HeaderText="Order" />
                                            <asp:TemplateField HeaderText="Active" HeaderStyle-Width="7%">
                                                <ItemTemplate><%# Convert.ToBoolean(Eval("IsActive")) ? "Yes" : "No" %></ItemTemplate>
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
                                    <asp:LinkButton ID="btnPointFirst" runat="server" CssClass="CUS-lbtn-1 mx-1" OnClick="btnPointFirst_Click" CausesValidation="false" ToolTip="First"><i class="fas fa-angle-double-left"></i></asp:LinkButton>
                                    <asp:LinkButton ID="btnPointPrevious" runat="server" CssClass="CUS-lbtn-1 mx-1" OnClick="btnPointPrevious_Click" CausesValidation="false" ToolTip="Previous"><i class="fas fa-angle-left"></i></asp:LinkButton>
                                    <asp:LinkButton ID="btnPointNext" runat="server" CssClass="CUS-lbtn-1 mx-1" OnClick="btnPointNext_Click" CausesValidation="false" ToolTip="Next"><i class="fas fa-angle-right"></i></asp:LinkButton>
                                    <asp:LinkButton ID="btnPointLast" runat="server" CssClass="CUS-lbtn-1 mx-1" OnClick="btnPointLast_Click" CausesValidation="false" ToolTip="Last"><i class="fas fa-angle-double-right"></i></asp:LinkButton>
                                    <span class="small text-muted mx-1">Go to</span>
                                    <asp:TextBox ID="txtPointGoToPage" runat="server" CssClass="form-control form-control-sm fz-custom1" Width="50px" Text="1" />
                                    <asp:LinkButton ID="btnPointGoToPage" runat="server" CssClass="CUS-lbtn-1 mx-1" OnClick="btnPointGoToPage_Click" CausesValidation="false">Go</asp:LinkButton>
                                    <asp:Label ID="lblPointPageTotal" runat="server" CssClass="small text-muted" />
                                </div>
                            </div>
                        </div>
                    </div>

                    <div id="map-editor" class="row my-1">
                        <div class="col border rounded shadow-sm">
                            <div class="row font-weight-bold bg-custom20" style="height:30px;border-bottom:1px solid #dee2e6;">
                                <div class="col d-flex align-items-center">Map Editor</div>
                                <div class="col-auto d-flex align-items-center">
                                    <asp:HyperLink ID="lnkEditorPdf" runat="server" Target="_blank" CssClass="CUS-lbtn-1" Visible="false">Open PDF</asp:HyperLink>
                                </div>
                            </div>
                            <div class="row my-1">
                                <div class="col-sm-8">
                                    <div class="row mt-1">
                                        <div class="col-sm-4 d-flex align-items-center">Inspection Point</div>
                                        <div class="col-sm-8"><asp:DropDownList ID="ddlEditorPoint" runat="server" CssClass="form-select form-select-sm rounded fz-custom1" /></div>
                                    </div>
                                </div>
                                <div class="col-sm-4 d-flex align-items-end">
                                    <asp:LinkButton ID="btnLoadEditor" runat="server" CssClass="btn btn-sm CUS-btn-outline-PColor-1 py-1 px-3 CUS-fz-5 CUS-BorRad-4 w-100" OnClick="btnLoadEditor_Click"><i class="fas fa-sync-alt"></i> Load</asp:LinkButton>
                                </div>
                            </div>
                            <asp:Panel ID="pnlEditor" runat="server" Visible="false">
                                <div class="row my-1">
                                    <div class="col-lg-8">
                                        <div class="inspection-map-toolbar d-flex flex-wrap align-items-center gap-2 mb-2">
                                            <button type="button" class="btn btn-sm btn-outline-secondary" id="btnMapZoomOut" title="Zoom out"><i class="bi bi-zoom-out"></i></button>
                                            <button type="button" class="btn btn-sm btn-outline-secondary" id="btnMapZoomIn" title="Zoom in"><i class="bi bi-zoom-in"></i></button>
                                            <button type="button" class="btn btn-sm btn-outline-secondary" id="btnMapZoomFit"><i class="bi bi-arrows-angle-contract me-1"></i> Fit</button>
                                            <span class="small text-muted" id="lblMapZoom">100%</span>
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
                                        <div class="border rounded p-2">
                                            <div class="small fw-bold mb-1">Marker Position</div>
                                            <div class="row">
                                                <div class="col-6"><div class="small">X (%)</div><asp:TextBox ID="txtMarkerX" runat="server" ClientIDMode="Static" CssClass="form-control form-control-sm fz-custom1" Text="50" /></div>
                                                <div class="col-6"><div class="small">Y (%)</div><asp:TextBox ID="txtMarkerY" runat="server" ClientIDMode="Static" CssClass="form-control form-control-sm fz-custom1" Text="50" /></div>
                                            </div>
                                            <div class="row mt-2"><div class="col"><asp:LinkButton ID="btnSaveMarker" runat="server" CssClass="btn btn-sm CUS-btn-outline-PColor-1 w-100" OnClick="btnSaveMarker_Click"><i class="fas fa-map-marker-alt"></i> Save Marker</asp:LinkButton></div></div>
                                        </div>
                                    </div>
                                </div>
                                <div class="row my-1">
                                    <div class="col">
                                        <asp:GridView ID="gvMapElements" runat="server" AutoGenerateColumns="false" BorderWidth="0" GridLines="None" CssClass="table-sm table-borderless mb-0 w-100" EmptyDataText="No marker">
                                            <HeaderStyle CssClass="CUS-fz-5 dtgrdhd-custom1 CUS-bg-Color-1" />
                                            <RowStyle CssClass="CUS-fz-5 dtgrddt-custom1" />
                                            <Columns>
                                                <asp:BoundField DataField="PointCode" HeaderText="Point Code" />
                                                <asp:BoundField DataField="PointName" HeaderText="Point Name" />
                                                <asp:BoundField DataField="XPercent" HeaderText="X %" DataFormatString="{0:0.00}" />
                                                <asp:BoundField DataField="YPercent" HeaderText="Y %" DataFormatString="{0:0.00}" />
                                                <asp:TemplateField HeaderText=""><ItemTemplate><asp:LinkButton ID="btnEditMarker" runat="server" CssClass="CUS-lbtn-1" CommandName="EditMarker" CommandArgument='<%# Eval("MapElementID") %>'><i class="far fa-edit"></i></asp:LinkButton></ItemTemplate></asp:TemplateField>
                                            </Columns>
                                        </asp:GridView>
                                    </div>
                                </div>
                            </asp:Panel>
                        </div>
                    </div>
                </div>
            </div>
        </td></tr>
    </table>
</asp:Content>

<%@ Page Title="Master Inspection Geofence" Language="C#" MasterPageFile="~/MasterPages/Site_BS_5.Master" AutoEventWireup="true" CodeBehind="M_InspectionGeofence.aspx.cs" Inherits="INSPEC.Secure.M_InspectionGeofence" %>
<%@ MasterType VirtualPath="~/MasterPages/Site_BS_5.Master" %>

<asp:Content ID="ContentHead" ContentPlaceHolderID="head" runat="server">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.css" />
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/leaflet.draw/1.0.4/leaflet.draw.css" />
    <link rel="stylesheet" href="../CSSCus/inspectionGeofence.css" />
    <script src="https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/leaflet.draw/1.0.4/leaflet.draw.js"></script>
    <script src="../JSCus/inspectionGeofence.js"></script>
</asp:Content>

<asp:Content ID="ContentMain" ContentPlaceHolderID="ContentPlaceHolder1" runat="server">
    <div class="container-fluid inspection-geofence-page">
        <div class="d-none">
            <asp:TextBox ID="txtConfirmAction" runat="server" AutoPostBack="true" OnTextChanged="txtConfirmAction_TextChanged" />
            <asp:TextBox ID="txtIsNew" runat="server" />
            <asp:HiddenField ID="hidPointsJson" runat="server" ClientIDMode="Static" />
            <asp:LinkButton ID="lbtnSyncPoints" runat="server" ClientIDMode="Static" OnClick="lbtnSyncPoints_Click" />
        </div>

        <div class="card shadow-sm border-0 mb-3">
            <div class="card-body">
                <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
                    <div>
                        <div class="h5 mb-1">Inspection Geofence</div>
                        <div class="small text-muted">Atur batas area fisik tempat inspeksi boleh dilakukan.</div>
                    </div>
                    <div class="inspection-geofence-scope">
                        <span class="badge text-bg-primary">Company: <asp:Literal ID="litCompany" runat="server" /></span>
                        <span class="badge text-bg-secondary">Location: <asp:Literal ID="litLocation" runat="server" /></span>
                    </div>
                </div>

                <div class="row g-3 align-items-end">
                    <div class="col-lg-4 col-md-6">
                        <label class="form-label small fw-semibold" for="<%= ddlSavedGeofence.ClientID %>">Open saved geofence</label>
                        <asp:DropDownList ID="ddlSavedGeofence" runat="server" CssClass="form-select form-select-sm"
                            AutoPostBack="true" OnSelectedIndexChanged="ddlSavedGeofence_SelectedIndexChanged" />
                    </div>
                    <div class="col-lg-2 col-md-3">
                        <label class="form-label small fw-semibold" for="<%= txtGeofenceID.ClientID %>">Geofence ID</label>
                        <asp:TextBox ID="txtGeofenceID" runat="server" CssClass="form-control form-control-sm" ReadOnly="true" />
                    </div>
                    <div class="col-lg-4 col-md-6">
                        <label class="form-label small fw-semibold" for="<%= txtGeofenceName.ClientID %>">Geofence Name <span class="text-danger">*</span></label>
                        <asp:TextBox ID="txtGeofenceName" runat="server" ClientIDMode="Static" MaxLength="100"
                            CssClass="form-control form-control-sm" placeholder="Contoh: Area Lift" />
                    </div>
                    <div class="col-lg-2 col-md-3 d-flex align-items-center">
                        <asp:CheckBox ID="chkIsActive" runat="server" Text="Active" CssClass="form-check-input me-2" Checked="true" />
                    </div>
                    <div class="col-12">
                        <label class="form-label small fw-semibold" for="<%= txtDescription.ClientID %>">Description</label>
                        <asp:TextBox ID="txtDescription" runat="server" MaxLength="500" TextMode="MultiLine" Rows="2"
                            CssClass="form-control form-control-sm" placeholder="Keterangan area (opsional)" />
                    </div>
                </div>
            </div>
        </div>

        <div class="row g-3">
            <div class="col-xl-8">
                <div class="card shadow-sm border-0 h-100">
                    <div class="card-header bg-white d-flex flex-wrap justify-content-between align-items-center gap-2">
                        <div>
                            <div class="fw-semibold">Draw inspection area</div>
                            <div class="small text-muted">Cari alamat, lalu gambar polygon mengelilingi area yang diizinkan.</div>
                        </div>
                        <span id="mapVertexBadge" class="badge text-bg-info">0 titik</span>
                    </div>
                    <div class="card-body">
                        <div class="row g-2 mb-2">
                            <div class="col">
                                <div class="input-group input-group-sm">
                                    <input type="text" id="mapSearchText" class="form-control" placeholder="Cari alamat / nama gedung..." aria-label="Cari alamat atau nama gedung" />
                                    <button type="button" id="btnMapSearch" class="btn btn-outline-primary"><i class="bi bi-search"></i> Cari</button>
                                </div>
                            </div>
                            <div class="col-auto">
                                <button type="button" id="btnMapLocate" class="btn btn-sm btn-outline-secondary"><i class="bi bi-crosshair"></i> Lokasi saya</button>
                            </div>
                        </div>
                        <div id="geofenceMap" role="application" aria-label="Peta untuk menggambar geofence"></div>
                        <div class="inspection-geofence-map-note mt-2">
                            <i class="bi bi-info-circle me-1"></i>
                            Gunakan tool polygon di sisi kanan atas peta. Klik minimal 3 titik untuk membentuk batas area, lalu klik titik pertama atau double-click untuk menyelesaikan.
                            Gunakan tool edit untuk menggeser titik dan tool delete untuk menghapus polygon.
                        </div>
                        <div id="mapMessage" class="small mt-2 text-muted" aria-live="polite">Peta siap. Cari gedung atau geser peta ke area yang akan diatur.</div>
                    </div>
                </div>
            </div>

            <div class="col-xl-4">
                <div class="card shadow-sm border-0 h-100">
                    <div class="card-header bg-white d-flex justify-content-between align-items-center">
                        <div>
                            <div class="fw-semibold">Polygon vertices</div>
                            <div class="small text-muted">Koordinat setiap sudut polygon.</div>
                        </div>
                        <asp:Label ID="lblPointCount" runat="server" CssClass="badge text-bg-secondary" Text="0 titik" />
                    </div>
                    <div class="card-body p-0">
                        <div class="inspection-geofence-grid-wrap">
                            <asp:DataGrid ID="gridPoints" runat="server" AutoGenerateColumns="false" GridLines="None"
                                CssClass="table table-sm table-hover align-middle mb-0" OnItemCommand="gridPoints_ItemCommand">
                                <HeaderStyle CssClass="table-light small text-nowrap" />
                                <ItemStyle CssClass="small" />
                                <AlternatingItemStyle CssClass="small" />
                                <Columns>
                                    <asp:BoundColumn DataField="SequenceNo" HeaderText="#" ItemStyle-Width="36px" />
                                    <asp:BoundColumn DataField="Latitude" HeaderText="Latitude" />
                                    <asp:BoundColumn DataField="Longitude" HeaderText="Longitude" />
                                    <asp:TemplateColumn HeaderText="Action">
                                        <ItemTemplate>
                                            <div class="d-flex gap-1">
                                                <asp:LinkButton ID="lbtnEditPoint" runat="server" CommandName="EditPoint"
                                                    CommandArgument='<%# Eval("SequenceNo") %>' CssClass="btn btn-sm btn-outline-primary py-0 px-2" ToolTip="Edit koordinat">
                                                    <i class="bi bi-pencil"></i>
                                                </asp:LinkButton>
                                                <asp:LinkButton ID="lbtnDeletePoint" runat="server" CommandName="DeletePoint"
                                                    CommandArgument='<%# Eval("SequenceNo") %>' CssClass="btn btn-sm btn-outline-danger py-0 px-2" ToolTip="Hapus titik">
                                                    <i class="bi bi-trash"></i>
                                                </asp:LinkButton>
                                            </div>
                                        </ItemTemplate>
                                    </asp:TemplateColumn>
                                </Columns>
                            </asp:DataGrid>
                            <asp:Panel ID="pnlPointsEmpty" runat="server" CssClass="inspection-geofence-empty">
                                Belum ada titik. Gambar polygon pada peta untuk membuat batas geofence.
                            </asp:Panel>
                        </div>
                        <asp:Panel ID="pnlPointEditor" runat="server" Visible="false" CssClass="border-top p-3 bg-body-tertiary">
                            <div class="small fw-semibold mb-2">Edit vertex <asp:Label ID="lblEditingPoint" runat="server" /></div>
                            <div class="row g-2">
                                <div class="col-6">
                                    <label class="form-label small mb-1">Latitude</label>
                                    <asp:TextBox ID="txtPointLatitude" runat="server" CssClass="form-control form-control-sm" />
                                </div>
                                <div class="col-6">
                                    <label class="form-label small mb-1">Longitude</label>
                                    <asp:TextBox ID="txtPointLongitude" runat="server" CssClass="form-control form-control-sm" />
                                </div>
                            </div>
                            <div class="d-flex justify-content-end gap-2 mt-2">
                                <asp:LinkButton ID="lbtnCancelPoint" runat="server" CssClass="btn btn-sm btn-light" OnClick="lbtnCancelPoint_Click">Cancel</asp:LinkButton>
                                <asp:LinkButton ID="lbtnApplyPoint" runat="server" CssClass="btn btn-sm btn-primary" OnClick="lbtnApplyPoint_Click">Apply coordinate</asp:LinkButton>
                            </div>
                            <asp:HiddenField ID="hidEditingSequence" runat="server" />
                        </asp:Panel>
                    </div>
                    <div class="card-footer bg-white small text-muted">
                        Minimal 3 titik diperlukan. Satu geofence menyimpan satu polygon; satu polygon bisa dipakai oleh banyak Inspection Type Detail.
                    </div>
                </div>
            </div>
        </div>

        <div class="inspection-geofence-footer-note mt-3">
            <i class="bi bi-shield-check me-1"></i>
            Koordinat disimpan sebagai latitude/longitude. Geofence ini dibatasi pada Company dan Location yang sedang aktif saat login.
        </div>
    </div>
</asp:Content>

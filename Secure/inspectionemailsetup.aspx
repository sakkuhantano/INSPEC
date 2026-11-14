<%@ Page Title="Inspection Email Setup" Language="C#" MasterPageFile="~/MasterPages/Site_BS_5.Master" AutoEventWireup="true" CodeBehind="inspectionemailsetup.aspx.cs" Inherits="INSPEC.Secure.inspectionemailsetup" %>
<%@ MasterType VirtualPath="~/MasterPages/Site_BS_5.Master" %>
<asp:Content ID="Content1" ContentPlaceHolderID="head" runat="server">
    <style>
        .email-setup-card { border: 1px solid var(--bs-border-color); border-radius: .75rem; }
        .email-setup-card .card-header { background: var(--bs-tertiary-bg); font-weight: 600; }
    </style>
</asp:Content>
<asp:Content ID="Content2" ContentPlaceHolderID="ContentPlaceHolder1" runat="server">
    <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
        <div>
            <h4 class="mb-1">Inspection Email & Approval Routing</h4>
            <div class="text-muted small">Company: <strong><%= Server.HtmlEncode(Master.Mn_CompanyID) %></strong> · Location: <strong><%= Server.HtmlEncode(Master.Mn_LocationID) %></strong></div>
        </div>
        <a class="btn btn-outline-secondary btn-sm" href="inspectionmaster.aspx"><i class="bi bi-arrow-left me-1"></i>Inspection Setup</a>
    </div>

    <asp:Panel ID="pnlMessage" runat="server" Visible="false" CssClass="alert mb-3">
        <asp:Literal ID="litMessage" runat="server" />
    </asp:Panel>
    <asp:Panel ID="pnlSmtpWarning" runat="server" Visible="false" CssClass="alert alert-warning mb-3">
        Email routing dan outbox sudah tersedia, tetapi SMTP belum siap mengirim. Isi <strong>smtpFrom</strong> pada Web.config dan pastikan relay SMTP menerima sender tersebut. Notifikasi akan tetap tersimpan di outbox dan dicoba ulang.
    </asp:Panel>

    <div class="card email-setup-card mb-3">
        <div class="card-header py-3"><i class="bi bi-diagram-3 me-2"></i>Approval recipients per Company + Location</div>
        <div class="card-body">
            <div class="row g-3">
                <div class="col-12 col-lg-6">
                    <label class="form-label fw-semibold" for="<%= ddlChiefEngSection.ClientID %>">Chief Engineering Section</label>
                    <asp:DropDownList ID="ddlChiefEngSection" runat="server" CssClass="form-select mb-2" AutoPostBack="true" OnSelectedIndexChanged="ddlChiefEngSection_SelectedIndexChanged" />
                    <label class="form-label fw-semibold" for="<%= ddlChiefEng.ClientID %>">Chief Engineering Employee</label>
                    <asp:DropDownList ID="ddlChiefEng" runat="server" CssClass="form-select" />
                    <div class="form-text">Employee difilter berdasarkan section yang dipilih dan Company aktif.</div>
                </div>
                <div class="col-12 col-lg-6">
                    <label class="form-label fw-semibold" for="<%= ddlChiefSecSection.ClientID %>">Chief Security Section</label>
                    <asp:DropDownList ID="ddlChiefSecSection" runat="server" CssClass="form-select mb-2" AutoPostBack="true" OnSelectedIndexChanged="ddlChiefSecSection_SelectedIndexChanged" />
                    <label class="form-label fw-semibold" for="<%= ddlChiefSec.ClientID %>">Chief Security Employee</label>
                    <asp:DropDownList ID="ddlChiefSec" runat="server" CssClass="form-select" />
                    <div class="form-text">Employee difilter berdasarkan section yang dipilih dan Company aktif.</div>
                </div>
            </div>
            <div class="d-flex justify-content-end mt-3">
                <asp:Button ID="btnSaveHeader" runat="server" Text="Save Location Recipients" CssClass="btn btn-primary" OnClick="btnSaveHeader_Click" />
            </div>
        </div>
    </div>

    <div class="card email-setup-card">
        <div class="card-header py-3"><i class="bi bi-people me-2"></i>SPV recipient per Section</div>
        <div class="card-body">
            <div class="row g-3 align-items-end">
                <div class="col-12 col-md-5">
                    <label class="form-label fw-semibold" for="<%= ddlSection.ClientID %>">Section</label>
                    <asp:DropDownList ID="ddlSection" runat="server" CssClass="form-select" AutoPostBack="true" OnSelectedIndexChanged="ddlSection_SelectedIndexChanged" />
                </div>
                <div class="col-12 col-md-7">
                    <label class="form-label fw-semibold" for="<%= ddlSPV.ClientID %>">SPV Employee</label>
                    <asp:DropDownList ID="ddlSPV" runat="server" CssClass="form-select" />
                </div>
            </div>
            <div class="d-flex justify-content-end mt-3">
                <asp:Button ID="btnSaveSPV" runat="server" Text="Save SPV for Section" CssClass="btn btn-primary" OnClick="btnSaveSPV_Click" />
            </div>
        </div>
    </div>
    <div class="form-text mt-3">Alamat email selalu dibaca dari <code>M_HRD_Employee.emailaddress</code>. Employee tanpa alamat email tidak dapat disimpan sebagai penerima.</div>
</asp:Content>

<%@ Page Title="Inspection Email Setup" Language="C#" MasterPageFile="~/MasterPages/Site_BS_5.Master" AutoEventWireup="true" CodeBehind="inspectionemailsetup.aspx.cs" Inherits="INSPEC.Secure.inspectionemailsetup" %><%@ MasterType VirtualPath="~/MasterPages/Site_BS_5.Master" %> <asp:Content ID="Content1" ContentPlaceHolderID="head" runat="server">
  <style>
    .email-setup-card {
      border: 1px solid var(--bs-border-color);
      border-radius: .75rem
    }

    .email-setup-card .card-header {
      background: var(--bs-tertiary-bg);
      font-weight: 600
    }

    .employee-picker {
      display: flex;
      gap: .5rem;
      align-items: center
    }
  </style>
</asp:Content>
<asp:Content ID="Content2" ContentPlaceHolderID="ContentPlaceHolder1" runat="server">
  <div class="mb-3">
    <h4 class="mb-1">Inspection Email &amp; Approval Routing</h4>
  </div>
  <asp:Panel ID="pnlMessage" runat="server" Visible="false" CssClass="alert mb-3">
    <asp:Literal ID="litMessage" runat="server" />
  </asp:Panel>
  <asp:Panel ID="pnlSmtpWarning" runat="server" Visible="false" CssClass="alert alert-warning mb-3">SMTP belum siap. Periksa konfigurasi smtpHost.</asp:Panel>
  <div class="card border-0 shadow-sm mb-3">
    <div class="card-header bg-body-tertiary fw-semibold">Chief Approver</div>
    <div class="card-body">
      <div class="row g-3">
        <div class="col-lg-6">
          <label class="form-label fw-semibold">Chief Engineering <span class="badge text-bg-light">PENG</span>
          </label>
          <div class="employee-picker">
            <asp:TextBox ID="txtChiefEng" runat="server" CssClass="form-control" ReadOnly="false" placeholder="Pilih NIK" />
            <asp:LinkButton ID="lBtnChiefEng" runat="server" CausesValidation="false" CssClass="btn btn-outline-primary">Search</asp:LinkButton>
          </div>
          <asp:Label ID="lblChiefEngName" runat="server" CssClass="form-text text-body-secondary" />
        </div>
        <div class="col-lg-6">
          <label class="form-label fw-semibold">Chief Security <span class="badge text-bg-light">PSEC</span>
          </label>
          <div class="employee-picker">
            <asp:TextBox ID="txtChiefSec" runat="server" CssClass="form-control" ReadOnly="false" placeholder="Pilih NIK" />
            <asp:LinkButton ID="lBtnChiefSec" runat="server" CausesValidation="false" CssClass="btn btn-outline-primary">Search</asp:LinkButton>
          </div>
          <asp:Label ID="lblChiefSecName" runat="server" CssClass="form-text text-body-secondary" />
        </div>
      </div>
      <div class="text-end mt-3">
        <asp:Button ID="btnSaveHeader" runat="server" Text="Save Chief Approver" CssClass="btn btn-primary" OnClick="btnSaveHeader_Click" />
      </div>
    </div>
  </div>
  <div class="card border-0 shadow-sm mb-3">
    <div class="card-header bg-body-tertiary d-flex justify-content-between align-items-center">
      <span>SPV Mapping per Section</span>
      <asp:Button ID="btnNewSPV" runat="server" Text="Add New Record" CssClass="btn btn-sm btn-primary" CausesValidation="false" OnClick="btnNewSPV_Click" />
    </div>
    <div class="card-body">
      <asp:HiddenField ID="hidSPVOriginalSection" runat="server" />
      <div class="row g-3 align-items-end">
        <div class="col-md-4">
          <label class="form-label">Section</label>
          <asp:DropDownList ID="ddlSection" runat="server" CssClass="form-select" AutoPostBack="true" OnSelectedIndexChanged="ddlSection_SelectedIndexChanged" />
        </div>
        <div class="col-md-5">
          <label class="form-label">SPV NIK</label>
          <div class="employee-picker">
            <asp:TextBox ID="txtSPV" runat="server" CssClass="form-control" ReadOnly="false" placeholder="Pilih NIK SPV" />
            <asp:LinkButton ID="lBtnSPV" runat="server" CausesValidation="false" CssClass="btn btn-outline-primary">Search</asp:LinkButton>
          </div>
          <asp:Label ID="lblSPVName" runat="server" CssClass="form-text text-body-secondary" />
        </div>
        <div class="col-md-3 d-flex gap-2">
          <asp:Button ID="btnSaveSPV" runat="server" Text="Save Mapping" CssClass="btn btn-primary" OnClick="btnSaveSPV_Click" />
          <asp:Button ID="btnCancelSPV" runat="server" Text="Cancel" CssClass="btn btn-outline-secondary" CausesValidation="false" OnClick="btnCancelSPV_Click" />
        </div>
      </div>
      <hr />
      <asp:GridView ID="gvSPV" runat="server" AutoGenerateColumns="false" CssClass="table table-sm table-hover align-middle" EmptyDataText="Belum ada mapping SPV." OnRowCommand="gvSPV_RowCommand">
        <Columns>
          <asp:BoundField DataField="SectionID" HeaderText="Section" />
          <asp:BoundField DataField="EmployeeID" HeaderText="NIK SPV" />
          <asp:BoundField DataField="EmployeeName" HeaderText="Nama SPV" />
          <asp:TemplateField HeaderText="Action">
            <ItemTemplate>
              <asp:LinkButton runat="server" CommandName="EditMapping" CommandArgument='<%# Eval("SectionID") %>' CssClass="btn btn-sm btn-outline-primary" CausesValidation="false">Edit </asp:LinkButton>
              <asp:LinkButton runat="server" CommandName="DeleteMapping" CommandArgument='<%# Eval("SectionID") %>' CssClass="btn btn-sm btn-outline-danger" CausesValidation="false" OnClientClick="return confirm('Hapus mapping ini?');">Delete </asp:LinkButton>
            </ItemTemplate>
          </asp:TemplateField>
        </Columns>
      </asp:GridView>
    </div>
  </div>
  <div class="card border-0 shadow-sm">
    <div class="card-header bg-body-tertiary fw-semibold">Email Notification per Inspection Mode</div>
    <div class="card-body">
      <div class="row g-3">
        <div class="col-md-4">
          <asp:CheckBox ID="chkEmailStandard" runat="server" CssClass="form-check-input" /> STANDARD
        </div>
        <div class="col-md-4">
          <asp:CheckBox ID="chkEmailBatch" runat="server" CssClass="form-check-input" /> BATCH
        </div>
        <div class="col-md-4">
          <asp:CheckBox ID="chkEmailLightning" runat="server" CssClass="form-check-input" /> LIGHTNING
        </div>
      </div>
      <div class="text-end mt-3">
        <asp:Button ID="btnSaveEmailMode" runat="server" Text="Save Email Settings" CssClass="btn btn-primary" OnClick="btnSaveEmailMode_Click" />
      </div>
    </div>
  </div>
</asp:Content>

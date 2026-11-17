<%@ Page Title="Inspection Email Setup" Language="C#" MasterPageFile="~/MasterPages/Site_BS_5.Master" AutoEventWireup="true" CodeBehind="inspectionemailsetup.aspx.cs" Inherits="INSPEC.Secure.inspectionemailsetup" %><%@ MasterType VirtualPath="~/MasterPages/Site_BS_5.Master" %> <asp:Content ID="Content1" ContentPlaceHolderID="head" runat="server">
<style>
.employee-badges{display:flex;flex-wrap:wrap;gap:.4rem;margin-top:.5rem}
.employee-badge{display:inline-flex;align-items:center;gap:.4rem;padding:.3rem .55rem;border-radius:50rem;background:var(--bs-primary-bg-subtle);color:var(--bs-primary-text-emphasis);border:1px solid var(--bs-primary-border-subtle);font-size:.85rem}
.employee-badge button{border:0;background:transparent;color:inherit;padding:0 .1rem;line-height:1;font-size:1rem}
</style>
<script type="text/javascript">
(function(){
 function vals(h){return (h.value||"").split(";").map(function(x){return x.trim();}).filter(Boolean);}
 function render(iid,hid,lid){
  var input=document.getElementById(iid),h=document.getElementById(hid),list=document.getElementById(lid);if(!input||!h||!list)return;
  var ids=vals(h),seen={};list.innerHTML="";
  ids.forEach(function(id){var k=id.toLowerCase();if(seen[k])return;seen[k]=1;
   var badge=document.createElement("span");badge.className="employee-badge";
   var label=document.createElement("span");label.textContent=id;
   var x=document.createElement("button");x.type="button";x.setAttribute("aria-label","Remove "+id);x.innerHTML="&times;";
   x.addEventListener("click",function(){h.value=vals(h).filter(function(v){return v.toLowerCase()!==k;}).join(";");render(iid,hid,lid);});
   badge.appendChild(label);badge.appendChild(x);list.appendChild(badge);
  });
  h.value=ids.filter(function(id,n){return ids.findIndex(function(v){return v.toLowerCase()===id.toLowerCase();})===n;}).join(";");
 }
 function add(iid,hid,lid){
  var input=document.getElementById(iid),h=document.getElementById(hid);if(!input||!h||!input.value.trim())return;
  var list=vals(h),seen={};list.forEach(function(v){seen[v.toLowerCase()]=1;});
  input.value.split(";").forEach(function(v){var id=v.trim(),k=id.toLowerCase();if(id&&!seen[k]){list.push(id);seen[k]=1;}});
  h.value=list.join(";");input.value="";render(iid,hid,lid);
 }
 window.addEventListener("load",function(){
  var fields=[
   ["<%= txtChiefEng.ClientID %>","<%= hidChiefEngEmployees.ClientID %>","<%= divChiefEngEmployees.ClientID %>"],
   ["<%= txtChiefSec.ClientID %>","<%= hidChiefSecEmployees.ClientID %>","<%= divChiefSecEmployees.ClientID %>"],
   ["<%= txtSPV.ClientID %>","<%= hidSPVEmployees.ClientID %>","<%= divSPVEmployees.ClientID %>"]
  ];
  fields.forEach(function(f){var input=document.getElementById(f[0]);if(input){
   input.addEventListener("change",function(){add(f[0],f[1],f[2]);});
   input.addEventListener("blur",function(){add(f[0],f[1],f[2]);});
   input.addEventListener("keydown",function(e){if(e.key==="Enter"){e.preventDefault();add(f[0],f[1],f[2]);}});
  }render(f[0],f[1],f[2]);});
  function collectAfterPopup(){[100,300,700,1200].forEach(function(delay){window.setTimeout(function(){if(!document.hidden){fields.forEach(function(f){add(f[0],f[1],f[2]);});}},delay);});}
  window.addEventListener("focus",collectAfterPopup);
  document.addEventListener("visibilitychange",function(){if(!document.hidden)collectAfterPopup();});
 });
})();
</script>
</asp:Content>
<asp:Content ID="Content2" ContentPlaceHolderID="ContentPlaceHolder1" runat="server">
<asp:Panel ID="pnlSmtpWarning" runat="server" Visible="false" CssClass="alert alert-warning mb-3">SMTP belum siap. Periksa konfigurasi smtpHost.</asp:Panel>
  <div class="card border-0 shadow-sm mb-3">
    <div class="card-header bg-body-tertiary fw-semibold py-2">Email Notification per Inspection Mode</div>
    <div class="card-body pt-2">
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
        <div class="col-md-4">
          <asp:CheckBox ID="chkEmailWO" runat="server" CssClass="form-check-input" /> WORK ORDER
        </div>
      </div>
    </div>
  </div>
  <div class="card border-0 shadow-sm mb-3">
    <div class="card-header bg-body-tertiary fw-semibold py-2">Chief Approver</div>
    <div class="card-body pt-2">
      <div class="row g-3">
        <div class="col-lg-6">
          <label class="form-label fw-semibold">Chief Engineering <span class="badge text-bg-light">PENG</span></label>
          <div class="d-flex gap-2 align-items-center">
            <asp:TextBox ID="txtChiefEng" runat="server" CssClass="form-control" ReadOnly="false" AutoPostBack="false" placeholder="Pilih employee via Search" />
            <asp:HiddenField ID="hidChiefEngEmployees" runat="server" />
            <div id="divChiefEngEmployees" runat="server" class="employee-badges"></div>
            <asp:LinkButton ID="lBtnChiefEng" runat="server" CausesValidation="false" CssClass="btn btn-sm CUS-btn-outline-PColor-1">Search</asp:LinkButton>
          </div>
          <asp:Label ID="lblChiefEngName" runat="server" CssClass="form-text text-body-secondary" /><div class="form-text text-body-secondary">Bisa lebih dari satu NIK, pisahkan dengan titik koma (;).</div>
        </div>
        <div class="col-lg-6">
          <label class="form-label fw-semibold">Chief Security <span class="badge text-bg-light">PSEC</span></label>
          <div class="d-flex gap-2 align-items-center">
            <asp:TextBox ID="txtChiefSec" runat="server" CssClass="form-control" ReadOnly="false" AutoPostBack="false" placeholder="Pilih employee via Search" />
            <asp:HiddenField ID="hidChiefSecEmployees" runat="server" />
            <div id="divChiefSecEmployees" runat="server" class="employee-badges"></div>
            <asp:LinkButton ID="lBtnChiefSec" runat="server" CausesValidation="false" CssClass="btn btn-sm CUS-btn-outline-PColor-1">Search</asp:LinkButton>
          </div>
          <asp:Label ID="lblChiefSecName" runat="server" CssClass="form-text text-body-secondary" /><div class="form-text text-body-secondary">Bisa lebih dari satu NIK, pisahkan dengan titik koma (;).</div>
        </div>
      </div>
    </div>
  </div>
  <div class="card border-0 shadow-sm mb-3">
    <div class="card-header bg-body-tertiary d-flex justify-content-between align-items-center py-2">
      <span>SPV Mapping per Section</span>
      <asp:Button ID="btnNewSPV" runat="server" Text="Add New Record" CssClass="btn btn-sm CUS-btn-outline-PColor-1" CausesValidation="false" OnClick="btnNewSPV_Click" />
    </div>
    <div class="card-body pt-2">
      <asp:Panel ID="pnlSPVEditor" runat="server" Visible="false">
        <asp:HiddenField ID="hidSPVOriginalSection" runat="server" />
        <div class="row g-3 align-items-end">
          <div class="col-md-4">
            <label class="form-label">Section</label>
            <asp:DropDownList ID="ddlSection" runat="server" CssClass="form-select form-select-sm" AutoPostBack="true" OnSelectedIndexChanged="ddlSection_SelectedIndexChanged" />
          </div>
          <div class="col-md-5">
            <label class="form-label">SPV NIK</label>
            <div class="d-flex gap-2 align-items-center">
              <asp:TextBox ID="txtSPV" runat="server" CssClass="form-control form-control-sm" ReadOnly="false" AutoPostBack="false" placeholder="Pilih employee via Search" />
            <asp:HiddenField ID="hidSPVEmployees" runat="server" />
            <div id="divSPVEmployees" runat="server" class="employee-badges"></div>
              <asp:LinkButton ID="lBtnSPV" runat="server" CausesValidation="false" CssClass="btn btn-sm CUS-btn-outline-PColor-1">Search</asp:LinkButton>
            </div>
            <asp:Label ID="lblSPVName" runat="server" CssClass="form-text text-body-secondary" /><div class="form-text text-body-secondary">Bisa lebih dari satu NIK, pisahkan dengan titik koma (;).</div>
          </div>
          <div class="col-md-3 d-flex align-items-end">
            <asp:Button ID="btnCancelSPV" runat="server" Text="Cancel" CssClass="btn btn-sm btn-outline-secondary" CausesValidation="false" OnClick="btnCancelSPV_Click" />
          </div>
        </div>
      </asp:Panel>
      <hr />
      <asp:GridView ID="gvSPV" runat="server" AutoGenerateColumns="false" CssClass="table table-sm table-hover align-middle" EmptyDataText="" OnRowCommand="gvSPV_RowCommand">
        <Columns>
          <asp:BoundField DataField="SectionID" HeaderText="Section" />
          <asp:BoundField DataField="EmployeeID" HeaderText="NIK SPV" />
          <asp:BoundField DataField="EmployeeName" HeaderText="Nama SPV" />
          <asp:TemplateField HeaderText="Action">
            <ItemTemplate>
              <asp:LinkButton runat="server" CommandName="EditMapping" CommandArgument='<%# Eval("SectionID") %>' CssClass="btn btn-sm CUS-btn-outline-PColor-1" CausesValidation="false">Edit</asp:LinkButton>
              <asp:LinkButton runat="server" CommandName="DeleteMapping" CommandArgument='<%# Eval("SectionID") %>' CssClass="btn btn-sm btn-outline-secondary" CausesValidation="false" OnClientClick="return confirm('Hapus mapping ini?');">Delete</asp:LinkButton>
            </ItemTemplate>
          </asp:TemplateField>
        </Columns>
      </asp:GridView>
    </div>
  </div>
</asp:Content>

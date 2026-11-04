<%@ Page Title="" Language="C#" MaintainScrollPositionOnPostback="true" MasterPageFile="~/MasterPages/Site_BS_5.Master" AutoEventWireup="true" CodeBehind="U_SettingCompany.aspx.cs" Inherits="INSPEC.Secure.U_SettingCompany" %>
<%@ MasterType VirtualPath="~/MasterPages/Site_BS_5.Master" %>

<asp:Content ID="Content1" ContentPlaceHolderID="head" runat="server">
</asp:Content>
<asp:Content ID="Content2" ContentPlaceHolderID="ContentPlaceHolder1" runat="server">
    <table border="0" cellspacing="0" cellpadding="0" style="width:100%;">
    <tr>
	    <td>
            <div class="row mt-1 border rounded shadow-sm" style="margin:auto;">
                <div class="col-sm-6 mb-1">
                    <div class="row mt-1">
                        <div class="col-sm-4 d-flex justify-content-start align-items-center">
                            <asp:LinkButton id="lbtnCompanyID"  
						                    Runat="server" 
						                    text="Company ID" 
						                    OnPreRender="lbtn_PreRender"
                                            CssClass="CUS-lbtn-1"
                                            ></asp:LinkButton>
                        </div>
                        <div class="col-sm-8">
                            <asp:TextBox    id="txtCompanyID" 
					                        runat="server" 
                                            CssClass="form-control form-control-sm fz-custom1"
                                            placeholder="Company ID"
					                        AutoPostBack="True"
                                            OnTextChanged="txtCompanyID_TextChanged"
                                            />
                        </div>
                    </div>
                    <div class="row mt-1">
                        <div class="col-sm-4 d-flex justify-content-start align-items-center">
                            <asp:Label runat="server" ID="lblCompanyNameCaption" Text="Company Name"></asp:Label>
                        </div>
                        <div class="col-sm-8">
                            <asp:TextBox id="txtCompanyName" 
					                     runat="server" 
					                     CssClass="form-control form-control-sm fz-custom1"
                                         placeholder="Company Name"
                                         ReadOnly="true"
                                         />
                        </div>
                    </div>
                    <div class="row mt-1">
                        <div class="col-sm-4 d-flex justify-content-start align-items-center">
                            <asp:LinkButton id="lbtnLocationID"  
						                    Runat="server" 
						                    text="Location ID" 
						                    OnPreRender="lbtn_PreRender"
						                    CssClass="CUS-lbtn-1"
                                            ></asp:LinkButton>  
                        </div>
                        <div class="col-sm-8">
                            <asp:TextBox    id="txtLocationID" 
					                        runat="server" 
					                        CssClass="form-control form-control-sm fz-custom1"
                                            placeholder="Location ID"
					                        AutoPostBack="True"
                                            OnTextChanged="txtLocationID_TextChanged"
                                            />
                        </div>
                    </div>
                    <div class="row mt-1">
                        <div class="col-sm-4 d-flex justify-content-start align-items-center">
                            <asp:Label runat="server" ID="lblLocationNameCaption" Text="Location Name"></asp:Label>  
                        </div>
                        <div class="col-sm-8">
                            <asp:TextBox id="txtLocationName" 
					                     runat="server" 
					                     CssClass="form-control form-control-sm fz-custom1"
                                         placeholder="Location Name"
                                         ReadOnly="true"
                                         />
                        </div>
                    </div>
                </div>
                <div class="col-sm-6 mb-1">
                </div>
            </div>
	    </td>
    </tr>
    </table>
</asp:Content>

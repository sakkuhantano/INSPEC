<%@ Page Title="" Language="C#" MaintainScrollPositionOnPostback="true" MasterPageFile="~/MasterPages/Site_BS_5.Master" AutoEventWireup="true" CodeBehind="T_DailyLogEmployee.aspx.cs" Inherits="INSPEC.Secure.T_DailyLogEmployee" %>
<%@ MasterType VirtualPath="~/MasterPages/Site_BS_5.Master" %>

<asp:Content ID="Content2" ContentPlaceHolderID="ContentPlaceHolder1" runat="server">
    <table border="0" cellspacing="0" cellpadding="0" style="width:100%;">
        <tr>
            <td>
                <asp:Label ID="lblError" runat="server" ForeColor="Red" />
                <div class="row mt-2 border rounded shadow-sm" style="margin:auto;"> 
                    <div class="col-sm-6 mb-1">
                        <div class="row mt-1">
                            <div class="col-sm-4 d-flex justify-content-start align-items-center">
                                <asp:TextBox ID="txtInspectionNos" runat="server" TextMode="MultiLine" Rows="4" Columns="55" />
                            </div>
                        </div>
                        <div class="row mt-1">
                            <div class="col-sm-4 d-flex justify-content-start align-items-center">
                                <asp:Label ID="yearTxt" runat="server" Text="Year"></asp:Label>
                            </div>
                            <div class="col-sm-8">
                                <div class="form-inline ">
                                    <div class="input-group date">
                                        <asp:TextBox ID="txtYear"
                                                     runat="server"
                                                     CssClass="form-control form-control-sm fz-custom1"
                                                     MaxLength="4"
                                                     Width="50px">
                                        </asp:TextBox>
                                    </div>
                                  <%--  <div class="input-group date" style="margin-left:8px">
                                        <asp:Label runat="server" ID="lbl_Year_Invalid" ForeColor="red" Font-Size="Small"></asp:Label>
                                    </div>--%>
                                </div>
                            </div>
                        </div>
                        <div class="row mt-1">
                            <div class="col-sm-4 d-flex justify-content-start align-items-center">
                                <asp:LinkButton id="lbtnCompanyID"  
						                        Runat="server" 
						                        text="Company ID" 
						                        OnPreRender="lbtn_PreRender">
                                </asp:LinkButton>
                            </div>
                            <div class="col-sm-8">
                                <div class="form-inline">
                                    <div class="input-group date" style="width:35%">
                                        <asp:TextBox id="txtCompanyID" 
					                                    runat="server" 
                                                        CssClass="form-control form-control-sm fz-custom1"
                                                        placeholder="Company ID"
					                                    AutoPostBack="True"
                                                        OnTextChanged="txtCompanyID_TextChanged"
                                        ></asp:TextBox>
                                    </div>
                                    <div class="input-group date" style="width:45%;margin-left:15px;">
                                        <asp:TextBox id="txtCompanyName" 
					                                runat="server"     
                                                    CssClass="form-control form-control-sm fz-custom1"
                                                    placeholder="Company Name"
                                                    ReadOnly="true"
                                        ></asp:TextBox>
                                    </div>
                                </div>
                            </div>
                        </div>
                        <div class="row mt-1">
                            <div class="col-sm-4 d-flex justify-content-start align-items-center">
                            </div>
                            <div class="col-sm-8">
                                <div class="form-check">
                                    <asp:CheckBox ID="cbxIncludeZero" runat="server" CssClass="form-check-input fz-custom1" OnCheckedChanged="CheckBox_Changed" Autopostback="true"/>
                                    <label class="form-check-label align-middle fz-custom1" for="cbxIncludeZero" style="width:100px;">Include Zero</label>
                                </div>
                            </div>
                        </div>
                        <div class="row mt-1">
                            <div class="col-sm-4 d-flex justify-content-start align-items-center">
                            </div>
                            <div class="col-sm-8">
                                <div class="form-check">
                                    <asp:CheckBox ID="cbxIncludeBank" runat="server" CssClass="form-check-input fz-custom1" OnCheckedChanged="CheckBox_Changed" Autopostback="true"/>
                                    <label class="form-check-label align-middle fz-custom1" for="cbxIncludeBank" style="width:100px">Include Bank</label>
                                </div>
                            </div>
                        </div>
                        <div class="row mt-1">
                            <div class="col-sm-4 d-flex justify-content-start align-items-center">
                            </div>
                            <div class="col-sm-8">
                                <div class="form-check">
                                    <asp:CheckBox ID="cbxIncludeDeposit" runat="server" CssClass="form-check-input fz-custom1" OnCheckedChanged="CheckBox_Changed" Autopostback="true" />
                                    <label class="form-check-label align-middle fz-custom1" for="cbxIncludeDeposit" style="width:100px;">Include Deposit</label>
                                </div>
                            </div>
                        </div>
                        <div class="row mt-1">
                            <div class="col-sm-4 d-flex justify-content-start align-items-center">
                            </div>
                            <div class="col-sm-8">
                                <div class="form-check">
                                    <asp:CheckBox ID="cbxIncludeProfitCenter" runat="server" CssClass="form-check-input fz-custom1" OnCheckedChanged="CheckBox_Changed" Autopostback="true" />
                                    <label class="form-check-label align-middle fz-custom1" for="cbxIncludeProfitCenter">Include Profit Center</label>
                                </div>
                            </div>
                        </div>
                        <div class="row mt-1">
                            <div class="col-sm-4 d-flex justify-content-start align-items-center">
                            </div>
                            <div class="col-sm-8">
                                <div class="form-check">
                                    <asp:CheckBox ID="cbxOnlyBaseCurr" runat="server" CssClass="form-check-input fz-custom1" OnCheckedChanged="CheckBox_Changed" Autopostback="true" />
                                    <label class="form-check-label align-middle fz-custom1" for="cbxOnlyBaseCurr">Only Base Curr</label>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </td>
        </tr>
    </table>
</asp:Content>

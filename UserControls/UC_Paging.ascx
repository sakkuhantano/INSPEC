<%@ Control Language="C#" AutoEventWireup="true" CodeBehind="UC_Paging.ascx.cs" Inherits="WAL.UC_Paging" %>

<table cellspacing="1" cellpadding="1" border="0">
    <tr>
        <td>
            <asp:LinkButton id="lbtnPrevious"  
                            Runat="server" 
                            text="<<"
                            CssClass="sbttn"
                            CausesValidation="False" 
                            ToolTip="Previous" OnClick="lbtnPrevious_Click">
                            </asp:LinkButton>
            &nbsp;
            <asp:Label runat="server" ID="lblPage" Text="Page"></asp:Label>
            &nbsp;
            <asp:DropDownList ID="ddlPaging" 
                              runat="server" 
                              AutoPostBack="true" 
                              width="50px" 
                              OnSelectedIndexChanged="ddlPaging_SelectedIndexChanged" 
                              >
            </asp:DropDownList>
            &nbsp;
            <asp:Label runat="server" ID="lblOF" Text="of"></asp:Label>
            &nbsp;
            <asp:Label runat="server" ID="lblMaxRowOnEachPage" Text="" Visible="false"></asp:Label>
            <asp:Label runat="server" ID="lblTotalPage" Text=""></asp:Label>
            &nbsp;
            <asp:LinkButton id="lbtnNext"  
                            Runat="server" 
                            text=">>"
                            CssClass="sbttn"
                            CausesValidation="False" 
                            ToolTip="Next" OnClick="lbtnNext_Click">
                            </asp:LinkButton>
        </td>
    </tr>
</table>
<%@ Page Title="" Language="C#" MasterPageFile="~/MasterPages/Site_BS_5.Master" AutoEventWireup="true" CodeBehind="Main.aspx.cs" Inherits="INSPEC.Secure.Main" %>
<%@ MasterType VirtualPath="~/MasterPages/Site_BS_5.Master" %>

<asp:Content ID="Content1" ContentPlaceHolderID="head" runat="server">
    <style type="text/css">
        .CUS-FF {
            font-family: Snell Roundhand, Courier New, Courier, monospace;
            font-weight:bold;
            font-size: 16px; 
            letter-spacing: 10px; 
            text-transform: uppercase;
        }

        @media only screen and (max-width: 992px) {
            .CUS-FF {
                letter-spacing: 7px; 
            }
        }

        @media only screen and (max-width: 768px) {
            .CUS-FF {
                letter-spacing: 4px; 
            }
        }

        @media only screen and (max-width: 576px) {
            .CUS-FF {
                letter-spacing: 0px; 
            }
        }
    </style>
    <script type='text/javascript'>
        
    </script>
</asp:Content>
<asp:Content ID="Content2" ContentPlaceHolderID="ContentPlaceHolder1" runat="server">
    <table border="0" cellspacing="0" cellpadding="0" style="width:100%;height:100%;">
    <tr>
        <td>
            <div id="divTittle" class="row justify-content-center align-items-center" style="margin:auto;z-index:-10;width:100%;">                
                <div class="CUS-FF col-sm-9 alert alert-info shadow d-flex justify-content-center align-items-center text-center" style="border-radius:40px;height:100%; min-height:70px;max-width:98%;">
                    <asp:Label ID="Label1" runat="server" Text="MOBILE INSPECTION"></asp:Label>
                </div>
            </div>
        </td>
    </tr>
    </table>

    <script>
        $(document).ready(function () {
            $("#div_menu_site").removeClass("shadow-sm");
            $("#div_menu_site").addClass("shadow");
        });
    </script>
</asp:Content>

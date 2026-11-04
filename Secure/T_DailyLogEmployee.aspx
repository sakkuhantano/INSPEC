<%@ Page Title="" Language="C#" MaintainScrollPositionOnPostback="true" MasterPageFile="~/MasterPages/Site1.Master" AutoEventWireup="true" CodeBehind="T_DailyLogEmployee.aspx.cs" Inherits="INSPEC.Secure.T_DailyLogEmployee" %>
<%@ MasterType VirtualPath="~/MasterPages/Site1.Master" %>

<asp:Content ID="Content1" ContentPlaceHolderID="head" runat="server">
    <link rel="stylesheet" href="../../WebFolder/bootstrap/css/bootstrap-datepicker3.css" />
    <script type="text/javascript" src="../../WebFolder/bootstrap/js/bootstrap-datepicker.min.js"></script>
    <style type="text/css">
      /* Scoped styles: do not override existing ASP.NET Master Page / ERP CSS. */
.la-page{font:12px Arial,Tahoma,sans-serif;color:#31485c;background:#f6f8fa;padding:13px;min-height:400px}
.la-page *{box-sizing:border-box}
.la-page button,.la-page input,.la-page select,.la-page textarea{font:12px Arial,Tahoma,sans-serif}
.la-page button{cursor:pointer}
.la-page button:disabled{opacity:.4;cursor:default}
.la-page button:focus,.la-page input:focus,.la-page select:focus,.la-page textarea:focus{outline:2px solid #8ed4e5;outline-offset:1px}
.la-head{background:#fff;border:1px solid #dbe3e9;border-radius:4px;text-align:center;padding:14px;margin-bottom:10px}
.la-heading{font-size:16px;font-weight:bold;color:#172c3e}
.la-subhead{color:#7a8d9d;font-size:11px;margin-top:4px}
.la-panel{background:#fff;border:1px solid #dbe3e9;border-radius:5px;margin-bottom:11px;overflow:hidden}
.la-date-panel{padding:16px 18px}
.la-label{display:block;color:#4e6779;font-size:11px;font-weight:bold;margin-bottom:8px}
.la-date-tools{display:table;width:100%}
.la-date-left,.la-date-right{display:table-cell;vertical-align:middle}
.la-date-right{text-align:right}
.la-date-trigger{background:#fff;border:1px solid #c7d6df;border-radius:4px;height:36px;padding:0 13px;color:#294960;font-weight:bold;white-space:nowrap;min-width:154px;text-align:left}
.la-nav{white-space:nowrap}
.la-nav button{display:inline-block;vertical-align:middle;min-width:36px;height:34px;margin-left:5px;border:1px solid #00a2c1;background:white;color:#008ea9;border-radius:18px;font-size:17px;text-align:center}
.la-nav button:hover:not(:disabled){background:#e9f9fc}
.la-nav .la-today{min-width:87px;padding:0 12px;font-size:12px;font-weight:bold;white-space:nowrap;background:#eaf8fc}
.la-date-caption{color:#8093a2;font-size:11px;margin-top:9px}
.la-pill{display:inline-block;padding:7px 12px;border:1px solid #00a2c1;border-radius:17px;background:white;color:#008fac;white-space:nowrap}
.la-pill:hover{background:#e8f8fc}
.la-pill.la-primary{background:#009fbd;color:white}
.la-pill.la-neutral{color:#5a7486;border-color:#cbd9e2}

.la-list-header{padding:14px 16px 10px}
.la-list-header strong{font-size:14px;color:#254258}
.la-hint{font-size:11px;color:#8d9da9;margin-top:4px}

.la-filters{padding:0 16px 13px}
.la-page input,.la-page select,.la-page textarea{background:#fff;border:1px solid #cbd8e1;color:#30485f;border-radius:4px;padding:8px 10px;max-width:100%}
.la-filters input{width:245px;max-width:52%}
.la-filters select{width:160px;max-width:43%;margin-left:6px}
.la-table-wrap{overflow-x:auto}
.la-table{width:100%;min-width:615px;border-collapse:collapse;table-layout:fixed}
.la-table th{background:#edf1f5;border-top:1px solid #dee6eb;border-bottom:1px solid #dee6eb;text-align:left;padding:12px;font-size:10px;color:#587080}
.la-table td{height:59px;border-bottom:1px solid #e8eef2;padding:11px 12px;vertical-align:middle}
.la-table th.la-action-cell,.la-table td.la-action-cell{text-align:center!important;vertical-align:middle!important;padding:6px!important}
.la-person{font-weight:bold;color:#28485c}
.la-secondary{margin-top:4px;font-size:10px;color:#95a6b2}
.la-shift{font-weight:bold;color:#345773}
.la-status{color:#a57829;white-space:nowrap}
.la-status.la-filled{color:#24815c}
.la-status:before{content:"";display:inline-block;width:7px;height:7px;margin-right:7px;background:currentColor;border-radius:50%;vertical-align:middle}
.la-row-button{display:inline-block;vertical-align:middle;text-align:center;width:90px;height:33px;line-height:31px;padding:0;margin:0;border:1px solid #00a4c3;border-radius:17px;background:#fff;color:#008ba8;font-weight:bold}
.la-row-button:hover{background:#e9faff}
.la-row-button.la-fill{background:#eaf9fc}
.la-row-button.la-close{color:#5c7889;border-color:#cbd8df}
.la-active-parent{background:#eaf7fb}
.la-child-row td{padding:0!important;height:auto!important;border-bottom:2px solid #b9dce8!important}
.la-child{padding:14px 17px;background:#f2f9fc;border-left:3px solid #00a3c3}
.la-child-card{border:1px solid #d7e5ec;background:white;border-radius:5px;overflow:hidden}
.la-child-header{padding:12px 15px;border-bottom:1px solid #e3ebf0;background:#fafcfd}
.la-child-tools{display:table;width:100%}
.la-child-name,.la-child-buttons{display:table-cell;vertical-align:middle}
.la-child-name strong{font-size:13px;color:#2c4c61}
.la-child-name small{display:block;font-size:11px;color:#8e9fad;margin-top:3px}
.la-child-buttons{text-align:right}
.la-child-buttons .la-pill{margin-left:4px}
.la-records{padding:2px 15px 13px}
.la-record{display:table;width:100%;table-layout:fixed;padding:13px 0;border-bottom:1px solid #e8eef2}
.la-record:last-child{border-bottom:0}
.la-record-time,.la-record-desc,.la-record-actions{display:table-cell;vertical-align:top}
.la-record-time{width:29%;padding-right:12px}
.la-record-time strong{color:#295370}
.la-record-time small{display:block;font-size:10px;color:#8a9cab;margin-top:4px}
.la-record-desc{width:48%;line-height:1.6;white-space:pre-wrap;overflow-wrap:break-word;padding-right:10px}
.la-record-actions{width:23%;text-align:right;white-space:nowrap}
.la-record-actions button{border:1px solid #b8dae6;border-radius:13px;background:#fff;padding:5px 9px;color:#008da9;margin-left:3px}

.la-form{padding:16px}
.la-form-title{font-size:14px;color:#2b4b63;font-weight:bold;margin-bottom:13px}
.la-form-columns{display:table;width:100%;table-layout:fixed}
.la-form-column{display:table-cell;vertical-align:top;width:50%;padding-right:11px}
.la-form-column:last-child{padding-right:0;padding-left:11px}
.la-field{margin-bottom:13px}
.la-field label{display:block;font-size:11px;color:#567083;font-weight:bold;margin-bottom:6px}
.la-field input,.la-field select,.la-field textarea{display:block;width:100%}
.la-field textarea{resize:vertical;line-height:1.55}
.la-form-footer{border-top:1px solid #e6edf1;padding-top:12px}

.la-confirm{padding:18px}
.la-confirm h3{font-size:14px;color:#344d61;margin:0 0 8px}
.la-confirm p{color:#768a99;line-height:1.6}
.la-confirm-preview{background:#f6f9fa;border:1px solid #e2eaf0;border-radius:4px;padding:12px;line-height:1.6;margin:12px 0 15px;white-space:pre-wrap;overflow-wrap:break-word}
.la-empty{text-align:center;padding:20px!important;color:#8799a7!important}
.la-pager{display:table;width:100%;border-top:1px solid #e6edf1;padding:13px 15px}
.la-range,.la-page-controls{display:table-cell;vertical-align:middle}
.la-range{font-size:11px;color:#8296a5}
.la-page-controls{text-align:right;white-space:nowrap}
.la-page-controls select{padding:6px;margin-right:8px}
.la-page-button{width:31px;height:31px;border:1px solid #d3e0e8;border-radius:4px;background:white;color:#58788c;margin-left:4px}
.la-page-button.la-on{background:#00a1be;border-color:#00a1be;color:#fff;font-weight:bold}



@media(max-width:720px){
 .la-page{padding:9px}
 .la-date-panel{padding:14px}
 .la-date-left,.la-date-right{display:block;text-align:left}
 .la-date-right{margin-top:12px}
 .la-child{padding:9px}
 .la-child-name,.la-child-buttons{display:block;text-align:left}
 .la-child-buttons{margin-top:10px}
 .la-child-buttons .la-pill{margin:0 5px 0 0}
 .la-record-time,.la-record-desc,.la-record-actions{display:block;width:100%;text-align:left;padding:0}
 .la-record-desc,.la-record-actions{margin-top:9px}
 .la-record-actions button{margin:0 6px 0 0}
 .la-form-column,.la-form-column:last-child{display:block;width:100%;padding:0}
 .la-range,.la-page-controls{display:block;text-align:center}
 .la-page-controls{margin-top:12px}
}
@media(max-width:600px){
 .la-table{display:block;min-width:0}
 .la-table thead{display:none}
 .la-table tbody,.la-table tr,.la-table td{display:block;min-width:0;width:100%;height:auto}
 .la-table tr.la-member-row{padding:11px;border-bottom:1px solid #e4eaef}
 .la-table tr.la-member-row td{padding:5px 8px;border:0}
 .la-table tr.la-member-row td.la-number{display:none}
 .la-table tr.la-member-row td.la-action-cell{text-align:center!important;padding:9px 8px 3px!important}
 .la-row-button{width:100%;max-width:200px}
 .la-table tr.la-child-row td{display:block;padding:0!important}
 .la-filters input,.la-filters select{max-width:100%;width:100%;margin:0 0 8px}
}

/* ASP.NET server-control refinements; keep existing ERP CSS untouched. */
.la-page .la-date-caption{display:block}
.la-server-date{display:inline-block;text-decoration:none!important;line-height:34px;vertical-align:middle}
.la-nav .la-server-nav{display:inline-block;line-height:33px;text-decoration:none;vertical-align:middle;white-space:nowrap}
.la-nav .la-server-nav.la-today{line-height:33px}
.la-net-filters input{width:230px;max-width:45%}
.la-net-filters .la-pill{margin-left:6px;vertical-align:middle}
.la-net-filters select{vertical-align:middle;margin-left:6px}
.la-server-table .la-row-button{line-height:31px;text-decoration:none}
.la-server-table .la-record-actions a{display:inline-block;text-decoration:none}
.la-server-table .la-record-actions a:hover{background:#e8f8fc}
.la-net-page{display:inline-block;vertical-align:middle;text-align:center;line-height:29px;text-decoration:none}
.la-progress{position:fixed;bottom:15px;right:15px;z-index:100;background:#143047;color:#fff;border-radius:5px;padding:11px 16px;box-shadow:0 4px 14px rgba(0,0,0,.18)}
.la-record-desc{overflow-wrap:break-word;word-wrap:break-word}
.la-form-footer a{margin-right:7px;text-decoration:none}
.la-child-buttons a{text-decoration:none}
.la-confirm a{text-decoration:none;margin-right:7px}
.la-page .la-empty{display:block}
.la-page .la-pill{line-height:18px}
@media(max-width:720px){
  .la-net-filters input{display:block;width:100%;max-width:100%;margin-bottom:8px}
  .la-net-filters .la-pill{margin-left:0}
  .la-net-filters select{width:auto;max-width:100%}
}

/* Pastikan tombol aksi dan judul AKSI rata tengah pada IE10/11. */
.la-server-table th.la-action-cell,.la-server-table td.la-action-cell{text-align:center!important;vertical-align:middle!important}
.la-server-table td.la-action-cell .la-row-button{display:inline-block;vertical-align:middle;text-align:center}


/* Konfirmasi Hapus dan notifikasi Save/Edit/Delete — ringan, responsif, IE10/11. */

.la-confirm h3{font-size:15px;color:#263f53;margin-bottom:5px}
.la-confirm p{margin:0 0 8px}
.la-confirm-preview{padding:13px 15px;margin:12px 0;border-left:3px solid #00a2c1;background:#f7fbfc}
.la-confirm-person{font-weight:bold;font-size:12px;color:#2d4d62}
.la-confirm-time{margin-top:6px;color:#486b81;font-size:11px}
.la-confirm-description{border-top:1px solid #e3ecf2;padding-top:9px;margin-top:10px;color:#314e62;white-space:pre-wrap;overflow-wrap:break-word;word-wrap:break-word}
.la-confirm .la-confirm-warning{font-size:11px;color:#8e6571;margin:0 0 16px}
.la-confirm-buttons{white-space:nowrap}
.la-confirm-buttons .la-pill{text-decoration:none!important;display:inline-block;text-align:center;min-width:93px;margin:0 8px 0 0!important;vertical-align:middle;padding:9px 15px}
.la-pill.la-danger-solid{background:#b74646;border-color:#b74646;color:#fff;font-weight:bold}
.la-pill.la-danger-solid:hover{background:#9f3636;border-color:#9f3636}
@media(max-width:450px){
  .la-confirm{padding:14px}
  .la-confirm-buttons{white-space:normal}
  .la-confirm-buttons .la-pill{margin-bottom:5px!important}
}



/* UI polish v2 — kotak ringkasan, ikon cari, tombol aksi konsisten.
   CSS IE10/11 compatible: display:table/inline-block, tanpa flex/grid. */
.la-stats-grid{display:table;width:100%;table-layout:fixed;margin:13px 0 3px;border-spacing:0}
.la-stat-cell{display:table-cell;vertical-align:top;width:33.3333%;padding-right:9px}
.la-stat-cell:last-child{padding-right:0}
.la-stat-box{border:1px solid #dce6ed;border-left:3px solid #00a5c5;border-radius:5px;background:#f8fbfd;min-height:78px;padding:12px 14px}
.la-stat-label{display:block;color:#586f81;font-size:11px;line-height:15px;font-weight:normal;margin-bottom:7px}
.la-stat-number{display:block;font-size:24px;line-height:27px;letter-spacing:-.4px;color:#203c50;font-weight:bold}
.la-stat-done{border-left-color:#399475;background:#f6fbf8}
.la-stat-done .la-stat-number{color:#257959}
.la-stat-pending{border-left-color:#cf9a54;background:#fffcf8}
.la-stat-pending .la-stat-number{color:#92632c}

/* Satu search bar dengan tombol kaca pembesar sebagai aksi pencarian. */
.la-filters-enhanced{padding-top:2px;padding-bottom:15px}
.la-search-group{display:inline-table;table-layout:fixed;width:306px;max-width:100%;vertical-align:middle;border:1px solid #c4d7e2;border-radius:5px;overflow:hidden;background:#fff}
.la-page .la-search-group input.la-search-input{display:table-cell;width:100%;max-width:none;height:35px;border:0;border-radius:0;margin:0;padding:7px 11px;vertical-align:middle;background:#fff;font-size:12px;outline-offset:-2px}
.la-net-filters .la-search-group .la-search-button{display:table-cell;width:41px;height:35px;line-height:33px;vertical-align:middle;text-align:center;border-left:1px solid #b7dce7;background:#eefaff;color:#008ba8;text-decoration:none;white-space:nowrap;padding:0;margin:0}
.la-net-filters .la-search-group .la-search-button:hover{background:#daf4fa}
.la-search-icon{display:inline-block;width:14px;height:14px;border:2px solid #008da9;border-radius:50%;position:relative;vertical-align:middle;margin-top:-4px;margin-right:3px}
.la-search-icon:after{content:"";position:absolute;width:8px;height:2px;background:#008da9;right:-7px;bottom:-3px;transform:rotate(45deg);-ms-transform:rotate(45deg)}
.la-sr-only{position:absolute!important;width:1px!important;height:1px!important;overflow:hidden!important;clip:rect(0,0,0,0)!important;white-space:nowrap!important}
.la-filters-enhanced select{height:37px;min-width:155px;max-width:100%;vertical-align:middle;margin-left:9px}

/* Edit/Hapus: bentuk, tinggi, lebar dan alignment seragam, tanpa ikon/emoji. */
.la-record-time{width:28%}
.la-record-desc{width:44%}
.la-record-actions{width:28%;text-align:right;white-space:nowrap;vertical-align:middle}
.la-server-table .la-record-actions a.la-mini-btn{display:inline-block;vertical-align:middle;box-sizing:border-box;width:71px;height:32px;line-height:30px;padding:0 7px;text-align:center;text-decoration:none!important;border-radius:5px;border:1px solid #b7dce8;font-weight:bold;font-size:11px;white-space:nowrap;margin-left:5px;background:#f2fafe;color:#007e9d;box-shadow:none}
.la-server-table .la-record-actions a.la-mini-edit:hover{background:#dff4fc;border-color:#8dcbdc}
.la-server-table .la-record-actions a.la-mini-delete{border-color:#e4c1c1;background:#fff9f9;color:#b34b4b}
.la-server-table .la-record-actions a.la-mini-delete:hover{background:#fff0f0;border-color:#dba3a3}
.la-server-table .la-record-actions a.la-mini-btn:focus{outline:2px solid #80c7de;outline-offset:1px}

@media(max-width:720px){
  .la-record-time,.la-record-desc,.la-record-actions{display:block;width:100%;text-align:left;vertical-align:top}
  .la-record-actions{margin-top:10px}
  .la-server-table .la-record-actions a.la-mini-btn{margin-left:0;margin-right:7px}
}
@media(max-width:600px){
  .la-stats-grid{display:table;width:100%;table-layout:fixed}
  .la-stat-cell{padding-right:6px}
  .la-stat-box{min-height:72px;padding:10px 9px}
  .la-stat-label{font-size:10px;line-height:13px}
  .la-stat-number{font-size:21px;line-height:24px}
  .la-net-filters .la-search-group{display:table;width:100%;max-width:100%;margin-bottom:9px}
  .la-filters-enhanced select{display:block;width:100%;margin:0}
}
@media(max-width:360px){
  .la-stats-grid,.la-stat-cell{display:block;width:100%}
  .la-stat-cell{padding:0 0 7px}
  .la-stat-box{min-height:0;padding:10px 12px}
  .la-stat-label,.la-stat-number{display:inline-block;vertical-align:middle;margin:0}
  .la-stat-number{float:right;font-size:20px;line-height:21px}
}

/* Sel tabel pembungkus menjaga ukuran input dan ikon tetap konsisten di IE10/IE11. */
.la-search-input-cell,.la-search-button-cell{display:table-cell;vertical-align:middle}
.la-search-button-cell{width:42px;border-left:1px solid #b7dce7}
.la-page .la-search-input-cell input.la-search-input{display:block;width:100%;max-width:none;height:35px;outline-offset:-2px}
.la-net-filters .la-search-button-cell .la-search-button{display:block;width:41px;height:35px;line-height:33px;border-left:0;margin:0}


/* Log Aktivitas — spacing fix only (VS2013 / IE10+).
   Paste at the VERY END of Content/log-aktivitas-updatepanel.css */

/* Detail child row: breathing room above/below the records. */
.la-page .la-child {
    padding: 18px 20px 20px;
}
.la-page .la-records {
    padding: 14px 18px 20px;
}
.la-page .la-record {
    padding: 15px 0;
    min-height: 60px;
}
.la-page .la-record-time,
.la-page .la-record-desc,
.la-page .la-record-actions {
    vertical-align: middle;
}
.la-page .la-record-actions .la-mini-btn {
    margin-top: 3px;
    margin-bottom: 3px;
}

/* Pagination: keep away from the table's bottom border and container edge. */
.la-page .la-pager {
    padding: 17px 20px 20px;
    min-height: 66px;
    border-top: 1px solid #e6edf1;
}
.la-page .la-range,
.la-page .la-page-controls {
    vertical-align: middle;
}
.la-page .la-page-controls select,
.la-page .la-page-button {
    vertical-align: middle;
}

@media (max-width: 720px) {
    .la-page .la-child { padding: 12px; }
    .la-page .la-records { padding: 12px 13px 17px; }
    .la-page .la-record { padding: 13px 0; }
    .la-page .la-pager { padding: 16px 12px 20px; }
    .la-page .la-range,
    .la-page .la-page-controls { display: block; text-align: center; }
    .la-page .la-page-controls { margin-top: 13px; }
}


/* Bootstrap Datepicker — konsisten dengan tema ERP, tidak terpotong oleh panel. */
.la-page .la-date-panel { overflow: visible; }
.la-page .la-date-tools { overflow: visible; }
.la-page input.la-server-date { width: 176px; min-width: 0; max-width: 100%;
    height: 36px; line-height: 20px; padding: 7px 12px; cursor: pointer;
    background: #fff; border: 1px solid #c7d6df; border-radius: 4px;
    color: #294960; font-weight: bold; }
.la-page input.la-server-date:focus { border-color: #00a4c3; box-shadow: 0 0 0 2px rgba(0,164,195,.12); }
.datepicker.dropdown-menu { z-index: 2100 !important; max-width: calc(100vw - 20px); }
.datepicker table { width: 100%; }
.datepicker table tr td.active, .datepicker table tr td.active:hover,
.datepicker table tr td span.active, .datepicker table tr td span.active:hover {
    background: #009fbd !important; color: #fff !important;
}
.datepicker table tr td.today:not(.active) { background: #e6f8fb !important; }
@media (max-width: 600px) {
    .la-page input.la-server-date { width: 100%; max-width: 280px; }
    .datepicker.dropdown-menu { font-size: 13px; }
}

/* Section + Profit Center + Ringkasan Aktivitas, IE10/11 */




.la-page .la-filters-enhanced select {min-width:120px;max-width:210px}
.la-page .la-hidden-date {display:none!important}
.la-page .la-form-note {font-size:11px;color:#728c9c;line-height:1.5;padding:0 0 12px}
.la-page .la-auto-time {text-align:center;font-size:13px;letter-spacing:.35px}
@media(max-width:760px){
 .la-page .la-filters-enhanced select {display:block;width:100%;max-width:100%;margin:9px 0 0}
 
 
}

/* Header metadata: ProfitCenterNo + SectionID milik employee login.
   Field dibentuk tanpa flex/grid untuk kompatibilitas IE10/11. */
.la-page .la-date-fields { display:block; font-size:0; }
.la-page .la-header-field { display:inline-block; width:146px; max-width:100%; margin:0 13px 6px 0; vertical-align:top; font-size:12px; }
.la-page .la-header-date-field { width:176px; }
.la-page .la-header-field .la-label { margin-bottom:8px; }
.la-page .la-header-value { height:36px; line-height:34px; width:100%; overflow:hidden; text-overflow:ellipsis;
    white-space:nowrap; border:1px solid #d8e4eb; background:#f5f9fb; border-radius:4px;
    padding:0 11px; font-weight:bold; color:#365c74; }
.la-page .la-date-panel .la-date-left { width:auto; }
.la-page .la-date-panel .la-date-right { width:194px; white-space:nowrap; }
@media(max-width:850px){
    .la-page .la-date-panel .la-date-left,
    .la-page .la-date-panel .la-date-right { display:block; width:100%; text-align:left; }
    .la-page .la-date-panel .la-date-right { margin-top:9px; }
}
@media(max-width:520px){
    .la-page .la-header-field { width:calc(50% - 9px); margin-right:12px; }
    .la-page .la-header-date-field { width:100%; }
    .la-page .la-header-field:nth-child(3) { margin-right:0; }
}


/* UI PATCH 2026-10-27: tanggal, statistik, filter, modal summary. */
/* Nav: center both axes and keep datepicker below text box. */
.la-page .la-date-panel .la-nav{white-space:nowrap;font-size:0}
.la-page .la-date-panel .la-nav .la-server-nav{
  display:inline-block;box-sizing:border-box;height:38px;min-width:38px;
  line-height:36px;padding:0;margin-left:5px;vertical-align:middle;
  text-align:center;text-decoration:none!important;border:1px solid #00a4c3;
  border-radius:19px;background:#fff;color:#008caa;font-size:18px;
}
.la-page .la-date-panel .la-nav .la-server-nav.la-today{
  width:105px;min-width:105px;height:38px;line-height:36px;
  padding:0 8px;white-space:nowrap;font-size:13px;font-weight:bold;
  text-align:center;background:#eaf9fc;
}
.la-page .la-date-panel .la-nav .la-server-nav:hover{background:#dcf5fb}
.la-page input.la-server-date{position:relative}
.datepicker.datepicker-dropdown{z-index:2200!important;margin-top:6px!important}
/* This works with bootstrap-datepicker orientation:'bottom', container:'body'. */
.la-page .la-date-panel,.la-page .la-date-tools{overflow:visible!important}

/* Larger and easier-to-read dashboard numbers. */
.la-page .la-stats-grid{margin:16px 0 12px}
.la-page .la-stat-box{padding:18px 20px;min-height:110px}
.la-page .la-stat-label{font-size:13px;line-height:18px;margin-bottom:12px}
.la-page .la-stat-number{font-size:36px;line-height:39px;font-weight:bold;letter-spacing:0}

/* Filter row: search visibly bordered, status select, then summary button. */
.la-page .la-filters-enhanced{padding:3px 16px 18px;font-size:0;white-space:normal}
.la-page .la-search-group{display:inline-table;box-sizing:border-box;width:310px;max-width:100%;
  border:1px solid #aebfcf;border-radius:5px;box-shadow:0 1px 2px rgba(20,42,65,.07);vertical-align:middle}
.la-page .la-search-group:focus-within{border-color:#009fbd;box-shadow:0 0 0 2px rgba(0,159,189,.12)}
.la-page .la-search-input-cell input.la-search-input{height:41px;line-height:20px;padding:9px 12px;font-size:12px;border:0!important}
.la-page .la-search-button-cell{width:46px;border-left:1px solid #c2d7e3}
.la-page .la-net-filters .la-search-button-cell .la-search-button{width:45px;height:41px;line-height:39px;background:#ecf9fd;text-decoration:none!important}
.la-page .la-filters-enhanced select{height:42px;min-width:160px;max-width:215px;margin:0 0 0 12px;
  vertical-align:middle;border:1px solid #c4d2dd;font-size:12px}
.la-page a.la-summary-action{display:inline-block;box-sizing:border-box;vertical-align:middle;
  height:42px;line-height:40px;padding:0 20px;margin:0 0 0 12px;
  border:1px solid #009fbd;border-radius:21px;background:#009fbd;color:#fff!important;
  text-align:center;font-size:12px;font-weight:bold;white-space:nowrap;text-decoration:none!important}
.la-page a.la-summary-action:hover,.la-page a.la-summary-action:focus{
  background:#008ba6;border-color:#008ba6;color:#fff!important;text-decoration:none!important}

/* Modal is independent of Bootstrap JS and stays functional across UpdatePanel postbacks. */


@media(max-width:760px){
  .la-page .la-filters-enhanced{padding:4px 13px 14px}
  .la-page .la-search-group{display:block;width:100%;max-width:100%;margin:0 0 10px}
  .la-page .la-filters-enhanced select{display:inline-block;width:calc(50% - 5px);max-width:none;
    min-width:0;margin:0 10px 0 0}
  .la-page a.la-summary-action{display:inline-block;width:calc(50% - 5px);margin:0;min-width:0;padding:0 8px}
  
  
  
  
  
  
  .la-page .la-stat-box{min-height:93px;padding:14px 12px}
  .la-page .la-stat-label{font-size:12px;margin-bottom:9px}
  .la-page .la-stat-number{font-size:30px;line-height:33px}
}
@media(max-width:420px){
  .la-page .la-stat-cell{padding-right:4px}
  .la-page .la-stat-box{padding:12px 8px;min-height:92px}
  .la-page .la-stat-label{font-size:11px;line-height:15px}
  .la-page .la-stat-number{font-size:27px;line-height:29px}
  
  
}

/* ===============================================================
   FINAL UI PATCH 27-10-2026 | ASP.NET Web Forms / IE10+ / UpdatePanel
   Overrides only. Keep these rules AFTER existing LogAktivitas CSS.
   =============================================================== */
/* Modal center via CSS tables: stable on IE10/11 and tall screens. */


/* Main pager spacing + clickable targets. */
.la-page .la-pager{padding:23px 20px 25px!important;min-height:85px;
  margin:0;border-top:1px solid #e4eaf0;background:#fff}
.la-page .la-page-controls select{height:39px;padding:7px 12px;margin-right:8px;
  border:1px solid #cad8e2;border-radius:5px;background:#fff}
.la-page .la-page-controls .la-page-button{display:inline-block;min-width:38px;
  width:auto;height:39px;line-height:37px;padding:0 9px;vertical-align:middle;
  margin-left:5px;text-decoration:none!important}
.la-page .la-page-controls .la-page-button.aspNetDisabled{opacity:.4}
/* Modal Hapus: inherits existing PnlConfirm ID within child row but is fixed over viewport. */
.la-page .la-confirm-overlay{position:fixed!important;top:0!important;bottom:0!important;
  left:0!important;right:0!important;width:auto!important;height:auto!important;
  z-index:10510!important;padding:0!important;overflow:auto!important;background:transparent!important}
.la-page .la-confirm-backdrop{position:fixed;top:0;right:0;bottom:0;left:0;
  background:#0c2131;background:rgba(9,29,44,.65)}
.la-page .la-confirm-dialog{position:relative;width:530px;max-width:100%;margin:0 auto;
  background:#fff;border-radius:10px;border:1px solid #dbe5eb;overflow:hidden;
  text-align:left;box-shadow:0 17px 40px rgba(9,27,40,.3)}
.la-page .la-confirm-head{display:table;width:100%;background:#f9fbfd;
  padding:16px 19px;border-bottom:1px solid #e5edf2}
.la-page .la-confirm-head h3{display:table-cell;vertical-align:middle;font-size:17px;
  font-weight:bold;color:#2b475c;margin:0}
.la-page .la-confirm-x{display:table-cell;vertical-align:middle;width:32px;height:32px;
  line-height:30px;text-align:center;color:#607b8e;font-size:24px;text-decoration:none!important}
.la-page .la-confirm-body{padding:18px 20px 21px}
.la-page .la-confirm-body>p{color:#687f91;font-size:12px;margin:0 0 13px}
.la-page .la-confirm-preview{padding:16px 18px;margin:12px 0 15px;
  background:#f7fafc;border:1px solid #dfe9ef;border-left:4px solid #00a1bf;
  border-radius:6px;line-height:1.55;white-space:normal}
.la-page .la-confirm-person{font-size:14px;font-weight:bold}
.la-page .la-confirm-time{margin-top:7px;font-size:12px}
.la-page .la-confirm-description{margin-top:12px;padding-top:12px;font-size:12px;
  max-height:180px;overflow:auto;white-space:pre-wrap}
.la-page .la-confirm .la-confirm-warning{color:#9a4b45;font-size:11px;margin:0 0 16px}
.la-page .la-confirm-buttons{text-align:right;white-space:normal}
.la-page .la-confirm-buttons .la-pill{min-width:105px;margin:0 0 0 9px!important;
  line-height:18px;vertical-align:middle;text-align:center;padding:10px 17px}
/* Toast at upper-right on all scroll positions, no inline duplicate banner. */


/* Avoid 100% table overflows and keep touch targets usable. */
@media(max-width:780px){
  
  
  
  
  
  
  
  .la-page .la-confirm-body{padding:15px}
  .la-page .la-confirm-head{padding:13px 16px}
  .la-page .la-pager{padding:21px 14px 24px!important}
}
@media(max-width:480px){
  
  
  
  
  
  
  .la-page .la-confirm-head{padding:12px 14px}
  .la-page .la-confirm-body{padding:14px}
  .la-page .la-confirm-buttons .la-pill{min-width:92px;margin-left:6px!important}
  
}

/* PATCH 2026-10-27: jenis log, status bebas, ringkasan yang responsif */
.la-page .la-logtype-field {min-width:152px;}
.la-page .la-logtype-select{box-sizing:border-box;display:block;width:100%;height:38px;
  border:1px solid #c4d5df;border-radius:5px;background:#fff;color:#28475b;
  padding:5px 11px;font-size:13px;line-height:24px;}
.la-page .la-logtype-select:focus{border-color:#009cbe;outline:2px solid rgba(0,156,190,.12);}


.la-page .la-record-kind {font-size:11px;font-weight:bold;color:#167590;margin-bottom:4px;}
.la-page .la-record-status {color:#526e7e;font-size:12px;margin-top:8px;white-space:pre-wrap;overflow-wrap:break-word;}
.la-page .la-record-status span {font-weight:bold;}
.la-page .la-status-help {display:block;color:#7990a0;font-size:11px;margin-top:6px;}


.la-page .la-record-activity {white-space:pre-wrap;word-wrap:break-word;}

@media(max-width:520px) {
  .la-page .la-header-field.la-logtype-field {width:calc(50% - 9px);min-width:0;}
  
  
  
  
}
/* ==============================================================
   FINAL ESTETIK 30-10-2026
   Modal Detail mengikuti dropdown Jenis Log utama + toast modern.
   ASP.NET Web Forms 4.5 / UpdatePanel / IE10+ friendly.
   Tempel PALING BAWAH log-aktivitas-updatepanel.css bila hanya patch CSS.
   ============================================================== */

/* ---------- DETAIL MODAL ---------- */


/* ---------- TOAST / FLOAT MESSAGE ---------- */


/* ---------- RESPONSIVE ---------- */


/* ===============================================================
   FINAL FLOAT NOTIFICATION — satu-satunya message style
   ASP.NET Web Forms 4.5 / IE10+ / UpdatePanel
   =============================================================== */
.la-page .la-float-notice{
    position:fixed!important;
    top:20px!important;right:20px!important;left:auto!important;bottom:auto!important;
    z-index:2147483000!important;
    display:block!important;box-sizing:border-box!important;
    width:400px!important;max-width:calc(100% - 40px)!important;
    margin:0!important;padding:0!important;
    border:1px solid #e4eaf0!important;border-left:5px solid #20a465!important;
    border-radius:14px!important;background:#fff!important;color:#52697a!important;
    box-shadow:0 18px 46px rgba(22,42,58,.22)!important;
    text-align:left!important;overflow:hidden!important;
    -webkit-animation:laNoticeIn .22s ease-out;animation:laNoticeIn .22s ease-out;
}
.la-page .la-float-notice.la-float-notice-error{border-left-color:#d94e4e!important}
.la-page .la-float-notice.la-float-notice-success{border-left-color:#20a465!important}
.la-page .la-float-notice .la-notice-inner{
    display:table!important;width:100%!important;table-layout:fixed!important;
    box-sizing:border-box!important;padding:15px 14px 15px 15px!important;
    background:#fff!important;
}
.la-page .la-float-notice .la-notice-symbol,
.la-page .la-float-notice .la-notice-copy,
.la-page .la-float-notice .la-notice-close{display:table-cell!important;vertical-align:top!important}
.la-page .la-float-notice .la-notice-symbol{
    width:44px!important;padding:1px 10px 0 0!important;color:#20a465!important;font-size:0!important;
}
.la-page .la-float-notice .la-notice-symbol:before{
    content:"✓"!important;display:block!important;box-sizing:border-box!important;
    width:34px!important;height:34px!important;line-height:34px!important;margin:0!important;
    border:0!important;border-radius:50%!important;background:#eaf7f0!important;color:#20a465!important;
    text-align:center!important;font-family:Arial,sans-serif!important;font-size:18px!important;font-weight:bold!important;
}
.la-page .la-float-notice.la-float-notice-error .la-notice-symbol{color:#d94e4e!important}
.la-page .la-float-notice.la-float-notice-error .la-notice-symbol:before{
    content:"!"!important;background:#fff0f0!important;color:#d94e4e!important;
}
.la-page .la-float-notice .la-notice-copy{
    width:auto!important;padding:0 10px 0 0!important;overflow:hidden!important;
    color:#5d7283!important;font-size:13px!important;line-height:1.45!important;
    word-break:normal!important;overflow-wrap:break-word!important;
}
.la-page .la-float-notice .la-notice-title{
    display:block!important;margin:0 0 4px!important;color:#263d4d!important;
    font-size:15px!important;line-height:1.25!important;font-weight:700!important;
}
.la-page .la-float-notice .la-notice-message{
    display:block!important;margin:0!important;color:#627889!important;
    font-size:13px!important;line-height:1.5!important;font-weight:400!important;
}
.la-page .la-float-notice .la-notice-close{
    width:30px!important;height:30px!important;line-height:28px!important;padding:0!important;
    border:0!important;border-radius:8px!important;background:transparent!important;color:#879aa8!important;
    text-align:center!important;text-decoration:none!important;font-family:Arial,sans-serif!important;
    font-size:22px!important;font-weight:400!important;opacity:1!important;cursor:pointer!important;
}
.la-page .la-float-notice .la-notice-close:hover,
.la-page .la-float-notice .la-notice-close:focus{
    background:#f2f6f8!important;color:#4d6576!important;outline:none!important;text-decoration:none!important;
}
@-webkit-keyframes laNoticeIn{from{opacity:0;-webkit-transform:translateY(-10px);transform:translateY(-10px)}to{opacity:1;-webkit-transform:translateY(0);transform:translateY(0)}}
@keyframes laNoticeIn{from{opacity:0;-webkit-transform:translateY(-10px);transform:translateY(-10px)}to{opacity:1;-webkit-transform:translateY(0);transform:translateY(0)}}
@media(max-width:767px){
    .la-page .la-float-notice{
        top:12px!important;right:12px!important;left:12px!important;width:auto!important;max-width:none!important;border-radius:12px!important;
    }
    .la-page .la-float-notice .la-notice-inner{padding:13px 11px 13px 12px!important}
    .la-page .la-float-notice .la-notice-symbol{width:40px!important;padding-right:8px!important}
    .la-page .la-float-notice .la-notice-symbol:before{width:31px!important;height:31px!important;line-height:31px!important;font-size:17px!important}
    .la-page .la-float-notice .la-notice-title{font-size:14px!important}
    .la-page .la-float-notice .la-notice-message{font-size:12px!important}
}

/* =====================================================================
   DETAIL AKTIVITAS — FINAL MODERN MODAL
   Satu-satunya style untuk modal ringkasan. Kompatibel IE10/IE11.
   ===================================================================== */
.la-page .la-summary-overlay{
    position:fixed;z-index:10050;top:0;right:0;bottom:0;left:0;
    overflow:auto;padding:0;text-align:center;-webkit-overflow-scrolling:touch;
}
.la-page .la-summary-backdrop{
    position:fixed;z-index:0;top:0;right:0;bottom:0;left:0;
    background:#112737;background:rgba(11,31,46,.60);
}
.la-page .la-dialog-table{display:table;width:100%;height:100%;table-layout:fixed}
.la-page .la-dialog-center{display:table-cell;padding:28px 20px;vertical-align:middle}
.la-page .la-summary-dialog{
    position:relative;z-index:1;display:block;width:1080px;max-width:100%;margin:0 auto;
    overflow:hidden;text-align:left;background:#fff;border:1px solid #e1e8ee;border-radius:16px;
    box-shadow:0 24px 65px rgba(8,31,47,.30);
}
.la-page .la-summary-modal-head{
    display:table;width:100%;box-sizing:border-box;table-layout:fixed;
    padding:22px 24px 18px;background:#fff;border-bottom:1px solid #edf1f4;
}
.la-page .la-summary-modal-title,.la-page .la-summary-modal-close{display:table-cell;vertical-align:middle}
.la-page .la-summary-modal-title{padding-right:18px}
.la-page .la-summary-title-text{
    display:block;margin:0 0 5px;color:#203746;font-size:23px;line-height:1.2;font-weight:700;
    letter-spacing:-.2px;
}
.la-page .la-summary-date{display:block;color:#7a8d9b;font-size:12px;line-height:1.45;font-weight:normal}
.la-page a.la-summary-modal-close{
    width:36px;height:36px;line-height:33px;text-align:center;border:1px solid #dae3e9;
    border-radius:10px;background:#fff;color:#718493!important;font-size:22px;font-weight:400;
    text-decoration:none!important;box-shadow:none;
}
.la-page a.la-summary-modal-close:hover,.la-page a.la-summary-modal-close:focus{
    background:#f5f8fa;border-color:#c7d4dd;color:#314a5b!important;outline:0;text-decoration:none!important;
}
.la-page .la-summary-modal-content{padding:22px 24px 24px;background:#fff}
.la-page .la-summary-search-row{margin:0 0 18px}
.la-page .la-summary-search-shell{
    display:table;width:520px;max-width:100%;height:46px;box-sizing:border-box;table-layout:fixed;
    overflow:hidden;background:#fff;border:1px solid #d5e0e7;border-radius:11px;
    box-shadow:0 1px 3px rgba(18,50,70,.05);
}
.la-page .la-summary-search-shell:focus-within{border-color:#1aa9c2;box-shadow:0 0 0 3px rgba(26,169,194,.10)}
.la-page .la-summary-search-leading{
    display:table-cell;width:42px;vertical-align:middle;position:relative;
}
.la-page .la-summary-search-leading:before{
    content:"";display:block;width:13px;height:13px;margin:0 auto;border:2px solid #73909f;border-radius:50%;
}
.la-page .la-summary-search-leading:after{
    content:"";position:absolute;width:7px;height:2px;background:#73909f;left:25px;top:27px;
    -webkit-transform:rotate(45deg);transform:rotate(45deg);-webkit-transform-origin:left center;transform-origin:left center;
}
.la-page input.la-summary-search-input{
    display:table-cell;width:100%;height:44px;box-sizing:border-box;padding:10px 8px 10px 0;
    border:0!important;outline:0!important;background:#fff;color:#30495a;font-size:13px;box-shadow:none!important;
}
.la-page a.la-summary-search-btn{
    display:table-cell;width:72px;height:44px;line-height:44px;vertical-align:middle;text-align:center;
    border-left:1px solid #e5ebef;background:#eef9fb;color:#078eaa!important;font-size:12px;font-weight:700;
    text-decoration:none!important;
}
.la-page a.la-summary-search-btn:hover,.la-page a.la-summary-search-btn:focus{
    background:#e3f5f8;color:#067d96!important;text-decoration:none!important;outline:0;
}
.la-page .la-summary-scroll{
    position:relative;max-height:50vh;overflow:auto;background:#fff;border:1px solid #e5ebf0;border-radius:12px;
}
.la-page .la-summary-table{width:100%;min-width:790px;margin:0;border-collapse:collapse;background:#fff}
.la-page .la-summary-table th{
    padding:14px 16px;background:#f4f7f9;color:#516a7a;border-bottom:1px solid #e2e9ee;
    font-size:12px;line-height:1.35;font-weight:700;text-align:left;white-space:nowrap;
}
.la-page .la-summary-table td{
    padding:15px 16px;color:#324b5c;border-top:1px solid #edf2f5;font-size:13px;line-height:1.55;vertical-align:top;
}
.la-page .la-summary-table tbody tr:first-child td{border-top:0}
.la-page .la-summary-table tbody tr:hover td{background:#fbfdfe}
.la-page .la-summary-date-cell{white-space:nowrap;color:#657c8c}
.la-page .la-summary-name{min-width:145px;font-weight:700;color:#284354}
.la-page .la-summary-activity{min-width:210px;white-space:normal;word-wrap:break-word}
.la-page .la-summary-status{min-width:145px;color:#596f7f;white-space:normal;word-wrap:break-word}
.la-page .la-time-chip{
    display:inline-block;min-width:48px;padding:4px 8px;text-align:center;white-space:nowrap;
    background:#eef8fa;border:1px solid #d8edf1;border-radius:7px;color:#247488;font-size:12px;font-weight:700;
}
.la-page .la-summary-empty{
    display:block!important;box-sizing:border-box;padding:48px 22px;text-align:center;color:#7b8e9c;
    font-size:13px;line-height:1.55;background:#fff;
}
.la-page .la-summary-empty:before{
    content:"";display:block;width:38px;height:38px;margin:0 auto 12px;border:1px solid #d9e4ea;
    border-radius:50%;background:#f7fafb;
}
.la-page .la-summary-modal-footer{
    display:table;width:100%;box-sizing:border-box;table-layout:fixed;padding:16px 24px 19px;
    background:#fbfcfd;border-top:1px solid #edf1f4;
}
.la-page .la-summary-range,.la-page .la-summary-modal-pager{display:table-cell;vertical-align:middle}
.la-page .la-summary-range{padding-right:16px;color:#728694;font-size:12px}
.la-page .la-summary-modal-pager{text-align:right;white-space:nowrap}
.la-page a.la-summary-page-btn{
    display:inline-block;width:36px;height:36px;box-sizing:border-box;margin-left:6px;line-height:33px;text-align:center;
    background:#fff;border:1px solid #d8e2e8;border-radius:9px;color:#607888!important;font-size:18px;font-weight:400;
    text-decoration:none!important;
}
.la-page a.la-summary-page-btn:hover,.la-page a.la-summary-page-btn:focus{
    background:#f3f8fa;border-color:#bfd0d9;color:#304b5d!important;text-decoration:none!important;outline:0;
}
.la-page a.la-summary-page-btn.aspNetDisabled,.la-page a.la-summary-page-btn[disabled]{opacity:.38;cursor:default;background:#f7f9fa}
.la-page .la-summary-page-label{
    display:inline-block;min-width:64px;padding:0 8px;text-align:center;color:#3f596a;font-size:12px;font-weight:700;
}
@media(max-width:780px){
    .la-page .la-dialog-center{padding:14px 9px}
    .la-page .la-summary-dialog{width:100%;border-radius:12px}
    .la-page .la-summary-modal-head{padding:17px 16px 14px}
    .la-page .la-summary-title-text{font-size:19px}
    .la-page .la-summary-modal-content{padding:15px 14px 17px}
    .la-page .la-summary-search-shell{width:100%}
    .la-page .la-summary-scroll{max-height:52vh}
    .la-page .la-summary-modal-footer{padding:15px 14px 18px}
    .la-page .la-summary-range,.la-page .la-summary-modal-pager{display:block;width:100%;text-align:center}
    .la-page .la-summary-range{padding:0 0 12px}
}
@media(max-width:480px){
    .la-page .la-dialog-center{padding:8px 5px}
    .la-page .la-summary-modal-head{padding:14px 12px}
    .la-page .la-summary-title-text{font-size:17px}
    .la-page .la-summary-date{font-size:11px}
    .la-page a.la-summary-modal-close{width:34px;height:34px;line-height:31px;font-size:20px}
    .la-page .la-summary-modal-content{padding:12px 10px 14px}
    .la-page .la-summary-scroll{max-height:55vh;border-radius:9px}
    .la-page .la-summary-table{min-width:720px}
    .la-page .la-summary-table th,.la-page .la-summary-table td{padding:12px 13px}
}

/* Character counter: Aktivitas 1000 karakter, Status 200 karakter. */
.la-page .la-field-label-row{display:table;width:100%;margin-bottom:6px;table-layout:fixed}
.la-page .la-field-label-row label,.la-page .la-word-counter{display:table-cell;vertical-align:bottom}
.la-page .la-field-label-row label{padding-right:12px;color:#40586a;font-weight:600}
.la-page .la-word-counter{text-align:right;white-space:nowrap;color:#718594;font-size:11px;font-weight:600}
.la-page .la-word-counter-low{color:#b55f28}
.la-page textarea.la-word-input{resize:vertical}
@media(max-width:480px){
    .la-page .la-field-label-row{display:block}
    .la-page .la-field-label-row label,.la-page .la-word-counter{display:block;width:100%;text-align:left}
    .la-page .la-word-counter{margin-top:3px}
}


    </style>
</asp:Content>
<asp:Content ID="Content2" ContentPlaceHolderID="ContentPlaceHolder1" runat="server">
    <asp:ScriptManager ID="smLogAktivitas" runat="server" EnablePartialRendering="true" />
    <asp:UpdatePanel ID="upLogAktivitas" runat="server" UpdateMode="Conditional" ChildrenAsTriggers="true">
    <ContentTemplate>
    <div class="la-page">
        <div class="la-head">
            <div class="la-heading">LOG AKTIVITAS ANAK BUAH</div>
            <div class="la-subhead">Pencatatan shift dan monitoring aktivitas harian</div>
        </div>

        <div class="la-panel la-date-panel">
            <div class="la-date-tools">
                <div class="la-date-left">
                    <div class="la-date-fields">
                        <div class="la-header-field la-header-date-field">
                            <span class="la-label">Tanggal Aktivitas</span>
                            <asp:TextBox ID="txtPeriod" runat="server" EnableViewState="false" CssClass="la-date-trigger la-server-date"
                                placeholder="Pilih Tanggal Periode" autocomplete="off" onkeypress="return false;"
                                onpaste="return false;"></asp:TextBox>
                            <asp:LinkButton ID="btnPeriodChanged" runat="server" Style="display:none"
                                OnClick="btnPeriodChanged_Click" CausesValidation="false" />
                        </div>
                        <div class="la-header-field">
                            <span class="la-label">Profit Center No</span>
                            <div class="la-header-value"><asp:Literal ID="litProfitCenterNo" runat="server" Mode="Encode" /></div>
                        </div>
                        <div class="la-header-field">
                            <span class="la-label">Section ID</span>
                            <div class="la-header-value"><asp:Literal ID="litSectionID" runat="server" Mode="Encode" /></div>
                        </div>
                        <div class="la-header-field la-logtype-field">
                            <span class="la-label">Jenis Log</span>
                            <asp:DropDownList ID="ddlLogType" runat="server" CssClass="la-logtype-select"
                                EnableViewState="false" AutoPostBack="true"
                                OnSelectedIndexChanged="ddlLogType_SelectedIndexChanged"
                                aria-label="Pilih jenis log">
                            </asp:DropDownList>
                        </div>
                    </div>
                </div>
                <div class="la-date-right">
                    <div class="la-nav">
                        <asp:LinkButton ID="btnPrevious" runat="server" CssClass="la-server-nav"
                            OnClick="btnPrevious_Click" ToolTip="Tanggal sebelumnya" CausesValidation="false">&#8249;</asp:LinkButton>
                        <asp:LinkButton ID="btnToday" runat="server" CssClass="la-server-nav la-today"
                            OnClick="btnToday_Click" CausesValidation="false">Hari Ini</asp:LinkButton>
                        <asp:LinkButton ID="btnNext" runat="server" CssClass="la-server-nav"
                            OnClick="btnNext_Click" ToolTip="Tanggal berikutnya" CausesValidation="false">&#8250;</asp:LinkButton>
                    </div>
                </div>
            </div>
            <asp:Label ID="lblDateCaption" runat="server" CssClass="la-date-caption" />


        </div>

        <%-- Floating notification. Diletakkan di UpdatePanel agar selalu mengikuti hasil event server. --%>
        <asp:Panel ID="pnlNotice" runat="server" CssClass="la-float-notice" Visible="false"
            role="status" aria-live="polite" aria-atomic="true">
            <div class="la-notice-inner">
                <span class="la-notice-symbol" aria-hidden="true"></span>
                <div class="la-notice-copy">
                    <asp:Label ID="lblNoticeTitle" runat="server" CssClass="la-notice-title" />
                    <div class="la-notice-message"><asp:Literal ID="litNotice" runat="server" Mode="Encode" /></div>
                </div>
                <asp:LinkButton ID="btnDismissNotice" runat="server" CssClass="la-notice-close"
                    ToolTip="Tutup pesan" CausesValidation="false" OnClick="btnDismissNotice_Click"
                    OnClientClick="laDismissServerNotice();">&#215;</asp:LinkButton>
            </div>
        </asp:Panel>
        <div class="la-panel">
            <div class="la-list-header">
                <strong>Daftar Anak Buah</strong>
                <div class="la-hint">Klik Isi atau Lihat untuk membuka detail di bawah baris anggota.</div>

                <div class="la-stats-grid" role="group" aria-label="Ringkasan aktivitas anak buah">
                    <div class="la-stat-cell"><div class="la-stat-box la-stat-total">
                        <span class="la-stat-label">Total Anak Buah</span>
                        <strong class="la-stat-number"><asp:Label ID="lblTotalMembers" runat="server" Text="0" /></strong>
                    </div></div>
                    <div class="la-stat-cell"><div class="la-stat-box la-stat-done">
                        <span class="la-stat-label">Sudah Diisi</span>
                        <strong class="la-stat-number"><asp:Label ID="lblCompletedMembers" runat="server" Text="0" /></strong>
                    </div></div>
                    <div class="la-stat-cell"><div class="la-stat-box la-stat-pending">
                        <span class="la-stat-label">Belum Diisi</span>
                        <strong class="la-stat-number"><asp:Label ID="lblPendingMembers" runat="server" Text="0" /></strong>
                    </div></div>
                </div>
            </div>

            <asp:Panel ID="pnlSearchFilters" runat="server" CssClass="la-filters la-net-filters la-filters-enhanced" DefaultButton="btnSearch">
                <span class="la-search-group">
                    <span class="la-search-input-cell">
                        <asp:TextBox ID="txtSearch" runat="server" EnableViewState="false" CssClass="la-search-input" MaxLength="100"
                            placeholder="Cari nama atau NIK..." aria-label="Cari nama atau NIK" />
                    </span>
                    <span class="la-search-button-cell">
                        <asp:LinkButton ID="btnSearch" runat="server" CssClass="la-search-button"
                            ToolTip="Cari" OnClick="btnSearch_Click" CausesValidation="false">
                            <span class="la-search-icon" aria-hidden="true"></span><span class="la-sr-only">Cari</span>
                        </asp:LinkButton>
                    </span>
                </span>
                <asp:DropDownList ID="ddlStatus" runat="server" AutoPostBack="true"
                    OnSelectedIndexChanged="ddlStatus_SelectedIndexChanged" aria-label="Filter status aktivitas">
                    <asp:ListItem Value="all">Semua Status</asp:ListItem>
                    <asp:ListItem Value="done">Sudah Diisi</asp:ListItem>
                    <asp:ListItem Value="empty">Belum Diisi</asp:ListItem>
                </asp:DropDownList>
                <asp:LinkButton ID="btnSummary" runat="server" CssClass="la-summary-action"
                    OnClick="btnSummary_Click" CausesValidation="false">Detail Aktivitas</asp:LinkButton>
            </asp:Panel>
            <%-- Modal ringkasan berada di bagian akhir halaman; tidak lagi inline di sini. --%>
            <%-- Ringkasan dipindahkan ke modal di luar panel tabel agar tidak terpotong overflow. --%>
            <div class="la-table-wrap">
                <table class="la-table la-server-table">
                    <colgroup>
                        <col style="width:7%" /><col style="width:31%" />
                        <col style="width:24%" /><col style="width:22%" /><col style="width:16%" />
                    </colgroup>
                    <thead><tr>
                        <th>NO.</th><th>ANAK BUAH</th><th>SHIFT KERJA</th>
                        <th>STATUS</th><th class="la-action-cell">AKSI</th>
                    </tr></thead>
                    <tbody>
                        <asp:Repeater ID="rptMembers" runat="server"
                            OnItemDataBound="rptMembers_ItemDataBound"
                            OnItemCommand="rptMembers_ItemCommand">
                            <ItemTemplate>
                                <tr id="trMember" runat="server" class="la-member-row">
                                    <td class="la-number"><asp:Literal ID="litNumber" runat="server" /></td>
                                    <td><div class="la-person"><%#: Eval("FullName") %></div>
                                        <div class="la-secondary"><%#: Eval("StaffCode") %></div></td>
                                    <td><asp:Literal ID="litShift" runat="server" /></td>
                                    <td><asp:Literal ID="litStatus" runat="server" /></td>
                                    <td class="la-action-cell">
                                        <asp:LinkButton ID="btnMember" runat="server"
                                            CssClass="la-row-button" CommandName="ToggleMember"
                                            CommandArgument='<%# Eval("MemberId") %>' CausesValidation="false" />
                                    </td>
                                </tr>
                                <tr id="trDetail" runat="server" class="la-child-row" visible="false">
                                    <td colspan="5">
                                        <div class="la-child"><div class="la-child-card">
                                            <div class="la-child-header"><div class="la-child-tools">
                                                <div class="la-child-name">
                                                    <strong><%#: Eval("FullName") %></strong>
                                                    <small><%#: Eval("StaffCode") %></small>
                                                </div>
                                                <div class="la-child-buttons">
                                                    <asp:LinkButton ID="btnAdd" runat="server" CssClass="la-pill la-primary"
                                                        OnClick="btnAdd_Click" CausesValidation="false">+ Tambah Aktivitas</asp:LinkButton>
                                                    <asp:LinkButton ID="btnClose" runat="server" CssClass="la-pill la-neutral"
                                                        OnClick="btnClose_Click" CausesValidation="false">Tutup</asp:LinkButton>
                                                </div>
                                            </div></div>
                                            <asp:Panel ID="pnlView" runat="server" CssClass="la-records">
                                                <asp:Label ID="lblEmpty" runat="server" CssClass="la-empty" Visible="false"
                                                    Text="Belum ada aktivitas pada tanggal ini." />
                                                <asp:Repeater ID="rptEntries" runat="server" OnItemCommand="rptEntries_ItemCommand">
                                                    <ItemTemplate>
                                                        <div class="la-record">
                                                            <div class="la-record-time">
                                                                <strong><%#: Eval("StartTime") %> – <%#: Eval("EndTime") %></strong>
                                                                <small><%# FormatDate(Convert.ToString(Eval("StartDate"))) %> → <%# FormatDate(Convert.ToString(Eval("EndDate"))) %></small>
                                                            </div>
                                                            <div class="la-record-desc">
                                                                <div class="la-record-kind"><%#: Eval("LogTypeLabel") %></div>
                                                                <div class="la-record-activity"><%#: Eval("ActivityText") %></div>
                                                                <div class="la-record-status"><span>Status:</span> <%#: Eval("StatusText") %></div>
                                                            </div>
                                                            <div class="la-record-actions">
                                                                <asp:LinkButton ID="btnEdit" runat="server" Text="Edit" CssClass="la-mini-btn la-mini-edit"
                                                                    CommandName="EditEntry" CommandArgument='<%# Eval("ActivityId") %>'
                                                                    ToolTip="Ubah aktivitas" Visible='<%# CanEditDetailEntry(Eval("StartDate"), Eval("IsCurrentMember")) %>'
                                                                    CausesValidation="false" />
                                                                <asp:LinkButton ID="btnDelete" runat="server" Text="Hapus" CssClass="la-mini-btn la-mini-delete"
                                                                    CommandName="DeleteEntry" CommandArgument='<%# Eval("ActivityId") %>'
                                                                    ToolTip="Hapus aktivitas" Visible='<%# CanEditDetailEntry(Eval("StartDate"), Eval("IsCurrentMember")) %>'
                                                                    CausesValidation="false" />
                                                            </div>
                                                        </div>
                                                    </ItemTemplate>
                                                </asp:Repeater>
                                            </asp:Panel>
                                            <asp:Panel ID="pnlEditor" runat="server" CssClass="la-form" Visible="false">
                                                <div class="la-form-title"><asp:Label ID="lblFormTitle" runat="server" /></div>
                                                <div class="la-form-note">Tanggal aktivitas otomatis hari ini. Jika jam selesai lebih awal atau sama, sistem mencatat selesai besok.</div>
                                                <div class="la-form-columns">
                                                    <div class="la-form-column">
                                                        <div class="la-field la-hidden-date"><label>Tanggal Mulai</label>
                                                            <span class="la-auto-date">Hari ini (otomatis)</span></div>
                                                        <div class="la-field"><label>Jam Mulai (HH:mm)</label>
                                                            <asp:TextBox ID="txtStartTime" runat="server" EnableViewState="false" CssClass="la-auto-time" MaxLength="5" placeholder="08:00" /></div>
                                                    </div>
                                                    <div class="la-form-column">
                                                        <div class="la-field la-hidden-date"><label>Tanggal Selesai</label>
                                                            <span class="la-auto-date">Otomatis menyesuaikan jam selesai (+1 hari jika lewat tengah malam)</span></div>
                                                        <div class="la-field"><label>Jam Selesai (HH:mm)</label>
                                                            <asp:TextBox ID="txtEndTime" runat="server" EnableViewState="false" CssClass="la-auto-time" MaxLength="5" placeholder="09:00" /></div>
                                                    </div>
                                                </div>
                                                <div class="la-field la-word-field">
                                                    <div class="la-field-label-row">
                                                        <label>Aktivitas / Pekerjaan</label>
                                                        <span class="la-word-counter"><span class="la-word-remaining">1000</span> karakter tersisa</span>
                                                    </div>
                                                    <asp:TextBox ID="txtActivity" runat="server" EnableViewState="false" TextMode="MultiLine" Rows="5"
                                                        CssClass="la-word-input" MaxLength="1000" data-char-limit="1000" placeholder="Tuliskan aktivitas atau pekerjaan..." />
                                                    <small class="la-status-help">Wajib diisi, maksimum 1.000 karakter.</small>
                                                </div>
                                                <div class="la-field la-word-field">
                                                    <div class="la-field-label-row">
                                                        <label>Status</label>
                                                        <span class="la-word-counter"><span class="la-word-remaining">200</span> karakter tersisa</span>
                                                    </div>
                                                    <asp:TextBox ID="txtWorkStatus" runat="server" EnableViewState="false" TextMode="MultiLine" Rows="3"
                                                        CssClass="la-word-input" MaxLength="200" data-char-limit="200" placeholder="Contoh: Sedang diproses, Selesai, Menunggu tindak lanjut..." />
                                                    <small class="la-status-help">Opsional, maksimum 200 karakter.</small>
                                                </div>
                                                <div class="la-form-footer">
                                                    <asp:LinkButton ID="btnSave" runat="server" CssClass="la-pill la-primary"
                                                        OnClick="btnSave_Click" CausesValidation="false">Simpan Aktivitas</asp:LinkButton>
                                                    <asp:LinkButton ID="btnCancelEdit" runat="server" CssClass="la-pill la-neutral"
                                                        OnClick="btnCancel_Click" CausesValidation="false">Batal</asp:LinkButton>
                                                </div>
                                            </asp:Panel>

                                            <%-- Confirmation menggunakan modal fixed; ID kontrol tetap agar C# tidak berubah. --%>
                                            <asp:Panel ID="pnlConfirm" runat="server" CssClass="la-confirm la-confirm-overlay" Visible="false"
                                                role="dialog" aria-modal="true" aria-label="Konfirmasi hapus aktivitas">
                                                <div class="la-confirm-backdrop" aria-hidden="true"></div>
                                                <div class="la-dialog-table"><div class="la-dialog-center">
                                                    <div class="la-confirm-dialog">
                                                        <div class="la-confirm-head">
                                                            <h3>Hapus aktivitas?</h3>
                                                            <asp:LinkButton ID="btnCloseDelete" runat="server" CssClass="la-confirm-x la-confirm-cancel"
                                                                OnClick="btnCancel_Click" CausesValidation="false"
                                                                ToolTip="Batal menghapus" aria-label="Batal menghapus">&#215;</asp:LinkButton>
                                                        </div>
                                                        <div class="la-confirm-body">
                                                            <p>Yakin ingin menghapus catatan berikut?</p>
                                                            <div class="la-confirm-preview">
                                                                <div class="la-confirm-person"><asp:Literal ID="litDeleteStaff" runat="server" Mode="Encode" /></div>
                                                                <div class="la-confirm-time"><asp:Literal ID="litDeleteWhen" runat="server" Mode="Encode" /></div>
                                                                <div class="la-confirm-description"><asp:Literal ID="litDeletePreview" runat="server" Mode="Encode" /></div>
                                                                <div class="la-confirm-description"><b>Status:</b> <asp:Literal ID="litDeleteStatus" runat="server" Mode="Encode" /></div>
                                                            </div>
                                                            <p class="la-confirm-warning">Aktivitas ini akan dinonaktifkan dan tidak ditampilkan lagi. Data tetap tersimpan.</p>
                                                            <div class="la-confirm-buttons">
                                                                <asp:LinkButton ID="btnCancelDelete" runat="server" CssClass="la-pill la-neutral la-confirm-cancel"
                                                                    OnClick="btnCancel_Click" CausesValidation="false">Batal</asp:LinkButton>
                                                                <asp:LinkButton ID="btnConfirmDelete" runat="server" CssClass="la-pill la-danger-solid"
                                                                    OnClick="btnConfirmDelete_Click" CausesValidation="false">Ya, Hapus</asp:LinkButton>
                                                            </div>
                                                        </div>
                                                    </div>
                                                </div></div>
                                            </asp:Panel>
                                        </div></div>
                                    </td>
                                </tr>
                            </ItemTemplate>
                        </asp:Repeater>
                    </tbody>
                </table>
            </div>
            <div class="la-pager">
                <div class="la-range"><asp:Label ID="lblRange" runat="server" /></div>
                <div class="la-page-controls">
                    <asp:DropDownList ID="ddlPageSize" runat="server" AutoPostBack="true"
                        OnSelectedIndexChanged="ddlPageSize_SelectedIndexChanged">
                        <asp:ListItem Value="10">10 / halaman</asp:ListItem>
                        <asp:ListItem Value="20">20 / halaman</asp:ListItem>
                        <asp:ListItem Value="50">50 / halaman</asp:ListItem>
                    </asp:DropDownList>
                    <asp:LinkButton ID="btnPagePrevious" runat="server" CssClass="la-page-button la-net-page"
                        OnClick="btnPagePrevious_Click" CausesValidation="false">&#8249;</asp:LinkButton>
                    <asp:Repeater ID="rptPages" runat="server" OnItemCommand="rptPages_ItemCommand">
                        <ItemTemplate><asp:LinkButton ID="btnPageNumber" runat="server"
                            CssClass='<%# Convert.ToBoolean(Eval("Current")) ? "la-page-button la-net-page la-on" : "la-page-button la-net-page" %>'
                            CommandName="GoPage" CommandArgument='<%# Eval("Number") %>'
                            Text='<%# Eval("Number") %>' CausesValidation="false" /></ItemTemplate>
                    </asp:Repeater>
                    <asp:LinkButton ID="btnPageNext" runat="server" CssClass="la-page-button la-net-page"
                        OnClick="btnPageNext_Click" CausesValidation="false">&#8250;</asp:LinkButton>
                </div>
            </div>
        </div>
        <%-- Modal Detail Aktivitas: mengikuti Jenis Log utama, tanpa dropdown kedua. --%>
        <asp:Panel ID="pnlSummary" runat="server" CssClass="la-summary-overlay" Visible="false"
            role="dialog" aria-modal="true" aria-label="Detail Aktivitas Tim">
            <div class="la-summary-backdrop" aria-hidden="true"></div>
            <div class="la-dialog-table">
                <div class="la-dialog-center">
                    <div class="la-summary-dialog" role="document">
                        <div class="la-summary-modal-head">
                            <div class="la-summary-modal-title">
                                <asp:Label ID="lblSummaryTitle" runat="server" CssClass="la-summary-title-text" />
                                <asp:Label ID="lblSummaryDate" runat="server" CssClass="la-summary-date" />
                            </div>
                            <asp:LinkButton ID="btnCloseSummary" runat="server" CssClass="la-summary-modal-close"
                                OnClick="btnCloseSummary_Click" CausesValidation="false"
                                ToolTip="Tutup" aria-label="Tutup detail aktivitas">&#215;</asp:LinkButton>
                        </div>

                        <div class="la-summary-modal-content">
                            <asp:Panel ID="pnlSummarySearch" runat="server" CssClass="la-summary-search-row"
                                DefaultButton="btnSummarySearch">
                                <span class="la-summary-search-shell">
                                    <span class="la-summary-search-leading" aria-hidden="true"></span>
                                    <asp:TextBox ID="txtSummarySearch" runat="server" EnableViewState="false"
                                        CssClass="la-summary-search-input" MaxLength="100"
                                        placeholder="Cari nama, NIK, aktivitas, atau status..."
                                        aria-label="Cari detail aktivitas" />
                                    <asp:LinkButton ID="btnSummarySearch" runat="server" CssClass="la-summary-search-btn"
                                        ToolTip="Cari" OnClick="btnSummarySearch_Click" CausesValidation="false">Cari</asp:LinkButton>
                                </span>
                            </asp:Panel>

                            <div class="la-summary-scroll" role="region" aria-label="Daftar aktivitas" tabindex="0">
                                <table class="la-summary-table">
                                    <thead>
                                        <tr>
                                            <th>Tanggal</th>
                                            <th>Mulai</th>
                                            <th>Selesai</th>
                                            <th>Nama</th>
                                            <th>Aktivitas</th>
                                            <th>Status</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <asp:Repeater ID="rptSummary" runat="server">
                                            <ItemTemplate>
                                                <tr>
                                                    <td class="la-summary-date-cell"><%#: Eval("ReportText") %></td>
                                                    <td><span class="la-time-chip"><%#: Eval("StartText") %></span></td>
                                                    <td><span class="la-time-chip"><%#: Eval("EndText") %></span></td>
                                                    <td class="la-summary-name"><%#: Eval("FullName") %></td>
                                                    <td class="la-summary-activity"><%#: Eval("Activity") %></td>
                                                    <td class="la-summary-status"><%#: Eval("StatusText") %></td>
                                                </tr>
                                            </ItemTemplate>
                                        </asp:Repeater>
                                    </tbody>
                                </table>
                                <asp:Label ID="lblSummaryEmpty" runat="server" CssClass="la-summary-empty"
                                    Visible="false" Text="Belum ada aktivitas pada tanggal ini." />
                            </div>
                        </div>

                        <div class="la-summary-modal-footer">
                            <asp:Label ID="lblSummaryRange" runat="server" CssClass="la-summary-range" />
                            <div class="la-summary-modal-pager">
                                <asp:LinkButton ID="btnSummaryPrev" runat="server" CssClass="la-summary-page-btn"
                                    OnClick="btnSummaryPrev_Click" CausesValidation="false"
                                    ToolTip="Halaman sebelumnya" aria-label="Halaman sebelumnya">&#8249;</asp:LinkButton>
                                <asp:Label ID="lblSummaryPage" runat="server" CssClass="la-summary-page-label" />
                                <asp:LinkButton ID="btnSummaryNext" runat="server" CssClass="la-summary-page-btn"
                                    OnClick="btnSummaryNext_Click" CausesValidation="false"
                                    ToolTip="Halaman berikutnya" aria-label="Halaman berikutnya">&#8250;</asp:LinkButton>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </asp:Panel>
    </div>
    </ContentTemplate>
    </asp:UpdatePanel>
    <asp:UpdateProgress ID="progressLog" runat="server" AssociatedUpdatePanelID="upLogAktivitas" DisplayAfter="250">
        <ProgressTemplate><div class="la-progress" role="status">Memproses...</div></ProgressTemplate>
    </asp:UpdateProgress>

    <script type="text/javascript">
        // Interaksi DOM saja; semua CRUD tetap event C# + UpdatePanel.
        // Satu sistem pesan saja: pnlNotice dari server diposisikan sebagai floating card.
        var laNoticeTimer = null;
        function laDismissServerNotice() {
            var notice = document.getElementById('<%= pnlNotice.ClientID %>');
        if (notice) { notice.style.display = 'none'; }
        if (laNoticeTimer) { window.clearTimeout(laNoticeTimer); laNoticeTimer = null; }
    }
    function laScheduleNoticeHide(delay) {
        var notice = document.getElementById('<%= pnlNotice.ClientID %>');
        if (!notice) { return; }
        notice.style.display = 'block';
        if (laNoticeTimer) { window.clearTimeout(laNoticeTimer); }
        laNoticeTimer = window.setTimeout(laDismissServerNotice, delay || 4500);
    }
    (function (w) {
        function attachPeriodPicker() {
            if (!w.jQuery || !w.jQuery.fn || !w.jQuery.fn.datepicker) { return; }
            var element = w.document.getElementById('<%= txtPeriod.ClientID %>');
            if (!element) { return; }
            var $picker = w.jQuery(element);
            if ($picker.data('la-picker-ready')) { return; }
            $picker.data('la-picker-ready', true);
            $picker.datepicker({
                format: 'dd-mm-yyyy',
                autoclose: true,
                todayHighlight: true,
                container: 'body',
                endDate: $picker.attr('data-end-date')
            });
            $picker.on('changeDate.laPeriod', function () {
                var current = $picker.val();
                if (!current || current === $picker.attr('data-server-date')) { return; }
                if (w.Sys && w.Sys.WebForms && w.Sys.WebForms.PageRequestManager &&
                    w.Sys.WebForms.PageRequestManager.getInstance().get_isInAsyncPostBack()) { return; }
                if (typeof w.__doPostBack === 'function') {
                    w.__doPostBack('<%= btnPeriodChanged.UniqueID %>', '');
                }
            });
        }
        function normalizeTime(raw) {
            var s = (raw || '').replace(/\s/g, '');
            var m, hours, mins;
            if (/^\d{1,2}:\d{1,2}$/.test(s)) {
                m = s.split(':'); hours = +m[0]; mins = +m[1];
            } else if (/^\d{3,4}$/.test(s)) {
                hours = +s.substring(0, s.length - 2); mins = +s.substring(s.length - 2);
            } else if (/^\d{1,2}$/.test(s)) { hours = +s; mins = 0; }
            else { return raw; }
            if (hours > 23 || mins > 59) { return raw; }
            return (hours < 10 ? '0' : '') + hours + ':' + (mins < 10 ? '0' : '') + mins;
        }
        function attachTimeInputs() {
            var inputs = document.querySelectorAll('.la-auto-time');
            for (var i = 0; i < inputs.length; i++) {
                if (inputs[i].getAttribute('data-la-bound')) { continue; }
                inputs[i].setAttribute('data-la-bound', '1');
                inputs[i].onblur = function () { this.value = normalizeTime(this.value); };
            }
        }
        // Hitung karakter, termasuk spasi dan baris baru. Konsisten dengan C# string.Length.
        function refreshCharacterCounter(input) {
            if (!input) { return; }
            var limit = parseInt(input.getAttribute('data-char-limit'), 10);
            if (!limit || limit < 1) { return; }
            var value = input.value || '';
            if (value.length > limit) {
                input.value = value.substring(0, limit);
                value = input.value;
            }
            var field = input.parentNode;
            var counter = field && field.querySelector ? field.querySelector('.la-word-counter') : null;
            var remaining = counter && counter.querySelector ? counter.querySelector('.la-word-remaining') : null;
            var left = Math.max(0, limit - value.length);
            if (remaining) {
                if ('textContent' in remaining) { remaining.textContent = left; }
                else { remaining.innerText = left; }
            }
            if (counter) {
                counter.className = 'la-word-counter' + (left <= Math.ceil(limit * 0.10) ? ' la-word-counter-low' : '');
            }
        }
        function attachCharacterCounters() {
            var inputs = w.document.querySelectorAll ? w.document.querySelectorAll('.la-word-input') : [];
            for (var i = 0; i < inputs.length; i++) {
                (function (input) {
                    refreshCharacterCounter(input);
                    if (input.getAttribute('data-la-char-bound')) { return; }
                    input.setAttribute('data-la-char-bound', '1');
                    input.oninput = function () { refreshCharacterCounter(input); };
                    input.onkeyup = function () { refreshCharacterCounter(input); };
                    input.onpaste = function () { w.setTimeout(function () { refreshCharacterCounter(input); }, 0); };
                })(inputs[i]);
            }
        }
        function attachDialogs() {
            var summary = w.document.getElementById('<%= pnlSummary.ClientID %>');
            var confirm = w.document.querySelector ? w.document.querySelector('.la-confirm-overlay') : null;
            var any = !!(summary || confirm);
            if (w.document.body) { w.document.body.style.overflow = any ? 'hidden' : ''; }
            if (confirm && !w.__laDeleteWasOpen) {
                var cancel = confirm.querySelector('.la-confirm-cancel');
                if (cancel && cancel.focus) { cancel.focus(); }
            } else if (summary && !w.__laSummaryWasOpen) {
                var close = w.document.getElementById('<%= btnCloseSummary.ClientID %>');
                    if (close && close.focus) { close.focus(); }
                }
            w.__laSummaryWasOpen = !!summary;
            w.__laDeleteWasOpen = !!confirm;
        }
        function attachControls() { attachPeriodPicker(); attachTimeInputs(); attachCharacterCounters(); attachDialogs(); }
        if (w.document.addEventListener) {
            w.document.addEventListener('keydown', function (ev) {
                ev = ev || w.event;
                if ((ev.keyCode || ev.which) !== 27) { return; }
                var confirm = w.document.querySelector ? w.document.querySelector('.la-confirm-overlay') : null;
                var modal = w.document.getElementById('<%= pnlSummary.ClientID %>');
                var control = confirm ? confirm.querySelector('.la-confirm-cancel') :
                    (modal ? w.document.getElementById('<%= btnCloseSummary.ClientID %>') : null);
                if (!control) { return; }
                if (ev.preventDefault) { ev.preventDefault(); }
                if (control.click) { control.click(); }
            }, false);
        }
        if (w.Sys && w.Sys.Application) {
            w.Sys.Application.add_load(attachControls);
        } else if (w.jQuery) {
            w.jQuery(attachControls);
        }
    })(window);
    </script>
</asp:Content>

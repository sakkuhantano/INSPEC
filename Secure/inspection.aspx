<%@ Page Title="Inspection Entry" Language="C#" MasterPageFile="~/MasterPages/Site1.Master" AutoEventWireup="true" CodeBehind="inspection.aspx.cs" Inherits="INSPEC.Secure.inspection" %>
<%@ MasterType VirtualPath="~/MasterPages/Site1.Master" %>
<asp:Content ID="Content1" ContentPlaceHolderID="head" runat="server">
<style>
    .inspection-card { border: 1px solid var(--bs-border-color); border-radius: .75rem; background: var(--bs-body-bg); }
.inspection-map-workspace{position:relative;min-height:calc(100dvh - 150px);border:1px solid var(--bs-border-color);border-radius:.9rem;background:var(--bs-body-bg);overflow:hidden}.inspection-map-toolbar{display:flex;align-items:center;justify-content:space-between;gap:.75rem;padding:.75rem .9rem;border-bottom:1px solid var(--bs-border-color);background:var(--bs-tertiary-bg)}.inspection-map-title-wrap{min-width:0}.inspection-map-eyebrow{font-size:.65rem;font-weight:800;letter-spacing:.09em;color:var(--bs-primary)}.inspection-map-title{font-weight:800;font-size:1rem;line-height:1.2;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.inspection-map-subtitle{color:var(--bs-secondary-color);font-size:.72rem;margin-top:.15rem}.inspection-map-actions{display:flex;align-items:center;gap:.35rem;flex:0 0 auto}.inspection-map-summary{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));border-bottom:1px solid var(--bs-border-color);background:var(--bs-tertiary-bg)}.inspection-map-stat{min-width:0;padding:.45rem .2rem;text-align:center;border-right:1px solid var(--bs-border-color);font-size:.58rem;color:var(--bs-secondary-color);text-transform:uppercase;letter-spacing:0}.inspection-map-stat:last-child{border-right:0}.inspection-map-stat-value{display:block;font-size:1.05rem;font-weight:900;color:var(--bs-body-color);line-height:1.15;margin-bottom:2px}.inspection-map-stat-label{display:block;line-height:1.15;min-height:1.35em}
.inspection-map-point.pending .inspection-map-point-dot{background:#64748b;color:#fff}
.inspection-map-point.done .inspection-map-point-dot{background:#198754;color:#fff}
    .inspection-map-point.abnormal .inspection-map-point-dot{background:#dc3545;color:#fff}
    .inspection-map-dot.abnormal{background:#dc3545}

.inspection-map-point.incomplete .inspection-map-point-dot{background:#ffc107;color:#212529}
.inspection-map-point-dot{font-size:.62rem;font-weight:900}
.inspection-point-list-row .inspection-map-point-dot{font-size:.75rem}
@media(max-width:575.98px){.inspection-map-stat{padding:.4rem .1rem;font-size:.52rem}.inspection-map-stat-value{font-size:1rem}.inspection-map-stat-label{font-size:.52rem}}.inspection-map-canvas{position:relative;min-height:520px;overflow:hidden;background:linear-gradient(135deg,#eef3f2,#f8faf9)}[data-bs-theme=dark] .inspection-map-canvas{background:linear-gradient(135deg,#151a1b,#202528)}.inspection-map-floorplan{position:absolute;inset:18px;border:2px solid rgba(4,93,93,.35);border-radius:18px;background:rgba(255,255,255,.72);box-shadow:inset 0 0 0 10px rgba(4,93,93,.035)}[data-bs-theme=dark] .inspection-map-floorplan{background:rgba(25,30,31,.82);border-color:rgba(32,201,151,.28)}.inspection-map-room{position:absolute;border:2px solid rgba(4,93,93,.25);border-radius:10px;display:flex;align-items:flex-start;justify-content:flex-start;padding:9px;font-size:.58rem;font-weight:800;color:rgba(4,93,93,.55);letter-spacing:.06em}[data-bs-theme=dark] .inspection-map-room{border-color:rgba(32,201,151,.22);color:rgba(32,201,151,.55)}.room-a{left:4%;top:5%;width:37%;height:30%}.room-b{left:47%;top:5%;width:48%;height:42%}.room-c{left:4%;top:42%;width:37%;height:51%}.room-d{left:47%;top:54%;width:48%;height:39%}.inspection-map-corridor{position:absolute;background:rgba(4,93,93,.08);border-radius:8px}.corridor-a{left:41%;top:8%;width:6%;height:84%}.corridor-b{left:8%;top:35%;width:84%;height:8%}.corridor-c{left:41%;top:47%;width:6%;height:8%}.inspection-map-points{position:absolute;inset:0}.inspection-map-point{position:absolute;transform:translate(-50%,-50%);width:34px;height:34px;border:0;padding:0;background:transparent;z-index:3;cursor:pointer}.inspection-map-point-dot{display:flex;width:28px;height:28px;margin:auto;border-radius:50%;align-items:center;justify-content:center;border:3px solid #fff;box-shadow:0 3px 10px rgba(0,0,0,.25);font-size:.58rem;font-weight:800;color:#fff}.inspection-map-point.pending .inspection-map-point-dot{background:#6c757d}.inspection-map-point.done .inspection-map-point-dot{background:#198754}.inspection-map-point.selected .inspection-map-point-dot{outline:4px solid rgba(13,110,253,.25);transform:scale(1.12)}.inspection-map-point-label{position:absolute;left:50%;top:30px;transform:translateX(-50%);white-space:nowrap;font-size:.58rem;font-weight:800;color:var(--bs-body-color);background:rgba(255,255,255,.9);border-radius:4px;padding:2px 4px;box-shadow:0 1px 4px rgba(0,0,0,.12)}[data-bs-theme=dark] .inspection-map-point-label{background:rgba(20,24,26,.9)}.inspection-map-north{position:absolute;right:14px;top:12px;width:38px;height:38px;border-radius:50%;background:var(--bs-body-bg);border:1px solid var(--bs-border-color);display:flex;flex-direction:column;align-items:center;justify-content:center;font-size:.6rem;color:var(--bs-danger);box-shadow:0 2px 8px rgba(0,0,0,.12)}.inspection-map-north i{font-size:1rem}.inspection-map-legend{position:absolute;left:14px;bottom:14px;display:flex;gap:.55rem;flex-wrap:wrap;padding:.45rem .6rem;border:1px solid var(--bs-border-color);border-radius:.55rem;background:rgba(255,255,255,.92);font-size:.62rem;box-shadow:0 2px 8px rgba(0,0,0,.08)}[data-bs-theme=dark] .inspection-map-legend{background:rgba(20,24,26,.94)}.inspection-map-dot{width:9px;height:9px;border-radius:50%;display:inline-block;margin-right:2px}.inspection-map-dot.pending{background:#6c757d}.inspection-map-dot.done{background:#198754}.inspection-map-hint{position:absolute;right:14px;bottom:14px;padding:.45rem .6rem;border-radius:.55rem;background:rgba(4,93,93,.94);color:#fff;font-size:.62rem;box-shadow:0 3px 12px rgba(0,0,0,.16)}.inspection-map-point-sheet{position:absolute;z-index:10;left:50%;bottom:16px;transform:translateX(-50%);width:min(460px,calc(100% - 32px));padding:1rem;border:1px solid var(--bs-border-color);border-radius:1rem;background:var(--bs-body-bg);box-shadow:0 18px 45px rgba(0,0,0,.22)}.inspection-map-sheet-handle{width:42px;height:4px;border-radius:99px;background:var(--bs-secondary-bg);margin:0 auto .7rem}.inspection-map-point-code{font-size:.68rem;color:var(--bs-primary);font-weight:900;letter-spacing:.08em}.inspection-map-point-name{font-weight:800;font-size:1rem}.inspection-map-point-status{display:inline-flex;padding:.35rem .55rem;border-radius:99px;background:var(--bs-tertiary-bg);font-size:.7rem;font-weight:700}.inspection-point-list{padding:.75rem;background:var(--bs-tertiary-bg);min-height:520px}.inspection-point-list-row{display:flex;align-items:center;gap:.7rem;padding:.75rem;margin-bottom:.55rem;border:1px solid var(--bs-border-color);border-radius:.7rem;background:var(--bs-body-bg);cursor:pointer}.inspection-point-list-row:last-child{margin-bottom:0}.inspection-point-list-row .inspection-map-point-dot{flex:0 0 28px}.inspection-point-list-row .point-main{min-width:0;flex:1}.inspection-point-list-row .point-code{font-size:.68rem;color:var(--bs-primary);font-weight:800}.inspection-point-list-row .point-name{font-weight:700;font-size:.85rem}@media(max-width:575.98px){.inspection-map-workspace{min-height:calc(100dvh - 118px);border-radius:.7rem}.inspection-map-toolbar{padding:.65rem;align-items:flex-start}.inspection-map-toolbar .inspection-map-actions{flex-wrap:wrap;justify-content:flex-end}.inspection-map-canvas{min-height:calc(100dvh - 300px)}.inspection-map-floorplan{inset:10px}.inspection-map-hint{display:none}.inspection-map-legend{left:10px;bottom:10px}.inspection-map-point-sheet{bottom:10px;width:calc(100% - 20px)}}

    /* Real PDF floor plan and compact map markers. */
    .inspection-map-canvas{min-height:320px;padding:12px;background:var(--bs-tertiary-bg);overflow:hidden;touch-action:none;position:relative}
    .inspection-map-pdf-stage{position:relative;width:max-content;max-width:100%;min-width:min(100%,320px);margin:0 auto;background:#fff;box-shadow:0 2px 12px rgba(0,0,0,.16);line-height:0;will-change:transform}
    .inspection-map-pdf-stage canvas{display:block;max-width:100%;height:auto}
    .inspection-map-points{position:absolute;inset:0;pointer-events:none}
    .inspection-map-point{pointer-events:auto;width:22px;height:22px;z-index:3;transform:translate(-50%,-50%) scale(var(--inspection-map-marker-scale,1));transform-origin:center center}
    .inspection-map-point-dot{width:17px;height:17px;border:2px solid #fff;font-size:.48rem;box-shadow:0 1px 4px rgba(0,0,0,.35)}
    .inspection-map-point-label{top:19px;font-size:.48rem;padding:1px 3px;line-height:1.2}
    .inspection-map-point.inactive{opacity:.35}
    .inspection-map-point.incomplete .inspection-map-point-dot{background:#ffc107;color:#212529}
    .inspection-map-dot.incomplete{background:#ffc107}
    .inspection-map-point-dot.pending{background:#6c757d}
    .inspection-map-point-dot.done{background:#198754}
    .inspection-map-point.abnormal .inspection-map-point-dot{background:#dc3545}
    .inspection-map-point-dot.abnormal{background:#dc3545}
    .inspection-map-dot.abnormal{background:#dc3545}
    
    .inspection-map-point-dot.incomplete{background:#ffc107;color:#212529}
    .inspection-map-legend{z-index:5;left:8px;bottom:8px;gap:.45rem;max-width:calc(100% - 16px)}
    .inspection-map-zoom-tools{position:absolute;z-index:6;top:8px;right:8px;display:flex;align-items:center;gap:3px;padding:4px;border:1px solid var(--bs-border-color);border-radius:.5rem;background:rgba(255,255,255,.94);box-shadow:0 2px 8px rgba(0,0,0,.12)}
    .inspection-map-zoom-tools .btn{min-width:30px;padding:.2rem .4rem}
    .inspection-map-zoom-label{min-width:42px;text-align:center;font-size:.68rem;font-weight:700;color:#334155}
    .inspection-map-canvas.inspection-map-zoomed{cursor:grab}
    .inspection-map-canvas.inspection-map-zoomed:active{cursor:grabbing}
    .inspection-map-pdf-message{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;padding:1rem;color:#6c757d;font-size:.85rem;text-align:center;line-height:1.4}
    .inspection-map-pdf-message.d-none{display:none}
    .inspection-point-list{min-height:320px;max-height:65vh;overflow:auto}
    .inspection-point-list-tools{position:sticky;top:0;z-index:5;background:var(--bs-tertiary-bg);padding-bottom:.5rem}
    .inspection-point-list-row{padding:.55rem .65rem;margin-bottom:.35rem}
    .inspection-point-list-row .point-name{font-size:.8rem}
    .inspection-map-point-sheet{position:fixed;z-index:1085;bottom:1rem}
    @media(max-width:575.98px){.inspection-map-canvas{min-height:260px;padding:6px}.inspection-map-point-sheet{bottom:.5rem}}

    /* Batch map workspace: compact, touch-friendly layout on phones. */
    @media (max-width: 575.98px) {
        .inspection-map-workspace {
            min-height: calc(100dvh - 105px);
            overflow: visible;
        }
        .inspection-map-toolbar {
            display: grid;
            grid-template-columns: minmax(0, 1fr);
            align-items: stretch;
            gap: .55rem;
            padding: .65rem;
        }
        .inspection-map-title-wrap {
            width: 100%;
            min-width: 0;
        }
        .inspection-map-title {
            white-space: normal;
            overflow-wrap: anywhere;
        }
        .inspection-map-actions {
            display: grid;
            grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
            width: 100%;
            min-width: 0;
            gap: .4rem;
        }
        .inspection-map-actions > .btn-group {
            display: flex;
            width: 100%;
            min-width: 0;
        }
        .inspection-map-actions > .btn-group > .btn {
            flex: 1 1 50%;
            min-width: 0;
            padding: .42rem .3rem;
            white-space: nowrap;
        }
        .inspection-map-actions > .btn {
            width: 100%;
            min-width: 0;
            min-height: 36px;
            padding: .38rem .35rem;
            white-space: normal;
            line-height: 1.15;
        }
        #btnDeleteInspectionBatchDraft {
            grid-column: 1 / -1;
        }
        .inspection-map-summary {
            grid-template-columns: repeat(5, minmax(0, 1fr));
        }
        .inspection-map-canvas {
            min-height: 380px;
            padding: 6px;
        }
        .inspection-map-zoom-tools {
            top: 6px;
            right: 6px;
            max-width: calc(100% - 12px);
        }
        .inspection-map-legend {
            display: flex;
            flex-wrap: wrap;
            position: absolute;
            left: 6px;
            right: 6px;
            bottom: 6px;
            max-width: none;
            font-size: .58rem;
        }
        .inspection-map-point-sheet {
            left: 8px;
            right: 8px;
            width: auto;
            bottom: max(.5rem, env(safe-area-inset-bottom));
        }
    }

    .inspection-approval-toolbar { width: 100%; }
    .inspection-filter-control { flex: 1 1 145px; min-width: 125px; }
    .inspection-date-control { flex: 0 1 135px; min-width: 120px; }
    .inspection-approval-tabs { flex: 0 0 auto; white-space: nowrap; }
    .inspection-record-tabbar { flex-wrap: nowrap !important; justify-content: flex-start !important; overflow-x: auto; overflow-y: hidden; }
    #inspectionRecordTabs { flex: 0 0 auto; white-space: nowrap; }
    #inspectionSubmittedFilters:not(.d-none) { display: flex !important; flex: 0 0 auto; flex-wrap: nowrap !important; margin-left: .5rem; white-space: nowrap; }
    #inspectionSubmittedFilters .inspection-date-control { flex: 0 0 135px; min-width: 135px; }
    #inspectionApprovalDateFilters:not(.d-none) { display: flex !important; }
    #inspectionScrollTools { position: static; }
    #inspectionScrollTools:not(.d-none) { display: block; }
    #inspectionScrollTools .btn { position: fixed; right: 1rem; z-index: 2070; width: 42px; height: 42px; border-radius: 50%; opacity: .82; box-shadow: 0 .2rem .6rem rgba(0,0,0,.18); }
    #inspectionScrollUp { bottom: 4.5rem; top: auto; }
    #inspectionScrollDown { bottom: 1.25rem; top: auto; }
    #inspectionScrollTools .btn:hover, #inspectionScrollTools .btn:focus { opacity: 1; }
    @media (min-width: 1200px) {
        .inspection-filter-control { flex-basis: 145px; }
    }
    @media (max-width: 767.98px) {
        .inspection-filter-control { flex: 1 1 130px; }
        .inspection-date-control { flex: 1 1 120px; }
        .inspection-approval-tabs { flex: 1 1 auto; }
    }
    .inspection-step { border-left: 3px solid var(--bs-primary); padding-left: .75rem; }
    .inspection-item { border: 1px solid var(--bs-border-color); border-radius: .65rem; padding: .85rem; margin-bottom: .75rem; }
    .inspection-item.anomaly { border-color: var(--bs-danger); }
    .inspection-item-label { font-weight: 600; margin-bottom: .65rem; display: block; }
    .inspection-muted { font-size: .8rem; color: var(--bs-secondary-color); }
    .inspection-photo-panel { border: 1px solid var(--bs-border-color); border-radius: .65rem; padding: .85rem; }
    .inspection-photo-item { width: 112px; height: 112px; position: relative; border: 1px solid var(--bs-border-color); border-radius: .5rem; overflow: hidden; }
    .inspection-photo-item img { width: 100%; height: 100%; object-fit: cover; }
    .inspection-photo-delete { position: absolute; top: .25rem; right: .25rem; line-height: 1; padding: .1rem .35rem; }
    .inspection-photo-item { cursor: zoom-in; }
    .inspection-photo-item:focus-visible { outline: 3px solid var(--bs-primary); outline-offset: 2px; }
    .inspection-approval-photo-item { display: block; padding: 0; background: transparent; }
    .inspection-followup-section-btn { min-width: 92px; text-align: center; }
    .inspection-followup-section-btn i { font-size: 1.25rem; display: block; margin-bottom: .25rem; }
    #inspectionFollowUpPanel .accordion-button::after,
    #inspectionSummaryPanel .accordion-button::after { display: none; }
    .inspection-photo-viewer-open { overflow: hidden; }
    .inspection-photo-viewer { position: fixed; inset: 0; z-index: 2050; display: flex; flex-direction: column; background: rgba(0,0,0,.94); color: #fff; padding: max(.75rem, env(safe-area-inset-top)) .75rem max(.75rem, env(safe-area-inset-bottom)); }
    .inspection-photo-viewer.d-none { display: none !important; }
    .inspection-photo-viewer-header { display: flex; align-items: center; justify-content: space-between; gap: .75rem; min-height: 44px; }
    .inspection-photo-viewer-stage { display: flex; flex: 1; min-height: 0; align-items: center; justify-content: center; gap: .5rem; touch-action: pan-y; }
    .inspection-photo-viewer-image { display: block; max-width: calc(100vw - 112px); max-height: calc(100dvh - 150px); width: auto; height: auto; object-fit: contain; user-select: none; -webkit-user-drag: none; }
    .inspection-photo-viewer-nav { flex: 0 0 auto; width: 42px; height: 52px; padding: 0; font-size: 1.5rem; }
    .inspection-photo-viewer-footer { text-align: center; padding-top: .5rem; color: rgba(255,255,255,.8); font-size: .9rem; }
    @media (max-width: 480px) {
        .inspection-photo-viewer-stage { gap: .2rem; }
        .inspection-photo-viewer-image { max-width: calc(100vw - 100px); max-height: calc(100dvh - 145px); }
        .inspection-photo-viewer-nav { width: 34px; height: 46px; }
    }
    .inspection-option-choice { min-width: 4.5rem; border-radius: .4rem !important; }
    #inspectionEditorTabs .nav-link.active { font-weight: 700; }
    .inspection-saved-row { border-bottom: 1px solid var(--bs-border-color); padding: .7rem 0; }
    .inspection-saved-row:last-child { border-bottom: 0; }
    #inspectionChecklistHost input, #inspectionChecklistHost select, #inspectionChecklistHost textarea { min-height: 38px; }
    .inspection-editor-sticky { position: -webkit-sticky; position: sticky; top: 64px; z-index: 1025; background: var(--bs-body-bg); padding: .35rem 0 .4rem; border-bottom: 1px solid var(--bs-border-color); }
    .inspection-editor-sticky-spacer { width: 100%; pointer-events: none; }
    /* Popovers are appended to body, so keep them above the sticky inspection header. */
    .popover { z-index: 1120 !important; }
    .inspection-form-header { padding-left: .55rem; }

    .inspection-approval-sticky { position: -webkit-sticky; position: sticky; top: 64px; z-index: 1025; background: var(--bs-body-bg); padding: .35rem 0 .4rem; border-bottom: 1px solid var(--bs-border-color); }
    /* Keep the complete inspection heading, tabs, and section navigation pinned below the master header. */
    #inspectionApprovalStickyHeader { position: -webkit-sticky !important; position: sticky !important; top: 112px !important; z-index: 1080 !important; background: var(--bs-body-bg); }
    .inspection-section-nav-host { width: 100%; }
    /* Bootstrap modal defaults sit below the sticky inspection header (z-index 1080). Keep dialogs and their backdrop above it. */
    .modal-backdrop { z-index: 1090 !important; }
    .modal { z-index: 1100 !important; }
    #inspectionApprovalTable [data-approval-sort] { cursor: pointer; user-select: none; }
    /* Compact SPV approval grid; keep each column label/value on one line. */
    #inspectionApprovalTable { font-size: .78rem; white-space: nowrap; }
    #inspectionApprovalTable > :not(caption) > * > * { padding: .35rem .45rem; }
    #inspectionApprovalTable thead th { font-size: .75rem; }
    #inspectionApprovalStickyHeader .nav-link.active { font-weight: 700; }
    #inspectionApprovalSectionNavHost .inspection-section-nav { margin-bottom: 0 !important; }
    #inspectionEditorTabs { white-space: nowrap; }
    #inspectionEditorTabs .nav-link.active { font-weight: 700; }
    .inspection-section-nav-host { min-width: 0; }
    .inspection-section-nav-host .inspection-section-nav { position: static; width: 100%; max-width: 100%; min-height: 58px; margin-bottom: 0 !important; padding: .6rem !important; }
    .inspection-section-nav-tabs { min-width: 0; overflow-x: auto; overflow-y: hidden; scrollbar-width: thin; -webkit-overflow-scrolling: touch; touch-action: pan-x; padding: .15rem 0 .35rem; }
    .inspection-section-nav-tabs .d-inline-flex { gap: .35rem; width: max-content; min-width: 100%; min-height: 42px; align-items: center; }
    .inspection-section-tab { display: inline-flex; align-items: center; min-height: 40px; white-space: nowrap; padding: .55rem .75rem; border-radius: .45rem; color: var(--bs-secondary-color); text-decoration: none; font-size: .875rem; font-weight: 600; border: 1px solid transparent; }
    .inspection-section-tab:hover { background: var(--bs-tertiary-bg); color: var(--bs-primary); }
    .inspection-section-tab.active { color: var(--bs-primary); background: var(--bs-primary-bg-subtle); border-color: var(--bs-primary-border-subtle); }
    .inspection-section-dropdown-item.active { color: var(--bs-primary); background: var(--bs-primary-bg-subtle); font-weight: 600; }
    @media (max-width: 575.98px) {
        .inspection-editor-sticky { top: 58px; }
        .inspection-approval-sticky { top: 58px; }
        #inspectionEditorStickyHeader { top: 58px !important; }
        #inspectionApprovalStickyHeader { top: 104px !important; }
        .inspection-form-heading { width: 100%; }
        .inspection-section-nav-host { width: 100%; max-width: 100%; }
        .inspection-section-nav-host .inspection-section-nav { width: 100%; }
        .inspection-section-tab { padding: .4rem .55rem; font-size: .8rem; }
    }

    /* Supervisor approval: compact, equal-width status tabs. */
    #inspectionApprovalQueueTabs { min-width: 0; }
    #inspectionApprovalQueueTabs .nav-item { min-width: 0; }
    #inspectionApprovalQueueTabs .nav-link { white-space: nowrap; }
    #inspectionApprovalQueueTabs .badge { font-size: .7em; }

    @media (max-width: 575.98px) {
        #inspectionApprovalListHeader { align-items: flex-start !important; gap: .5rem; }
        #inspectionApprovalListHeader > div { min-width: 0; }
        #inspectionApprovalListHeader h5 { font-size: 1.05rem; }
        #inspectionApprovalQueueTabs {
            display: grid;
            grid-template-columns: repeat(3, minmax(0, 1fr));
            width: 100%;
            border-bottom: 1px solid var(--bs-border-color);
        }
        #inspectionApprovalQueueTabs .nav-item { width: 100%; }
        #inspectionApprovalQueueTabs .nav-link {
            width: 100%;
            padding: .55rem .2rem;
            font-size: .78rem;
            text-align: center;
            white-space: normal;
            border-radius: .45rem .45rem 0 0;
        }
        #inspectionApprovalQueueTabs .badge {
            margin-left: .15rem !important;
            padding: .25em .4em;
            font-size: .68em;
        }
        #inspectionApprovalListView > .table-responsive {
            overflow: visible;
            margin: 0;
        }
        #inspectionApprovalTable {
            display: block;
            width: 100%;
            margin-bottom: 0;
            white-space: normal;
            border: 0;
        }
        #inspectionApprovalTable thead { display: none; }
        #inspectionApprovalTable tbody {
            display: flex;
            flex-direction: column;
            gap: .65rem;
        }
        #inspectionApprovalTable tbody tr {
            display: block;
            padding: .55rem .7rem;
            border: 1px solid var(--bs-border-color);
            border-radius: .65rem;
            background: var(--bs-body-bg);
            box-shadow: 0 .1rem .25rem rgba(0,0,0,.04);
        }
        #inspectionApprovalTable tbody td {
            display: grid;
            grid-template-columns: minmax(6.25rem, 38%) minmax(0, 1fr);
            align-items: start;
            gap: .5rem;
            width: 100%;
            padding: .3rem 0 !important;
            border: 0;
            font-size: .82rem;
            white-space: normal;
            overflow-wrap: anywhere;
        }
        #inspectionApprovalTable tbody td[data-label]::before {
            content: attr(data-label);
            color: var(--bs-secondary-color);
            font-size: .74rem;
            font-weight: 600;
        }
        #inspectionApprovalTable tbody td[data-label="Transaction No."] {
            display: block;
            padding-bottom: .45rem !important;
            margin-bottom: .2rem;
            border-bottom: 1px solid var(--bs-border-color);
        }
        #inspectionApprovalTable tbody td[data-label="Transaction No."] button {
            text-align: left;
            white-space: normal !important;
            overflow-wrap: anywhere;
        }
        #inspectionApprovalTable tbody td.approval-select-cell {
            display: flex;
            justify-content: flex-end;
            padding: 0 0 .35rem !important;
        }
        #inspectionApprovalTable tbody td[colspan] {
            display: block;
            text-align: center;
        }
        #inspectionApprovalBatchActions {
            display: grid !important;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            width: 100%;
        }
        #inspectionApprovalBatchActions .btn { min-width: 0; }
    }

    /* Keep inspection entry and supervisor approval usable on narrow phones. */
    .inspection-card, .inspection-item, .inspection-photo-panel { min-width: 0; }
    .inspection-item-label, .inspection-muted { overflow-wrap: anywhere; }
    .inspection-option-list { min-width: 0; }
    .inspection-option-choice { max-width: 100%; white-space: normal; }
    #inspectionApprovalDetailPanel,
    #inspectionApprovalParameters,
    #inspectionApprovalDetail { min-width: 0; overflow-wrap: anywhere; }
    #inspectionApprovalDetailPanel .table-responsive { max-width: 100%; }

    @media (max-width: 575.98px) {
        .inspection-card { padding: .75rem !important; }
        .inspection-approval-toolbar > .inspection-filter-control {
            flex: 1 1 calc(50% - .5rem);
            min-width: 0;
        }
        #inspectionApprovalDateFilters {
            flex: 1 1 100%;
            flex-wrap: wrap;
            min-width: 0;
        }
        #inspectionApprovalDateFilters .inspection-date-control {
            flex: 1 1 120px;
            min-width: 0;
        }
        .inspection-approval-tabs { flex: 0 0 auto; }
        #inspectionSubmittedFilters { flex: 0 0 auto !important; }
        #inspectionSubmittedFilters .inspection-date-control { flex: 0 0 115px; min-width: 115px; }
        #inspectionApprovalBatchActions { flex: 1 1 100%; }
        #inspectionApprovalBatchActions .btn { flex: 1 1 auto; }
        .inspection-photo-panel .d-flex.align-items-center.justify-content-between {
            flex-wrap: wrap;
        }
        #inspectionFollowUpPanel .btn-group.w-100 {
            flex-direction: column;
            gap: .35rem;
        }
        #inspectionFollowUpPanel .btn-group.w-100 > .btn {
            width: 100%;
            border-radius: .375rem !important;
        }
        #inspectionFormPanel > .d-flex.flex-wrap.gap-2 > .btn {
            flex: 1 1 100%;
        }
        #inspectionApprovalDetailPanel .d-flex.justify-content-end .btn {
            flex: 1 1 auto;
        }
        #inspectionScrollTools .btn { right: .5rem; width: 38px; height: 38px; }
        #inspectionScrollUp { bottom: 4rem; top: auto; }
        #inspectionScrollDown { bottom: .75rem; top: auto; }

        /* Technician Submitted filters sit below the tabs instead of extending the tab row off-screen. */
        .inspection-record-tabbar {
            display: flex !important;
            flex-wrap: wrap !important;
            align-items: stretch !important;
            overflow: visible !important;
            gap: .65rem !important;
        }
        #inspectionRecordTabs {
            display: flex;
            flex: 1 1 100%;
            width: 100%;
            overflow: visible;
        }
        #inspectionRecordTabs .nav-item { flex: 1 1 0; }
        #inspectionRecordTabs .nav-link {
            width: 100%;
            padding: .55rem .45rem;
            font-size: .82rem;
            text-align: center;
        }
        #inspectionSubmittedFilters:not(.d-none) {
            display: grid !important;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            flex: 1 1 100% !important;
            width: 100%;
            min-width: 0;
            margin-left: 0;
            gap: .55rem !important;
            white-space: normal;
        }
        #inspectionSubmittedFilters .inspection-date-control {
            width: 100%;
            min-width: 0;
            flex: initial;
        }
        #inspectionSubmittedFilters input[type="date"] {
            width: 100%;
            min-width: 0;
        }
        #btnFilterSubmitted {
            grid-column: 1 / -1;
            width: 100%;
        }
    }

    /* Draft and Submitted lists: turn the six-column grid into readable cards on phones. */
    @media (max-width: 575.98px) {
        #inspectionDraftList,
        #inspectionSubmittedList,
        .inspection-record-table-wrap {
            width: 100%;
            max-width: 100%;
            min-width: 0;
        }
        .inspection-record-table-wrap {
            overflow: visible;
            margin: 0;
        }
        .inspection-record-table {
            display: block;
            width: 100%;
            border: 0;
            margin-bottom: 0;
        }
        .inspection-record-table thead { display: none; }
        .inspection-record-table tbody {
            display: flex;
            flex-direction: column;
            gap: .65rem;
        }
        .inspection-record-table tbody tr.inspection-record-main-row {
            display: block;
            width: 100%;
            padding: .55rem .7rem;
            border: 1px solid var(--bs-border-color);
            border-radius: .65rem;
            background: var(--bs-body-bg);
            box-shadow: 0 .1rem .25rem rgba(0,0,0,.04);
        }
        .inspection-record-table tbody tr.inspection-record-main-row td {
            display: grid;
            grid-template-columns: minmax(6.5rem, 38%) minmax(0, 1fr);
            align-items: start;
            gap: .5rem;
            width: 100%;
            min-width: 0;
            padding: .32rem 0 !important;
            border: 0;
            font-size: .82rem;
            white-space: normal;
            overflow-wrap: anywhere;
            word-break: break-word;
        }
        .inspection-record-table tbody tr.inspection-record-main-row td::before {
            content: attr(data-label);
            color: var(--bs-secondary-color);
            font-size: .74rem;
            font-weight: 600;
        }
        .inspection-record-table tbody tr.inspection-record-main-row td:first-child {
            display: block;
            padding-bottom: .45rem !important;
            margin-bottom: .2rem;
            border-bottom: 1px solid var(--bs-border-color);
            font-weight: 600;
        }
        .inspection-record-table tbody tr.inspection-record-main-row td:first-child::before {
            content: none;
        }
        .inspection-record-table tbody tr.inspection-record-main-row td:first-child button {
            display: inline-block;
            max-width: 100%;
            text-align: left;
            white-space: normal !important;
            overflow-wrap: anywhere;
        }
        .inspection-record-table tbody tr.inspection-record-main-row td:last-child button {
            max-width: 100%;
            white-space: normal;
        }
        .inspection-record-table tbody tr.inspection-grid-message-row {
            display: block;
            width: 100%;
            margin-top: -.55rem;
            padding: .45rem .7rem;
            border: 1px solid var(--bs-warning-border-subtle);
            border-radius: .55rem;
            background: var(--bs-warning-bg-subtle);
        }
        .inspection-record-table tbody tr.inspection-grid-message-row td {
            display: block;
            width: 100%;
            padding: 0 !important;
            border: 0;
            white-space: normal !important;
            overflow-wrap: anywhere;
            word-break: break-word;
        }
    }


    /* Samsung S25 / compact mobile inspection layout */
    .inspection-map-image { display:block; max-width:none; height:auto; user-select:none; -webkit-user-drag:none; }
    .inspection-image-preview { display:block; width:100%; max-height:70vh; object-fit:contain; background:#f8f9fa; }
    .inspection-coordinate-pdf[data-map-url] { display:block; }
    @media (max-width:575.98px) {
        .inspection-map-workspace { min-height:calc(100dvh - 108px); }
        .inspection-map-toolbar { align-items:center; gap:.4rem; padding:.55rem; }
        .inspection-map-title { font-size:.92rem; }
        .inspection-map-subtitle { font-size:.68rem; }
        .inspection-map-actions .btn { min-width:40px; min-height:40px; }
        .inspection-map-canvas { min-height:44dvh; max-height:58dvh; padding:4px; }
        .inspection-map-zoom-tools { top:6px; right:6px; gap:2px; padding:3px; }
        .inspection-map-zoom-tools .btn { min-width:40px; min-height:40px; padding:.25rem; }
        .inspection-map-zoom-label { min-width:40px; font-size:.7rem; }
        .inspection-map-point { width:44px; height:44px; }
        .inspection-map-point-dot { width:19px; height:19px; font-size:.5rem; }
        .inspection-map-point-label { top:30px; font-size:.56rem; }
        .inspection-map-legend { left:6px; right:6px; bottom:6px; max-width:none; gap:.35rem .55rem; padding:.4rem .5rem; font-size:.68rem; }
        .inspection-map-hint { display:none; }
        .inspection-point-list { min-height:36dvh; max-height:52dvh; padding:.5rem; }
        .inspection-point-list-row { min-height:56px; padding:.65rem; }
        .inspection-map-point-sheet { left:8px; right:8px; bottom:max(.5rem,env(safe-area-inset-bottom)); width:auto; transform:none; padding:.85rem; }
        .inspection-map-point-sheet .btn { min-height:44px; }
        #inspectionChecklistHost input, #inspectionChecklistHost select { min-height:44px; }
        #inspectionChecklistHost textarea { min-height:76px; }
        .inspection-item { padding:.75rem; margin-bottom:.6rem; }
        .inspection-option-choice { min-height:42px; }
        .inspection-photo-item { width:88px; height:88px; }
    }
.inspection-point-list-row.active{border-color:var(--bs-primary)!important;background:var(--bs-primary-bg-subtle)!important;box-shadow:inset 3px 0 0 var(--bs-primary)}
</style>
</asp:Content>

<asp:Content ID="Content3" ContentPlaceHolderID="stickybar" runat="server">
<div class="sticky-bar-wrapper w-100">
    <div class="d-flex align-items-center justify-content-between gap-2 p-2">
        <div class="flex-grow-1 text-center">
            <div class="fw-bold">Inspection Entry</div>
            <div class="inspection-muted" id="inspectionConnectionLabel">Offline-ready</div>
        </div>
        <div class="d-flex align-items-center justify-content-end gap-2 flex-shrink-0">
            <button type="button" id="btnBackToInspectionRecords" class="btn btn-sm btn-outline-secondary d-none text-nowrap">
                <i class="bi bi-arrow-left"></i> Back to List
            </button>
            <button type="button" id="btnBackToInspectionApprovalList" class="btn btn-sm btn-outline-secondary d-none text-nowrap">
                <i class="bi bi-arrow-left"></i> Back to List
            </button>
            
        </div>
    </div>
</div>
</asp:Content>

<asp:Content ID="Content2" ContentPlaceHolderID="ContentPlaceHolder1" runat="server">
<div class="container-fluid px-2 px-md-3 pb-4">
    <div id="inspectionApprovalPanel" class="inspection-card p-3 mb-3 d-none">
        <div id="inspectionApprovalListView">
        <div id="inspectionApprovalListHeader" class="d-flex justify-content-between align-items-center mb-3">
            <div>
                <div class="text-uppercase text-primary fw-bold inspection-muted">Supervisor</div>
                <h5 class="mb-0">Inspection Approval</h5>
                <div class="inspection-muted">Inspeksi Complete dari teknisi pada section yang menjadi tanggung jawab Anda.</div>
            </div>
            <button type="button" id="btnRefreshInspectionApproval" class="btn btn-sm btn-outline-primary">Refresh</button>
        </div>
            <div class="inspection-approval-toolbar mb-3">
                <div class="d-flex flex-wrap align-items-end gap-2 mb-3">
            <div class="inspection-filter-control">
                <label for="selApprovalType" class="form-label small mb-1">Type</label>
                <select id="selApprovalType" class="form-select form-select-sm"><option value="">All types</option></select>
            </div>
            <div class="inspection-filter-control">
                <label for="selApprovalDetail" class="form-label small mb-1">Detail</label>
                <select id="selApprovalDetail" class="form-select form-select-sm"><option value="">All details</option></select>
            </div>
            <div class="inspection-filter-control">
                <label for="selApprovalTemplate" class="form-label small mb-1">Template</label>
                <select id="selApprovalTemplate" class="form-select form-select-sm"><option value="">All templates</option></select>
            </div>
            <div id="inspectionApprovalDateFilters" class="d-none align-items-end gap-2">
                <div class="inspection-date-control"><label for="txtApprovalDateFrom" class="form-label small mb-1">From</label><input type="date" id="txtApprovalDateFrom" lang="id-ID" class="form-control form-control-sm" aria-label="Approved date from" /></div>
                <div class="inspection-date-control"><label for="txtApprovalDateThru" class="form-label small mb-1">Thru</label><input type="date" id="txtApprovalDateThru" lang="id-ID" class="form-control form-control-sm" aria-label="Approved date thru" /></div>
                </div>
                </div>
                <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
            <ul class="nav nav-tabs inspection-approval-tabs mb-0" id="inspectionApprovalQueueTabs" role="tablist">
                <li class="nav-item" role="presentation">
                    <button type="button" class="nav-link active" id="btnInspectionApprovalOutstanding" role="tab" aria-selected="true">
                        Outstanding <span id="inspectionApprovalOutstandingCount" class="badge text-bg-secondary ms-1">0</span>
                    </button>
                </li>
                <li class="nav-item" role="presentation">
                    <button type="button" class="nav-link" id="btnInspectionApprovalApproved" role="tab" aria-selected="false">
                        Approved <span id="inspectionApprovalApprovedCount" class="badge text-bg-secondary ms-1">0</span>
                    </button>
                </li>
                <li class="nav-item" role="presentation">
                    <button type="button" class="nav-link" id="btnInspectionApprovalVoid" role="tab" aria-selected="false">
                        Void <span id="inspectionApprovalVoidCount" class="badge text-bg-secondary ms-1">0</span>
                    </button>
                </li>
            </ul>
            <div id="inspectionApprovalBatchActions" class="d-flex flex-wrap align-items-center gap-1">
                <button type="button" id="btnInspectionApprovalPreview" class="btn btn-sm btn-outline-primary" disabled title="Select all inspections to enable Preview"><i class="bi bi-file-earmark-excel me-1"></i>Preview</button>
                <button type="button" id="btnApprovalSelectAll" class="btn btn-sm btn-outline-secondary" title="Select all filtered inspections" aria-label="Select all filtered inspections">Select All</button>
                <button type="button" id="btnBatchApproveInspection" class="btn btn-sm btn-success" title="Approve selected inspections" aria-label="Approve selected inspections">Approve</button>
                <button type="button" id="btnBatchVoidInspection" class="btn btn-sm btn-outline-danger" title="Void selected inspections" aria-label="Void selected inspections">Void</button>
            </div>
                </div>
            </div>
        <div class="table-responsive">
            <table id="inspectionApprovalTable" class="table table-sm table-hover align-middle">
                <thead><tr>
                    <th id="thInspectionApprovalSelectAll"><input type="checkbox" id="chkAllInspectionApproval" class="form-check-input" aria-label="Select all filtered inspections"></th>
                    <th role="button" tabindex="0" data-approval-sort="InspectionNo" class="text-nowrap">Transaction No. <span class="approval-sort-indicator"></span></th><th role="button" tabindex="0" data-approval-sort="InspectionTypeName">Inspection Type <span class="approval-sort-indicator"></span></th><th role="button" tabindex="0" data-approval-sort="InspectionTypeDetailName">Inspection Type Detail <span class="approval-sort-indicator"></span></th>
                    <th role="button" tabindex="0" data-approval-sort="InspectionDate" class="text-nowrap">Date <span class="approval-sort-indicator"></span></th><th role="button" tabindex="0" data-approval-sort="ScheduledTime">Scheduled <span class="approval-sort-indicator"></span></th><th role="button" tabindex="0" data-approval-sort="StartDateTime" class="text-nowrap">Start – End <span class="approval-sort-indicator"></span></th><th role="button" tabindex="0" data-approval-sort="TechnicianName">Technician <span class="approval-sort-indicator"></span></th>
                </tr></thead>
                <tbody id="inspectionApprovalQueue"><tr><td colspan="8" class="text-muted py-3">Memuat antrean...</td></tr></tbody>
            </table>
        </div>
    </div>

    <div id="inspectionApprovalDetailPanel" class="border-top pt-3 d-none">
        <div id="inspectionApprovalStickyHeader" class="inspection-approval-sticky mb-3">
            <div class="d-flex justify-content-between align-items-start flex-wrap gap-2 mb-2">
                <div>
                    <h5 class="mb-1">Inspection Detail</h5>
                    <div id="inspectionApprovalDetailSubtitle" class="inspection-muted"></div>
                </div>
            </div>
            <ul class="nav nav-tabs mb-2" role="tablist">
                <li class="nav-item"><button class="nav-link active" id="inspectionApprovalParamTab" data-bs-toggle="tab" data-bs-target="#inspectionApprovalParamPane" type="button" role="tab">PARAMETERS</button></li>
                <li class="nav-item"><button class="nav-link" id="inspectionApprovalChecklistTab" data-bs-toggle="tab" data-bs-target="#inspectionApprovalChecklistPane" type="button" role="tab">CHECKLIST</button></li>
            </ul>
            <div id="inspectionApprovalSectionNavHost" class="inspection-section-nav-host d-none"></div>
        </div>
        <div class="tab-content">
            <div class="tab-pane fade show active" id="inspectionApprovalParamPane"><div id="inspectionApprovalParameters"></div></div>
            <div class="tab-pane fade" id="inspectionApprovalChecklistPane"><div id="inspectionApprovalDetail" class="small"></div></div>
        </div>
        <div class="mt-4 border-top pt-3" id="inspectionApprovalRemarkPanel">
            <label for="txtInspectionApprovalRemark" class="form-label fw-semibold">Supervisor Remark (optional)</label>
            <textarea id="txtInspectionApprovalRemark" class="form-control" rows="3" maxlength="500" placeholder="Catatan supervisor..."></textarea>
        </div>
        <div class="d-flex flex-wrap justify-content-end gap-2 mt-3">
            <button type="button" id="btnApproveInspection" class="btn btn-success">Approve</button>
            <button type="button" id="btnVoidInspection" class="btn btn-outline-danger">Void</button>
        </div>
    </div>
</div>

    <div class="modal fade" id="inspectionReasonCancelModal" tabindex="-1" aria-hidden="true">
        <div class="modal-dialog modal-dialog-centered">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title" id="inspectionReasonCancelTitle">Reason Cancel</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <label for="txtInspectionReasonCancel" class="form-label">Reason Cancel (wajib)</label>
                    <textarea id="txtInspectionReasonCancel" class="form-control" rows="4" maxlength="500" placeholder="Masukkan alasan pembatalan..."></textarea>
                    <div class="form-text">Maksimal 500 karakter.</div>
                    <div id="inspectionReasonCancelError" class="text-danger small mt-2 d-none"></div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal">Batal</button>
                    <button type="button" id="btnConfirmInspectionReasonCancel" class="btn btn-danger">Lanjutkan</button>
                </div>
            </div>
        </div>
    </div>

    <div class="modal fade" id="inspectionApprovalActionModal" tabindex="-1" aria-hidden="true">
        <div class="modal-dialog"><div class="modal-content">
            <div class="modal-header"><h5 class="modal-title" id="inspectionApprovalActionTitle">Approval action</h5><button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button></div>
            <div class="modal-body">
                <div id="inspectionApprovalActionDescription" class="small text-muted mb-3"></div>
                <label for="txtInspectionApprovalActionRemark" class="form-label" id="lblInspectionApprovalActionRemark">Remark</label>
                <textarea id="txtInspectionApprovalActionRemark" class="form-control" rows="4" maxlength="500"></textarea>
                <div id="inspectionApprovalActionError" class="text-danger small mt-2 d-none"></div>
            </div>
            <div class="modal-footer"><button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal">Cancel</button><button type="button" id="btnConfirmInspectionApprovalAction" class="btn btn-primary">Confirm</button></div>
        </div></div>
    </div>
    <div id="inspectionScrollTools" class="d-none" aria-label="Quick scroll controls">
        <button type="button" id="inspectionScrollUp" class="btn btn-light border" title="Scroll to top" aria-label="Scroll to top"><i class="bi bi-chevron-up"></i></button>
        <button type="button" id="inspectionScrollDown" class="btn btn-light border" title="Scroll to bottom" aria-label="Scroll to bottom"><i class="bi bi-chevron-down"></i></button>
    </div>

    <div id="inspectionRecordsPanel" class="inspection-card p-3 mb-3">
        <div class="d-flex justify-content-between align-items-center mb-2">
            <div>
                <div class="text-uppercase text-primary fw-bold inspection-muted">Inspection Records</div>
                <h6 class="mb-0">Daftar inspeksi</h6>
            </div>
            <button type="button" class="btn btn-sm btn-primary" id="btnNewInspection">
                <i class="bi bi-plus-circle"></i> New
            </button>
        </div>
        <div class="inspection-record-tabbar d-flex flex-wrap justify-content-between align-items-end gap-2 mb-3">
            <ul class="nav nav-tabs mb-0" id="inspectionRecordTabs" role="tablist">
                <li class="nav-item" role="presentation">
                    <button class="nav-link active" id="inspectionDraftTab" data-bs-toggle="tab" data-bs-target="#inspectionDraftPane" type="button" role="tab">DRAFT</button>
                </li>
                <li class="nav-item" role="presentation">
                    <button class="nav-link" id="inspectionSubmittedTab" data-bs-toggle="tab" data-bs-target="#inspectionSubmittedPane" type="button" role="tab">SUBMITTED</button>
                </li>
            </ul>
            <div id="inspectionSubmittedFilters" class="d-none align-items-end gap-2 flex-wrap">
                <div class="inspection-date-control">
                    <label for="txtSubmittedFrom" class="form-label small mb-1">From</label>
                    <input type="date" id="txtSubmittedFrom" lang="id-ID" class="form-control form-control-sm" />
                </div>
                <div class="inspection-date-control">
                    <label for="txtSubmittedThru" class="form-label small mb-1">Thru</label>
                    <input type="date" id="txtSubmittedThru" lang="id-ID" class="form-control form-control-sm" />
                </div>
                <button type="button" id="btnFilterSubmitted" class="btn btn-sm btn-primary">
                    <i class="bi bi-search"></i> Filter
                </button>
            </div>
        </div>
        <div class="tab-content">
            <div class="tab-pane fade show active" id="inspectionDraftPane" role="tabpanel">
                <div id="inspectionDraftList" class="small">
                    <div class="text-muted py-2">Memuat draft...</div>
                </div>
            </div>
            <div class="tab-pane fade" id="inspectionSubmittedPane" role="tabpanel">
                <div id="inspectionSubmittedList" class="small">
                    <div class="text-muted py-2">Memuat inspeksi submitted...</div>
                </div>
            </div>
        </div>
    </div>

    <div id="inspectionInputPanel" class="d-none">
    <div id="inspectionEditorStickyHeader" class="inspection-editor-sticky mb-2"><div class="inspection-form-header d-flex align-items-center gap-2 mb-2"><h6 id="inspectionFormTitle" class="mb-0 text-truncate flex-shrink-1">Checklist</h6><button type="button" id="btnInspectionFormInfo" class="btn btn-sm btn-outline-secondary py-0 px-2 flex-shrink-0" aria-label="Informasi inspeksi" title="Informasi inspeksi"><i class="bi bi-info-circle-fill"></i></button></div><ul id="inspectionEditorTabs" class="nav nav-tabs mb-2 d-none" role="tablist"><li class="nav-item"><button type="button" id="btnInspectionParamTab" class="nav-link" role="tab">PARAM</button></li><li class="nav-item"><button type="button" id="btnInspectionChecklistTab" class="nav-link active" role="tab">CHECKLIST</button></li><li class="nav-item"><button type="button" id="btnInspectionMapTab" class="nav-link" role="tab"><i class="bi bi-map me-1"></i>MAP</button></li></ul><div id="inspectionSectionNavHost" class="inspection-section-nav-host d-none"></div></div>
    <div id="inspectionParamsPane">
    <div id="inspectionStartPanel" class="inspection-card p-3 mb-3">
        <div class="inspection-step mb-3">
            <div class="fw-bold">1. Inspection Type</div>
            <div class="inspection-muted">Pilih jenis inspeksi sesuai Section login.</div>
        </div>
        <div class="mb-3">
            <label for="selInspectionType" class="form-label small fw-semibold">Inspection Type</label>
            <select id="selInspectionType" class="form-select form-select-sm">
                <option value="">Pilih Inspection Type...</option>
            </select>
        </div>

        <div class="inspection-step mb-3">
            <div class="fw-bold">2. Template</div>
            <div class="inspection-muted">Hanya template Inspection yang sesuai Type dan Section.</div>
        </div>
        <div class="mb-3">
            <label for="selInspectionTemplate" class="form-label small fw-semibold">Inspection Template</label>
            <select id="selInspectionTemplate" class="form-select form-select-sm" disabled>
                <option value="">Pilih template...</option>
            </select>
        </div>

        <div class="inspection-step mb-3">
            <div class="fw-bold">3. Inspection Detail</div>
            <div class="inspection-muted">Pilih lokasi atau objek yang akan diperiksa.</div>
        </div>
        <div class="mb-3">
            <label for="selInspectionDetail" class="form-label small fw-semibold">Inspection Detail</label>
            <select id="selInspectionDetail" class="form-select form-select-sm" disabled>
                <option value="">Pilih detail...</option>
            </select>
        </div>
        <div class="inspection-step mb-3">
            <div class="fw-bold">4. Schedule Time</div>
            <div class="inspection-muted">Pilih jam sesuai jadwal detail. Jika detail tidak memiliki jadwal, inspeksi akan dicatat sebagai Tanpa Jadwal.</div>
        </div>
        <div class="mb-3">
            <label for="selInspectionScheduleTime" class="form-label small fw-semibold">Schedule Time</label>
            <select id="selInspectionScheduleTime" class="form-select form-select-sm" disabled>
                <option value="">Pilih jam...</option>
            </select>
            <div id="inspectionScheduleHint" class="inspection-muted mt-1"></div>
        </div>

        <div class="mb-3">
            <label for="txtInspectionDate" class="form-label small fw-semibold">Tanggal inspeksi</label>
            <input id="txtInspectionDate" lang="id-ID" type="date" class="form-control form-control-sm" disabled readonly aria-readonly="true" />
        </div>
        <div id="inspectionStartButtonRow"><button type="button" id="btnStartInspection" class="btn btn-primary w-100" disabled><i class="bi bi-clipboard-check"></i> Start Checklist</button></div>
    </div>
    </div>
    <div id="inspectionMapWorkspace" class="inspection-map-workspace d-none">
        <div class="inspection-map-toolbar">
            <div class="inspection-map-title-wrap">
                <div class="inspection-map-eyebrow"><i class="bi bi-geo-alt-fill me-1"></i>INSPECTION LOCATION MAP</div>
                <div id="inspectionMapTitle" class="inspection-map-title">Inspection Map</div>
                <div id="inspectionMapSubtitle" class="inspection-map-subtitle">Warna titik menunjukkan status inspeksi</div>
            </div>
            <div class="inspection-map-actions">
                <div class="btn-group btn-group-sm" role="group">
                    <button type="button" id="btnInspectionMapView" class="btn btn-primary"><i class="bi bi-map me-1"></i>Map</button>
                    <button type="button" id="btnInspectionPointListView" class="btn btn-outline-primary"><i class="bi bi-list-ul me-1"></i>List</button>
                </div>
                <button type="button" id="btnInspectionNextPending" class="btn btn-sm btn-outline-warning" title="Buka titik wajib berikutnya"><i class="bi bi-arrow-right-circle me-1"></i>Next Wajib</button>
                <button type="button" id="btnInspectionMapReset" class="btn btn-sm btn-outline-secondary" title="Reset map"><i class="bi bi-arrows-fullscreen"></i></button>
                <button type="button" id="btnDeleteInspectionBatchDraft" class="btn btn-sm btn-outline-danger d-none" title="Hapus draft batch dari perangkat">
                    <i class="bi bi-trash me-1"></i>Delete Draft Batch
                </button>
            </div>
        </div>
        <div class="inspection-map-summary" aria-label="Ringkasan status semua titik">
            <div class="inspection-map-stat"><span class="inspection-map-stat-value" id="inspectionMapTotalCount">0</span><span class="inspection-map-stat-label">Total</span></div>
            <div class="inspection-map-stat"><span class="inspection-map-stat-value text-success" id="inspectionMapDoneCount">0</span><span class="inspection-map-stat-label">Selesai</span></div>
            <div class="inspection-map-stat"><span class="inspection-map-stat-value text-danger" id="inspectionMapAbnormalCount">0</span><span class="inspection-map-stat-label">Abnormal</span></div>
            <div class="inspection-map-stat"><span class="inspection-map-stat-value text-secondary" id="inspectionMapPendingCount">0</span><span class="inspection-map-stat-label">Belum dicek</span></div>
            <div class="inspection-map-stat"><span class="inspection-map-stat-value text-warning" id="inspectionMapIncompleteCount">0</span><span class="inspection-map-stat-label">Belum lengkap</span></div>
        </div>
        <div id="inspectionMapSelectWrap" class="px-3 pt-2 d-none">
            <label for="inspectionMapSelect" class="form-label small fw-semibold mb-1">Floor Plan</label>
            <select id="inspectionMapSelect" class="form-select form-select-sm"></select>
        </div>
        <div id="inspectionMapCanvas" class="inspection-map-canvas" aria-label="Inspection map">
            <div class="inspection-map-zoom-tools" aria-label="Map zoom controls">
                <button type="button" id="btnInspectionMapZoomOut" class="btn btn-sm btn-light border" title="Zoom out" aria-label="Zoom out"><i class="bi bi-zoom-out"></i></button>
                <span id="inspectionMapZoomLabel" class="inspection-map-zoom-label">100%</span>
                <button type="button" id="btnInspectionMapZoomIn" class="btn btn-sm btn-light border" title="Zoom in" aria-label="Zoom in"><i class="bi bi-zoom-in"></i></button>
                <button type="button" id="btnInspectionMapZoomReset" class="btn btn-sm btn-light border" title="Reset zoom" aria-label="Reset zoom"><i class="bi bi-arrows-fullscreen"></i></button>
            </div>
            <div id="inspectionMapPdfStage" class="inspection-map-pdf-stage">
                <canvas id="inspectionMapPdfCanvas" aria-label="PDF floor plan"></canvas>
                <div id="inspectionMapPoints" class="inspection-map-points"></div>
                <div id="inspectionMapPdfMessage" class="inspection-map-pdf-message">Pilih map untuk menampilkan denah.</div>
            </div>
            <div class="inspection-map-legend" aria-label="Legenda status inspection point"><span><i class="inspection-map-dot pending"></i> <span id="inspectionMapPendingLegend">Belum diperiksa</span></span><span><i class="inspection-map-dot done"></i> Normal / Selesai</span><span><i class="inspection-map-dot abnormal"></i> Abnormal</span><span><i class="inspection-map-dot incomplete"></i> Belum lengkap</span></div>
            <div class="inspection-map-hint"><i class="bi bi-hand-index-thumb me-1"></i>Pilih marker untuk membuka checklist · Car park: inspeksi tiap slot yang ada kendaraan; slot kosong tidak perlu di-action.</div>
        </div>
        <div id="inspectionPointList" class="inspection-point-list d-none"></div>
        <div id="inspectionMapSummaryHost" class="px-3 pb-3"></div>
        <div class="d-flex justify-content-end gap-2 p-2 border-top">
            <button type="button" id="btnSubmitInspectionBatch" class="btn btn-primary btn-sm"><i class="bi bi-send-check me-1"></i>Submit Batch</button>
        </div>
        <div id="inspectionMapPointSheet" class="inspection-map-point-sheet d-none">
            <div class="inspection-map-sheet-handle"></div>
            <div class="d-flex align-items-start justify-content-between gap-2">
                <div><div id="inspectionMapPointCode" class="inspection-map-point-code">P-01</div><div id="inspectionMapPointName" class="inspection-map-point-name">Inspection Point</div><div id="inspectionMapPointMeta" class="inspection-muted"></div></div>
                <button type="button" id="btnCloseInspectionMapPoint" class="btn btn-sm btn-light border rounded-circle" aria-label="Close"><i class="bi bi-x-lg"></i></button>
            </div>
            <div id="inspectionMapPointStatus" class="inspection-map-point-status mt-3"></div>
            <div id="inspectionMapPointDescription" class="small text-muted mt-2"></div>
            <div class="d-flex gap-2 mt-3">
                <button type="button" id="btnOpenInspectionPointChecklist" class="btn btn-primary flex-fill"><i class="bi bi-clipboard-check me-1"></i>Open Checklist</button>
            </div>
        </div>
    </div>
    <div id="inspectionChecklistPane" class="d-none">
    <div id="inspectionFormPanel" class="inspection-card p-3 mb-3 d-none">
        <div class="inspection-photo-panel mb-3"><div class="fw-bold mb-2"><i class="bi bi-camera-fill me-2"></i>FIELD DOCUMENTATION BEFORE</div><div id="inspectionPhotoBeforeList" class="d-flex flex-wrap gap-2 mb-2"></div><div class="d-flex align-items-center justify-content-between gap-2"><label class="inspection-muted mb-0">Ambil foto sebelum inspeksi</label><button type="button" id="btnAddInspectionBeforePhoto" class="btn btn-sm btn-outline-primary" onclick="document.getElementById('inspectionPhotoBeforeInput').click()"><i class="bi bi-camera"></i> Take Picture</button><input id="inspectionPhotoBeforeInput" type="file" accept="image/*" capture="environment" multiple hidden /></div><div id="inspectionBeforePhotoCount" class="inspection-muted mt-1">0 foto</div></div>
        <div id="inspectionChecklistGateMessage" class="alert alert-warning py-2 small"></div><div id="inspectionChecklistHost"></div>
        <div id="inspectionPointConditionPanel" class="d-none mt-3"></div>
        <div class="inspection-photo-panel mt-3" id="inspectionAfterPhotoPanel"><div class="fw-bold mb-2"><i class="bi bi-camera-fill me-2"></i>FIELD DOCUMENTATION AFTER</div><div id="inspectionPhotoAfterList" class="d-flex flex-wrap gap-2 mb-2"></div><div class="d-flex align-items-center justify-content-between gap-2"><label class="inspection-muted mb-0">Ambil foto setelah inspeksi</label><button type="button" id="btnAddInspectionAfterPhoto" class="btn btn-sm btn-outline-primary" onclick="document.getElementById('inspectionPhotoAfterInput').click()" disabled><i class="bi bi-camera"></i> Take Picture</button><input id="inspectionPhotoAfterInput" type="file" accept="image/*" capture="environment" multiple hidden /></div><div id="inspectionAfterPhotoCount" class="inspection-muted mt-1">0 foto</div></div>
        <div class="accordion-item border-warning shadow-sm mt-3" id="inspectionFollowUpPanel">
            <div class="accordion-header"><div class="accordion-button bg-warning-subtle text-dark fw-bold">
                <i class="bi bi-lightbulb-fill fs-5 me-2 text-warning"></i><div class="d-flex flex-column">
                    <span>FOLLOW UP WORK ORDER RECOMMENDATION</span><small class="text-muted fw-normal">Tentukan apakah diperlukan Work Order lanjutan.</small>
                </div>
            </div></div>
            <div class="accordion-body p-3">
                <div class="alert alert-warning py-2 px-3 mb-3 small"><i class="bi bi-info-circle-fill me-1"></i>
                    Bila ditemukan kerusakan yang memerlukan pekerjaan lanjutan, pilih <strong>Recommend Follow Up</strong>, kemudian tentukan section yang bertanggung jawab dan isi WO Remark.
                </div>
                <div class="mb-3" data-role="followup">
                    <div class="btn-group w-100 shadow-sm" role="group" aria-label="Follow Up recommendation">
                        <input class="btn-check" type="radio" name="inspectionFollowUp" id="inspectionFollowUpNo" value="No Follow Up" checked>
                        <label class="btn btn-outline-primary" for="inspectionFollowUpNo">No Follow Up</label>
                        <input class="btn-check" type="radio" name="inspectionFollowUp" id="inspectionFollowUpYes" value="Recommend Follow Up">
                        <label class="btn btn-outline-primary" for="inspectionFollowUpYes">Recommend Follow Up</label>
                    </div>
                </div>
                <div id="inspectionFollowUpDetails" class="d-none">
                    <div class="card border-warning-subtle bg-light mb-3"><div class="card-body">
                        <label class="form-label small fw-semibold mb-2"><i class="bi bi-diagram-3-fill me-1"></i>Responsible Section</label>
                        <div id="inspectionFollowUpSectionGroup" class="d-flex flex-wrap gap-2"></div>
                        <select id="inspectionFollowUpSection" class="d-none" aria-hidden="true" tabindex="-1"><option value="">Pilih section tujuan...</option></select>
                    </div></div>
                    <div class="card border-warning-subtle bg-light"><div class="card-body">
                        <label class="form-label small fw-semibold mb-2" for="txtInspectionFollowUpRemark"><i class="bi bi-card-text me-1"></i>Follow Up Work Order Description</label>
                        <textarea id="txtInspectionFollowUpRemark" class="form-control" rows="3" maxlength="300" placeholder="Jelaskan pekerjaan lanjutan yang direkomendasikan..."></textarea>
                        <div class="d-flex justify-content-between align-items-center mt-2"><small class="text-muted">Maksimum 300 karakter.</small><small id="inspectionFollowUpRemarkCounter" class="text-muted">0 / 300</small></div>
                    </div></div>
                </div>
            </div>
        </div>
        <div class="accordion-item border-info shadow-sm mt-3" id="inspectionSummaryPanel">
            <div class="accordion-header"><div class="accordion-button bg-info-subtle text-dark fw-bold">
                <i class="bi bi-clipboard2-check-fill fs-5 me-2 text-info"></i><div class="d-flex flex-column">
                    <span>FINAL INSPECTION SUMMARY</span><small class="text-muted fw-normal">Ringkasan hasil inspeksi dan pekerjaan yang telah dilakukan.</small>
                </div>
            </div></div>
            <div class="accordion-body p-3">
                <div class="alert alert-info py-2 px-3 mb-3 small"><i class="bi bi-info-circle-fill me-1"></i>
                    Jelaskan secara singkat hasil pemeriksaan, tindakan yang dilakukan, serta kondisi akhir unit setelah pekerjaan selesai.
                </div>
                <textarea id="txtInspectionSummary" class="form-control" rows="5" maxlength="500" placeholder=""></textarea>
                <div class="d-flex justify-content-between align-items-center mt-2"><small class="text-muted">Maksimum 500 karakter.</small><small id="inspectionSummaryCounter" class="text-muted">0 / 500</small></div>
            </div>
        </div>
        <div class="d-flex flex-wrap gap-2 mt-3">
            <button type="button" id="btnSaveInspectionDraft" class="btn btn-outline-secondary flex-fill">
                <i class="bi bi-save"></i> Save Draft
            </button>
            <button type="button" id="btnDeleteInspectionDraft" class="btn btn-outline-danger flex-fill d-none">
                <i class="bi bi-trash"></i> Delete Draft
            </button>
            <button type="button" id="btnCompleteInspection" class="btn btn-primary flex-fill">
                <i class="bi bi-check-circle"></i> Submit
            </button>
        </div>
    </div>
    </div>
    </div>
</div>
    <div id="inspectionPhotoViewer" class="inspection-photo-viewer d-none" role="dialog" aria-modal="true" aria-hidden="true" aria-label="Preview foto Inspection">
        <div class="inspection-photo-viewer-header">
            <div id="inspectionPhotoViewerTitle" class="fw-semibold small">FIELD DOCUMENTATION BEFORE</div>
            <button type="button" id="inspectionPhotoViewerClose" class="btn btn-outline-light btn-sm" aria-label="Tutup preview foto"><i class="bi bi-x-lg"></i> Tutup</button>
        </div>
        <div id="inspectionPhotoViewerStage" class="inspection-photo-viewer-stage">
            <button type="button" id="inspectionPhotoViewerPrev" class="btn btn-outline-light inspection-photo-viewer-nav" aria-label="Foto sebelumnya">&#8249;</button>
            <img id="inspectionPhotoViewerImage" class="inspection-photo-viewer-image" alt="" />
            <button type="button" id="inspectionPhotoViewerNext" class="btn btn-outline-light inspection-photo-viewer-nav" aria-label="Foto berikutnya">&#8250;</button>
        </div>
        <div class="inspection-photo-viewer-footer"><span id="inspectionPhotoViewerCount">1 / 1</span><div class="small">Gunakan panah atau geser foto ke kiri/kanan</div></div>
    </div>
<script type="text/javascript" src="../JSCus/inspection.js?v=20261110-batch-offline-list-1"></script>
<script type="text/javascript" src="../JSCus/inspectionApprovalOffline.js"></script>
<script type="text/javascript" src="../JSCus/pdf.min.js"></script>
<script type="text/javascript" src="../JSCus/inspectionMapWorkspace.js?v=20261110-point-direct-open-1"></script>
</asp:Content>

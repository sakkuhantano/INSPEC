(function () {
    "use strict";

    var wired = false;
    var selectedPoint = null;

    var demoPoints = [
        { id:"P-01", name:"Main Entrance", type:"GENERAL", x:10, y:18, status:"done", description:"Area entrance / lobby." },
        { id:"P-02", name:"Lobby Lamp A", type:"LIGHTING", x:28, y:27, status:"pending", description:"Fixed inspection point." },
        { id:"P-03", name:"Lobby Lamp B", type:"LIGHTING", x:37, y:16, status:"abnormal", description:"Abnormality found on previous visit." },
        { id:"P-04", name:"Parking Bay A01", type:"CAR PARK", x:57, y:18, status:"pending", description:"Parking bay A01." },
        { id:"P-05", name:"Parking Bay A02", type:"CAR PARK", x:73, y:29, status:"done", description:"Parking bay A02." },
        { id:"P-06", name:"Parking Bay A03", type:"CAR PARK", x:88, y:16, status:"pending", description:"Parking bay A03." },
        { id:"P-07", name:"Transformer TR-01", type:"TRANSFORMER", x:19, y:58, status:"done", description:"Transformer inspection point." },
        { id:"P-08", name:"Panel EP-01", type:"ELECTRICAL", x:31, y:78, status:"pending", description:"Electrical panel inspection point." },
        { id:"P-09", name:"Genset GS-01", type:"GENSET", x:57, y:69, status:"abnormal", description:"Generator set inspection point." },
        { id:"P-10", name:"Pump P-01", type:"MECHANICAL", x:76, y:62, status:"pending", description:"Mechanical equipment point." },
        { id:"P-11", name:"Fire Extinguisher FE-01", type:"FIRE", x:88, y:78, status:"done", description:"Fire safety point." },
        { id:"P-12", name:"Service Door", type:"GENERAL", x:58, y:86, status:"pending", description:"Service area access point." }
    ];

    function esc(value) {
        return String(value == null ? "" : value).replace(/[&<>"']/g, function (c) {
            return ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", """:"&quot;", "'":"&#39;" })[c];
        });
    }

    function statusLabel(status) {
        return status === "done" ? "DONE" : status === "abnormal" ? "ABNORMAL" : "PENDING";
    }

    function pointClass(status) {
        return status === "done" || status === "abnormal" ? status : "pending";
    }

    function renderPoints() {
        var host = document.getElementById("inspectionMapPoints");
        if (!host) return;
        host.innerHTML = demoPoints.map(function (p) {
            return '<button type="button" class="inspection-map-point ' + pointClass(p.status) + '" ' +
                'style="left:' + p.x + '%;top:' + p.y + '%" data-point-id="' + esc(p.id) + '" aria-label="' + esc(p.id + " " + p.name) + '">' +
                '<span class="inspection-map-point-dot">' + esc(p.id.replace("P-","")) + '</span>' +
                '<span class="inspection-map-point-label">' + esc(p.id) + '</span></button>';
        }).join("");

        host.querySelectorAll(".inspection-map-point").forEach(function (button) {
            button.addEventListener("click", function () {
                openPoint(button.getAttribute("data-point-id"));
            });
        });
    }

    function renderList() {
        var host = document.getElementById("inspectionPointList");
        if (!host) return;
        host.innerHTML = demoPoints.map(function (p) {
            return '<div class="inspection-point-list-row" data-point-id="' + esc(p.id) + '">' +
                '<span class="inspection-map-point-dot ' + pointClass(p.status) + '"></span>' +
                '<div class="point-main"><div class="point-code">' + esc(p.id) + ' · ' + esc(p.type) + '</div>' +
                '<div class="point-name">' + esc(p.name) + '</div></div>' +
                '<span class="badge ' + (p.status === "abnormal" ? "text-bg-danger" : p.status === "done" ? "text-bg-success" : "text-bg-secondary") + '">' + statusLabel(p.status) + '</span>' +
                '<i class="bi bi-chevron-right text-muted"></i></div>';
        }).join("");
        host.querySelectorAll(".inspection-point-list-row").forEach(function (row) {
            row.addEventListener("click", function () { openPoint(row.getAttribute("data-point-id")); });
        });
    }

    function updateSummary() {
        var total = demoPoints.length;
        var done = demoPoints.filter(function (p) { return p.status === "done"; }).length;
        var abnormal = demoPoints.filter(function (p) { return p.status === "abnormal"; }).length;
        var pending = total - done - abnormal;
        var set = function (id, value) { var el = document.getElementById(id); if (el) el.textContent = String(value); };
        set("inspectionMapTotalCount", total);
        set("inspectionMapDoneCount", done);
        set("inspectionMapAbnormalCount", abnormal);
        set("inspectionMapPendingCount", pending);
    }

    function openPoint(id) {
        selectedPoint = demoPoints.find(function (p) { return p.id === id; }) || null;
        if (!selectedPoint) return;

        document.querySelectorAll(".inspection-map-point").forEach(function (el) {
            el.classList.toggle("selected", el.getAttribute("data-point-id") === id);
        });

        var code = document.getElementById("inspectionMapPointCode");
        var name = document.getElementById("inspectionMapPointName");
        var meta = document.getElementById("inspectionMapPointMeta");
        var status = document.getElementById("inspectionMapPointStatus");
        var desc = document.getElementById("inspectionMapPointDescription");
        if (code) code.textContent = selectedPoint.id;
        if (name) name.textContent = selectedPoint.name;
        if (meta) meta.textContent = selectedPoint.type + " · Location Map";
        if (status) {
            status.className = "inspection-map-point-status mt-3 " + (selectedPoint.status === "abnormal" ? "text-danger" : selectedPoint.status === "done" ? "text-success" : "text-warning");
            status.innerHTML = '<i class="bi ' + (selectedPoint.status === "done" ? "bi-check-circle-fill" : selectedPoint.status === "abnormal" ? "bi-exclamation-triangle-fill" : "bi-clock-fill") + ' me-1"></i>' + statusLabel(selectedPoint.status);
        }
        if (desc) desc.textContent = selectedPoint.description;
        var sheet = document.getElementById("inspectionMapPointSheet");
        if (sheet) sheet.classList.remove("d-none");
    }

    function closePoint() {
        selectedPoint = null;
        var sheet = document.getElementById("inspectionMapPointSheet");
        if (sheet) sheet.classList.add("d-none");
        document.querySelectorAll(".inspection-map-point.selected").forEach(function (el) { el.classList.remove("selected"); });
    }

    function switchMapList(showList) {
        var canvas = document.getElementById("inspectionMapCanvas");
        var list = document.getElementById("inspectionPointList");
        var mapBtn = document.getElementById("btnInspectionMapView");
        var listBtn = document.getElementById("btnInspectionPointListView");
        if (!canvas || !list) return;
        canvas.classList.toggle("d-none", showList);
        list.classList.toggle("d-none", !showList);
        if (mapBtn) { mapBtn.classList.toggle("btn-primary", !showList); mapBtn.classList.toggle("btn-outline-primary", showList); }
        if (listBtn) { listBtn.classList.toggle("btn-primary", showList); listBtn.classList.toggle("btn-outline-primary", !showList); }
    }

    window.showInspectionMapWorkspace = function (record, activate) {
        var workspace = document.getElementById("inspectionMapWorkspace");
        if (!workspace) return;
        renderPoints();
        renderList();
        updateSummary();

        var typeName = record && record.InspectionTypeName ? record.InspectionTypeName : "Inspection";
        var detailName = record && record.InspectionTypeDetailName ? record.InspectionTypeDetailName : "";
        var title = document.getElementById("inspectionMapTitle");
        var subtitle = document.getElementById("inspectionMapSubtitle");
        if (title) title.textContent = typeName + (detailName ? " · " + detailName : "");
        if (subtitle) subtitle.textContent = "Tap a point to inspect · " + (record && record.ScheduledTime ? record.ScheduledTime : "No schedule");

        if (activate) {
            workspace.classList.remove("d-none");
            document.getElementById("inspectionParamsPane").classList.add("d-none");
            document.getElementById("inspectionChecklistPane").classList.add("d-none");
            var mapTab = document.getElementById("btnInspectionMapTab");
            var paramTab = document.getElementById("btnInspectionParamTab");
            var checklistTab = document.getElementById("btnInspectionChecklistTab");
            if (mapTab) mapTab.classList.add("active");
            if (paramTab) paramTab.classList.remove("active");
            if (checklistTab) checklistTab.classList.remove("active");
            closePoint();
            switchMapList(false);
        }
    };

    window.wireInspectionMapWorkspace = function () {
        if (wired) return;
        wired = true;
        var mapTab = document.getElementById("btnInspectionMapTab");
        if (mapTab) {
            mapTab.addEventListener("click", function () {
                if (window.showInspectionMapWorkspace) window.showInspectionMapWorkspace(window.currentInspectionRecord || null, true);
            });
        }
        var checklistTab = document.getElementById("btnInspectionChecklistTab");
        if (checklistTab) {
            checklistTab.addEventListener("click", function () {
                var workspace = document.getElementById("inspectionMapWorkspace");
                if (workspace) workspace.classList.add("d-none");
            });
        }
        var paramTab = document.getElementById("btnInspectionParamTab");
        if (paramTab) {
            paramTab.addEventListener("click", function () {
                var workspace = document.getElementById("inspectionMapWorkspace");
                if (workspace) workspace.classList.add("d-none");
            });
        }
        var close = document.getElementById("btnCloseInspectionMapPoint");
        if (close) close.addEventListener("click", closePoint);
        var mapView = document.getElementById("btnInspectionMapView");
        var listView = document.getElementById("btnInspectionPointListView");
        if (mapView) mapView.addEventListener("click", function () { switchMapList(false); });
        if (listView) listView.addEventListener("click", function () { switchMapList(true); closePoint(); });
        var reset = document.getElementById("btnInspectionMapReset");
        if (reset) reset.addEventListener("click", function () { switchMapList(false); closePoint(); });

        var openChecklist = document.getElementById("btnOpenInspectionPointChecklist");
        if (openChecklist) openChecklist.addEventListener("click", function () {
            closePoint();
            var workspace = document.getElementById("inspectionMapWorkspace");
            if (workspace) workspace.classList.add("d-none");
            var checklistTab = document.getElementById("btnInspectionChecklistTab");
            if (checklistTab) checklistTab.click();
            var host = document.getElementById("inspectionChecklistHost");
            if (host) window.setTimeout(function () { host.scrollIntoView({ behavior:"smooth", block:"start" }); }, 80);
        });

        var markDone = document.getElementById("btnMarkInspectionPointDone");
        if (markDone) markDone.addEventListener("click", function () {
            if (!selectedPoint) return;
            selectedPoint.status = "done";
            var target = demoPoints.find(function (p) { return p.id === selectedPoint.id; });
            if (target) target.status = "done";
            renderPoints(); renderList(); updateSummary();
            openPoint(selectedPoint.id);
        });
    };

    document.addEventListener("DOMContentLoaded", function () {
        window.setTimeout(function () {
            if (typeof window.wireInspectionMapWorkspace === "function") window.wireInspectionMapWorkspace();
        }, 0);
    });
})();

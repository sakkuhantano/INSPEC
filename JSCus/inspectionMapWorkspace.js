(function () {
    "use strict";

    var wired = false;
    var selectedPoint = null;
    var currentMapRecord = null;
    var currentMaps = [];
    var currentPoints = [];
    var currentMapId = "";
    var currentPdfDocument = null;
    var listPage = 1;
    var listPageSize = 20;
    var listKeyword = "";

    function esc(value) {
        return String(value == null ? "" : value).replace(/[&<>"']/g, function (c) {
            return ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", "\"":"&quot;", "'":"&#39;" })[c];
        });
    }

    function normalizedStatus(status) {
        status = String(status || "PENDING").toUpperCase();
        if (status === "DONE" || status === "INSPECTED") return "DONE";
        if (status === "ABNORMAL") return "ABNORMAL";
        if (status === "INCOMPLETE") return "INCOMPLETE";
        return "PENDING";
    }

    function pointClass(status) {
        return normalizedStatus(status).toLowerCase();
    }

    function statusLabel(status) {
        var value = normalizedStatus(status);
        return value === "DONE" ? "DONE" : value === "ABNORMAL" ? "ABNORMAL" :
            value === "INCOMPLETE" ? "INCOMPLETE" : "PENDING";
    }

    function getPointTransaction(point) {
        if (!currentMapRecord || !Array.isArray(currentMapRecord.Points)) return null;
        return currentMapRecord.Points.find(function (item) {
            return Number(item.InspectionPointID) === Number(point.InspectionPointID);
        }) || null;
    }

    function getPointStatus(point) {
        var transaction = getPointTransaction(point);
        return normalizedStatus(transaction && transaction.Status);
    }

    function getVisiblePoints() {
        return currentPoints.slice();
    }

    function renderPoints() {
        var host = document.getElementById("inspectionMapPoints");
        if (!host) return;
        var mapId = Number(currentMapId || 0);
        var points = currentPoints.filter(function (point) {
            return mapId && Number(point.MapID || 0) === mapId &&
                point.MapX !== null && point.MapX !== undefined &&
                point.MapY !== null && point.MapY !== undefined;
        });
        host.innerHTML = points.map(function (point) {
            var status = getPointStatus(point);
            var code = String(point.PointCode || "");
            return '<button type="button" class="inspection-map-point ' + pointClass(status) + '" ' +
                'style="left:' + Number(point.MapX) + '%;top:' + Number(point.MapY) + '%" ' +
                'data-point-id="' + esc(point.InspectionPointID) + '" aria-label="' +
                esc(code + " " + (point.PointName || "")) + '" title="' +
                esc(code + " - " + (point.PointName || "") + " · " + statusLabel(status)) + '">' +
                '<span class="inspection-map-point-dot"></span>' +
                '<span class="inspection-map-point-label">' + esc(code) + '</span></button>';
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

        var all = getVisiblePoints();
        var keyword = String(listKeyword || "").trim().toLowerCase();
        var filtered = all.filter(function (point) {
            return !keyword ||
                String(point.PointCode || "").toLowerCase().indexOf(keyword) >= 0 ||
                String(point.PointName || "").toLowerCase().indexOf(keyword) >= 0 ||
                String(point.PointObjectType || "").toLowerCase().indexOf(keyword) >= 0;
        });
        var pageCount = Math.max(1, Math.ceil(filtered.length / listPageSize));
        listPage = Math.min(Math.max(1, listPage), pageCount);
        var start = (listPage - 1) * listPageSize;
        var rows = filtered.slice(start, start + listPageSize);

        host.innerHTML =
            '<div class="inspection-point-list-tools">' +
                '<div class="d-flex gap-2 align-items-center mb-2">' +
                    '<input type="search" id="inspectionPointSearch" class="form-control form-control-sm" ' +
                    'placeholder="Cari Point Code / Name..." value="' + esc(listKeyword) + '">' +
                    '<select id="inspectionPointPageSize" class="form-select form-select-sm" style="width:82px">' +
                        '<option value="10"' + (listPageSize === 10 ? ' selected' : '') + '>10</option>' +
                        '<option value="20"' + (listPageSize === 20 ? ' selected' : '') + '>20</option>' +
                        '<option value="50"' + (listPageSize === 50 ? ' selected' : '') + '>50</option>' +
                    '</select>' +
                '</div>' +
                '<div class="d-flex align-items-center justify-content-between small text-muted">' +
                    '<span>' + (filtered.length ? (start + 1) + '-' + Math.min(start + listPageSize, filtered.length) : 0) +
                    ' dari ' + filtered.length + ' point</span>' +
                    '<div class="btn-group btn-group-sm">' +
                        '<button type="button" class="btn btn-outline-secondary" id="inspectionPointPrev" ' + (listPage <= 1 ? 'disabled' : '') + '><i class="bi bi-chevron-left"></i></button>' +
                        '<span class="btn btn-outline-secondary disabled">' + listPage + ' / ' + pageCount + '</span>' +
                        '<button type="button" class="btn btn-outline-secondary" id="inspectionPointNext" ' + (listPage >= pageCount ? 'disabled' : '') + '><i class="bi bi-chevron-right"></i></button>' +
                    '</div>' +
                '</div>' +
            '</div>' +
            (rows.length ? rows.map(function (point) {
                var status = getPointStatus(point);
                return '<button type="button" class="inspection-point-list-row w-100 text-start" data-point-id="' +
                    esc(point.InspectionPointID) + '">' +
                    '<span class="inspection-map-point-dot ' + pointClass(status) + '"></span>' +
                    '<span class="point-main"><span class="point-code d-block">' + esc(point.PointCode) +
                    ' · ' + esc(point.PointObjectType || "GENERAL") + '</span>' +
                    '<span class="point-name d-block">' + esc(point.PointName) + '</span></span>' +
                    '<span class="badge ' + (status === "DONE" ? "text-bg-success" :
                    status === "ABNORMAL" ? "text-bg-danger" :
                    status === "INCOMPLETE" ? "text-bg-warning" : "text-bg-secondary") + '">' +
                    statusLabel(status) + '</span><i class="bi bi-chevron-right text-muted"></i></button>';
            }).join("") : '<div class="text-muted small text-center py-4">Tidak ada Inspection Point yang cocok.</div>');

        host.querySelectorAll("[data-point-id]").forEach(function (button) {
            button.addEventListener("click", function () {
                openPoint(button.getAttribute("data-point-id"));
            });
        });
        var search = document.getElementById("inspectionPointSearch");
        if (search) search.addEventListener("input", function () {
            listKeyword = this.value;
            listPage = 1;
            renderList();
            var next = document.getElementById("inspectionPointSearch");
            if (next) { next.focus(); next.setSelectionRange(listKeyword.length, listKeyword.length); }
        });
        var size = document.getElementById("inspectionPointPageSize");
        if (size) size.addEventListener("change", function () {
            listPageSize = Number(this.value) || 20;
            listPage = 1;
            renderList();
        });
        var prev = document.getElementById("inspectionPointPrev");
        var next = document.getElementById("inspectionPointNext");
        if (prev) prev.addEventListener("click", function () { listPage--; renderList(); });
        if (next) next.addEventListener("click", function () { listPage++; renderList(); });
    }

    function updateSummary() {
        var points = getVisiblePoints();
        var done = points.filter(function (p) { return getPointStatus(p) === "DONE"; }).length;
        var abnormal = points.filter(function (p) { return getPointStatus(p) === "ABNORMAL"; }).length;
        var incomplete = points.filter(function (p) { return getPointStatus(p) === "INCOMPLETE"; }).length;
        var pending = points.length - done - abnormal - incomplete;
        var set = function (id, value) {
            var element = document.getElementById(id);
            if (element) element.textContent = String(value);
        };
        set("inspectionMapTotalCount", points.length);
        set("inspectionMapDoneCount", done);
        set("inspectionMapAbnormalCount", abnormal);
        set("inspectionMapPendingCount", pending + incomplete);
    }

    function openPoint(id) {
        selectedPoint = currentPoints.find(function (point) {
            return String(point.InspectionPointID) === String(id);
        }) || null;
        if (!selectedPoint) return;

        document.querySelectorAll(".inspection-map-point").forEach(function (element) {
            element.classList.toggle("selected", element.getAttribute("data-point-id") === String(id));
        });

        var statusValue = getPointStatus(selectedPoint);
        var code = document.getElementById("inspectionMapPointCode");
        var name = document.getElementById("inspectionMapPointName");
        var meta = document.getElementById("inspectionMapPointMeta");
        var status = document.getElementById("inspectionMapPointStatus");
        var desc = document.getElementById("inspectionMapPointDescription");
        if (code) code.textContent = selectedPoint.PointCode || "";
        if (name) name.textContent = selectedPoint.PointName || "";
        if (meta) meta.textContent = (selectedPoint.PointObjectType || "GENERAL") +
            (selectedPoint.MapCode ? " · " + selectedPoint.MapCode : " · Tanpa denah");
        if (status) {
            status.className = "inspection-map-point-status mt-3 " +
                (statusValue === "ABNORMAL" ? "text-danger" : statusValue === "DONE" ? "text-success" :
                statusValue === "INCOMPLETE" ? "text-warning" : "text-secondary");
            status.textContent = statusLabel(statusValue);
        }
        if (desc) desc.textContent = selectedPoint.PointDescription || selectedPoint.ObjectReferenceCode || "";
        var sheet = document.getElementById("inspectionMapPointSheet");
        if (sheet) sheet.classList.remove("d-none");
    }

    function closePoint() {
        selectedPoint = null;
        var sheet = document.getElementById("inspectionMapPointSheet");
        if (sheet) sheet.classList.add("d-none");
        document.querySelectorAll(".inspection-map-point.selected").forEach(function (element) {
            element.classList.remove("selected");
        });
    }

    function switchMapList(showList) {
        var canvas = document.getElementById("inspectionMapCanvas");
        var list = document.getElementById("inspectionPointList");
        var mapButton = document.getElementById("btnInspectionMapView");
        var listButton = document.getElementById("btnInspectionPointListView");
        if (!canvas || !list) return;
        var hasMap = currentMaps.some(function (map) {
            return Number(map.MapID) === Number(currentMapId) && !!map.MapUrl;
        });
        canvas.classList.toggle("d-none", showList || !hasMap);
        list.classList.toggle("d-none", !showList && hasMap);
        if (mapButton) {
            mapButton.classList.toggle("btn-primary", !showList && hasMap);
            mapButton.classList.toggle("btn-outline-primary", showList || !hasMap);
            mapButton.disabled = !hasMap;
        }
        if (listButton) {
            listButton.classList.toggle("btn-primary", showList || !hasMap);
            listButton.classList.toggle("btn-outline-primary", !showList && hasMap);
        }
    }

    async function renderPdf(map) {
        var message = document.getElementById("inspectionMapPdfMessage");
        var canvas = document.getElementById("inspectionMapPdfCanvas");
        var stage = document.getElementById("inspectionMapPdfStage");
        if (!canvas || !stage) return;

        if (currentPdfDocument && currentPdfDocument.destroy) {
            try { await currentPdfDocument.destroy(); } catch (_) { }
            currentPdfDocument = null;
        }
        var context = canvas.getContext("2d");
        context.clearRect(0, 0, canvas.width, canvas.height);
        canvas.width = 0;
        canvas.height = 0;

        if (!map || !map.MapUrl) {
            if (message) {
                message.textContent = "Denah PDF belum tersedia. Gunakan tampilan List untuk memilih Inspection Point.";
                message.classList.remove("d-none");
            }
            stage.style.width = "100%";
            stage.style.minHeight = "260px";
            return;
        }
        if (!window.pdfjsLib) {
            if (message) {
                message.textContent = "PDF.js belum termuat. Periksa file pdf.min.js.";
                message.classList.remove("d-none");
            }
            return;
        }

        try {
            window.pdfjsLib.GlobalWorkerOptions.workerSrc = "../JSCus/pdf.worker.min.js";
            if (message) {
                message.textContent = "Memuat denah PDF...";
                message.classList.remove("d-none");
            }
            if (map.PdfBlob && typeof map.PdfBlob.arrayBuffer === "function") {
                var pdfBytes = new Uint8Array(await map.PdfBlob.arrayBuffer());
                currentPdfDocument = await window.pdfjsLib.getDocument({ data: pdfBytes }).promise;
            } else {
                currentPdfDocument = await window.pdfjsLib.getDocument({
                    url: map.MapUrl,
                    withCredentials: true
                }).promise;
            }
            var page = await currentPdfDocument.getPage(1);
            var baseViewport = page.getViewport({ scale: 1 });
            var availableWidth = Math.max(300, Math.min(1200, document.getElementById("inspectionMapCanvas").clientWidth - 28));
            var scale = availableWidth / baseViewport.width;
            var pixelRatio = Math.min(window.devicePixelRatio || 1, 1.5);
            var viewport = page.getViewport({ scale: scale * pixelRatio });
            canvas.width = Math.floor(viewport.width);
            canvas.height = Math.floor(viewport.height);
            canvas.style.width = Math.floor(viewport.width / pixelRatio) + "px";
            canvas.style.height = Math.floor(viewport.height / pixelRatio) + "px";
            stage.style.width = canvas.style.width;
            stage.style.minHeight = "0";
            await page.render({ canvasContext: context, viewport: viewport }).promise;
            if (message) message.classList.add("d-none");
            renderPoints();
        } catch (error) {
            console.error("Inspection PDF render failed:", error);
            if (message) {
                message.textContent = "Denah PDF gagal dimuat: " + (error && error.message ? error.message : "periksa akses file PDF.");
                message.classList.remove("d-none");
            }
        }
    }

    function renderMapOptions() {
        var wrap = document.getElementById("inspectionMapSelectWrap");
        var select = document.getElementById("inspectionMapSelect");
        if (!select || !wrap) return;
        var maps = currentMaps.filter(function (map) { return !!map.MapUrl; });
        wrap.classList.toggle("d-none", maps.length <= 1);
        select.innerHTML = maps.map(function (map) {
            return '<option value="' + esc(map.MapID) + '">' + esc(map.MapCode + " - " + map.MapName + " (v" + map.MapVersion + ")") + '</option>';
        }).join("");
        if (maps.length) {
            if (!maps.some(function (map) { return Number(map.MapID) === Number(currentMapId); }))
                currentMapId = String(maps[0].MapID);
            select.value = currentMapId;
        } else {
            currentMapId = "";
            select.innerHTML = '<option value="">Tanpa denah</option>';
        }
    }

    window.showInspectionMapWorkspace = function (record, activate) {
        if (record) currentMapRecord = record;
        record = record || currentMapRecord;
        var workspace = document.getElementById("inspectionMapWorkspace");
        if (!workspace || !record) return;
        if (typeof window.mountInspectionBatchSummary === "function")
            window.mountInspectionBatchSummary(record);

        var setup = record.BatchMapSetup || {};
        currentMaps = Array.isArray(setup.maps) ? setup.maps : [];
        currentPoints = Array.isArray(setup.points) ? setup.points : [];
        if (!currentPoints.length && Array.isArray(record.PointMaster)) currentPoints = record.PointMaster;
        if (!currentMapId && currentMaps.length) currentMapId = String(currentMaps[0].MapID);
        renderMapOptions();

        var submitBatchButton = document.getElementById("btnSubmitInspectionBatch");
        if (submitBatchButton) submitBatchButton.classList.toggle("d-none", String(record.Status || "").toUpperCase() === "DONE");

        var typeName = record.InspectionTypeName || "Inspection";
        var detailName = record.InspectionTypeDetailName || "";
        var title = document.getElementById("inspectionMapTitle");
        var subtitle = document.getElementById("inspectionMapSubtitle");
        if (title) title.textContent = typeName + (detailName ? " · " + detailName : "");
        if (subtitle) subtitle.textContent = "Batch " + (record.InspectionNo || "baru") +
            " · " + currentPoints.length + " Inspection Point";

        renderList();
        updateSummary();
        renderPoints();
        var selectedMap = currentMaps.find(function (map) {
            return Number(map.MapID) === Number(currentMapId);
        }) || null;
        renderPdf(selectedMap);

        if (activate) {
            workspace.classList.remove("d-none");
            var paramPane = document.getElementById("inspectionParamsPane");
            var checklistPane = document.getElementById("inspectionChecklistPane");
            if (paramPane) paramPane.classList.add("d-none");
            if (checklistPane) checklistPane.classList.add("d-none");
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

    window.refreshInspectionMapPointStatuses = function () {
        renderPoints();
        renderList();
        updateSummary();
    };

    window.getSelectedInspectionMapPoint = function () {
        return selectedPoint;
    };

    window.wireInspectionMapWorkspace = function () {
        if (wired) return;
        wired = true;

        var mapTab = document.getElementById("btnInspectionMapTab");
        if (mapTab) mapTab.addEventListener("click", async function () {
            if (currentMapRecord && Number(currentMapRecord.ActiveInspectionPointID || 0) > 0 &&
                typeof window.saveBatchInspectionPoint === "function") {
                await window.saveBatchInspectionPoint("DRAFT");
                return;
            }
            if (window.showInspectionMapWorkspace) window.showInspectionMapWorkspace(currentMapRecord, true);
        });

        var checklistTab = document.getElementById("btnInspectionChecklistTab");
        if (checklistTab) checklistTab.addEventListener("click", function () {
            var workspace = document.getElementById("inspectionMapWorkspace");
            if (workspace) workspace.classList.add("d-none");
        });

        var paramTab = document.getElementById("btnInspectionParamTab");
        if (paramTab) paramTab.addEventListener("click", function () {
            var workspace = document.getElementById("inspectionMapWorkspace");
            if (workspace) workspace.classList.add("d-none");
        });

        var close = document.getElementById("btnCloseInspectionMapPoint");
        if (close) close.addEventListener("click", closePoint);
        var mapView = document.getElementById("btnInspectionMapView");
        var listView = document.getElementById("btnInspectionPointListView");
        if (mapView) mapView.addEventListener("click", function () { switchMapList(false); });
        if (listView) listView.addEventListener("click", function () { switchMapList(true); closePoint(); });

        var reset = document.getElementById("btnInspectionMapReset");
        if (reset) reset.addEventListener("click", function () {
            switchMapList(false);
            closePoint();
            var map = currentMaps.find(function (item) { return Number(item.MapID) === Number(currentMapId); });
            renderPdf(map || null);
        });

        var mapSelect = document.getElementById("inspectionMapSelect");
        if (mapSelect) mapSelect.addEventListener("change", function () {
            currentMapId = this.value;
            listPage = 1;
            renderList();
            updateSummary();
            var map = currentMaps.find(function (item) { return Number(item.MapID) === Number(currentMapId); });
            renderPdf(map || null);
        });

        var openChecklist = document.getElementById("btnOpenInspectionPointChecklist");
        if (openChecklist) openChecklist.addEventListener("click", function () {
            if (!selectedPoint) return;
            var point = selectedPoint;
            closePoint();
            if (typeof window.openBatchInspectionPointChecklist === "function") {
                window.openBatchInspectionPointChecklist(point);
            } else {
                if (typeof showInspectionNotice === "function")
                    showInspectionNotice("Modul checklist per titik belum siap dibuka.", "warning");
            }
        });

        var submit = document.getElementById("btnSubmitInspectionBatch");
        if (submit) submit.addEventListener("click", function () {
            if (typeof window.submitInspectionBatch === "function") window.submitInspectionBatch();
            else if (typeof showInspectionNotice === "function")
                showInspectionNotice("Submit batch belum tersedia.", "warning");
        });
    };

    document.addEventListener("DOMContentLoaded", function () {
        window.setTimeout(function () {
            if (typeof window.wireInspectionMapWorkspace === "function")
                window.wireInspectionMapWorkspace();
        }, 0);
    });
})();
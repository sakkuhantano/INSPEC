(function () {
    "use strict";

    var wired = false;
    var selectedPoint = null;
    var currentMapRecord = null;
    var currentMaps = [];
    var currentPoints = [];
    var currentMapId = "";
    var currentPdfDocument = null;
    var currentPdfPage = null;
    var currentPdfFitScale = 1;
    var pdfCanvasRenderTask = null;
    var pdfCanvasRenderTimer = null;
    var pdfCanvasRenderSequence = 0;
    var pdfRenderSequence = 0;
    var listPage = 1;
    var listPageSize = 20;
    var listKeyword = "";
    var mapZoom = 1;
    var mapPanX = 0;
    var mapPanY = 0;
    var mapPointers = {};
    var mapGesture = null;
    var mapMinZoom = 1;
    var mapMaxZoom = 4;

    function esc(value) {
        return String(value == null ? "" : value).replace(/[&<>"']/g, function (c) {
            return ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", "\"":"&quot;", "'":"&#39;" })[c];
        });
    }

    function flagEnabled(value) {
        return value === true || value === 1 || value === "1" ||
            String(value == null ? "" : value).toLowerCase() === "true";
    }

    function normalizedStatus(status) {
        status = String(status || "PENDING").toUpperCase();
        if (status === "DONE" || status === "INSPECTED" || status === "ABNORMAL") return "DONE";
        if (status === "INCOMPLETE") return "INCOMPLETE";
        return "PENDING";
    }

    function pointClass(status) {
        return String(status || "").toUpperCase() === "ABNORMAL" ? "abnormal" : normalizedStatus(status).toLowerCase();
    }

    function statusLabel(status, point) {
        if (String(status || "").toUpperCase() === "ABNORMAL") return "ABNORMAL";
        var value = normalizedStatus(status);
        return value === "DONE" ? "SELESAI" :
            value === "INCOMPLETE" ? "BELUM LENGKAP" : "BELUM DIPERIKSA";
    }

    function statusSymbol(status) {
        if (String(status || "").toUpperCase() === "ABNORMAL") return "!";
        var value = normalizedStatus(status);
        return value === "DONE" ? "✓" : value === "INCOMPLETE" ? "…" : "·";
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

    function isNormalAbnormalRequired(point) {
        var value = point && point.IsNormalAbnormalRequired;
        return value === true || value === 1 || value === "1" ||
            String(value || "").trim().toUpperCase() === "Y" ||
            String(value || "").trim().toUpperCase() === "TRUE";
    }

    function getPointVisualStatus(point) {
        // The master-map flag controls whether this point may be classified as abnormal.
        if (!isNormalAbnormalRequired(point)) return getPointStatus(point);
        var transaction = getPointTransaction(point);
        if (transaction && String(transaction.AbnormalRemark || "").trim()) return "ABNORMAL";
        var template = currentMapRecord && currentMapRecord.TemplateSnapshot;
        var templateItems = [];
        (template && Array.isArray(template.sections) ? template.sections : []).forEach(function (section) {
            (section.items || []).forEach(function (item) { templateItems.push(item); });
        });
        if (templateItems.length === 1 && String(templateItems[0].type || "").toUpperCase() === "OPTION") {
            var answer = transaction && (transaction.Items || []).find(function (item) {
                return Number(item.IDItem) === Number(templateItems[0].idItem);
            });
            var value = String(answer && answer.Value || "").trim().toUpperCase();
            if (/^(OFF|MATI|NO|RUSAK|ABNORMAL|TIDAK|NOT OK)$/.test(value)) return "ABNORMAL";
            if (value) return "DONE";
        }
        return getPointStatus(point);
    }

    function getTemplateOptionItems() {
        var template = currentMapRecord && currentMapRecord.TemplateSnapshot;
        var result = [];
        (template && Array.isArray(template.sections) ? template.sections : []).forEach(function (section) {
            (section.items || []).forEach(function (item) {
                if (String(item.type || "").toUpperCase() === "OPTION") result.push(item);
            });
        });
        return result;
    }

    function renderPointOptionControls(point) {
        var optionItems = getTemplateOptionItems();
        if (!optionItems.length) return "";
        var transaction = getPointTransaction(point);
        var savedItems = transaction && Array.isArray(transaction.Items) ? transaction.Items : [];
        var readOnly = String(currentMapRecord && currentMapRecord.Status || "").toUpperCase() === "DONE";
        var blockReason = typeof window.getBatchPointQuickOptionBlockReason === "function"
            ? window.getBatchPointQuickOptionBlockReason(point) : "";
        return '<div class="inspection-point-option-controls mt-1 d-flex flex-column gap-1">' +
            optionItems.map(function (item) {
                var saved = savedItems.find(function (answer) { return Number(answer.IDItem) === Number(item.idItem); });
                var selected = String(saved && saved.Value || "");
                var options = String(item.optionList || "").split(";").map(function (value) { return value.trim(); }).filter(Boolean);
                if (!options.length) return "";
                var snapshot = currentMapRecord && currentMapRecord.TemplateSnapshot;
                var versionInfo = snapshot && (snapshot.VersionInfo || snapshot.versionInfo || snapshot);
                var versionRemark1 = flagEnabled(item.versionIsRemark1Required) ||
                    flagEnabled(item.VersionIsRemark1Required) || flagEnabled(versionInfo && versionInfo.VersionIsRemark1Required) ||
                    flagEnabled(versionInfo && versionInfo.IsRemark1Required);
                var versionRemark2 = flagEnabled(item.versionIsRemark2Required) ||
                    flagEnabled(item.VersionIsRemark2Required) || flagEnabled(versionInfo && versionInfo.VersionIsRemark2Required) ||
                    flagEnabled(versionInfo && versionInfo.IsRemark2Required);
                var rawRemarkOptions = item.remarkRequiredOptions || item.RemarkRequiredOptions || [];
                var remarkOptions = Array.isArray(rawRemarkOptions) ? rawRemarkOptions.map(function (x) { return String(x).trim(); }) :
                    String(rawRemarkOptions || "").split(";").map(function (x) { return x.trim(); }).filter(Boolean);
                var optionRequiresRemark = remarkOptions.indexOf(selected.trim()) >= 0;
                var remarkHtml = "";
                [1, 2].forEach(function (number) {
                    var versionEnabled = number === 1 ? versionRemark1 : versionRemark2;
                    var itemRequired = number === 1
                        ? (flagEnabled(item.isRemark1Required) || flagEnabled(item.IsRemark1Required))
                        : (flagEnabled(item.isRemark2Required) || flagEnabled(item.IsRemark2Required));
                    var mandatory = number === 1
                        ? (flagEnabled(item.isRemark1Mandatory) || flagEnabled(item.IsRemark1Mandatory))
                        : (flagEnabled(item.isRemark2Mandatory) || flagEnabled(item.IsRemark2Mandatory));
                    var text = number === 1
                        ? (item.remark1Text || item.Remark1Text)
                        : (item.remark2Text || item.Remark2Text);
                    var field = number === 1 ? "Remark1" : "Remark2";
                    if (!(itemRequired || (versionEnabled && remarkOptions.length))) return;
                    var visible = itemRequired || (versionEnabled && optionRequiresRemark);
                    var inputRequired = visible && (!!mandatory || optionRequiresRemark);
                    var value = saved && saved[field] != null ? saved[field] : "";
                    remarkHtml += '<div class="inspection-point-remark' + (visible ? "" : " d-none") + '">' +
                        '<label class="small text-muted mb-1">' + esc(text || "Remark" + number) +
                        (inputRequired ? ' (wajib)' : '') + '</label>' +
                        '<input type="text" maxlength="500" class="form-control form-control-sm" ' +
                        'data-point-remark-item="' + esc(item.idItem) + '" data-point-remark-field="' + number +
                        '" data-point-id="' + esc(point.InspectionPointID) + '" value="' + esc(value) + '"' +
                        (readOnly ? " disabled" : "") + (inputRequired ? " required" : "") + '></div>';
                });
                return '<div class="inspection-point-option-group">' +
                    '<div class="small text-muted mb-1">' + esc(item.label || "Checklist") + '</div>' +
                    '<div class="d-flex flex-wrap gap-1">' + options.map(function (option) {
                        var active = selected === option;
                        return '<button type="button" class="btn btn-sm ' +
                            (active ? 'btn-primary' : 'btn-outline-primary') +
                            ' inspection-point-option-choice" ' + ((readOnly || blockReason) ? 'disabled aria-disabled="true" title="' + esc(blockReason || "Inspection sudah read-only.") + '" ' : '') +
                            'data-point-option-item="' + esc(item.idItem) +
                            '" data-point-option-value="' + esc(option) + '" data-point-id="' +
                            esc(point.InspectionPointID) + '">' + esc(option) + '</button>';
                    }).join("") + '</div>' + remarkHtml + '</div>';
            }).join("") + '</div>';
    }

    function pointRequiresInspection(point) {
        if (!point || point.RequireAllPoints === undefined || point.RequireAllPoints === null) return true;
        return !(point.RequireAllPoints === false || point.RequireAllPoints === 0 ||
            String(point.RequireAllPoints).toLowerCase() === "false" || String(point.RequireAllPoints) === "0");
    }

    function getVisiblePoints() {
        if (!currentMapId) return [];
        return currentPoints.filter(function (point) {
            return Number(point.MapID || 0) === Number(currentMapId);
        });
    }

    function findNextPendingPoint() {
        var pending = getVisiblePoints().filter(function (point) {
            var status = getPointStatus(point);
            return status === "INCOMPLETE" || (status === "PENDING" && pointRequiresInspection(point));
        });
        if (!pending.length) return null;
        pending.sort(function (a, b) {
            var ao = Number(a.DisplayOrder || 0), bo = Number(b.DisplayOrder || 0);
            if (ao !== bo) return ao - bo;
            return String(a.PointCode || "").localeCompare(String(b.PointCode || ""));
        });
        return pending[0];
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
        var svg = ['<svg class="inspection-map-svg-overlay" viewBox="0 0 100 100" preserveAspectRatio="none" aria-label="Inspection point vector shapes">'];
        var circleMarkers = [];
        points.forEach(function (point) {
            var status = getPointVisualStatus(point);
            var code = String(point.PointCode || "");
            var pointName = String(point.PointName || "");
            var title = code + " - " + pointName + " · " + statusLabel(status, point);
            if (String(point.ShapeType || "CIRCLE").toUpperCase() === "PATH" && point.SvgPathData) {
                var strokeWidth = Math.max(0.25, Math.min(10, Number(point.StrokeWidth) || 1.5));
                svg.push('<path class="inspection-map-svg-path ' + pointClass(status) + '" d="' +
                    esc(point.SvgPathData) + '" stroke-width="' + strokeWidth + '" data-point-id="' +
                    esc(point.InspectionPointID) + '" role="button" tabindex="0" aria-label="' +
                    esc(title) + '" title="' + esc(title) + '"><title>' + esc(title) + '</title></path>');
                return;
            }
            var x = Math.max(0, Math.min(100, Number(point.MapX) || 0));
            var y = Math.max(0, Math.min(100, Number(point.MapY) || 0));
            var shape = {};
            try { shape = typeof point.ShapeAttributes === "string" ? JSON.parse(point.ShapeAttributes || "{}") : (point.ShapeAttributes || {}); } catch (_) { shape = {}; }
            var cx = isFinite(Number(shape.cx)) ? Math.max(0, Math.min(100, Number(shape.cx))) : x;
            var cy = isFinite(Number(shape.cy)) ? Math.max(0, Math.min(100, Number(shape.cy))) : y;
            var radius = isFinite(Number(shape.r)) && Number(shape.r) > 0 ? Math.max(0.2, Math.min(8, Number(shape.r))) : 2.0;
            var circleAspect = host.clientWidth && host.clientHeight ? host.clientWidth / host.clientHeight : 1;
            var circleTransform = 'translate(' + cx + ' ' + cy + ') scale(1 ' + circleAspect + ') translate(' + (-cx) + ' ' + (-cy) + ')';
            svg.push('<circle class="inspection-map-svg-circle ' + pointClass(status) + '" cx="' + cx + '" cy="' + cy + '" r="' + radius + '" transform="' + circleTransform + '" data-point-id="' + esc(point.InspectionPointID) + '" role="button" tabindex="0" aria-label="' + esc(title) + '" title="' + esc(title) + '"><title>' + esc(title) + '</title></circle>');
            circleMarkers.push('<button type="button" class="inspection-map-point ' + pointClass(status) + '" ' +
                'style="left:' + x + '%;top:' + y + '%" data-point-id="' + esc(point.InspectionPointID) +
                '" aria-label="' + esc(title) + '" title="' + esc(title) + '">' +
                '<span class="inspection-map-point-dot">' + statusSymbol(status) + '</span>' +
                '<span class="inspection-map-point-label">' + esc(code) + '</span></button>');
        });
        svg.push('</svg>');
        host.innerHTML = svg.join("") + circleMarkers.join("");

        host.querySelectorAll("[data-point-id]").forEach(function (shape) {
            shape.addEventListener("click", function (event) {
                event.preventDefault();
                event.stopPropagation();
                openPoint(shape.getAttribute("data-point-id"));
            });
            shape.addEventListener("keydown", function (event) {
                if (event.key === "Enter" || event.key === " ") {
                    event.preventDefault();
                    openPoint(shape.getAttribute("data-point-id"));
                }
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
                false;
        });
        var pageCount = Math.max(1, Math.ceil(filtered.length / listPageSize));
        listPage = Math.min(Math.max(1, listPage), pageCount);
        var start = (listPage - 1) * listPageSize;
        var rows = filtered.slice(start, start + listPageSize);

        if (window.bootstrap && bootstrap.Tooltip) {
            host.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function (element) {
                var oldTooltip = bootstrap.Tooltip.getInstance(element);
                if (oldTooltip) oldTooltip.dispose();
            });
        }

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
                var status = getPointVisualStatus(point);
                var transaction = getPointTransaction(point);
                var issueCount = Number(transaction && transaction.ValidationIssueCount || point.ValidationIssueCount || 0);
                var quickOptionBlockReason = typeof window.getBatchPointQuickOptionBlockReason === "function"
                    ? window.getBatchPointQuickOptionBlockReason(point) : "";
                return '<div class="inspection-point-list-entry mb-1">' +
                    '<div role="button" tabindex="0" class="inspection-point-list-row w-100 text-start ' + (issueCount ? "validation-has-issues" : "") + '" data-point-id="' +
                    esc(point.InspectionPointID) + '">' +
                    '<span class="inspection-map-point-dot ' + pointClass(status) + '">' + statusSymbol(status) + '</span>' +
                    '<span class="point-main"><span class="point-code d-block">' + esc(point.PointCode) + '</span>' +
                    '<span class="point-name-line"><span class="point-name">' + esc(point.PointName) + '</span>' +
                    (quickOptionBlockReason ? '<button type="button" class="point-info-button" data-bs-toggle="tooltip" data-bs-trigger="click focus" data-bs-placement="top" data-bs-container="body" data-bs-title="' +
                        esc(quickOptionBlockReason) + '" aria-label="Informasi persyaratan point ' + esc(point.PointCode) + '"><i class="bi bi-info-circle"></i></button>' : '') +
                    '</span></span>' +
                    '<span class="badge ' + (issueCount ? "text-bg-danger" : status === "ABNORMAL" ? "text-bg-danger" :
                    status === "DONE" ? "text-bg-success" :
                    status === "INCOMPLETE" ? "text-bg-warning" : "text-bg-secondary") + '">' +
                    (issueCount ? issueCount + " temuan" : statusLabel(status, point)) + '</span><i class="bi bi-chevron-right text-muted"></i></div>' +
                    renderPointOptionControls(point) +
                    '<div class="text-end mt-1"><button type="button" class="btn btn-outline-secondary btn-sm py-0 px-2" data-open-point-checklist="' +
                    esc(point.InspectionPointID) + '"><i class="bi bi-list-check me-1"></i>Checklist</button></div>' + '</div>';
            }).join("") : '<div class="text-muted small text-center py-4">Tidak ada Inspection Point yang cocok.</div>');

        if (window.bootstrap && bootstrap.Tooltip) {
            host.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function (element) {
                bootstrap.Tooltip.getOrCreateInstance(element, {
                    trigger: "click focus",
                    container: "body",
                    placement: "top",
                    boundary: "viewport"
                });
                element.addEventListener("click", function (event) {
                    event.preventDefault();
                    event.stopPropagation();
                });
            });
        }
        host.querySelectorAll(".inspection-point-list-row[data-point-id]").forEach(function (row) {
            row.classList.toggle("active", !!selectedPoint &&
                row.getAttribute("data-point-id") === String(selectedPoint.InspectionPointID));
            row.addEventListener("click", function () {
                openPoint(row.getAttribute("data-point-id"));
            });
            row.addEventListener("keydown", function (event) {
                if (event.key === "Enter" || event.key === " ") {
                    event.preventDefault();
                    openPoint(row.getAttribute("data-point-id"));
                }
            });
        });
        host.querySelectorAll(".inspection-point-option-choice").forEach(function (button) {
            button.addEventListener("click", async function (event) {
                event.preventDefault();
                event.stopPropagation();
                if (typeof window.setBatchInspectionPointOption !== "function") {
                    if (typeof showToast === "function") showToast("Penyimpanan pilihan checklist belum tersedia.", "warning");
                    return;
                }
                button.disabled = true;
                try {
                    await window.setBatchInspectionPointOption(
                        button.getAttribute("data-point-id"),
                        button.getAttribute("data-point-option-item"),
                        button.getAttribute("data-point-option-value")
                    );
                    renderList();
                    renderPoints();
                    updateSummary();
                } catch (error) {
                    console.error("Unable to save batch point option:", error);
                    if (typeof showToast === "function") showToast(error.message || "Pilihan point gagal disimpan.", "warning");
                } finally {
                    button.disabled = false;
                }
            });
        });
        host.querySelectorAll("[data-point-remark-item]").forEach(function (input) {
            input.addEventListener("change", async function () {
                if (typeof window.setBatchInspectionPointRemark !== "function") return;
                input.disabled = true;
                try {
                    await window.setBatchInspectionPointRemark(
                        input.getAttribute("data-point-id"),
                        input.getAttribute("data-point-remark-item"),
                        input.getAttribute("data-point-remark-field"),
                        input.value
                    );
                    renderList();
                    renderPoints();
                    updateSummary();
                } catch (error) {
                    console.error("Unable to save batch point remark:", error);
                    if (typeof showToast === "function") showToast(error.message || "Remark point gagal disimpan.", "warning");
                    input.disabled = false;
                }
            });
        });
        host.querySelectorAll("[data-open-point-checklist]").forEach(function (button) {
            button.addEventListener("click", function (event) {
                event.preventDefault();
                event.stopPropagation();
                var point = currentPoints.find(function (item) {
                    return String(item.InspectionPointID) === button.getAttribute("data-open-point-checklist");
                });
                if (point && typeof window.openBatchInspectionPointChecklist === "function")
                    window.openBatchInspectionPointChecklist(point);
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

        var nextPending = document.getElementById("btnInspectionNextPending");
        if (nextPending) nextPending.addEventListener("click", function () {
            var point = findNextPendingPoint();
            if (!point) {
                if (typeof showToast === "function")
                    showToast("Tidak ada titik wajib atau checklist yang masih perlu diselesaikan.", "success");
                return;
            }
            openPoint(point.InspectionPointID);
        });
    }

    function updateSummary() {
        var points = getVisiblePoints();
        var template = currentMapRecord && currentMapRecord.TemplateSnapshot;
        var templateItems = [];
        (template && Array.isArray(template.sections) ? template.sections : []).forEach(function (section) {
            (section.items || []).forEach(function (item) { templateItems.push(item); });
        });
        var binaryItem = templateItems.length === 1 ? templateItems[0] : null;
        var binaryOptions = binaryItem && String(binaryItem.type || "").toUpperCase() === "OPTION"
            ? String(binaryItem.optionList || "").split(";").map(function (value) { return value.trim().toUpperCase(); }).filter(Boolean)
            : [];
        var isOnOffTemplate = binaryOptions.indexOf("ON") >= 0 && binaryOptions.indexOf("OFF") >= 0;
        var done = points.filter(function (p) { return getPointStatus(p) === "DONE"; }).length;
        var hasNormalAbnormal = points.some(isNormalAbnormalRequired);
        var abnormal = hasNormalAbnormal
            ? points.filter(function (p) { return getPointVisualStatus(p) === "ABNORMAL"; }).length
            : 0;
        var incomplete = points.filter(function (p) { return getPointStatus(p) === "INCOMPLETE"; }).length;
        var pending = points.filter(function (p) { return getPointStatus(p) === "PENDING"; }).length;
        var set = function (id, value) {
            var element = document.getElementById(id);
            if (element) element.textContent = String(value);
        };
        var labels = {
            done: document.querySelector("#inspectionMapDoneCount"),
            abnormal: document.querySelector("#inspectionMapAbnormalCount"),
            pending: document.querySelector("#inspectionMapPendingCount"),
            incomplete: document.querySelector("#inspectionMapIncompleteCount")
        };
        var labelFor = function (element, value) {
            var label = element && element.parentElement ? element.parentElement.querySelector(".inspection-map-stat-label") : null;
            if (label) label.textContent = value;
        };
        set("inspectionMapTotalCount", points.length);
        var abnormalStat = document.getElementById("inspectionMapAbnormalCount");
        var abnormalLegend = document.getElementById("inspectionMapAbnormalLegendItem");
        if (abnormalStat && abnormalStat.parentElement)
            abnormalStat.parentElement.classList.toggle("d-none", !hasNormalAbnormal);
        if (abnormalLegend) abnormalLegend.classList.toggle("d-none", !hasNormalAbnormal);
        if (isOnOffTemplate && hasNormalAbnormal) {
            // ON/OFF is only presented as a two-state result when the master point
            // explicitly allows Normal/Abnormal classification.
            var onCount = 0, offCount = 0, pendingCount = 0;
            points.forEach(function (masterPoint) {
                var transaction = getPointTransaction(masterPoint);
                var answer = transaction && (transaction.Items || []).find(function (item) {
                    return Number(item.IDItem) === Number(binaryItem.idItem);
                });
                var value = String(answer && answer.Value || "").trim().toUpperCase();
                if (value === "ON") onCount++;
                else if (value === "OFF") offCount++;
                else pendingCount++;
            });
            set("inspectionMapDoneCount", onCount);
            set("inspectionMapAbnormalCount", offCount);
            set("inspectionMapPendingCount", pendingCount);
            set("inspectionMapIncompleteCount", 0);
            labelFor(labels.done, "ON");
            labelFor(labels.abnormal, "OFF");
            labelFor(labels.pending, "Belum dipilih");
            labelFor(labels.incomplete, "—");
        } else {
            set("inspectionMapDoneCount", done);
            set("inspectionMapAbnormalCount", abnormal);
            set("inspectionMapPendingCount", pending);
            set("inspectionMapIncompleteCount", incomplete);
            labelFor(labels.done, "Selesai");
            labelFor(labels.abnormal, "Abnormal");
            labelFor(labels.pending, "Belum dicek");
            labelFor(labels.incomplete, "Belum lengkap");
        }
        var pendingLegend = document.getElementById("inspectionMapPendingLegend");
        if (pendingLegend) pendingLegend.textContent = "Belum diperiksa";
    }

    function openPoint(id) {
        selectedPoint = currentPoints.find(function (point) {
            return String(point.InspectionPointID) === String(id);
        }) || null;
        if (!selectedPoint) return;

        document.querySelectorAll(".inspection-map-point, .inspection-map-svg-path").forEach(function (element) {
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
                (statusValue === "ABNORMAL" ? "text-danger" :
                statusValue === "DONE" ? "text-success" :
                statusValue === "INCOMPLETE" ? "text-warning" : "text-secondary");
            status.textContent = statusLabel(statusValue, selectedPoint);
        }
        var pointTransaction = getPointTransaction(selectedPoint);
        var abnormalRemark = String(pointTransaction && pointTransaction.AbnormalRemark || "").trim();
        if (desc) desc.textContent = abnormalRemark
            ? "ABNORMAL: " + abnormalRemark
            : (selectedPoint.PointDescription || selectedPoint.ObjectReferenceCode || "");
        var sheet = document.getElementById("inspectionMapPointSheet");
        if (sheet) sheet.classList.add("d-none");

        // On phones, a map tap is the primary navigation: open the point checklist
        // immediately instead of exposing/focusing the desktop Point List below the map.
        // Desktop keeps the existing list-selection workflow.
        if (window.matchMedia && window.matchMedia("(max-width: 767.98px)").matches &&
            typeof window.openBatchInspectionPointChecklist === "function") {
            window.openBatchInspectionPointChecklist(selectedPoint).catch(function (error) {
                console.error("Unable to open inspection point checklist from map:", error);
                if (typeof showToast === "function")
                    showToast(error && error.message ? error.message : "Checklist point gagal dibuka.", "warning");
            });
            return;
        }

        // Desktop: select and scroll to the matching Point List row.
        listKeyword = "";
        var pointIndex = currentPoints.findIndex(function (point) {
            return String(point.InspectionPointID) === String(id);
        });
        if (pointIndex >= 0) listPage = Math.floor(pointIndex / listPageSize) + 1;
        switchMapList();
        renderList();
        var listHost = document.getElementById("inspectionPointList");
        var row = listHost && listHost.querySelector('.inspection-point-list-row[data-point-id="' + String(id) + '"]');
        if (listHost && row) {
            var hostRect = listHost.getBoundingClientRect();
            var rowRect = row.getBoundingClientRect();
            var targetTop = listHost.scrollTop + rowRect.top - hostRect.top -
                Math.max(0, (listHost.clientHeight - rowRect.height) / 2);
            listHost.scrollTo({ top: Math.max(0, targetTop), behavior: "smooth" });
        }
    }

    function closePoint() {
        selectedPoint = null;
        var sheet = document.getElementById("inspectionMapPointSheet");
        if (sheet) sheet.classList.add("d-none");
        document.querySelectorAll(".inspection-map-point.selected").forEach(function (element) {
            element.classList.remove("selected");
        });
    }

    function switchMapList() {
        var canvas = document.getElementById("inspectionMapCanvas");
        var list = document.getElementById("inspectionPointList");
        if (!canvas || !list) return;
        var hasMap = currentMaps.some(function (map) {
            return Number(map.MapID) === Number(currentMapId) && !!map.MapUrl;
        });
        canvas.classList.toggle("d-none", !hasMap);
        list.classList.remove("d-none");
        var content = document.querySelector(".inspection-map-content");
        if (content) content.classList.toggle("no-map", !hasMap);
    }

    function getMapElements() {
        return {
            viewport: document.getElementById("inspectionMapCanvas"),
            stage: document.getElementById("inspectionMapPdfStage"),
            points: document.getElementById("inspectionMapPoints"),
            zoomLabel: document.getElementById("inspectionMapZoomLabel")
        };
    }

    function applyMapTransform() {
        var elements = getMapElements();
        if (!elements.stage) return;
        elements.stage.style.transformOrigin = "center top";
        elements.stage.style.transform = "translate3d(" + mapPanX + "px," + mapPanY + "px,0) scale(" + mapZoom + ")";
        if (elements.points) elements.points.style.setProperty("--inspection-map-marker-scale", String(1 / mapZoom));
        if (elements.zoomLabel) elements.zoomLabel.textContent = Math.round(mapZoom * 100) + "%";
        var viewport = elements.viewport;
        if (viewport) viewport.classList.toggle("inspection-map-zoomed", mapZoom > 1.001);
    }

    function resetMapView() {
        mapZoom = 1;
        mapPanX = 0;
        mapPanY = 0;
        mapPointers = {};
        mapGesture = null;
        applyMapTransform();
    }

    function zoomMapTo(nextZoom, clientX, clientY) {
        var elements = getMapElements();
        if (!elements.viewport || !elements.stage) return;
        var rect = elements.viewport.getBoundingClientRect();
        var x = clientX == null ? rect.left + rect.width / 2 : clientX;
        var y = clientY == null ? rect.top + rect.height / 2 : clientY;
        var localX = x - rect.left - rect.width / 2;
        var localY = y - rect.top;
        var next = Math.max(mapMinZoom, Math.min(mapMaxZoom, nextZoom));
        if (Math.abs(next - mapZoom) < 0.001) return;
        var ratio = next / mapZoom;
        mapPanX = (mapPanX - localX) * ratio + localX;
        mapPanY = (mapPanY - localY) * ratio + localY;
        mapZoom = next;
        applyMapTransform();
        schedulePdfCanvasRender();
    }

    function wireMapGestures() {
        var elements = getMapElements();
        var viewport = elements.viewport;
        if (!viewport || viewport.getAttribute("data-map-gestures") === "1") return;
        viewport.setAttribute("data-map-gestures", "1");

        viewport.addEventListener("wheel", function (event) {
            if (!currentPdfDocument && !document.querySelector('#inspectionMapPdfStage img.inspection-map-image')) return;
            event.preventDefault();
            var factor = event.deltaY < 0 ? 1.15 : 1 / 1.15;
            zoomMapTo(mapZoom * factor, event.clientX, event.clientY);
        }, { passive: false });

        viewport.addEventListener("pointerdown", function (event) {
            if ((!currentPdfDocument && !document.querySelector("#inspectionMapPdfStage img.inspection-map-image")) || (event.target.closest && (event.target.closest(".inspection-map-point") || event.target.closest(".inspection-map-zoom-tools")))) return;
            if (event.pointerType === "mouse" && event.button !== 0) return;
            try { viewport.setPointerCapture(event.pointerId); } catch (_) { }
            mapPointers[event.pointerId] = { x: event.clientX, y: event.clientY };
            var ids = Object.keys(mapPointers);
            if (ids.length >= 2) {
                var p1 = mapPointers[ids[0]], p2 = mapPointers[ids[1]];
                var dx = p2.x - p1.x, dy = p2.y - p1.y;
                mapGesture = { type: "pinch", distance: Math.sqrt(dx * dx + dy * dy), zoom: mapZoom };
            } else {
                mapGesture = { type: "pan", x: event.clientX, y: event.clientY, panX: mapPanX, panY: mapPanY };
            }
        });

        viewport.addEventListener("pointermove", function (event) {
            if (!Object.prototype.hasOwnProperty.call(mapPointers, event.pointerId)) return;
            mapPointers[event.pointerId] = { x: event.clientX, y: event.clientY };
            var ids = Object.keys(mapPointers);
            if (ids.length >= 2) {
                var p1 = mapPointers[ids[0]], p2 = mapPointers[ids[1]];
                var dx = p2.x - p1.x, dy = p2.y - p1.y;
                var distance = Math.sqrt(dx * dx + dy * dy);
                if (mapGesture && mapGesture.type === "pinch" && mapGesture.distance > 0) {
                    var midpointX = (p1.x + p2.x) / 2;
                    var midpointY = (p1.y + p2.y) / 2;
                    zoomMapTo(mapGesture.zoom * (distance / mapGesture.distance), midpointX, midpointY);
                } else {
                    mapGesture = { type: "pinch", distance: distance, zoom: mapZoom };
                }
            } else if (mapGesture && mapGesture.type === "pan") {
                mapPanX = mapGesture.panX + event.clientX - mapGesture.x;
                mapPanY = mapGesture.panY + event.clientY - mapGesture.y;
                applyMapTransform();
            }
        });

        function finishPointer(event) {
            delete mapPointers[event.pointerId];
            var ids = Object.keys(mapPointers);
            if (ids.length === 1) {
                var p = mapPointers[ids[0]];
                mapGesture = { type: "pan", x: p.x, y: p.y, panX: mapPanX, panY: mapPanY };
            } else if (!ids.length) {
                mapGesture = null;
            }
        }
        viewport.addEventListener("pointerup", finishPointer);
        viewport.addEventListener("pointercancel", finishPointer);
        viewport.addEventListener("lostpointercapture", finishPointer);
    }

    function schedulePdfCanvasRender() {
        if (!currentPdfPage) return;
        if (pdfCanvasRenderTimer) clearTimeout(pdfCanvasRenderTimer);
        pdfCanvasRenderTimer = setTimeout(function () {
            pdfCanvasRenderTimer = null;
            renderPdfCanvasAtZoom();
        }, 140);
    }

    async function renderPdfCanvasAtZoom() {
        if (!currentPdfPage) return;
        var canvas = document.getElementById('inspectionMapPdfCanvas');
        if (!canvas) return;
        var sequence = ++pdfCanvasRenderSequence;
        var previousTask = pdfCanvasRenderTask;
        if (previousTask && previousTask.cancel) {
            try { previousTask.cancel(); } catch (_) { }
            try { await previousTask.promise; } catch (_) { }
        }
        if (sequence !== pdfCanvasRenderSequence) return;
        pdfCanvasRenderTask = null;
        var ratio = Math.min(window.devicePixelRatio || 1, 2);
        var renderScale = currentPdfFitScale * mapZoom * ratio;
        var viewport = currentPdfPage.getViewport({ scale: renderScale });
        var displayViewport = currentPdfPage.getViewport({ scale: currentPdfFitScale });
        canvas.width = Math.max(1, Math.floor(viewport.width));
        canvas.height = Math.max(1, Math.floor(viewport.height));
        canvas.style.width = Math.floor(displayViewport.width) + 'px';
        canvas.style.height = Math.floor(displayViewport.height) + 'px';
        var stage = document.getElementById('inspectionMapPdfStage');
        if (stage) {
            stage.style.width = canvas.style.width;
            stage.style.minHeight = '0';
        }
        var context = canvas.getContext('2d');
        try {
            var task = currentPdfPage.render({ canvasContext: context, viewport: viewport });
            pdfCanvasRenderTask = task;
            await task.promise;
            if (sequence !== pdfCanvasRenderSequence) return;
            pdfCanvasRenderTask = null;
        } catch (error) {
            if (sequence !== pdfCanvasRenderSequence) return;
            pdfCanvasRenderTask = null;
            if (!(error && (error.name === 'RenderingCancelledException' || /cancel/i.test(error.message || '')))) {
                console.error('Inspection map PDF zoom render failed:', error);
            }
        }
    }

    async function renderPdf(map) {
        var requestId = ++pdfRenderSequence;
        var message = document.getElementById('inspectionMapPdfMessage');
        var canvas = document.getElementById('inspectionMapPdfCanvas');
        var stage = document.getElementById('inspectionMapPdfStage');
        if (!canvas || !stage) return;
        resetMapView();
        currentPdfPage = null;
        currentPdfFitScale = 1;
        if (pdfCanvasRenderTimer) { clearTimeout(pdfCanvasRenderTimer); pdfCanvasRenderTimer = null; }
        pdfCanvasRenderSequence++;
        if (pdfCanvasRenderTask && pdfCanvasRenderTask.cancel) { try { pdfCanvasRenderTask.cancel(); } catch (_) { } pdfCanvasRenderTask = null; }
        if (currentPdfDocument && currentPdfDocument.destroy) { try { await currentPdfDocument.destroy(); } catch (_) { } currentPdfDocument = null; }
        if (requestId !== pdfRenderSequence) return;
        var previousImage = stage.querySelector('img.inspection-map-image');
        if (previousImage) { if (previousImage.dataset.objectUrl) URL.revokeObjectURL(previousImage.dataset.objectUrl); previousImage.remove(); }
        canvas.style.display = 'block';
        var pointsHost = document.getElementById("inspectionMapPoints");
        if (pointsHost) pointsHost.innerHTML = "";
        var context = canvas.getContext('2d'); context.clearRect(0, 0, canvas.width, canvas.height); canvas.width = 0; canvas.height = 0;
        if (!map || !map.MapUrl) {
            if (message) { message.textContent = 'Denah belum tersedia. Pilih Inspection Point dari daftar.'; message.classList.remove('d-none'); }
            stage.style.width = '100%';
            stage.style.minHeight = '260px';
            return;
        }
        try {
            if (message) { message.textContent = 'Memuat denah...'; message.classList.remove('d-none'); }
            var blob = map.MapBlob || map.PdfBlob || null;
            if (!blob || typeof blob.arrayBuffer !== 'function') {
                var response = await fetch(map.MapUrl, { credentials: 'same-origin' });
                if (requestId !== pdfRenderSequence) return;
                if (!response.ok) throw new Error('HTTP ' + response.status);
                blob = await response.blob();
                if (requestId !== pdfRenderSequence) return;
                map.MapBlob = blob;
            }
            var mime = String(blob.type || '').toLowerCase();
            var urlPath = String(map.MapUrl).split('?')[0].toLowerCase();
            var isJpeg = mime.indexOf('image/jpeg') === 0 || /\.(jpg|jpeg)$/.test(urlPath);
            if (isJpeg) {
                canvas.style.display = 'none';
                var image = document.createElement('img'); image.className = 'inspection-map-image'; image.alt = 'Inspection floor plan'; image.draggable = false;
                stage.insertBefore(image, document.getElementById('inspectionMapPoints'));
                var objectUrl = URL.createObjectURL(blob); image.dataset.objectUrl = objectUrl;
                image.onload = function () {
                    if (requestId !== pdfRenderSequence) return;
                    var mapViewport = document.getElementById('inspectionMapCanvas');
                    var availableWidth = Math.max(300, Math.min(2400, mapViewport.clientWidth - 16));
                    var availableHeight = Math.max(260, mapViewport.clientHeight - 16);
                    image.style.width = 'auto'; image.style.height = 'auto';
                    image.style.maxWidth = availableWidth + 'px'; image.style.maxHeight = availableHeight + 'px';
                    image.style.objectFit = 'contain'; image.style.display = 'block';
                    stage.style.width = image.clientWidth + 'px';
                    stage.style.width = available + 'px'; stage.style.minHeight = '0';
                    if (message) message.classList.add('d-none'); applyMapTransform(); renderPoints();
                };
                image.onerror = function () {
                    if (requestId !== pdfRenderSequence) return;
                    if (message) { message.textContent = 'Gambar JPG/JPEG tidak dapat dibuka.'; message.classList.remove('d-none'); }
                };
                image.src = objectUrl; return;
            }
            canvas.style.display = 'block';
            if (!window.pdfjsLib) throw new Error('PDF.js belum termuat. Periksa file pdf.min.js.');
            window.pdfjsLib.GlobalWorkerOptions.workerSrc = '../JSCus/pdf.worker.min.js';
            var pdfData = new Uint8Array(await blob.arrayBuffer());
            if (requestId !== pdfRenderSequence) return;
            var loadedDocument = await window.pdfjsLib.getDocument({ data: pdfData }).promise;
            if (requestId !== pdfRenderSequence) {
                if (loadedDocument && loadedDocument.destroy) loadedDocument.destroy();
                return;
            }
            currentPdfDocument = loadedDocument;
            var page = await currentPdfDocument.getPage(1);
            if (requestId !== pdfRenderSequence) return;
            currentPdfPage = page;
            var base = page.getViewport({ scale: 1 });
            var mapViewport = document.getElementById('inspectionMapCanvas');
            var width = Math.max(300, Math.min(2400, mapViewport.clientWidth - 16));
            var height = Math.max(260, mapViewport.clientHeight - 16);
            var fitScale = Math.min(width / base.width, height / base.height);
            // Keep the canvas at its fitted CSS size, but render enough backing pixels
            // for the current zoom level. Zoom changes trigger a fresh PDF.js render.
            currentPdfFitScale = fitScale;
            await renderPdfCanvasAtZoom();
            if (requestId !== pdfRenderSequence) return;
            if (message) message.classList.add('d-none'); applyMapTransform(); renderPoints();
        } catch (error) {
            if (requestId !== pdfRenderSequence) return;
            console.error('Inspection map render failed:', error);
            if (message) { message.textContent = 'Denah gagal dimuat: ' + (error && error.message ? error.message : 'periksa file map.'); message.classList.remove('d-none'); }
        }
    }
    function hasMapGroups() {
        return currentMaps.some(function (map) {
            var groupId = map.MapGroupID;
            if (groupId === null || groupId === undefined) return false;
            var value = String(groupId).trim();
            return value !== "" && value !== "0" && value.toLowerCase() !== "null" && value.toLowerCase() !== "undefined";
        });
    }

    function renderMapCards() {
        var host = document.getElementById("inspectionMapCards");
        var picker = document.getElementById("inspectionMapPicker");
        if (!host) return;
        if (!hasMapGroups()) {
            host.innerHTML = "";
            if (picker) picker.classList.add("d-none");
            return;
        }
        if (picker) picker.classList.remove("d-none");
        if (!currentMaps.length) {
            host.innerHTML = '<div class="alert alert-light border small mb-0">Belum ada Inspection Map untuk Inspection Detail Code ini.</div>';
            return;
        }
        host.innerHTML = currentMaps.map(function (map) {
            return '<button type="button" class="inspection-map-choice-card" data-inspection-map-id="' + esc(map.MapID) + '">' +
                '<span class="inspection-map-choice-title">' + esc(map.MapName || "Inspection Map") + '</span>' +
                '</button>';
        }).join("");
        host.querySelectorAll("[data-inspection-map-id]").forEach(function (button) {
            button.addEventListener("click", function () {
                showSelectedInspectionMap(this.getAttribute("data-inspection-map-id"));
            });
        });
        updateSelectedMapCard();
    }

    function updateSelectedMapCard() {
        var host = document.getElementById("inspectionMapCards");
        if (!host) return;
        host.querySelectorAll("[data-inspection-map-id]").forEach(function (button) {
            var selected = String(button.getAttribute("data-inspection-map-id")) === String(currentMapId);
            button.classList.toggle("active", selected);
            button.setAttribute("aria-pressed", selected ? "true" : "false");
        });
    }

    function showMapPicker() {
        var picker = document.getElementById("inspectionMapPicker");
        var summary = document.getElementById("inspectionMapSummary");
        var content = document.getElementById("inspectionMapContent");
        var summaryHost = document.getElementById("inspectionMapSummaryHost");
        var submitBar = document.getElementById("inspectionMapSubmitBar");
        var nextButton = document.getElementById("btnInspectionNextPending");
        if (picker) picker.classList.toggle("d-none", !hasMapGroups());
        if (summary) summary.classList.add("d-none");
        if (content) content.classList.add("d-none");
        if (summaryHost) summaryHost.classList.add("d-none");
        if (submitBar) submitBar.classList.add("d-none");
        if (nextButton) nextButton.classList.add("d-none");
        currentMapId = "";
        renderMapCards();
        closePoint();
        resetMapView();
        if (currentMaps.length) showSelectedInspectionMap(currentMaps[0].MapID);
    }

    function showSelectedInspectionMap(mapId) {
        var map = currentMaps.find(function (item) { return Number(item.MapID) === Number(mapId); });
        if (!map) return;
        currentMapId = String(map.MapID);
        var summary = document.getElementById("inspectionMapSummary");
        var content = document.getElementById("inspectionMapContent");
        var summaryHost = document.getElementById("inspectionMapSummaryHost");
        var submitBar = document.getElementById("inspectionMapSubmitBar");
        var nextButton = document.getElementById("btnInspectionNextPending");
        if (summary) summary.classList.remove("d-none");
        if (content) content.classList.remove("d-none");
        if (summaryHost) summaryHost.classList.remove("d-none");
        if (submitBar) submitBar.classList.remove("d-none");
        if (nextButton) nextButton.classList.toggle("d-none", String(currentMapRecord && currentMapRecord.Status || "").toUpperCase() === "DONE");
        var title = document.getElementById("inspectionMapTitle");
        var subtitle = document.getElementById("inspectionMapSubtitle");
        if (title) title.textContent = map.MapName || "Inspection Map";
        if (subtitle) subtitle.textContent = (map.MapCode || "") + " · " + currentPoints.filter(function (point) {
                return Number(point.MapID) === Number(map.MapID);
            }).length + " inspection points";
        updateSelectedMapCard();
        closePoint();
        switchMapList();
        resetMapView();
        listPage = 1;
        renderList();
        updateSummary();
        renderPoints();
        window.requestAnimationFrame(function () { renderPdf(map); });
    }

    function setInspectionSectionNavForTab(tabName) {
        var navHost = document.getElementById("inspectionSectionNavHost");
        if (!navHost) return;
        // Section navigation is useful only while filling checklist sections.
        navHost.classList.toggle("d-none", tabName !== "checklist");
    }

    window.resetInspectionMapWorkspace = async function () {
        currentMapRecord = null;
        currentMaps = [];
        currentPoints = [];
        currentMapId = "";
        selectedPoint = null;
        listPage = 1;
        listKeyword = "";
        resetMapView();
        closePoint();
        var list = document.getElementById("inspectionPointList");
        if (list) { list.scrollTop = 0; list.innerHTML = ""; }
        var points = document.getElementById("inspectionMapPoints");
        if (points) points.innerHTML = "";
        var summary = document.getElementById("inspectionMapSummaryHost");
        var checklistPane = document.getElementById("inspectionChecklistPane");
        if (checklistPane) {
            ["inspectionFollowUpPanel", "inspectionSummaryPanel", "inspectionReasonVoidPanel"].forEach(function (id) {
                var panel = document.getElementById(id);
                if (panel) checklistPane.appendChild(panel);
            });
        }
        if (summary) summary.innerHTML = "";
        var title = document.getElementById("inspectionMapTitle");
        var subtitle = document.getElementById("inspectionMapSubtitle");
        if (title) title.textContent = "Inspection Map";
        if (subtitle) subtitle.textContent = "Warna titik menunjukkan status inspeksi";
        await renderPdf(null);
        var workspace = document.getElementById("inspectionMapWorkspace");
        if (workspace) workspace.classList.add("d-none");
    };

    window.showInspectionMapWorkspace = function (record, activate) {
        var isDifferentRecord = !!record && (!currentMapRecord ||
            String(currentMapRecord.LocalInspectionID || "") !== String(record.LocalInspectionID || ""));
        if (isDifferentRecord) {
            currentMapId = "";
            selectedPoint = null;
            listPage = 1;
            listKeyword = "";
            resetMapView();
            closePoint();
        }
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
        if (!currentMaps.some(function (map) { return Number(map.MapID) === Number(currentMapId); }))
            currentMapId = "";

        var nextPendingButton = document.getElementById("btnInspectionNextPending");
        if (nextPendingButton) nextPendingButton.classList.toggle("d-none", String(record.Status || "").toUpperCase() === "DONE");

        var submitBatchButton = document.getElementById("btnSubmitInspectionBatch");
        if (submitBatchButton) submitBatchButton.classList.toggle("d-none", String(record.Status || "").toUpperCase() === "DONE");

        var typeName = record.InspectionTypeName || "Inspection";
        var detailName = record.InspectionTypeDetailName || "";
        var title = document.getElementById("inspectionMapTitle");
        var subtitle = document.getElementById("inspectionMapSubtitle");
        if (title) title.textContent = typeName + (detailName ? " · " + detailName : "");
        if (subtitle) subtitle.textContent = "Batch " + (record.InspectionNo || "baru") +
            " · " + currentPoints.length + " Unit Inspeksi";

        var selectedMap = currentMaps.find(function (map) {
            return Number(map.MapID) === Number(currentMapId);
        }) || null;

        if (activate) {
            // Make the map viewport measurable before PDF.js calculates its canvas size.
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
            setInspectionSectionNavForTab("map");
            closePoint();
            switchMapList();
            showMapPicker();
            if (typeof window.updateInspectionParameterTabGate === "function")
                window.updateInspectionParameterTabGate();
        } else if (!workspace.classList.contains("d-none") && selectedMap) {
            renderPdf(selectedMap);
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

        wireMapGestures();
        var zoomIn = document.getElementById("btnInspectionMapZoomIn");
        var zoomOut = document.getElementById("btnInspectionMapZoomOut");
        var zoomReset = document.getElementById("btnInspectionMapZoomReset");
        if (zoomIn) zoomIn.addEventListener("click", function () { zoomMapTo(mapZoom * 1.25); });
        if (zoomOut) zoomOut.addEventListener("click", function () { zoomMapTo(mapZoom / 1.25); });
        if (zoomReset) zoomReset.addEventListener("click", resetMapView);

        var mapTab = document.getElementById("btnInspectionMapTab");
        if (mapTab) mapTab.addEventListener("click", function () {
            if (currentMapRecord && Number(currentMapRecord.ActiveInspectionPointID || 0) > 0) {
                // Returning to MAP is navigation, not Save Point. Discard the
                // unsaved editor values and leave previously saved point data intact.
                currentMapRecord.ActiveInspectionPointID = 0;
                currentMapRecord.Items = [];
            }
            setInspectionSectionNavForTab("map");
            if (window.showInspectionMapWorkspace) window.showInspectionMapWorkspace(currentMapRecord, true);
        });

        var checklistTab = document.getElementById("btnInspectionChecklistTab");
        if (checklistTab) checklistTab.addEventListener("click", function () {
            if (currentMapRecord && String(currentMapRecord.InspectionMode || "").toUpperCase() === "BATCH" &&
                !Number(currentMapRecord.ActiveInspectionPointID || 0)) {
                if (typeof showToast === "function")
                    showToast("Pilih Inspection Point dari denah atau daftar terlebih dahulu.", "info");
                return;
            }
            setInspectionSectionNavForTab("checklist");
            var workspace = document.getElementById("inspectionMapWorkspace");
            if (workspace) workspace.classList.add("d-none");
        });

        var paramTab = document.getElementById("btnInspectionParamTab");
        if (paramTab) paramTab.addEventListener("click", function () {
            setInspectionSectionNavForTab("param");
            var workspace = document.getElementById("inspectionMapWorkspace");
            if (workspace) workspace.classList.add("d-none");
        });

        var close = document.getElementById("btnCloseInspectionMapPoint");
        if (close) close.addEventListener("click", closePoint);
        var mapView = document.getElementById("btnInspectionMapView");
        var listView = document.getElementById("btnInspectionPointListView");
        if (mapView) mapView.addEventListener("click", function () { switchMapList(); });
        if (listView) listView.addEventListener("click", function () { switchMapList(); closePoint(); });

        var reset = document.getElementById("btnInspectionMapReset");
        if (reset) reset.addEventListener("click", function () {
            switchMapList();
            closePoint();
            resetMapView();
        });


        var openChecklist = document.getElementById("btnOpenInspectionPointChecklist");
        if (openChecklist) openChecklist.addEventListener("click", function () {
            if (!selectedPoint) return;
            var point = selectedPoint;
            closePoint();
            if (typeof window.openBatchInspectionPointChecklist === "function") {
                window.openBatchInspectionPointChecklist(point);
            } else {
                if (typeof showToast === "function")
                    showToast("Modul checklist per titik belum siap dibuka.", "warning");
            }
        });

        var submit = document.getElementById("btnSubmitInspectionBatch");
        if (submit) submit.addEventListener("click", function () {
            if (typeof window.submitInspectionBatch === "function") window.submitInspectionBatch();
            else if (typeof showToast === "function")
                showToast("Submit batch belum tersedia.", "warning");
        });
    };

    document.addEventListener("DOMContentLoaded", function () {
        window.setTimeout(function () {
            if (typeof window.wireInspectionMapWorkspace === "function")
                window.wireInspectionMapWorkspace();
        }, 0);
    });
})();
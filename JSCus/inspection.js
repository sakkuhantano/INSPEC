let inspectionLogin = null;
let inspectionTechnicianName = "";
let inspectionCompanyID = "";
let inspectionLocationID = "";
let inspectionTypes = [];
let inspectionDetails = [];
let inspectionTenants = [];
let inspectionTenantSuites = [];
let inspectionTenantSuiteMasterRows = [];
let inspectionTemplates = [];
let inspectionRecords = [];
let serverSubmittedInspectionRecords = [];
let serverSlotRecords = [];
let currentInspectionRecord = null;
let currentInspectionReadOnly = false;
let inspectionGpsWatchId = null;
let inspectionLatestGps = null;
let inspectionAutoSaveTimer = null;
let inspectionPhotoViewerState = { type: "", photos: [], index: 0, objectUrl: null, touchStartX: null };
let serverInspectionPhotoPreview = [];
let inspectionPhotoBaseline = null;
let inspectionPhotoWritePromise = null;
let inspectionGridSort = { key: "inspectionDate", direction: "asc" };
let inspectionBatchValidationState = { errors: [], index: -1 };
let activeInspectionScheduleTime = "";
let returnedInspectionDeepLinkHandled = false;
let approvalInspectionDeepLinkHandled = false;
let inspectionDetailSearchOptions = [];
let inspectionDetailSelectDisabled = true;
let inspectionDetailLastSelectedValue = "";

function syncInspectionDetailSearchOptions() {
    const select = document.getElementById("selInspectionDetail");
    const search = document.getElementById("txtInspectionDetailSearch");
    if (!select || !search) return;
    inspectionDetailSelectDisabled = select.disabled;
    inspectionDetailLastSelectedValue = select.value || "";
    inspectionDetailSearchOptions = Array.from(select.options).map(option => ({
        value: option.value,
        text: option.textContent,
        disabled: option.disabled
    }));
    applyInspectionDetailSearch();
}

function applyInspectionDetailSearch() {
    const select = document.getElementById("selInspectionDetail");
    const search = document.getElementById("txtInspectionDetailSearch");
    const optionHost = document.getElementById("inspectionDetailDropdownOptions");
    const dropdownButton = document.getElementById("selInspectionDetailDropdownButton");
    if (!select || !search) return;

    const keyword = String(search.value || "").trim().toLowerCase();
    const options = inspectionDetailSearchOptions;
    const matches = options.filter(option =>
        !option.value || !keyword ||
        (String(option.value) + " " + String(option.text)).toLowerCase().includes(keyword)
    );

    if (dropdownButton) {
        const selected = options.find(option => String(option.value || "") === String(select.value || ""));
        dropdownButton.textContent = selected && selected.value
            ? selected.text
            : "Pilih detail...";
        dropdownButton.disabled = inspectionDetailSelectDisabled;
    }

    if (!optionHost) return;
    optionHost.innerHTML = matches.length
        ? matches.map(option => {
            const selected = String(option.value || "") === String(select.value || "");
            return '<button type="button" class="dropdown-item rounded small' +
                (selected ? ' active' : '') +
                (option.disabled ? ' disabled' : '') +
                '" data-inspection-detail-value="' + escInspection(option.value) + '"' +
                (option.disabled ? ' disabled aria-disabled="true"' : '') + '>' +
                escInspection(option.text || option.value) +
                '</button>';
        }).join("")
        : '<div class="dropdown-item-text small text-muted py-2">Detail tidak ditemukan.</div>';
}

function isInspectionMapMode(mode) {
    return ["BATCH", "LIGHTNING"].indexOf(String(mode || "").trim().toUpperCase()) >= 0;
}

function isInspectionTenantDetail(detail) {
    const value = detail && detail.IsTenantInspection;
    return value === true || value === 1 || value === "1" || String(value || "").toLowerCase() === "true";
}

function getSelectedInspectionTenantID() {
    const select = document.getElementById("selInspectionTenant");
    return select ? String(select.value || "").trim() : "";
}

function getSelectedInspectionSuiteNo() {
    const select = document.getElementById("selInspectionSuite");
    return select ? String(select.value || "").trim() : "";
}

function applyInspectionTenantSearch() {
    const search = document.getElementById("txtInspectionTenantSearch");
    const tenantSelect = document.getElementById("selInspectionTenant");
    const optionHost = document.getElementById("inspectionTenantDropdownOptions");
    const dropdownButton = document.getElementById("selInspectionTenantDropdownButton");
    if (!tenantSelect) return;

    const keyword = String(search && search.value || "").trim().toLocaleLowerCase();
    const options = Array.from(tenantSelect.options);

    // Keep the hidden native select as the source of truth. The visible Bootstrap
    // dropdown is only the searchable presentation layer, so all existing
    // tenant-lock/availability logic can continue using selInspectionTenant.
    if (dropdownButton) {
        const selected = tenantSelect.options[tenantSelect.selectedIndex];
        dropdownButton.textContent = selected && selected.value
            ? selected.textContent
            : "Pilih tenant...";
        dropdownButton.disabled = tenantSelect.disabled;
    }

    if (!optionHost) return;
    const matches = options.filter(option =>
        !option.value ||
        !keyword ||
        String(option.textContent || option.value).toLocaleLowerCase().indexOf(keyword) >= 0
    );

    optionHost.innerHTML = matches.length
        ? matches.map(option => {
            const selected = String(option.value || "") === String(tenantSelect.value || "");
            return '<button type="button" class="dropdown-item rounded small' +
                (selected ? ' active' : '') +
                (option.disabled ? ' disabled' : '') +
                '" data-inspection-tenant-value="' + escInspection(option.value) + '"' +
                (option.disabled ? ' disabled aria-disabled="true"' : '') + '>' +
                escInspection(option.textContent || option.value) +
                '</button>';
        }).join("")
        : '<div class="dropdown-item-text small text-muted py-2">Tenant tidak ditemukan.</div>';
}


function formatInspectionTenantLabel(tenantId, tenantName) {
    const id = String(tenantId || "").trim();
    const name = String(tenantName || "").trim();
    if (id && name) return id + " - " + name;
    return id || name || "-";
}

async function resolveInspectionTenantName(tenantId, fallbackName) {
    const id = String(tenantId || "").trim();
    const fallback = String(fallbackName || "").trim();
    if (!id) return fallback;
    if (fallback) return fallback;

    const loaded = inspectionTenants.find(row =>
        String(row.TenantID || "").trim() === id &&
        String(row.CompanyID || "") === String(inspectionCompanyID || "") &&
        String(row.LocationID || "") === String(inspectionLocationID || ""));
    if (loaded && String(loaded.TenantName || "").trim())
        return String(loaded.TenantName).trim();

    if (typeof db !== "undefined" && db &&
        db.objectStoreNames.contains("inspection_tenants")) {
        try {
            const cachedRows = await readInspectionStore("inspection_tenants");
            const cached = cachedRows.find(row =>
                String(row.TenantID || "").trim() === id &&
                String(row.CompanyID || "") === String(inspectionCompanyID || "") &&
                String(row.LocationID || "") === String(inspectionLocationID || ""));
            if (cached && String(cached.TenantName || "").trim())
                return String(cached.TenantName).trim();
        } catch (error) {
            console.warn("Unable to resolve cached Inspection tenant name:", error);
        }
    }
    return "";
}

function formatInspectionTenantSuiteInfo(tenantId, tenantName, suiteNo) {
    const id = String(tenantId || "").trim();
    const suite = String(suiteNo || "").trim();
    if (!id && !suite) return "";
    return "Tenant: " + formatInspectionTenantLabel(id, tenantName) +
        " / Suite: " + (suite || "-");
}

function inspectionTenantMatchesRecord(record, detail) {
    if (!isInspectionTenantDetail(detail)) return true;
    const tenantId = getSelectedInspectionTenantID();
    const suiteNo = getSelectedInspectionSuiteNo();
    return !!tenantId && !!suiteNo &&
        String(record && record.TenantID || "").trim() === tenantId &&
        String(record && record.SuiteNo || "").trim() === suiteNo;
}

window.getActiveInspectionScheduleTime = function () {
    return activeInspectionScheduleTime || String(currentInspectionRecord && currentInspectionRecord.ActiveScheduleTime || "");
};
window.setInspectionActiveScheduleTime = function (value) {
    activeInspectionScheduleTime = String(value || "");
    if (currentInspectionRecord && String(currentInspectionRecord.InspectionMode || "").toUpperCase() === "LIGHTNING")
        currentInspectionRecord.ActiveScheduleTime = activeInspectionScheduleTime;
};

function stopInspectionGpsWatch() {
    if (inspectionGpsWatchId !== null && navigator.geolocation) {
        try { navigator.geolocation.clearWatch(inspectionGpsWatchId); } catch (_) {}
    }
    inspectionGpsWatchId = null;
}

function startInspectionGpsWatch() {
    stopInspectionGpsWatch();
    inspectionLatestGps = null;
    if (!navigator.geolocation) return;
    try {
        inspectionGpsWatchId = navigator.geolocation.watchPosition(function (position) {
            if (!position || !position.coords) return;
            inspectionLatestGps = {
                GPSLatitude: Number(position.coords.latitude),
                GPSLongitude: Number(position.coords.longitude),
                GPSAccuracy: Number(position.coords.accuracy),
                GPSCapturedAt: new Date(position.timestamp || Date.now()).toISOString()
            };
            if (currentInspectionRecord && !currentInspectionReadOnly) {
                currentInspectionRecord.GPSLatitude = inspectionLatestGps.GPSLatitude;
                currentInspectionRecord.GPSLongitude = inspectionLatestGps.GPSLongitude;
                currentInspectionRecord.GPSAccuracy = inspectionLatestGps.GPSAccuracy;
                currentInspectionRecord.GPSCapturedAt = inspectionLatestGps.GPSCapturedAt;
            }
        }, function (error) {
            // GPS is audit metadata only. Permission denial/unavailability must never block inspection.
            console.warn("Inspection GPS unavailable:", error && error.message ? error.message : error);
        }, {
            enableHighAccuracy: true,
            maximumAge: 30000,
            timeout: 5000
        });
    } catch (error) {
        console.warn("Inspection GPS watch could not be started:", error);
    }
}

function applyLatestInspectionGps(record) {
    if (!record || currentInspectionReadOnly) return;
    if (inspectionLatestGps) {
        record.GPSLatitude = inspectionLatestGps.GPSLatitude;
        record.GPSLongitude = inspectionLatestGps.GPSLongitude;
        record.GPSAccuracy = inspectionLatestGps.GPSAccuracy;
        record.GPSCapturedAt = inspectionLatestGps.GPSCapturedAt;
    }
}

async function ensureInspectionGpsBeforeSubmit(record) {
    if (!record || currentInspectionReadOnly || !navigator.geolocation) return false;

    if (inspectionLatestGps) {
        applyLatestInspectionGps(record);
        return true;
    }

    // The user can complete the whole checklist and press Submit before
    // watchPosition() has delivered its first fix. Request one synchronously
    // from the Submit flow so GPS is not lost just because the user was fast.
    try {
        const position = await new Promise((resolve, reject) => {
            navigator.geolocation.getCurrentPosition(resolve, reject, {
                enableHighAccuracy: true,
                maximumAge: 0,
                timeout: 8000
            });
        });

        if (!position || !position.coords) return false;

        inspectionLatestGps = {
            GPSLatitude: Number(position.coords.latitude),
            GPSLongitude: Number(position.coords.longitude),
            GPSAccuracy: Number(position.coords.accuracy),
            GPSCapturedAt: new Date(position.timestamp || Date.now()).toISOString()
        };
        applyLatestInspectionGps(record);
        return true;
    } catch (error) {
        // GPS is audit metadata only. Submit must remain possible when the
        // browser/device cannot provide a fix.
        console.warn("Inspection GPS unavailable at submit:", error && error.message ? error.message : error);
        return false;
    }
}
function getInspectionTemplateDetailCodes(template) {
    return String(template && template.InspectionTypeDetailCode || "")
        .split(";")
        .map(code => code.trim().toUpperCase())
        .filter(Boolean);
}

function isInspectionTemplateDetailAllowed(template, detailCode) {
    const allowedCodes = getInspectionTemplateDetailCodes(template);
    return !allowedCodes.length ||
        allowedCodes.indexOf(String(detailCode || "").trim().toUpperCase()) >= 0;
}

let inspectionFollowUpSections = [
    { Code: "ACON", Name: "Air Cond." },
    { Code: "COMM", Name: "Comm." },
    { Code: "MECH", Name: "Mechanical" },
    { Code: "ELEC", Name: "Electrical" },
    { Code: "CIVIL", Name: "Civil" },
    { Code: "PFIT", Name: "Fit Out" },
    { Code: "PHKP", Name: "Housekeeping" },
    { Code: "PSEC", Name: "Security" }
];

document.addEventListener("DOMContentLoaded", async function () {
    wireInspectionScrollTools();
    wireInspectionEditorStickyHeader();
    try {
        inspectionLogin = getLoginData();
        inspectionTechnicianName = inspectionLogin && (inspectionLogin.name || inspectionLogin.Name || inspectionLogin.employeename || inspectionLogin.employeeName) || "";
        if (!inspectionLogin || !inspectionLogin.employeeid) {
            window.location.href = "../Login.aspx";
            return;
        }
        const companyLocation = (inspectionLogin.curcompany || "").split(";");
        inspectionCompanyID = companyLocation[0] || "";
        inspectionLocationID = companyLocation[1] || "";

        const approvalMode = new URLSearchParams(window.location.search).get("type") === "approval";
        if (approvalMode) {
            if (!hasAuthorizedMenu(20022)) {
                showToast("Akun ini tidak memiliki akses approval Inspection.", "warning");
                return;
            }
            // Approval uses the exact same cached, versioned checklist template as technician entry.
            if (typeof db === "undefined" || !db) await initIndexedDB();
            if (db.objectStoreNames.contains("inspection_templates")) await loadInspectionCache(true);
            ["inspectionStartPanel", "inspectionFormPanel"].forEach(id => document.getElementById(id).classList.add("d-none"));
            document.querySelectorAll(".inspection-card").forEach(el => {
                if (el.id !== "inspectionApprovalPanel") el.classList.add("d-none");
            });
            document.getElementById("inspectionApprovalPanel").classList.remove("d-none");
            wireInspectionApprovalEvents();
            await loadInspectionApprovalQueue();
            return;
        }

        if (!hasAuthorizedMenu(20021)) {
            showToast("Akun ini tidak memiliki akses input inspeksi teknisi.", "warning");
            return;
        }

        if (typeof db === "undefined" || !db) {
            await initIndexedDB();
        }
        if (!db.objectStoreNames.contains("inspection_records")) {
            throw new Error("IndexedDB belum memiliki store inspeksi. Refresh halaman setelah aplikasi diperbarui.");
        }

        const submittedToday = localDateString(new Date());
        document.getElementById("txtSubmittedFrom").value = formatInspectionDateDMY(submittedToday);
        document.getElementById("txtSubmittedThru").value = formatInspectionDateDMY(submittedToday);
        wireInspectionDatePicker("txtSubmittedFrom", "pickerSubmittedFrom");
        wireInspectionDatePicker("txtSubmittedThru", "pickerSubmittedThru");
        document.getElementById("txtInspectionDate").value = formatInspectionDateDMY(submittedToday);
        document.getElementById("txtInspectionDate").disabled = true;
        document.getElementById("txtInspectionDate").setAttribute("aria-readonly", "true");
        wireInspectionEvents();
        await loadInspectionCache();

        // Populate the cross-device server slot cache as soon as the Inspection page opens.
        // Offline users continue with the local cache; online users see slots used by other technicians.
        if (navigator.onLine && typeof downloadTodayInspectionSlots === "function") {
            try {
                await downloadTodayInspectionSlots();
            } catch (scheduleError) {
                console.warn("Initial Inspection slot refresh failed:", scheduleError);
            }
        }

        // Sync may add/remove server transactions; refresh the shared slot cache before repainting the list.
        window.addEventListener("syncCompleted", async function () {
            try {
                if (navigator.onLine && typeof downloadTodayInspectionSlots === "function") {
                    await downloadTodayInspectionSlots();
                }
                await refreshSavedInspectionList();
            } catch (err) {
                console.error("Unable to refresh inspections after sync:", err);
            }
        });
        await refreshSavedInspectionList();

        document.getElementById("inspectionConnectionLabel").textContent =
            navigator.onLine ? "Online • offline data ready" : "Offline • data tersimpan di perangkat";
        if (!inspectionTypes.length || !inspectionTemplates.length) {
            showToast("Belum ada master/template Inspection offline. Hubungkan internet lalu tekan Sync terlebih dahulu.", "warning");
        }
    } catch (err) {
        console.error("Inspection page initialization failed:", err);
        showToast(err.message || "Gagal membuka input inspeksi.", "danger");
    }
});

function wireInspectionPhotoViewerEvents() {
    const close = document.getElementById("inspectionPhotoViewerClose");
    const prev = document.getElementById("inspectionPhotoViewerPrev");
    const next = document.getElementById("inspectionPhotoViewerNext");
    const viewer = document.getElementById("inspectionPhotoViewer");
    const stage = document.getElementById("inspectionPhotoViewerStage");
    if (close && !close.dataset.viewerWired) {
        close.dataset.viewerWired = "1";
        close.addEventListener("click", closeInspectionPhotoViewer);
    }
    if (prev && !prev.dataset.viewerWired) {
        prev.dataset.viewerWired = "1";
        prev.addEventListener("click", () => stepInspectionPhotoViewer(-1));
    }
    if (next && !next.dataset.viewerWired) {
        next.dataset.viewerWired = "1";
        next.addEventListener("click", () => stepInspectionPhotoViewer(1));
    }
    if (viewer && !viewer.dataset.viewerWired) {
        viewer.dataset.viewerWired = "1";
        viewer.addEventListener("click", event => {
            if (event.target.id === "inspectionPhotoViewer") closeInspectionPhotoViewer();
        });
    }
    if (stage && !stage.dataset.viewerWired) {
        stage.dataset.viewerWired = "1";
        stage.addEventListener("touchstart", event => {
            inspectionPhotoViewerState.touchStartX = event.changedTouches && event.changedTouches.length
                ? event.changedTouches[0].clientX : null;
        }, { passive: true });
        stage.addEventListener("touchend", event => {
            const startX = inspectionPhotoViewerState.touchStartX;
            const endX = event.changedTouches && event.changedTouches.length ? event.changedTouches[0].clientX : null;
            inspectionPhotoViewerState.touchStartX = null;
            if (startX == null || endX == null || Math.abs(endX - startX) < 45) return;
            stepInspectionPhotoViewer(endX < startX ? 1 : -1);
        }, { passive: true });
    }
    if (!document.documentElement.dataset.inspectionViewerKeysWired) {
        document.documentElement.dataset.inspectionViewerKeysWired = "1";
        document.addEventListener("keydown", handleInspectionPhotoViewerKeydown);
    }
}

function wireInspectionEvents() {
    wireInspectionPhotoViewerEvents();
    wireInspectionReasonCancelDialog();
    document.getElementById("btnBackToInspectionRecords").addEventListener("click", function () {
        closeInspectionForm().catch(err => {
            console.error("Unable to return to inspection list:", err);
            showToast(err.message || "Gagal kembali ke daftar inspeksi.", "warning");
        });
    });
    document.getElementById("selInspectionType").addEventListener("change", function () {
        onInspectionTypeChanged();
        updateInspectionParameterTabGate();
    });
    document.getElementById("selInspectionDetail").addEventListener("change", function () {
        inspectionDetailLastSelectedValue = this.value || "";
        const detailSearch = document.getElementById("txtInspectionDetailSearch");
        if (detailSearch && detailSearch.value) {
            detailSearch.value = "";
            applyInspectionDetailSearch();
            this.value = inspectionDetailLastSelectedValue;
        }
        onInspectionDetailChanged();
        updateInspectionParameterTabGate();
    });
    document.getElementById("selInspectionTenant").addEventListener("change", async function () {
        const tenantSearch = document.getElementById("txtInspectionTenantSearch");
        if (tenantSearch) {
            tenantSearch.value = "";
            applyInspectionTenantSearch();
        }
        try {
            await loadInspectionTenantSuites(this.value || "");
        } catch (error) {
            showToast(error.message || "Gagal memuat Suite No tenant.", "warning");
        }
        refreshInspectionScheduleOptions();
        refreshInspectionTenantAvailability();
        refreshInspectionSuiteAvailability();
        refreshInspectionDetailAvailability();
        updateStartButton();
        updateInspectionParameterTabGate();
    });
    document.getElementById("selInspectionSuite").addEventListener("change", function () {
        refreshInspectionTenantAvailability();
        refreshInspectionSuiteAvailability();
        refreshInspectionDetailAvailability();
        refreshInspectionScheduleOptions();
        updateStartButton();
        updateInspectionParameterTabGate();
    });
    const detailSearchInput = document.getElementById("txtInspectionDetailSearch");
    if (detailSearchInput) detailSearchInput.addEventListener("input", applyInspectionDetailSearch);

    const tenantSearchInput = document.getElementById("txtInspectionTenantSearch");
    if (tenantSearchInput) tenantSearchInput.addEventListener("input", applyInspectionTenantSearch);

    const detailDropdown = document.getElementById("inspectionDetailDropdown");
    if (detailDropdown) {
        detailDropdown.addEventListener("click", function (event) {
            const option = event.target.closest("[data-inspection-detail-value]");
            if (!option || option.disabled) return;
            const select = document.getElementById("selInspectionDetail");
            if (!select) return;
            inspectionDetailLastSelectedValue = option.getAttribute("data-inspection-detail-value") || "";
            select.value = inspectionDetailLastSelectedValue;
            select.dispatchEvent(new Event("change", { bubbles: true }));
            applyInspectionDetailSearch();
            const dropdownButton = document.getElementById("selInspectionDetailDropdownButton");
            if (dropdownButton && window.bootstrap && bootstrap.Dropdown) {
                bootstrap.Dropdown.getOrCreateInstance(dropdownButton).hide();
            }
        });
        detailDropdown.addEventListener("shown.bs.dropdown", function () {
            const search = document.getElementById("txtInspectionDetailSearch");
            if (search && !search.disabled) {
                search.focus();
                search.select();
            }
        });
    }

    const tenantDropdown = document.getElementById("inspectionTenantDropdown");
    if (tenantDropdown) {
        tenantDropdown.addEventListener("click", function (event) {
            const option = event.target.closest("[data-inspection-tenant-value]");
            if (!option || option.disabled) return;
            const tenantSelect = document.getElementById("selInspectionTenant");
            if (!tenantSelect) return;
            tenantSelect.value = option.getAttribute("data-inspection-tenant-value") || "";
            tenantSelect.dispatchEvent(new Event("change", { bubbles: true }));
            const dropdownButton = document.getElementById("selInspectionTenantDropdownButton");
            if (dropdownButton && window.bootstrap && bootstrap.Dropdown) {
                bootstrap.Dropdown.getOrCreateInstance(dropdownButton).hide();
            }
        });
        tenantDropdown.addEventListener("shown.bs.dropdown", function () {
            const search = document.getElementById("txtInspectionTenantSearch");
            if (search && !search.disabled) {
                search.focus();
                search.select();
            }
        });
    }

    document.getElementById("selInspectionScheduleTime").addEventListener("change", function () {
        refreshInspectionScheduleOptions();
        refreshInspectionTenantAvailability();
        refreshInspectionSuiteAvailability();
        updateStartButton();
        updateInspectionParameterTabGate();
    });
    document.getElementById("selInspectionTemplate").addEventListener("change", function () {
        const typeCode = document.getElementById("selInspectionType").value;
        const selectedTemplate = inspectionTemplates.find(x => Number(x.IDTemplate) === Number(this.value));
        const pinnedDetailCodes = String(selectedTemplate && selectedTemplate.InspectionTypeDetailCode || "")
            .split(";").map(x => x.trim().toUpperCase()).filter(Boolean)
            .filter((code, index, all) => all.indexOf(code) === index);
        const normalizeDetailCode = value => String(value || "").trim().toUpperCase();
        const pinnedDetailSet = new Set(pinnedDetailCodes);
        const details = inspectionDetails.filter(x =>
            x.InspectionTypeCode === typeCode &&
            x.CompanyID === inspectionCompanyID &&
            x.LocationID === inspectionLocationID &&
            (!pinnedDetailSet.size || pinnedDetailSet.has(normalizeDetailCode(x.InspectionTypeDetailCode)))
        );
        const detailSelect = document.getElementById("selInspectionDetail");
        const previousDetail = detailSelect.value;
        detailSelect.innerHTML = '<option value="">Pilih detail...</option>' +
            details.map(detail =>
                '<option value="' + escInspection(detail.InspectionTypeDetailCode) + '">' +
                escInspection(detail.InspectionTypeDetailName) + '</option>'
            ).join("");
        pinnedDetailCodes.forEach(function(code) {
            if (!details.some(detail => normalizeDetailCode(detail.InspectionTypeDetailCode) === code))
                detailSelect.add(new Option(code + " (tidak tersedia di lokasi ini)", code));
        });
        if (pinnedDetailSet.size) {
            if (pinnedDetailCodes.length === 1) {
                detailSelect.value = pinnedDetailCodes[0];
            } else if (previousDetail && pinnedDetailSet.has(normalizeDetailCode(previousDetail))) {
                detailSelect.value = previousDetail;
            } else {
                detailSelect.value = "";
            }
            detailSelect.disabled = pinnedDetailCodes.length === 1;
        } else {
            detailSelect.disabled = !this.value || details.length === 0;
            if (previousDetail && details.some(detail => normalizeDetailCode(detail.InspectionTypeDetailCode) === normalizeDetailCode(previousDetail)))
                detailSelect.value = previousDetail;
        }
        const selectedDetail = details.find(detail => normalizeDetailCode(detail.InspectionTypeDetailCode) === normalizeDetailCode(detailSelect.value));
        onInspectionDetailChanged();
        refreshInspectionDetailAvailability();
        syncInspectionDetailSearchOptions();
        updateStartButton();
        refreshInspectionScheduleOptions();
        refreshInspectionTenantAvailability();
        refreshInspectionSuiteAvailability();
        updateInspectionParameterTabGate();
    });
    document.getElementById("txtInspectionDate").addEventListener("change", function () {
        refreshInspectionDetailAvailability();
        refreshInspectionScheduleOptions();
        refreshInspectionTenantAvailability();
        refreshInspectionSuiteAvailability();
        updateStartButton();
    });
    document.getElementById("btnStartInspection").addEventListener("click", startNewInspection);
    document.getElementById("btnNewInspection").addEventListener("click", resetInspectionSelection);
    document.getElementById("selSubmittedType").addEventListener("change", function () {
        document.getElementById("selSubmittedDetail").value = "";
        document.getElementById("selSubmittedScheduleTime").value = "";
        refreshSavedInspectionList().catch(err => showToast(err.message || "Gagal memfilter inspeksi.", "warning"));
    });
    document.getElementById("selSubmittedDetail").addEventListener("change", function () {
        document.getElementById("selSubmittedScheduleTime").value = "";
        refreshSavedInspectionList().catch(err => showToast(err.message || "Gagal memfilter inspeksi.", "warning"));
    });
    document.getElementById("selSubmittedScheduleTime").addEventListener("change", () =>
        refreshSavedInspectionList().catch(err => showToast(err.message || "Gagal memfilter inspeksi.", "warning")));
    document.getElementById("btnFilterSubmitted").addEventListener("click", function () {
        refreshSavedInspectionList().catch(err => {
            console.error("Unable to filter submitted inspections:", err);
            showToast(err.message || "Gagal memfilter inspeksi submitted.", "warning");
        });
    });
    const submittedFilters = document.getElementById("inspectionSubmittedFilters");
    const updateSubmittedFiltersVisibility = () => {
        const submittedActive = document.getElementById("inspectionSubmittedTab").classList.contains("active");
        if (submittedFilters) submittedFilters.classList.toggle("d-none", !submittedActive);
    };
    document.getElementById("inspectionDraftTab").addEventListener("shown.bs.tab", updateSubmittedFiltersVisibility);
    document.getElementById("inspectionSubmittedTab").addEventListener("shown.bs.tab", updateSubmittedFiltersVisibility);
    updateSubmittedFiltersVisibility();
    document.getElementById("btnInspectionParamTab").addEventListener("click", () => showInspectionEditorTab("param"));
    if (typeof wireInspectionMapWorkspace === "function") wireInspectionMapWorkspace();
    document.getElementById("btnInspectionChecklistTab").addEventListener("click", async () => {
        const isBatch = currentInspectionRecord &&
            isInspectionMapMode(currentInspectionRecord.InspectionMode);
        if (isBatch && !Number(currentInspectionRecord.ActiveInspectionPointID || 0)) {
            updateInspectionParameterTabGate();
            if (typeof showInspectionMapWorkspace === "function")
                showInspectionMapWorkspace(currentInspectionRecord, true);
            showToast("Pilih Inspection Point dari denah atau daftar terlebih dahulu untuk membuka Checklist.", "info");
            return;
        }
        // Server-only submitted records intentionally use synthetic parameter options because
        // their original masters may no longer exist in IndexedDB. They are read-only, so
        // don't revalidate those synthetic values against the local master caches.
        if (!currentInspectionReadOnly && !isInspectionParameterSelectionComplete()) {
            updateInspectionParameterTabGate();
            showInspectionEditorTab("param");
            showToast("Lengkapi Inspection Type, detail/jadwal, dan template terlebih dahulu sebelum membuka Checklist.", "warning");
            return;
        }
        if (currentInspectionRecord && !currentInspectionReadOnly && !await applyInspectionParameters()) return;
        showInspectionEditorTab("checklist");
    });
    document.getElementById("btnSaveInspectionDraft").addEventListener("click", () => saveInspection("DRAFT"));
    document.getElementById("btnDeleteInspectionDraft").addEventListener("click", async () => {
        if (currentInspectionRecord) await deleteLocalInspectionDraft(currentInspectionRecord.LocalInspectionID);
    });
    document.getElementById("btnDeleteInspectionBatchDraft").addEventListener("click", async () => {
        if (!currentInspectionRecord ||
            !isInspectionMapMode(currentInspectionRecord.InspectionMode)) return;
        await deleteLocalInspectionDraft(currentInspectionRecord.LocalInspectionID);
    });
    document.getElementById("btnCompleteInspection").addEventListener("click", () => saveInspection("DONE"));
    document.getElementById("inspectionPhotoBeforeInput").addEventListener("change", e => handleInspectionPhotoInput(e, "BEFORE"));
    document.getElementById("inspectionPhotoAfterInput").addEventListener("change", e => handleInspectionPhotoInput(e, "AFTER"));
    document.getElementById("inspectionPhotoBeforeList").addEventListener("click", handleInspectionPhotoListClick);
    document.getElementById("inspectionPhotoAfterList").addEventListener("click", handleInspectionPhotoListClick);
    ["inspectionDraftList", "inspectionSubmittedList"].forEach(function (listId) {
        document.getElementById(listId).addEventListener("click", async function (event) {
            const deleteButton = event.target.closest("[data-delete-conflict]");
            if (deleteButton) {
                await queueConflictInspectionDelete(deleteButton.dataset.deleteConflict);
                return;
            }
            const editReasonButton = event.target.closest("[data-edit-delete-reason]");
            if (editReasonButton) {
                const pendingRecord = inspectionRecords.find(item =>
                    item.LocalInspectionID === editReasonButton.dataset.editDeleteReason &&
                    item.SyncStatus === "DELETE_PENDING" &&
                    item.DeleteOriginalSyncStatus === "VOIDED");
                if (!pendingRecord) return;
                let existingReasonCancel = String(pendingRecord.DeleteReasonCancel || "").trim();
                const reasonVoid = String(pendingRecord.ReasonVoid || "").trim();

                // Older client versions could incorrectly copy the SPV's ReasonVoid into
                // DeleteReasonCancel. A queued delete has not been applied on the server yet,
                // so do not treat that SPV remark as a technician-entered cancel reason.
                if (existingReasonCancel && reasonVoid &&
                    existingReasonCancel === reasonVoid) {
                    existingReasonCancel = "";
                    pendingRecord.DeleteReasonCancel = "";
                    await persistInspectionRecord(pendingRecord);
                }

                const reason = await showInspectionReasonCancelDialog(
                    "Perbarui Reason Cancel",
                    existingReasonCancel
                );
                if (reason === null) return;
                pendingRecord.DeleteReasonCancel = reason;
                pendingRecord.UpdatedAt = new Date().toISOString();
                delete pendingRecord.DeleteArchiveError;
                await persistInspectionRecord(pendingRecord);
                await refreshSavedInspectionList();
                showToast("Reason Cancel diperbarui. Jalankan Sync untuk menerapkannya ke server.", "success");
                return;
            }
            const button = event.target.closest("[data-open-inspection]");
            if (button) {
                await openSavedInspection(button.dataset.openInspection);
                return;
            }
            const returnedButton = event.target.closest("[data-open-returned-inspection]");
            if (returnedButton) {
                await openServerReturnedInspection(Number(returnedButton.dataset.openReturnedInspection));
                return;
            }
            const serverButton = event.target.closest("[data-open-server-inspection]");
            if (serverButton) await openServerSubmittedInspection(serverButton.dataset.openServerInspection);
        });
    });
    window.addEventListener("inspectionConflict", function (event) {
        refreshSavedInspectionList().catch(console.error);
        const count = event.detail && event.detail.count ? event.detail.count : 1;
        const badge = document.getElementById("inspectionConflictBadge");
        if (badge) {
            badge.textContent = "!";
            badge.classList.remove("d-none");
        }
        showToast(count + " inspeksi mengalami konflik saat sync. Buka daftar inspeksi untuk melihat alasan dan pilih Delete Local Transaction bila record lokal memang harus dibuang.", "warning");
    });
    document.getElementById("inspectionChecklistHost").addEventListener("input", function (event) { if (event.target) event.target.classList.remove("is-invalid", "border-danger", "text-danger"); const item = event.target && event.target.closest(".inspection-item"); if (item) item.classList.remove("inspection-validation-error", "border", "border-danger", "rounded", "p-2"); scheduleInspectionAutosave(); updateInspectionChecklistGate(); });
    document.getElementById("inspectionFollowUpPanel").addEventListener("change", function (event) {
        if (event.target.matches('input[name="inspectionFollowUp"]')) updateInspectionFollowUpPanel();
    });
    const summaryInput = document.getElementById("txtInspectionSummary");
    if (summaryInput) summaryInput.addEventListener("input", function () {
        this.classList.remove("is-invalid");
        const counter = document.getElementById("inspectionSummaryCounter");
        if (counter) counter.textContent = this.value.length + " / 500";
    });
    document.getElementById("txtInspectionFollowUpRemark").addEventListener("input", function () {
        this.classList.remove("is-invalid");
        document.getElementById("inspectionFollowUpRemarkCounter").textContent = this.value.length + " / 300";
    });
    // OPTION radios are toggle buttons in every inspection mode
    // (STANDARD, BATCH and LIGHTNING): selected = blue, tap again = clear.
    document.getElementById("inspectionChecklistHost").addEventListener("click", function (event) {
        const label = event.target && event.target.closest(".inspection-option-choice");
        if (!label || currentInspectionReadOnly) return;
        const input = document.getElementById(label.getAttribute("for"));
        if (!input || input.disabled || !input.matches('input[type="radio"][data-role="value"]') ||
            !input.closest('.inspection-item[data-item-type="OPTION"]')) return;
        event.preventDefault();
        event.stopPropagation();
        const wasChecked = input.checked;
        const groupName = input.name;
        document.getElementById("inspectionChecklistHost")
            .querySelectorAll('input[type="radio"][data-role="value"]')
            .forEach(option => { if (option.name === groupName) option.checked = false; });
        input.checked = !wasChecked;
        input.dispatchEvent(new Event("change", { bubbles: true }));
    }, true);
    document.getElementById("inspectionChecklistHost").addEventListener("change", function (event) {
        if (event.target) event.target.classList.remove("is-invalid", "border-danger", "text-danger");
        const changedItem = event.target && event.target.closest(".inspection-item");
        if (changedItem) changedItem.classList.remove("inspection-validation-error", "border", "border-danger", "rounded", "p-2");
        if (event.target && event.target.matches('[data-role="value"][type="radio"]')) updateInspectionRemarkPanels();
        scheduleInspectionAutosave();
        updateInspectionChecklistGate();
    });
    if (summaryInput) summaryInput.addEventListener("input", scheduleInspectionAutosave);
    document.querySelectorAll('input[name="inspectionFollowUp"]').forEach(input => input.addEventListener("change", function () {
        updateInspectionFollowUpPanel();
        scheduleInspectionAutosave();
    }));
    document.getElementById("inspectionFollowUpSection").addEventListener("change", function () {
        this.classList.remove("is-invalid");
        scheduleInspectionAutosave();
    });
    document.getElementById("txtInspectionFollowUpRemark").addEventListener("input", scheduleInspectionAutosave);
}

async function loadInspectionCache(includeAllTemplates, skipMapSetupRefresh) {
    inspectionTypes = await readInspectionStore(
        db.objectStoreNames.contains("inspection_types_scoped") ? "inspection_types_scoped" : "inspection_types"
    );
    inspectionDetails = await readInspectionStore("inspection_type_details");
    inspectionTemplates = await readInspectionStore("inspection_templates");

    // Reconcile cached BATCH template remark flags at read time as well as during Sync.
    // This protects a newly started transaction from a legacy IndexedDB row whose
    // nested item flags were saved as false even though the version-level switch is on.
    const batchTypeCodes = new Set(inspectionTypes
        .filter(type => isInspectionMapMode(type.InspectionMode))
        .map(type => String(type.InspectionTypeCode || "").trim().toUpperCase()));
    const cachedFlag = value => value !== undefined && value !== null && value !== "" &&
        !(value === false || value === 0 || value === "0" || String(value).toLowerCase() === "false");
    inspectionTemplates = inspectionTemplates.map(template => {
        if (!batchTypeCodes.has(String(template.InspectionTypeCode || "").trim().toUpperCase()))
            return template;
        const versionRemark1 = cachedFlag(template.IsRemark1Required !== undefined
            ? template.IsRemark1Required : template.isRemark1Required);
        const versionRemark2 = cachedFlag(template.IsRemark2Required !== undefined
            ? template.IsRemark2Required : template.isRemark2Required);
        const remark1Text = template.Remark1Text || template.remark1Text || "";
        const remark2Text = template.Remark2Text || template.remark2Text || "";
        return Object.assign({}, template, {
            sections: (template.sections || template.Sections || []).map(section => Object.assign({}, section, {
                items: (section.items || section.Items || []).map(item => {
                    const useDefault1 = cachedFlag(item.isUseDefaultRemark1 !== undefined
                        ? item.isUseDefaultRemark1 : item.IsUseDefaultRemark1);
                    const useDefault2 = cachedFlag(item.isUseDefaultRemark2 !== undefined
                        ? item.isUseDefaultRemark2 : item.IsUseDefaultRemark2);
                    const itemRemark1 = cachedFlag(item.isRemark1Required !== undefined
                        ? item.isRemark1Required : item.IsRemark1Required);
                    const itemRemark2 = cachedFlag(item.isRemark2Required !== undefined
                        ? item.isRemark2Required : item.IsRemark2Required);
                    return Object.assign({}, item, {
                        versionIsRemark1Required: versionRemark1,
                        versionIsRemark2Required: versionRemark2,
                        isRemark1Required: versionRemark1 && (useDefault1 || itemRemark1),
                        isRemark2Required: versionRemark2 && (useDefault2 || itemRemark2),
                        remark1Text: useDefault1 ? remark1Text : (item.remark1Text || item.Remark1Text || "Remark"),
                        remark2Text: useDefault2 ? remark2Text : (item.remark2Text || item.Remark2Text || "Remark")
                    });
                })
            }))
        });
    });

    const sections = (inspectionLogin.section || "").split(";").filter(Boolean);
    inspectionTypes = inspectionTypes.filter(x =>
        sections.includes(String(x.SectionID || "")) &&
        (!x.CompanyID || x.CompanyID === inspectionCompanyID) &&
        (!x.LocationID || x.LocationID === inspectionLocationID)
    );
    inspectionDetails = inspectionDetails.filter(x =>
        x.CompanyID === inspectionCompanyID && x.LocationID === inspectionLocationID
    );
    inspectionTemplates = inspectionTemplates.filter(x =>
        (includeAllTemplates || sections.includes(x.SectionID)) &&
        x.TemplateType === "I" &&
        !!x.InspectionTypeCode
    );

    // The server master endpoint filters Inspection Types by configured active templates,
    // but IndexedDB can still contain older type rows from an earlier master download.
    // Apply the same essential relationship locally so stale cached rows cannot leak into
    // the New Inspection dropdown.
    inspectionTypes = inspectionTypes.filter(type =>
        inspectionTemplates.some(template =>
            String(template.InspectionTypeCode || "").trim() === String(type.InspectionTypeCode || "").trim() &&
            String(template.SectionID || "").trim() === String(type.SectionID || "").trim()
        )
    );

    if (navigator.onLine && !skipMapSetupRefresh) {
        await cacheInspectionMapSetupsForOfflineUse();
    }

    const typeSelect = document.getElementById("selInspectionType");
    typeSelect.innerHTML = '<option value="">Pilih Inspection Type...</option>' +
        inspectionTypes.map(type =>
            '<option value="' + escInspection(type.InspectionTypeCode) + '">' +
            escInspection(type.InspectionTypeCode + " - " + type.InspectionTypeName) + '</option>'
        ).join("");
    resetDetailAndTemplateOptions();
}

async function cacheInspectionMapSetupsForOfflineUse() {
    const storeName = db.objectStoreNames.contains("inspection_types_scoped")
        ? "inspection_types_scoped" : "inspection_types";
    let changed = false;
    for (const type of inspectionTypes) {
        if (!isInspectionMapMode(type.InspectionMode)) continue;
        type.BatchMapSetups = type.BatchMapSetups || {};
        const details = inspectionDetails.filter(detail =>
            String(detail.InspectionTypeCode || "") === String(type.InspectionTypeCode || ""));
        for (const detail of details) {
            const key = String(detail.InspectionTypeDetailCode || "").toUpperCase();
            if (!key) continue;
            try {
                const response = await fetch("inspection.aspx/GetBatchInspectionMap", {
                    method: "POST",
                    headers: { "Content-Type": "application/json; charset=utf-8" },
                    body: JSON.stringify({
                        inspectionTypeCode: type.InspectionTypeCode,
                        inspectionTypeDetailCode: detail.InspectionTypeDetailCode,
                        employeeId: inspectionLogin.employeeid,
                        companyId: inspectionCompanyID,
                        locationId: inspectionLocationID
                    })
                });
                const payload = await response.json();
                if (!response.ok) throw new Error((payload && (payload.Message || payload.ExceptionMessage)) || "Map setup request failed.");
                const setup = payload && Object.prototype.hasOwnProperty.call(payload, "d") ? payload.d : payload;
                if (!setup || setup.success !== true || !Array.isArray(setup.points)) continue;
                for (const map of (setup.maps || [])) {
                    if (!map.MapUrl || map.MapBlob || map.PdfBlob) continue;
                    try {
                        const mapResponse = await fetch(map.MapUrl, { cache: "no-store" });
                        if (!mapResponse.ok) continue;
                        map.MapBlob = await mapResponse.blob();
                    } catch (mapError) {
                        console.warn("Inspection map could not be cached for offline use:", map.MapName, mapError);
                    }
                }
                type.BatchMapSetups[key] = setup;
                changed = true;
            } catch (error) {
                console.warn("Inspection map setup cache refresh failed:", type.InspectionTypeCode, key, error);
            }
        }
    }
    if (!changed) return;
    await new Promise((resolve, reject) => {
        const tx = db.transaction(storeName, "readwrite");
        const store = tx.objectStore(storeName);
        inspectionTypes.forEach(type => {
            if (isInspectionMapMode(type.InspectionMode)) store.put(type);
        });
        tx.oncomplete = resolve;
        tx.onerror = () => reject(tx.error || new Error("Gagal menyimpan cache Inspection Map."));
        tx.onabort = () => reject(tx.error || new Error("Penyimpanan cache Inspection Map dibatalkan."));
    });
}

function readInspectionStore(storeName) {
    return new Promise((resolve, reject) => {
        const tx = db.transaction(storeName, "readonly");
        const req = tx.objectStore(storeName).getAll();
        req.onsuccess = () => resolve(req.result || []);
        req.onerror = () => reject(req.error);
    });
}

function cacheInspectionLookupRows(storeName, rows, scopeTenantId) {
    return new Promise((resolve, reject) => {
        if (!db || !db.objectStoreNames.contains(storeName)) {
            reject(new Error("Tenant cache belum tersedia. Refresh halaman setelah aplikasi diperbarui."));
            return;
        }
        const companyId = String(inspectionCompanyID || "");
        const locationId = String(inspectionLocationID || "");
        const incoming = rows || [];
        const incomingKeys = new Set(incoming.map(row => storeName === "inspection_tenants"
            ? [row.CompanyID, row.LocationID, row.TenantID].join("|")
            : [row.CompanyID, row.LocationID, row.TenantID, row.SuiteNo].join("|")));
        const tx = db.transaction(storeName, "readwrite");
        const store = tx.objectStore(storeName);
        const readReq = store.getAll();
        readReq.onsuccess = () => {
            (readReq.result || []).forEach(row => {
                const inScope = String(row.CompanyID || "") === companyId &&
                    String(row.LocationID || "") === locationId &&
                    (storeName !== "inspection_tenant_suites" ||
                        String(row.TenantID || "") === String(scopeTenantId || ""));
                const key = storeName === "inspection_tenants"
                    ? [row.CompanyID, row.LocationID, row.TenantID].join("|")
                    : [row.CompanyID, row.LocationID, row.TenantID, row.SuiteNo].join("|");
                if (inScope && !incomingKeys.has(key)) {
                    if (storeName === "inspection_tenants")
                        store.delete([row.CompanyID, row.LocationID, row.TenantID]);
                    else
                        store.delete([row.CompanyID, row.LocationID, row.TenantID, row.SuiteNo]);
                }
            });
            incoming.forEach(row => store.put(row));
        };
        readReq.onerror = () => { try { tx.abort(); } catch (_) {} reject(readReq.error); };
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error || new Error("Gagal menyimpan cache tenant."));
        tx.onabort = () => reject(tx.error || new Error("Penyimpanan cache tenant dibatalkan."));
    });
}

function cacheInspectionTenantSuiteMasterRows(rows) {
    return new Promise((resolve, reject) => {
        if (!db || !db.objectStoreNames.contains("inspection_tenant_suites")) {
            resolve(false);
            return;
        }
        const companyId = String(inspectionCompanyID || "");
        const locationId = String(inspectionLocationID || "");
        const incoming = rows || [];
        const tx = db.transaction("inspection_tenant_suites", "readwrite");
        const store = tx.objectStore("inspection_tenant_suites");
        const readReq = store.getAll();
        readReq.onsuccess = () => {
            (readReq.result || []).forEach(row => {
                if (String(row.CompanyID || "") === companyId &&
                    String(row.LocationID || "") === locationId) {
                    store.delete([row.CompanyID, row.LocationID, row.TenantID, row.SuiteNo]);
                }
            });
            incoming.forEach(row => store.put(row));
        };
        readReq.onerror = () => { try { tx.abort(); } catch (_) {} reject(readReq.error); };
        tx.oncomplete = () => resolve(true);
        tx.onerror = () => reject(tx.error || new Error("Gagal menyimpan master Suite tenant."));
        tx.onabort = () => reject(tx.error || new Error("Penyimpanan master Suite tenant dibatalkan."));
    });
}

async function loadInspectionTenantSuiteMasterRows() {
    let rows = [];
    try {
        rows = (await readInspectionStore("inspection_tenant_suites")).filter(row =>
            String(row.CompanyID || "") === String(inspectionCompanyID || "") &&
            String(row.LocationID || "") === String(inspectionLocationID || ""));
    } catch (error) {
        console.warn("Unable to read cached tenant Suite master:", error);
    }

    if (navigator.onLine) {
        try {
            const response = await fetch("inspection.aspx/GetInspectionTenantSuites", {
                method: "POST",
                headers: { "Content-Type": "application/json; charset=utf-8" },
                body: JSON.stringify({
                    employeeId: inspectionLogin.employeeid,
                    companyId: inspectionCompanyID,
                    locationId: inspectionLocationID,
                    tenantId: ""
                })
            });
            const payload = await response.json();
            if (!response.ok)
                throw new Error((payload && payload.Message) || "Gagal memuat seluruh Suite tenant.");
            const result = payload && Object.prototype.hasOwnProperty.call(payload, "d") ? payload.d : payload;
            rows = (result && result.data || []).map(row => Object.assign({}, row, {
                CompanyID: inspectionCompanyID,
                LocationID: inspectionLocationID
            }));
            try {
                await cacheInspectionTenantSuiteMasterRows(rows);
            } catch (cacheError) {
                console.warn("Unable to cache tenant Suite master snapshot:", cacheError);
            }
        } catch (error) {
            console.warn("Tenant Suite master refresh failed; using cached snapshot:", error);
        }
    }

    const unique = [];
    const seen = new Set();
    rows.forEach(row => {
        const key = [row.CompanyID, row.LocationID, row.TenantID, row.SuiteNo].join("|");
        if (!seen.has(key)) {
            seen.add(key);
            unique.push(row);
        }
    });
    inspectionTenantSuiteMasterRows = unique;
    return unique;
}

async function loadInspectionTenantOptions() {
    const tenantSelect = document.getElementById("selInspectionTenant");
    const suiteSelect = document.getElementById("selInspectionSuite");
    if (!tenantSelect || !suiteSelect) return;
    const tenantSearch = document.getElementById("txtInspectionTenantSearch");
    tenantSelect.disabled = true;
    if (tenantSearch) {
        tenantSearch.value = "";
        tenantSearch.disabled = true;
    }
    suiteSelect.disabled = true;
    suiteSelect.innerHTML = '<option value="">Pilih tenant terlebih dahulu...</option>';

    let rows = (await readInspectionStore("inspection_tenants")).filter(row =>
        String(row.CompanyID || "") === String(inspectionCompanyID || "") &&
        String(row.LocationID || "") === String(inspectionLocationID || ""));
    if (navigator.onLine) {
        try {
            const response = await fetch("inspection.aspx/GetInspectionTenantList", {
                method: "POST",
                headers: { "Content-Type": "application/json; charset=utf-8" },
                body: JSON.stringify({
                    employeeId: inspectionLogin.employeeid,
                    companyId: inspectionCompanyID,
                    locationId: inspectionLocationID
                })
            });
            const payload = await response.json();
            if (!response.ok) throw new Error((payload && payload.Message) || "Gagal memuat daftar tenant.");
            const result = payload && Object.prototype.hasOwnProperty.call(payload, "d") ? payload.d : payload;
            rows = (result && result.data || []).map(row => Object.assign({}, row, {
                CompanyID: inspectionCompanyID,
                LocationID: inspectionLocationID
            }));
            await cacheInspectionLookupRows("inspection_tenants", rows);
        } catch (error) {
            console.warn("Tenant list refresh failed; using cached list:", error);
            if (!rows.length) throw error;
        }
    }
    inspectionTenants = rows.slice().sort((a, b) =>
        String(a.TenantName || a.TenantID || "").localeCompare(String(b.TenantName || b.TenantID || "")));
    tenantSelect.innerHTML = '<option value="">Pilih tenant...</option>' + inspectionTenants.map(row =>
        '<option value="' + escInspection(row.TenantID) + '">' +
        escInspection(String(row.TenantID || "") + " - " + String(row.TenantName || "")) + '</option>'
    ).join("");
    tenantSelect.disabled = inspectionTenants.length === 0;
    if (tenantSearch) tenantSearch.disabled = inspectionTenants.length === 0;
    applyInspectionTenantSearch();
    if (!inspectionTenants.length)
        throw new Error("Daftar tenant aktif belum tersedia. Jalankan Sync saat online terlebih dahulu.");

    await loadInspectionTenantSuiteMasterRows();
    refreshInspectionTenantAvailability();
}

async function loadInspectionTenantSuites(tenantId) {
    const suiteSelect = document.getElementById("selInspectionSuite");
    if (!suiteSelect) return;
    suiteSelect.disabled = true;
    suiteSelect.innerHTML = '<option value="">Pilih Suite No...</option>';
    inspectionTenantSuites = [];
    if (!tenantId) {
        suiteSelect.innerHTML = '<option value="">Pilih tenant terlebih dahulu...</option>';
        return;
    }

    let rows = (await readInspectionStore("inspection_tenant_suites")).filter(row =>
        String(row.CompanyID || "") === String(inspectionCompanyID || "") &&
        String(row.LocationID || "") === String(inspectionLocationID || "") &&
        String(row.TenantID || "") === String(tenantId));
    if (navigator.onLine) {
        try {
            const response = await fetch("inspection.aspx/GetInspectionTenantSuites", {
                method: "POST",
                headers: { "Content-Type": "application/json; charset=utf-8" },
                body: JSON.stringify({
                    employeeId: inspectionLogin.employeeid,
                    companyId: inspectionCompanyID,
                    locationId: inspectionLocationID,
                    tenantId: tenantId
                })
            });
            const payload = await response.json();
            if (!response.ok) throw new Error((payload && payload.Message) || "Gagal memuat Suite No.");
            const result = payload && Object.prototype.hasOwnProperty.call(payload, "d") ? payload.d : payload;
            rows = (result && result.data || []).map(row => Object.assign({}, row, {
                CompanyID: inspectionCompanyID,
                LocationID: inspectionLocationID,
                TenantID: tenantId
            }));
            await cacheInspectionLookupRows("inspection_tenant_suites", rows, tenantId);
        } catch (error) {
            console.warn("Tenant suite refresh failed; using cached list:", error);
            if (!rows.length) throw error;
        }
    }
    inspectionTenantSuites = rows.slice().sort((a, b) =>
        String(a.SuiteNo || "").localeCompare(String(b.SuiteNo || "")));
    suiteSelect.innerHTML = '<option value="">Pilih Suite No...</option>' + inspectionTenantSuites.map(row =>
        '<option value="' + escInspection(row.SuiteNo) + '">' + escInspection(row.SuiteNo) + '</option>'
    ).join("");
    suiteSelect.disabled = inspectionTenantSuites.length === 0;
    if (!inspectionTenantSuites.length)
        showToast("Suite aktif untuk tenant ini tidak tersedia.", "warning");
}

function refreshInspectionTenantAvailability() {
    const tenantSelect = document.getElementById("selInspectionTenant");
    if (!tenantSelect) return;

    const typeCode = document.getElementById("selInspectionType").value;
    const type = inspectionTypes.find(x =>
        String(x.InspectionTypeCode || "") === String(typeCode || ""));
    const detailCode = document.getElementById("selInspectionDetail").value;
    const detail = inspectionDetails.find(x =>
        String(x.InspectionTypeCode || "") === String(typeCode || "") &&
        String(x.InspectionTypeDetailCode || "") === String(detailCode || ""));
    const selectedDate = parseInspectionDateFilter(
        document.getElementById("txtInspectionDate").value) || localDateString(new Date());
    const today = localDateString(new Date());
    const selectedTemplateId = Number(document.getElementById("selInspectionTemplate").value);
    const templates = inspectionTemplates.filter(template =>
        String(template.InspectionTypeCode || "") === String(typeCode || "") &&
        (!type || String(template.SectionID || "") === String(type.SectionID || "")) &&
        (!selectedTemplateId || Number(template.IDTemplate) === selectedTemplateId));
    const scheduleSelect = document.getElementById("selInspectionScheduleTime");
    const selectedTime = scheduleSelect ? String(scheduleSelect.value || "") : "";

    const resetOptions = () => {
        Array.from(tenantSelect.options).forEach(option => {
            if (!option.value) return;
            option.disabled = false;
            const tenant = inspectionTenants.find(row =>
                String(row.TenantID || "").trim() === String(option.value || "").trim());
            option.textContent = tenant
                ? String(tenant.TenantID || "") + " - " + String(tenant.TenantName || "")
                : option.value;
        });
    };

    if (!type || !isInspectionTenantDetail(detail) ||
        selectedDate !== today || !templates.length) {
        resetOptions();
        applyInspectionTenantSearch();
        return;
    }

    const suiteMasterRows = (inspectionTenantSuiteMasterRows || []).filter(row =>
        String(row.CompanyID || "") === String(inspectionCompanyID || "") &&
        String(row.LocationID || "") === String(inspectionLocationID || ""));
    // Without a complete Suite master snapshot we cannot safely declare a tenant fully used.
    if (!suiteMasterRows.length) {
        resetOptions();
        applyInspectionTenantSearch();
        return;
    }

    const configuredTimes = getInspectionScheduleTimes(detail);
    const isLightning = String(type.InspectionMode || "").trim().toUpperCase() === "LIGHTNING";
    let slotTimes = isLightning
        ? [configuredTimes.length ? configuredTimes[0] : ""]
        : (configuredTimes.length ? configuredTimes : [""]);
    if (selectedTime) slotTimes = [selectedTime];

    Array.from(tenantSelect.options).forEach(option => {
        const tenantId = String(option.value || "").trim();
        if (!tenantId) return;

        option.disabled = false;
        const baseTenant = inspectionTenants.find(row =>
            String(row.TenantID || "").trim() === tenantId);
        const baseLabel = baseTenant
            ? String(baseTenant.TenantID || "") + " - " + String(baseTenant.TenantName || "")
            : tenantId;
        const suites = suiteMasterRows.filter(row =>
            String(row.TenantID || "").trim() === tenantId);
        if (!suites.length) {
            option.textContent = baseLabel;
            return;
        }

        let totalSlots = 0;
        let occupiedSlots = 0;
        let firstConflict = null;
        suites.forEach(suite => {
            const suiteNo = String(suite.SuiteNo || "").trim();
            if (!suiteNo) return;
            templates.forEach(template => {
                slotTimes.forEach(time => {
                    totalSlots++;
                    const matchesKey = record =>
                        parseInspectionDate(record.InspectionDate) === selectedDate &&
                        String(record.CompanyID || "") === String(inspectionCompanyID || "") &&
                        String(record.LocationID || "") === String(inspectionLocationID || "") &&
                        String(record.SectionID || "") === String(type.SectionID || "") &&
                        String(record.InspectionTypeCode || "") === String(typeCode || "") &&
                        String(record.InspectionTypeDetailCode || "") === String(detailCode || "") &&
                        String(record.TenantID || "").trim() === tenantId &&
                        String(record.SuiteNo || "").trim() === suiteNo &&
                        String(record.ScheduledTime || "") === String(time || "") &&
                        Number(record.IDTemplate) === Number(template.IDTemplate) &&
                        !isCurrentInspectionSlotRecord(record);

                    const local = inspectionRecords.find(matchesKey);
                    const server = serverSlotRecords.find(matchesKey);
                    if (local || server) {
                        occupiedSlots++;
                        if (!firstConflict) firstConflict = { local, server };
                    }
                });
            });
        });

        const fullyOccupied = totalSlots > 0 && occupiedSlots === totalSlots;
        option.disabled = fullyOccupied;
        option.textContent = fullyOccupied
            ? baseLabel + (firstConflict && firstConflict.local &&
                ["CONFLICT", "DELETE_PENDING"].includes(firstConflict.local.SyncStatus)
                ? " • KONFLIK"
                : firstConflict && firstConflict.local && !firstConflict.server
                    ? " • DRAFT DI PERANGKAT INI"
                    : " • SUDAH DIINSPEKSI")
            : baseLabel;
    });

    // If the selected tenant has no remaining Suite/slot, release both selections.
    const selectedOption = tenantSelect.options[tenantSelect.selectedIndex];
    if (selectedOption && selectedOption.value && selectedOption.disabled) {
        tenantSelect.value = "";
        const suiteSelect = document.getElementById("selInspectionSuite");
        if (suiteSelect) {
            suiteSelect.innerHTML = '<option value="">Pilih tenant terlebih dahulu...</option>';
            suiteSelect.value = "";
            suiteSelect.disabled = true;
        }
        inspectionTenantSuites = [];
    }
    applyInspectionTenantSearch();
}

function isCurrentInspectionSlotRecord(record) {
    if (!record || !currentInspectionRecord) return false;
    const currentLocalId = String(currentInspectionRecord.LocalInspectionID || "");
    const candidateLocalId = String(record.LocalInspectionID || record.ClientInspectionID || "");
    if (currentLocalId && candidateLocalId && currentLocalId === candidateLocalId) return true;
    const currentInspectionId = Number(currentInspectionRecord.InspectionID || currentInspectionRecord.ServerInspectionID || 0);
    const candidateInspectionId = Number(record.InspectionID || record.ServerInspectionID || 0);
    return currentInspectionId > 0 && candidateInspectionId > 0 &&
        currentInspectionId === candidateInspectionId;
}

function refreshInspectionSuiteAvailability() {
    const suiteSelect = document.getElementById("selInspectionSuite");
    if (!suiteSelect) return;

    const tenantId = getSelectedInspectionTenantID();
    const typeCode = document.getElementById("selInspectionType").value;
    const type = inspectionTypes.find(x =>
        String(x.InspectionTypeCode || "") === String(typeCode || ""));
    const detailCode = document.getElementById("selInspectionDetail").value;
    const detail = inspectionDetails.find(x =>
        String(x.InspectionTypeCode || "") === String(typeCode || "") &&
        String(x.InspectionTypeDetailCode || "") === String(detailCode || ""));
    const selectedDate = parseInspectionDateFilter(
        document.getElementById("txtInspectionDate").value) || localDateString(new Date());
    const today = localDateString(new Date());
    const selectedTemplateId = Number(document.getElementById("selInspectionTemplate").value);
    const templates = inspectionTemplates.filter(template =>
        String(template.InspectionTypeCode || "") === String(typeCode || "") &&
        (!type || String(template.SectionID || "") === String(type.SectionID || "")) &&
        (!selectedTemplateId || Number(template.IDTemplate) === selectedTemplateId));
    const scheduleSelect = document.getElementById("selInspectionScheduleTime");
    const selectedTime = scheduleSelect ? String(scheduleSelect.value || "") : "";

    const resetOptions = () => {
        Array.from(suiteSelect.options).forEach(option => {
            if (!option.value) return;
            option.disabled = false;
            option.textContent = option.value;
        });
    };

    // Keep the same date scope as the existing Type / Detail / Schedule availability checks.
    if (!tenantId || !isInspectionTenantDetail(detail) || !type ||
        selectedDate !== today || !templates.length) {
        resetOptions();
        return;
    }

    const configuredTimes = getInspectionScheduleTimes(detail);
    const isLightning = String(type.InspectionMode || "").trim().toUpperCase() === "LIGHTNING";
    let slotTimes = isLightning
        ? [configuredTimes.length ? configuredTimes[0] : ""]
        : (configuredTimes.length ? configuredTimes : [""]);
    // When a Schedule Time has been chosen, lock only suites occupied at that exact time.
    // Before a time is chosen, a suite remains available while at least one of its slots is free.
    if (selectedTime) slotTimes = [selectedTime];

    Array.from(suiteSelect.options).forEach(option => {
        const suiteNo = String(option.value || "").trim();
        if (!suiteNo) return;

        option.disabled = false;
        const baseLabel = suiteNo;
        let totalSlots = 0;
        let occupiedSlots = 0;
        let firstConflict = null;

        templates.forEach(template => {
            slotTimes.forEach(time => {
                totalSlots++;
                const matchesKey = record =>
                    parseInspectionDate(record.InspectionDate) === selectedDate &&
                    String(record.CompanyID || "") === String(inspectionCompanyID || "") &&
                    String(record.LocationID || "") === String(inspectionLocationID || "") &&
                    String(record.SectionID || "") === String(type.SectionID || "") &&
                    String(record.InspectionTypeCode || "") === String(typeCode || "") &&
                    String(record.InspectionTypeDetailCode || "") === String(detailCode || "") &&
                    String(record.TenantID || "").trim() === tenantId &&
                    String(record.SuiteNo || "").trim() === suiteNo &&
                    String(record.ScheduledTime || "") === String(time || "") &&
                    Number(record.IDTemplate) === Number(template.IDTemplate) &&
                    !isCurrentInspectionSlotRecord(record);

                const local = inspectionRecords.find(matchesKey);
                const server = serverSlotRecords.find(matchesKey);
                if (local || server) {
                    occupiedSlots++;
                    if (!firstConflict) firstConflict = { local, server };
                }
            });
        });

        const fullyOccupied = totalSlots > 0 && occupiedSlots === totalSlots;
        option.disabled = fullyOccupied;
        option.textContent = fullyOccupied
            ? baseLabel + (firstConflict && firstConflict.local &&
                ["CONFLICT", "DELETE_PENDING"].includes(firstConflict.local.SyncStatus)
                ? " • KONFLIK"
                : firstConflict && firstConflict.local && !firstConflict.server
                    ? " • DRAFT DI PERANGKAT INI"
                    : " • SUDAH DIINSPEKSI")
            : baseLabel;
    });

    // Never leave a now-locked Suite selected; otherwise Start Inspection could
    // continue using a value that is no longer available.
    const selectedOption = suiteSelect.options[suiteSelect.selectedIndex];
    if (selectedOption && selectedOption.value && selectedOption.disabled)
        suiteSelect.value = "";
}

function resetInspectionTenantSelection() {
    const panel = document.getElementById("inspectionTenantPanel");
    const tenantSelect = document.getElementById("selInspectionTenant");
    const suiteSelect = document.getElementById("selInspectionSuite");
    if (panel) panel.classList.add("d-none");
    const tenantSearch = document.getElementById("txtInspectionTenantSearch");
    if (tenantSearch) {
        tenantSearch.value = "";
        tenantSearch.disabled = true;
    }
    if (tenantSelect) {
        tenantSelect.innerHTML = '<option value="">Pilih tenant...</option>';
        tenantSelect.value = "";
        tenantSelect.disabled = true;
    }
    applyInspectionTenantSearch();
    if (suiteSelect) {
        suiteSelect.innerHTML = '<option value="">Pilih tenant terlebih dahulu...</option>';
        suiteSelect.value = "";
        suiteSelect.disabled = true;
    }
}

function refreshInspectionDetailAvailability() {
    const detailSelect = document.getElementById("selInspectionDetail");
    const typeCode = document.getElementById("selInspectionType").value;
    const type = inspectionTypes.find(x =>
        String(x.InspectionTypeCode || "") === String(typeCode || "")
    );
    const selectedDate = parseInspectionDateFilter(document.getElementById("txtInspectionDate").value) || localDateString(new Date());
    const today = localDateString(new Date());

    Array.from(detailSelect.options).forEach(option => {
        if (!option.value) return;

        option.disabled = false;
        const detailCode = option.value;
        const detail = inspectionDetails.find(x =>
            String(x.InspectionTypeCode || "") === String(typeCode || "") &&
            String(x.InspectionTypeDetailCode || "") === String(detailCode || "")
        );
        const baseLabel = detail ? detail.InspectionTypeDetailName : option.textContent;
        const selectedTemplateId = Number(document.getElementById("selInspectionTemplate").value);
        const templates = inspectionTemplates.filter(template =>
            String(template.InspectionTypeCode || "") === String(typeCode || "") &&
            (!type || String(template.SectionID || "") === String(type.SectionID || "")) &&
            (!selectedTemplateId || Number(template.IDTemplate) === selectedTemplateId)
        );

        // Keep the existing duplicate key semantics: each configured template has
        // its own slots. A detail is unavailable only when every time/template
        // combination is already occupied for today's date.
        if (!type || !detail || selectedDate !== today || !templates.length) {
            option.textContent = baseLabel;
            return;
        }

        const times = getInspectionScheduleTimes(detail);
        const isLightning = String(type.InspectionMode || "").toUpperCase() === "LIGHTNING";
        const slotTimes = isLightning
            ? [times.length ? times[0] : ""]
            : (times.length ? times : [""]);
        let totalSlots = 0;
        let occupiedSlots = 0;

        templates.forEach(template => {
            slotTimes.forEach(time => {
                totalSlots++;
                const matchesKey = record =>
                    parseInspectionDate(record.InspectionDate) === selectedDate &&
                    String(record.CompanyID || "") === String(inspectionCompanyID || "") &&
                    String(record.LocationID || "") === String(inspectionLocationID || "") &&
                    String(record.SectionID || "") === String(type.SectionID || "") &&
                    String(record.InspectionTypeCode || "") === String(typeCode || "") &&
                    String(record.InspectionTypeDetailCode || "") === String(detailCode || "") &&
                    String(record.ScheduledTime || "") === String(time || "") &&
                    Number(record.IDTemplate) === Number(template.IDTemplate) &&
                    inspectionTenantMatchesRecord(record, detail);

                if (inspectionRecords.some(matchesKey) || serverSlotRecords.some(matchesKey)) {
                    occupiedSlots++;
                }
            });
        });

        const fullyOccupied = totalSlots > 0 && occupiedSlots === totalSlots;
        option.disabled = fullyOccupied;
        option.textContent = fullyOccupied
            ? baseLabel + " • SUDAH DIINSPEKSI"
            : baseLabel;
    });
}

function onInspectionTypeChanged() {
    resetInspectionTenantSelection();
    inspectionTenantSuites = [];
    const typeCode = document.getElementById("selInspectionType").value;
    const type = inspectionTypes.find(x => x.InspectionTypeCode === typeCode);
    const templates = inspectionTemplates.filter(x =>
        x.InspectionTypeCode === typeCode &&
        (!type || x.SectionID === type.SectionID)
    );
    const templateSelect = document.getElementById("selInspectionTemplate");
    templateSelect.innerHTML = '<option value="">Pilih template...</option>' +
        templates.map(template =>
            '<option value="' + escInspection(template.IDTemplate) + '">' +
            escInspection(template.TemplateNo + " - " + template.TemplateName + " (v" + template.Version + ")") +
            '</option>'
        ).join("");
    templateSelect.disabled = !typeCode || templates.length === 0;

    const detailSelect = document.getElementById("selInspectionDetail");
    const typeDetails = inspectionDetails.filter(detail =>
        String(detail.InspectionTypeCode || "") === String(typeCode || "") &&
        String(detail.CompanyID || "") === String(inspectionCompanyID || "") &&
        String(detail.LocationID || "") === String(inspectionLocationID || "")
    );
    detailSelect.innerHTML = '<option value="">Pilih detail...</option>' +
        typeDetails.map(detail =>
            '<option value="' + escInspection(detail.InspectionTypeDetailCode) + '">' +
            escInspection(detail.InspectionTypeDetailName) + '</option>'
        ).join("");
    detailSelect.disabled = !typeCode || typeDetails.length === 0;
    inspectionDetailSearchOptions = [];
    inspectionDetailLastSelectedValue = "";
    const detailSearch = document.getElementById("txtInspectionDetailSearch");
    if (detailSearch) {
        detailSearch.value = "";
        detailSearch.disabled = detailSelect.disabled;
    }
    inspectionDetailSelectDisabled = detailSelect.disabled;
    syncInspectionDetailSearchOptions();
    resetInspectionScheduleTimeOptions();
    const scheduleControl = document.getElementById("selInspectionScheduleTime");
    if (scheduleControl && scheduleControl.closest(".mb-3"))
        scheduleControl.closest(".mb-3").classList.toggle("d-none",
            String(type && type.InspectionMode || "").trim().toUpperCase() === "LIGHTNING");
    document.getElementById("inspectionScheduleHint").textContent = type
        ? "Section: " + type.SectionID + ". Pilih detail dan template sesuai kebutuhan, lalu jam jadwal."
        : "";
    updateStartButton();
    refreshInspectionScheduleOptions();
}

function onInspectionDetailChanged() {
    const typeCode = document.getElementById("selInspectionType").value;
    const detailCode = document.getElementById("selInspectionDetail").value;
    const detail = inspectionDetails.find(x =>
        x.InspectionTypeCode === typeCode &&
        x.InspectionTypeDetailCode === detailCode
    );
    const tenantPanel = document.getElementById("inspectionTenantPanel");
    let tenantLoad = Promise.resolve();
    if (isInspectionTenantDetail(detail)) {
        if (tenantPanel) tenantPanel.classList.remove("d-none");
        tenantLoad = loadInspectionTenantOptions().catch(error => {
            console.warn("Unable to load Inspection tenant options:", error);
            showToast(error.message || "Gagal memuat daftar tenant.", "warning");
            updateStartButton();
        });
    } else {
        resetInspectionTenantSelection();
        inspectionTenantSuites = [];
    }
    populateInspectionScheduleTimeOptions(detail);
    const selectedType = inspectionTypes.find(x => x.InspectionTypeCode === typeCode);
    const scheduleControl = document.getElementById("selInspectionScheduleTime");
    if (scheduleControl && scheduleControl.closest(".mb-3"))
        scheduleControl.closest(".mb-3").classList.toggle("d-none",
            String(selectedType && selectedType.InspectionMode || "").trim().toUpperCase() === "LIGHTNING");
    refreshInspectionDetailAvailability();
    updateStartButton();
    refreshInspectionScheduleOptions();
    return tenantLoad;
}

function getInspectionScheduleTimes(detail) {
    return String(detail && detail.ScheduleTime || "").split(";").map(time => time.trim())
        .filter(time => /^([01]\d|2[0-3]):[0-5]\d$/.test(time));
}

function resetInspectionScheduleTimeOptions() {
    const select = document.getElementById("selInspectionScheduleTime");
    if (!select) return;
    select.innerHTML = '<option value="">Pilih jam...</option>';
    select.value = "";
    select.disabled = true;
}

function populateInspectionScheduleTimeOptions(detail) {
    const select = document.getElementById("selInspectionScheduleTime");
    if (!select) return;
    const times = getInspectionScheduleTimes(detail);
    if (!detail) {
        select.innerHTML = '<option value="">Pilih detail terlebih dahulu...</option>';
        select.value = "";
        select.disabled = true;
    } else if (!times.length) {
        // A detail without configured ScheduleTime is a valid unscheduled inspection.
        // Keep the field visibly explicit while storing an empty ScheduledTime value.
        select.innerHTML = '<option value="">Inspeksi Tanpa Jadwal</option>';
        select.value = "";
        select.disabled = true;
    } else {
        select.innerHTML = '<option value="">Pilih jam...</option>' +
            times.map(time => '<option value="' + escInspection(time) + '">' +
                escInspection(time) + '</option>').join("");
        select.value = "";
        select.disabled = false;
    }
    const hint = document.getElementById("inspectionScheduleHint");
    if (hint) {
        hint.textContent = !detail
            ? "Pilih Inspection Detail terlebih dahulu."
            : !times.length
                ? "Detail ini tidak memiliki Schedule Time. Inspeksi akan dicatat sebagai Tanpa Jadwal."
                : "Pilih salah satu jam sesuai jadwal inspeksi.";
    }
}

function refreshInspectionScheduleOptions() {
    const select = document.getElementById("selInspectionScheduleTime");
    const typeCode = document.getElementById("selInspectionType").value;
    const type = inspectionTypes.find(x => String(x.InspectionTypeCode || "") === String(typeCode || ""));
    const detailCode = document.getElementById("selInspectionDetail").value;
    const templateId = Number(document.getElementById("selInspectionTemplate").value);
    const selectedDate = parseInspectionDateFilter(document.getElementById("txtInspectionDate").value) || localDateString(new Date());
    const today = localDateString(new Date());
    let emptyCount = 0;
    let slotCount = 0;
    let occupiedCount = 0;

    Array.from(select.options).forEach(option => {
        if (!option.value) return;

        // Re-evaluate every time the template/date/type changes. Do not leave a stale
        // disabled state from a previous selection.
        option.disabled = false;

        const time = option.value || "";
        const detail = inspectionDetails.find(x =>
            String(x.InspectionTypeCode || "") === String(typeCode || "") &&
            String(x.InspectionTypeDetailCode || "") === String(detailCode || "")
        );
        const baseLabel = time;

        // The slot key is the complete business key: date + company/location +
        // section + template + inspection type + detail + scheduled time.
        const matchesKey = record =>
            parseInspectionDate(record.InspectionDate) === selectedDate &&
            String(record.CompanyID || "") === String(inspectionCompanyID || "") &&
            String(record.LocationID || "") === String(inspectionLocationID || "") &&
            String(record.SectionID || "") === String(type ? type.SectionID : "") &&
            String(record.InspectionTypeCode || "") === String(typeCode || "") &&
            String(record.InspectionTypeDetailCode || "") === String(detailCode || "") &&
            String(record.ScheduledTime || "") === String(time || "") &&
            Number(record.IDTemplate) === templateId &&
            inspectionTenantMatchesRecord(record, detail);

        if (!templateId || !type || selectedDate !== today) {
            option.textContent = baseLabel;
            return;
        }

        // When reopening an existing inspection (especially from SUBMITTED),
        // its own slot must not be treated as occupied by another transaction.
        const isCurrentInspection = record => {
            if (!record || !currentInspectionRecord) return false;
            const currentLocalId = String(currentInspectionRecord.LocalInspectionID || "");
            const candidateLocalId = String(record.LocalInspectionID || "");
            if (currentLocalId && candidateLocalId && currentLocalId === candidateLocalId) return true;
            const currentInspectionId = Number(currentInspectionRecord.InspectionID || 0);
            const candidateInspectionId = Number(record.InspectionID || 0);
            return currentInspectionId > 0 && candidateInspectionId > 0 &&
                currentInspectionId === candidateInspectionId;
        };
        const isCurrentLocal = inspectionRecords.some(record => matchesKey(record) && isCurrentInspection(record));
        const isCurrentServer = serverSlotRecords.some(record => matchesKey(record) && isCurrentInspection(record));
        const local = inspectionRecords.find(record => matchesKey(record) && !isCurrentInspection(record));
        const server = serverSlotRecords.find(record => matchesKey(record) && !isCurrentInspection(record));
        slotCount++;

        // The selected record's own slot is neither available nor occupied by
        // another inspection. Keep its saved time label neutral when reopened.
        if (isCurrentLocal || isCurrentServer) {
            option.textContent = baseLabel;
            emptyCount++;
        } else if (local || server) {
            option.disabled = true;
            occupiedCount++;
            if (local && (local.SyncStatus === "CONFLICT" || local.SyncStatus === "DELETE_PENDING")) {
                option.textContent = baseLabel + " • KONFLIK";
            } else if (server) {
                option.textContent = baseLabel + " • SUDAH DIINSPEKSI" +
                    (server.TechnicianName ? " (" + server.TechnicianName + ")" : "");
            } else {
                option.textContent = baseLabel + " • DRAFT DI PERANGKAT INI";
            }
        } else {
            option.textContent = baseLabel + " • TERSEDIA";
            emptyCount++;
        }
    });

    // The user may choose a time before choosing the template. When the template
    // is selected later, a previously selected time can become occupied. Clear it
    // immediately; otherwise a disabled-but-selected option could still pass the
    // required-value check and allow Start Inspection.
    const selectedOption = select.options[select.selectedIndex];
    if (selectedOption && selectedOption.value && selectedOption.disabled) {
        select.value = "";
    }

    const hint = document.getElementById("inspectionScheduleHint");
    const selectedDetail = inspectionDetails.find(x =>
        String(x.InspectionTypeCode || "") === String(typeCode || "") &&
        String(x.InspectionTypeDetailCode || "") === String(detailCode || "")
    );
    const hasScheduledTimes = getInspectionScheduleTimes(selectedDetail).length > 0;
    if (hint && detailCode && !hasScheduledTimes) {
        hint.textContent = "Detail ini tidak memiliki Schedule Time. Inspeksi akan dicatat sebagai Tanpa Jadwal.";
    } else if (hint && detailCode && templateId && selectedDate === today) {
        hint.textContent = slotCount
            ? emptyCount + " jam tersedia, " + occupiedCount + " sudah terisi/diinspeksi dari " + slotCount + " jadwal."
            : "Tidak ada slot jadwal yang tersedia untuk kombinasi ini.";
    }
    updateStartButton();
}

function resetDetailAndTemplateOptions() {
    resetInspectionTenantSelection();
    inspectionTenantSuites = [];
    const detailSelect = document.getElementById("selInspectionDetail");
    detailSelect.innerHTML = '<option value="">Pilih detail...</option>';
    detailSelect.disabled = true;
    resetInspectionScheduleTimeOptions();
    resetTemplateOptions();
}

function resetTemplateOptions() {
    const templateSelect = document.getElementById("selInspectionTemplate");
    templateSelect.innerHTML = '<option value="">Pilih template...</option>';
    templateSelect.disabled = true;
}

function updateStartButton() {
    const typeCode = document.getElementById("selInspectionType").value;
    const detailCode = document.getElementById("selInspectionDetail").value;
    const detail = inspectionDetails.find(x =>
        x.InspectionTypeCode === typeCode && x.InspectionTypeDetailCode === detailCode
    );
    const templateId = Number(document.getElementById("selInspectionTemplate").value);
    const template = inspectionTemplates.find(x => Number(x.IDTemplate) === templateId);
    const detailMatchesTemplate = !!template &&
        isInspectionTemplateDetailAllowed(template, detailCode);
    const hasScheduledTimes = getInspectionScheduleTimes(detail).length > 0;
    const selectedType = inspectionTypes.find(x => String(x.InspectionTypeCode || "") === String(typeCode || ""));
    const isLightning = String(selectedType && selectedType.InspectionMode || "").trim().toUpperCase() === "LIGHTNING";
    const scheduledTime = document.getElementById("selInspectionScheduleTime").value;
    const tenantRequired = isInspectionTenantDetail(detail);
    const tenantComplete = !tenantRequired || (!!getSelectedInspectionTenantID() && !!getSelectedInspectionSuiteNo());
    const enabled = !!typeCode && !!detail && !!detailCode && detailMatchesTemplate && tenantComplete &&
        (isLightning ? hasScheduledTimes : (!hasScheduledTimes || !!scheduledTime)) && !!templateId;
    document.getElementById("btnStartInspection").disabled = !enabled;
}

async function startNewInspection() {
    const typeCode = document.getElementById("selInspectionType").value;
    const detailCode = document.getElementById("selInspectionDetail").value;
    const templateId = Number(document.getElementById("selInspectionTemplate").value);
    const type = inspectionTypes.find(x => x.InspectionTypeCode === typeCode);
    const detail = inspectionDetails.find(x =>
        x.InspectionTypeCode === typeCode && x.InspectionTypeDetailCode === detailCode
    );
    let template = inspectionTemplates.find(x => Number(x.IDTemplate) === templateId);
    const configuredScheduleTimes = getInspectionScheduleTimes(detail);
    const requestedMode = String(type && type.InspectionMode || "STANDARD").trim().toUpperCase();
    const inspectionMode = requestedMode === "LIGHTNING" ? "LIGHTNING" :
        requestedMode === "BATCH" ? "BATCH" : "STANDARD";
    const scheduledTime = inspectionMode === "LIGHTNING"
        ? (configuredScheduleTimes[0] || "")
        : (document.getElementById("selInspectionScheduleTime").value || "");
    const tenantId = isInspectionTenantDetail(detail) ? getSelectedInspectionTenantID() : "";
    const suiteNo = isInspectionTenantDetail(detail) ? getSelectedInspectionSuiteNo() : "";
    const selectedTenant = inspectionTenants.find(row =>
        String(row.TenantID || "").trim() === tenantId);
    const tenantName = selectedTenant ? String(selectedTenant.TenantName || "").trim() : "";

    if (!type || !detail || !template ||
        !isInspectionTemplateDetailAllowed(template, detail.InspectionTypeDetailCode) ||
        (inspectionMode === "LIGHTNING" ? !configuredScheduleTimes.length :
            (configuredScheduleTimes.length > 0 && !scheduledTime)) ||
        (isInspectionTenantDetail(detail) && (!tenantId || !suiteNo))) {
        showToast("Pilih Inspection Type, detail, tenant, Suite No, jam jadwal (jika tersedia), dan template yang valid.", "warning");
        return;
    }

    // Online BATCH starts must use the exact authoritative template version from
    // the server, not a possibly stale IndexedDB snapshot. STANDARD keeps its
    // existing cache-first flow and is deliberately not affected.
    if (isInspectionMapMode(inspectionMode) && navigator.onLine) {
        try {
            const templateResponse = await fetch("dashboard.aspx/getCheckList", {
                method: "POST",
                headers: { "Content-Type": "application/json; charset=utf-8" },
                body: JSON.stringify({
                    section: inspectionLogin.section || "",
                    templateNo: template.TemplateNo,
                    version: String(template.Version || ""),
                    modelcode: "",
                    companyId: inspectionCompanyID,
                    locationId: inspectionLocationID,
                    templateType: "I",
                    employeeId: inspectionLogin.employeeid
                })
            });
            const templatePayload = await templateResponse.json();
            if (!templateResponse.ok)
                throw new Error((templatePayload && (templatePayload.Message || templatePayload.ExceptionMessage)) ||
                    "Gagal memuat ulang Master Checklist BATCH.");
            const exactTemplates = templatePayload && Object.prototype.hasOwnProperty.call(templatePayload, "d")
                ? templatePayload.d : templatePayload;
            const authoritativeTemplate = (Array.isArray(exactTemplates) ? exactTemplates : []).find(item =>
                Number(item.IDTemplate) === Number(template.IDTemplate) &&
                Number(item.IDVersion) === Number(template.IDVersion)
            );
            if (!authoritativeTemplate)
                throw new Error("Template BATCH versi " + String(template.Version || "") +
                    " tidak ditemukan lagi di server. Jalankan Sync dan pilih template kembali.");

            template = authoritativeTemplate;
            const cachedIndex = inspectionTemplates.findIndex(item =>
                Number(item.IDTemplate) === Number(template.IDTemplate));
            if (cachedIndex >= 0) inspectionTemplates[cachedIndex] = template;
            await new Promise((resolve, reject) => {
                const tx = db.transaction("inspection_templates", "readwrite");
                tx.objectStore("inspection_templates").put(template);
                tx.oncomplete = resolve;
                tx.onerror = () => reject(tx.error || new Error("Gagal memperbarui cache Master Checklist BATCH."));
                tx.onabort = () => reject(tx.error || new Error("Pembaruan cache Master Checklist BATCH dibatalkan."));
            });
        } catch (templateError) {
            console.error("Unable to refresh exact BATCH template before start:", templateError);
            showToast("Master Checklist BATCH belum berhasil diverifikasi dari server. Inspeksi belum dimulai. " +
                (templateError.message || templateError), "danger");
            return;
        }
    }

    const inspectionDate = parseInspectionDateFilter(document.getElementById("txtInspectionDate").value) || localDateString(new Date());
    if (navigator.onLine && typeof downloadTodayInspectionSlots === "function") {
        try {
            await downloadTodayInspectionSlots();
            await refreshSavedInspectionList();
        } catch (scheduleError) {
            console.warn("Today schedule refresh failed before Start Inspection:", scheduleError);
            showToast("Jadwal server belum berhasil diperbarui. Pemeriksaan lokal tetap dilakukan; jika koneksi bermasalah, lanjutkan dengan hati-hati.", "warning");
        }
    }
    const duplicate = inspectionRecords.find(record =>
        parseInspectionDate(record.InspectionDate) === inspectionDate &&
        record.CompanyID === inspectionCompanyID &&
        record.LocationID === inspectionLocationID &&
        record.SectionID === type.SectionID &&
        record.InspectionTypeCode === type.InspectionTypeCode &&
        record.InspectionTypeDetailCode === detail.InspectionTypeDetailCode &&
        String(record.ScheduledTime || "") === String(scheduledTime || "") &&
        Number(record.IDTemplate) === Number(template.IDTemplate) &&
        inspectionTenantMatchesRecord(record, detail)
    );
    if (duplicate) {
        if (duplicate.SyncStatus === "CONFLICT" || duplicate.SyncStatus === "DELETE_PENDING") {
            showToast("Draft ini masih memiliki konflik data. " +
                getInspectionConflictDisplayReason(duplicate) +
                " Selesaikan draft ini terlebih dahulu sebelum membuat inspeksi baru.", "warning");
            return;
        }
        showToast("Jadwal ini sudah memiliki inspeksi di perangkat (" +
            (duplicate.InspectionNo || "TEMP-" + String(duplicate.LocalInspectionID || "").substring(0, 8)) +
            "). Buka record yang sudah ada, jangan membuat duplikat.", "warning");
        await openSavedInspection(duplicate.LocalInspectionID);
        return;
    }

    const loginData = getLoginData();
    const lastScheduleSync = loginData && loginData.lastInspectionScheduleSyncAt
        ? new Date(loginData.lastInspectionScheduleSyncAt) : null;
    const today = localDateString(new Date());
    if (!navigator.onLine && (!lastScheduleSync || localDateString(lastScheduleSync) !== today)) {
        const proceedOffline = await showConfirmation({
            title: "Mulai Inspeksi Offline",
            message: "Jadwal server hari ini belum pernah berhasil disinkronkan di perangkat ini. Pemeriksaan lokal saja tidak dapat memastikan slot belum dipakai teknisi lain. Tetap mulai inspeksi secara offline?",
            yesText: "Lanjutkan"
        });
        if (!proceedOffline) return;
    }

    const serverDuplicate = serverSlotRecords.find(record =>
        parseInspectionDate(record.InspectionDate) === inspectionDate &&
        record.CompanyID === inspectionCompanyID &&
        record.LocationID === inspectionLocationID &&
        record.SectionID === type.SectionID &&
        record.InspectionTypeCode === type.InspectionTypeCode &&
        record.InspectionTypeDetailCode === detail.InspectionTypeDetailCode &&
        String(record.ScheduledTime || "") === String(scheduledTime || "") &&
        Number(record.IDTemplate) === Number(template.IDTemplate) &&
        inspectionTenantMatchesRecord(record, detail)
    );
    if (serverDuplicate) {
        showToast("Jadwal ini sudah terisi di server (" +
            (serverDuplicate.InspectionNo || serverDuplicate.Status || "inspection") +
            "). Record server tetap dipertahankan; jangan membuat transaksi duplikat.", "warning");
        return;
    }

    if (navigator.onLine) {
        try {
            const response = await fetch("inspection.aspx/CheckInspectionDuplicate", {
                method: "POST",
                headers: { "Content-Type": "application/json; charset=utf-8" },
                body: JSON.stringify({
                    employeeId: inspectionLogin.employeeid,
                    companyId: inspectionCompanyID,
                    locationId: inspectionLocationID,
                    sectionId: type.SectionID,
                    inspectionTypeCode: type.InspectionTypeCode,
                    inspectionTypeDetailCode: detail.InspectionTypeDetailCode,
                    scheduledTime: scheduledTime,
                    templateId: Number(template.IDTemplate),
                    inspectionDate: inspectionDate,
                    tenantId: tenantId,
                    suiteNo: suiteNo
                })
            });
            const payload = await response.json();
            if (!response.ok) {
                const requestError = new Error((payload && payload.Message) || "Gagal memvalidasi jadwal inspeksi.");
                requestError.status = response.status;
                throw requestError;
            }
            const check = payload && Object.prototype.hasOwnProperty.call(payload, "d") ? payload.d : payload;
            if (check && check.duplicate) {
                if (isInspectionTenantDetail(detail)) {
                    showToast("Tenant dan Suite yang sama sudah memiliki inspeksi dengan jadwal dan template tersebut. Silakan periksa inspeksi yang sudah ada; duplikat tidak dibuat.", "warning");
                } else {
                    showToast("Jadwal ini sudah memiliki inspeksi " +
                        (check.InspectionNo || "di server") + " untuk tanggal dan template tersebut. Duplikat tidak dibuat.", "warning");
                }
                return;
            }
        } catch (err) {
            const message = String(err.message || err).toLowerCase();
            if (err.status === 403 || /not authorized|not assigned|unauthorized|employee is required/.test(message)) {
                showToast("Validasi server menolak akses inspeksi: " + (err.message || err), "danger");
                return;
            }
            // If the server is unreachable, offline entry remains possible; upload performs final validation.
            console.warn("Unable to pre-check duplicate inspection:", err);
            showToast("Pemeriksaan jadwal server gagal. Jika koneksi bermasalah, inspeksi tetap bisa dibuat offline dan akan divalidasi lagi saat upload.", "warning");
        }
    }

    let batchMapSetup = null;
    if (isInspectionMapMode(inspectionMode)) {
        if (navigator.onLine) {
            try {
                const response = await fetch("inspection.aspx/GetBatchInspectionMap", {
                    method: "POST",
                    headers: { "Content-Type": "application/json; charset=utf-8" },
                    body: JSON.stringify({
                        inspectionTypeCode: type.InspectionTypeCode,
                        inspectionTypeDetailCode: detail.InspectionTypeDetailCode,
                        employeeId: inspectionLogin.employeeid,
                        companyId: inspectionCompanyID,
                        locationId: inspectionLocationID
                    })
                });
                const payload = await response.json();
                if (!response.ok) throw new Error((payload && payload.Message) || "Gagal memuat Inspection Point.");
                batchMapSetup = payload && Object.prototype.hasOwnProperty.call(payload, "d") ? payload.d : payload;
                if (!batchMapSetup || batchMapSetup.success !== true)
                    throw new Error("Data map Inspection tidak valid.");
                // Do not download every floor plan before opening the batch.
                // Point data is enough to enter the workspace; renderPdf loads only
                // the selected map asynchronously after the workspace becomes visible.
            } catch (mapError) {
                showToast("Tidak dapat memuat denah dan Inspection Point: " + (mapError.message || mapError), "danger");
                return;
            }
        } else {
            const cachedSetups = type.BatchMapSetups || {};
            batchMapSetup = cachedSetups[String(detail.InspectionTypeDetailCode || "").toUpperCase()] || null;
        }

        if (!batchMapSetup || !Array.isArray(batchMapSetup.points) || !batchMapSetup.points.length) {
            showToast("Data Inspection Point untuk batch ini belum tersedia offline. Jalankan Sync saat online sebelum memulai batch.", "warning");
            return;
        }
        if (!navigator.onLine && (batchMapSetup.maps || []).some(map =>
            map.MapUrl && (!(map.MapBlob || map.PdfBlob) || typeof (map.MapBlob || map.PdfBlob).arrayBuffer !== "function"))) {
            showToast("Denah belum tersimpan offline. Checklist tetap bisa dikerjakan melalui tampilan List; denah dapat dibuka saat online.", "warning");
        }
    }

    currentInspectionRecord = {
        LocalInspectionID: newInspectionId(),
        ServerInspectionID: 0,
        CompanyID: inspectionCompanyID,
        LocationID: inspectionLocationID,
        SectionID: type.SectionID,
        OwnerEmployeeID: inspectionLogin.employeeid,
        TechnicianName: inspectionTechnicianName || inspectionLogin.employeeid,
        InspectionTypeCode: type.InspectionTypeCode,
        InspectionTypeName: type.InspectionTypeName,
        InspectionTypeDetailCode: detail.InspectionTypeDetailCode,
        InspectionTypeDetailName: detail.InspectionTypeDetailName,
        TenantID: tenantId,
        TenantName: tenantName,
        SuiteNo: suiteNo,
        ScheduledTime: scheduledTime,
        IDTemplate: Number(template.IDTemplate),
        IDVersion: Number(template.IDVersion),
        TemplateNo: template.TemplateNo,
        TemplateName: template.TemplateName,
        TemplateVersion: String(template.Version || ""),
        TemplateSnapshot: JSON.parse(JSON.stringify(template)),
        PhotoRequirement: getInspectionPhotoRequirement(template),
        InspectionDate: inspectionDate,
        StartDateTime: localDateTimeString(new Date()),
        EndDateTime: "",
        Status: "DRAFT",
        SyncStatus: "PENDING",
        Summary: "",
        FollowUp: "No Follow Up",
        FollowUpSection: "",
        FollowUpRemark: "",
        FollowUpWONo: "",
        InspectionMode: inspectionMode,
        BatchMapSetup: batchMapSetup,
        Schedules: inspectionMode === "LIGHTNING" ? configuredScheduleTimes.slice() : [],
        ActiveScheduleTime: inspectionMode === "LIGHTNING" ? scheduledTime : "",
        Points: [],
        ActiveInspectionPointID: 0,
        Items: []
    };

    if (typeof window.resetInspectionMapWorkspace === "function")
        await window.resetInspectionMapWorkspace();
    await renderInspectionForm(currentInspectionRecord, false, "checklist");
    const mapWorkspace = document.getElementById("inspectionMapWorkspace");
    if (isInspectionMapMode(inspectionMode) && typeof showInspectionMapWorkspace === "function") {
        // BATCH starts directly in the MAP workspace so the denah and point list
        // are immediately visible after the parameters are applied.
        showInspectionMapWorkspace(currentInspectionRecord, true);
    } else if (mapWorkspace) {
        mapWorkspace.classList.add("d-none");
    }
    // A newly created inspection should open at FIELD DOCUMENTATION BEFORE,
    // not at a leftover scroll position from the previous screen.
    window.setTimeout(() => {
        const beforePhotoPanel = document.getElementById("btnAddInspectionBeforePhoto")?.closest(".inspection-photo-panel");
        if (!beforePhotoPanel) return;
        const stickyHeader = document.getElementById("inspectionEditorStickyHeader");
        beforePhotoPanel.scrollIntoView({ behavior: "auto", block: "start" });
        if (stickyHeader && stickyHeader.getClientRects().length) {
            const offset = beforePhotoPanel.getBoundingClientRect().top - stickyHeader.getBoundingClientRect().bottom - 8;
            if (Math.abs(offset) > 2) window.scrollBy({ top: offset, behavior: "auto" });
        }
        updateInspectionScrollTools();
    }, 80);
}

function parseInspectionDateValue(value) {
    if (value == null || value === "") return null;
    if (value instanceof Date) return isNaN(value.getTime()) ? null : value;
    const raw = String(value).trim();
    // ASP.NET ASMX serializes DateTime as /Date(milliseconds)/.
    const dotNet = raw.match(/^\/?Date\((-?\d+)(?:[+-]\d{4})?\)\/?$/i);
    if (dotNet) {
        const parsed = new Date(Number(dotNet[1]));
        return isNaN(parsed.getTime()) ? null : parsed;
    }
    const parsed = new Date(raw);
    return isNaN(parsed.getTime()) ? null : parsed;
}

function inspectionDateInputValue(value) {
    const iso = parseInspectionDate(value);
    return iso ? formatInspectionDateDMY(iso) : "";
}

function formatInspectionDateDMY(value) {
    if (!value) return "-";
    const raw = String(value).trim();
    const match = raw.match(/^(\d{4})-(\d{2})-(\d{2})/);
    const date = match ? new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3])) : parseInspectionDateValue(value);
    if (!date) return "-";
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return String(date.getDate()).padStart(2, "0") + "-" + months[date.getMonth()] + "-" + date.getFullYear();
}

function parseInspectionDateFilter(value) {
    const raw = String(value || "").trim();
    if (!raw) return "";
    if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) return raw;
    const match = raw.match(/^(\d{1,2})[-\s]([A-Za-z]{3})[-\s](\d{4})$/);
    if (!match) return "";
    const months = { jan:1, feb:2, mar:3, apr:4, may:5, jun:6, jul:7, aug:8, sep:9, oct:10, nov:11, dec:12 };
    const month = months[match[2].toLowerCase()];
    const day = Number(match[1]), year = Number(match[3]);
    if (!month || day < 1 || day > 31) return "";
    const date = new Date(year, month - 1, day);
    if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) return "";
    return year + "-" + String(month).padStart(2, "0") + "-" + String(day).padStart(2, "0");
}

function wireInspectionDatePicker(textId, pickerId) {
    const textInput = document.getElementById(textId);
    const datePicker = document.getElementById(pickerId);
    if (!textInput || !datePicker || textInput.dataset.datePickerWired === "1") return;

    const syncPickerFromText = function () {
        const parsed = parseInspectionDateFilter(textInput.value);
        datePicker.value = parsed || "";
    };
    const syncTextFromPicker = function () {
        if (!datePicker.value) return;
        textInput.value = formatInspectionDateDMY(datePicker.value);
        textInput.dispatchEvent(new Event("change", { bubbles: true }));
    };

    textInput.addEventListener("change", syncPickerFromText);
    textInput.addEventListener("blur", syncPickerFromText);
    datePicker.addEventListener("change", syncTextFromPicker);
    textInput.dataset.datePickerWired = "1";
    syncPickerFromText();
}

function formatInspectionClock(value) {
    if (!value) return "--:--";
    const date = parseInspectionDateValue(value);
    if (!date || date.getFullYear() <= 1900) return "--:--";
    return String(date.getHours()).padStart(2, "0") + ":" +
        String(date.getMinutes()).padStart(2, "0");
}

async function cleanupInspectionPhotosByRequirement(localInspectionId, requirement) {
    const normalized = normalizeInspectionPhotoRequirement(requirement);
    const keep = normalized === "BOTH" ? ["BEFORE", "AFTER"] :
        normalized === "BEFORE" ? ["BEFORE"] : normalized === "AFTER" ? ["AFTER"] : [];
    await new Promise((resolve, reject) => {
        const tx = db.transaction("inspection_photos", "readwrite");
        const store = tx.objectStore("inspection_photos");
        const index = store.index("LocalInspectionID");
        const req = index.openCursor(IDBKeyRange.only(localInspectionId));
        req.onsuccess = () => {
            const cursor = req.result;
            if (!cursor) return;
            const type = String(cursor.value.Type || "").toUpperCase();
            if (["BEFORE", "AFTER"].includes(type) && !keep.includes(type)) cursor.delete();
            cursor.continue();
        };
        tx.oncomplete = resolve;
        tx.onerror = () => reject(tx.error || new Error("Gagal membersihkan foto inspeksi yang tidak diaktifkan."));
        tx.onabort = () => reject(tx.error || new Error("Pembersihan foto inspeksi dibatalkan."));
    });
}
function getBatchPointQuickOptionBlockReason(point) {
    const record = currentInspectionRecord;
    if (!record || !isInspectionMapMode(record.InspectionMode))
        return "Batch/Lightning inspection tidak sedang aktif.";
    const requirement = getInspectionPhotoRequirement(record);
    // Quick OPTION selection is blocked only when BEFORE is mandatory,
    // because the full checklist is also gated only by the BEFORE photo.
    // AFTER-only templates may select the option first; completion validation
    // still enforces the required AFTER photo before the point/batch is finished.
    if (requirement === "BEFORE" || requirement === "BOTH") {
        const photoText = requirement === "BOTH" ? "BEFORE dan AFTER" : "BEFORE";
        return "Template Version mewajibkan foto " + photoText + ". Buka checklist lengkap untuk melanjutkan.";
    }
    // Other checklist requirements (NORMAL/ABNORMAL, numeric/text values,
    // remarks, etc.) are validated when the point is completed. They must not
    // prevent choosing an OPTION value from the point list.
    // The quick OPTION control is intentionally gated only by a mandatory
    // BEFORE photo because that is the only prerequisite needed before entering
    // the point checklist.
    return "";
}
window.getBatchPointQuickOptionBlockReason = getBatchPointQuickOptionBlockReason;

function normalizeInspectionPhotoRequirement(value) {
    const requirement = String(value == null ? "" : value).trim().toUpperCase();
    // Empty/null means the version has no photo requirement. The master must
    // explicitly store BEFORE/AFTER/BOTH when one of those is required.
    return ["NONE", "BEFORE", "AFTER", "BOTH"].includes(requirement) ? requirement : "NONE";
}

function getInspectionPhotoRequirement(source) {
    const record = source || {};
    const template = record.TemplateSnapshot || record;
    const versionInfo = template.VersionInfo || template.versionInfo || template;
    const value = versionInfo.PhotoRequirement !== undefined && versionInfo.PhotoRequirement !== null
        ? versionInfo.PhotoRequirement
        : (versionInfo.photoRequirement !== undefined && versionInfo.photoRequirement !== null
            ? versionInfo.photoRequirement
            : (template.PhotoRequirement !== undefined && template.PhotoRequirement !== null
                ? template.PhotoRequirement : record.PhotoRequirement));
    return normalizeInspectionPhotoRequirement(value);
}

function isInspectionFlagEnabled(value, defaultValue) {
    if (value === undefined || value === null || value === "") return defaultValue === true;
    return !(value === false || value === 0 || value === "0" || String(value).toLowerCase() === "false");
}

function inspectionTemplateRequiresSummary(template) {
    if (!template) return true;
    const versionInfo = template.VersionInfo || template.versionInfo || template;
    const value = versionInfo.isSummaryRequired !== undefined
        ? versionInfo.isSummaryRequired : versionInfo.IsSummaryRequired;
    return isInspectionFlagEnabled(value, true);
}

function inspectionTemplateRequiresFollowUp(template) {
    if (!template) return true;
    const versionInfo = template.VersionInfo || template.versionInfo || template;
    const value = versionInfo.isFollowUpRequired !== undefined
        ? versionInfo.isFollowUpRequired : versionInfo.IsFollowUpRequired;
    return isInspectionFlagEnabled(value, true);
}

function renderBatchPointCondition(masterPoint, point, readOnly) {
    const host = document.getElementById("inspectionPointConditionPanel");
    if (!host) return;
    const required = isInspectionFlagEnabled(masterPoint && masterPoint.IsNormalAbnormalRequired, false);
    if (!required) {
        host.innerHTML = "";
        host.classList.add("d-none");
        return;
    }
    if (!point.PointCondition && String(point.AbnormalRemark || "").trim())
        point.PointCondition = "ABNORMAL";
    else if (!point.PointCondition &&
        (Number(point.InspectionPointTransactionID || 0) > 0 || currentInspectionRecord.SyncStatus === "SYNCED"))
        point.PointCondition = "NORMAL";
    const choice = String(point.PointCondition || "").toUpperCase();
    const remark = String(point.AbnormalRemark || "");
    const id = String(masterPoint.InspectionPointID).replace(/[^0-9a-z_-]/gi, "");
    host.innerHTML = '<div class="inspection-item border rounded-3 p-3">' +
        '<div class="fw-bold mb-2"><i class="bi bi-clipboard2-pulse me-2"></i>KONDISI TITIK PEMERIKSAAN <span class="text-danger">*</span></div>' +
        '<div class="inspection-option-list d-flex flex-wrap gap-2" role="group" aria-label="Kondisi titik pemeriksaan">' +
            '<input class="btn-check" type="radio" name="inspectionPointCondition" id="pointConditionNormal_' + id + '" value="NORMAL" ' + (choice === "NORMAL" ? "checked " : "") + (readOnly ? "disabled" : "") + '>' +
            '<label class="btn btn-outline-primary inspection-option-choice" for="pointConditionNormal_' + id + '">NORMAL</label>' +
            '<input class="btn-check" type="radio" name="inspectionPointCondition" id="pointConditionAbnormal_' + id + '" value="ABNORMAL" ' + (choice === "ABNORMAL" ? "checked " : "") + (readOnly ? "disabled" : "") + '>' +
            '<label class="btn btn-outline-primary inspection-option-choice" for="pointConditionAbnormal_' + id + '">ABNORMAL</label>' +
        '</div>' +
        '<div id="pointAbnormalRemarkRow_' + id + '" class="mt-3 ' + (choice === "ABNORMAL" ? "" : "d-none") + '">' +
            '<label class="form-label small fw-semibold">Abnormal Remark <span class="text-danger">*</span></label>' +
            '<textarea id="txtPointAbnormalRemark_' + id + '" class="form-control" rows="3" maxlength="500" placeholder="Jelaskan kondisi abnormal (maks. 500 karakter)" ' + (readOnly ? "disabled" : "") + '>' +
                remark.replace(/[&<>"]/g, function (ch) { return ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", "\"":"&quot;" })[ch]; }) +
            '</textarea>' +
            '<div class="small text-muted text-end mt-1">Maksimum 500 karakter.</div>' +
        '</div>' +
    '</div>';
    host.classList.remove("d-none");
    host.querySelectorAll('input[name="inspectionPointCondition"]').forEach(input => {
        input.addEventListener("change", function () {
            point.PointCondition = this.value;
            const row = document.getElementById("pointAbnormalRemarkRow_" + id);
            if (row) row.classList.toggle("d-none", this.value !== "ABNORMAL");
            if (this.value === "NORMAL") point.AbnormalRemark = "";
            if (this.value === "ABNORMAL") {
                const field = document.getElementById("txtPointAbnormalRemark_" + id);
                if (field) field.focus();
            }
        });
    });
    const remarkInput = document.getElementById("txtPointAbnormalRemark_" + id);
    if (remarkInput) remarkInput.addEventListener("input", function () {
        this.classList.remove("is-invalid");
        const panel = this.closest(".inspection-validation-error");
        if (panel) panel.classList.remove("inspection-validation-error", "border", "border-danger", "rounded", "p-2");
        point.AbnormalRemark = this.value;
    });
}


function applyInspectionPhotoRequirement(record) {
    const requirement = getInspectionPhotoRequirement(record);
    const beforePanel = document.getElementById("btnAddInspectionBeforePhoto")?.closest(".inspection-photo-panel");
    const afterPanel = document.getElementById("inspectionAfterPhotoPanel") ||
        document.getElementById("btnAddInspectionAfterPhoto")?.closest(".inspection-photo-panel");
    if (beforePanel) beforePanel.classList.toggle("d-none", requirement !== "BEFORE" && requirement !== "BOTH");
    if (afterPanel) afterPanel.classList.toggle("d-none", requirement !== "AFTER" && requirement !== "BOTH");
    return requirement;
}

function getInspectionLightningWorkflowStatus(record) {
    if (!record || String(record.InspectionMode || "").toUpperCase() !== "LIGHTNING") return "DRAFT";
    if (isInspectionFlagEnabled(record.IsApproved2, false)) return "ACKNOWLEDGE 2";
    if (isInspectionFlagEnabled(record.IsApproved1, false)) return "ACKNOWLEDGE 1";
    if (isInspectionFlagEnabled(record.IsApproved, false)) return "VERIFIED";
    if (isInspectionFlagEnabled(record.IsSubmitted, false)) return "CHECKED";
    return "DRAFT";
}

function renderInspectionApprovalWorkflowCards(record, modeOverride) {
    const panel = document.getElementById("inspectionApprovalWorkflowPanel");
    const host = document.getElementById("inspectionApprovalWorkflowCards");
    if (!panel || !host) return;

    const recordMode = String(modeOverride || (record && record.InspectionMode) || "").trim().toUpperCase();
    const typeMaster = record && inspectionTypes.find(type =>
        String(type.InspectionTypeCode || "") === String(record.InspectionTypeCode || "")
    );
    const inspectionMode = recordMode || String(typeMaster && typeMaster.InspectionMode || "").trim().toUpperCase();

    // Approval Workflow is exclusive to LIGHTNING inspections.
    if (!record || inspectionMode !== "LIGHTNING") {
        host.innerHTML = "";
        panel.classList.add("d-none");
        panel.setAttribute("aria-hidden", "true");
        panel.style.removeProperty("display");
        panel.style.removeProperty("flex");
        return;
    }

    // Keep the workflow visible before submit, but render it as one compact strip
    // so it does not consume the vertical space needed by the floor plan.
    panel.classList.remove("d-none");
    panel.hidden = false;
    panel.setAttribute("aria-hidden", "false");
    panel.style.setProperty("display", "block", "important");
    panel.style.setProperty("flex", "0 0 auto");

    const stages = [
        {
            label: "CHECKED BY",
            role: "Technician / Submit",
            flag: "IsSubmitted",
            by: record.SubmittedByName || record.TechnicianName || record.SubmittedBy || record.OwnerEmployeeID,
            date: record.SubmittedDate,
            color: "primary"
        },
        {
            label: "VERIFIED BY",
            role: "Supervisor (SPV)",
            flag: "IsApproved",
            by: record.ApprovedByName || record.ApprovedBy,
            date: record.ApprovedDate,
            color: "warning"
        },
        {
            label: "ACKNOWLEDGED BY 1",
            role: "Chief Engineering",
            flag: "IsApproved1",
            by: record.Approved1ByName || record.Approved1By,
            date: record.Approved1Date,
            color: "info"
        },
        {
            label: "ACKNOWLEDGED BY 2",
            role: "Chief Security",
            flag: "IsApproved2",
            by: record.Approved2ByName || record.Approved2By,
            date: record.Approved2Date,
            color: "success"
        }
    ];

    host.innerHTML = '<div class="inspection-approval-workflow-strip">' +
        stages.map(function (stage) {
            const done = isInspectionFlagEnabled(record[stage.flag], false);
            const person = String(stage.by || "").trim();
            const timestamp = stage.date
                ? formatInspectionDateDMY(stage.date) + " " + formatInspectionClockTime(stage.date)
                : "";
            const cardClass = done
                ? "border-" + stage.color + " bg-" + stage.color + "-subtle"
                : "border-secondary-subtle bg-body-secondary";
            const titleClass = done ? "text-" + stage.color + "-emphasis" : "text-secondary";
            const details = done
                ? '<div class="inspection-approval-workflow-person text-body">' +
                    escInspection(person || "Nama belum tersedia") + '</div>' +
                    '<div class="inspection-approval-workflow-date"><i class="bi bi-calendar-event me-1"></i>' +
                    escInspection(timestamp || "Waktu belum tersedia") + '</div>'
                : '<div class="inspection-approval-workflow-status text-secondary">Data belum tersedia</div>';

            return '<div class="inspection-approval-workflow-card">' +
                '<div class="card ' + cardClass + '">' +
                    '<div class="card-body">' +
                        '<div class="inspection-approval-workflow-title ' + titleClass + '">' + escInspection(stage.label) + '</div>' +
                        '<div class="inspection-approval-workflow-role">' + escInspection(stage.role) + '</div>' +
                        details +
                    '</div>' +
                '</div>' +
            '</div>';
        }).join("") +
    '</div>';
}

// Expose the renderer so the MAP workspace can refresh the panel after switching layouts.
window.renderInspectionApprovalWorkflowCards = renderInspectionApprovalWorkflowCards;

window.mountInspectionBatchSummary = function (record) {
    const host = document.getElementById("inspectionMapSummaryHost");
    const checklistPane = document.getElementById("inspectionChecklistPane");
    const followUp = document.getElementById("inspectionFollowUpPanel");
    const summary = document.getElementById("inspectionSummaryPanel");
    const reasonVoid = document.getElementById("inspectionReasonVoidPanel");
    if (!host || !checklistPane || !followUp || !summary) return;
    const isBatch = record && isInspectionMapMode(record.InspectionMode);
    if (isBatch) {
        host.appendChild(followUp);
        host.appendChild(summary);
        if (reasonVoid) host.appendChild(reasonVoid);
        host.classList.remove("d-none");
        followUp.classList.toggle("d-none", !inspectionTemplateRequiresFollowUp(record.TemplateSnapshot));
        summary.classList.toggle("d-none", !inspectionTemplateRequiresSummary(record.TemplateSnapshot));
        const readOnly = currentInspectionReadOnly || record.Status === "DONE";
        document.querySelectorAll('input[name="inspectionFollowUp"]').forEach(el => { el.disabled = readOnly; });
        document.getElementById("inspectionFollowUpSection").disabled = readOnly;
        document.querySelectorAll('input[name="inspectionFollowUpSectionChoice"]').forEach(el => { el.disabled = readOnly; });
        document.getElementById("txtInspectionFollowUpRemark").disabled = readOnly;
        const summaryInput = document.getElementById("txtInspectionSummary");
        if (summaryInput) summaryInput.disabled = readOnly;
    } else {
        const formPanel = document.getElementById("inspectionFormPanel");
        const actionRow = document.getElementById("btnSaveInspectionDraft");
        const actionContainer = actionRow ? actionRow.parentElement : null;
        if (formPanel && actionContainer) {
            formPanel.insertBefore(followUp, actionContainer);
            formPanel.insertBefore(summary, actionContainer);
            if (reasonVoid) formPanel.insertBefore(reasonVoid, actionContainer);
        }
        host.classList.add("d-none");
        followUp.classList.toggle("d-none", !inspectionTemplateRequiresFollowUp(record.TemplateSnapshot));
        summary.classList.toggle("d-none", !inspectionTemplateRequiresSummary(record.TemplateSnapshot));
    }
};

async function renderInspectionForm(record, readOnly, initialTab) {
    serverInspectionPhotoPreview = [];
    currentInspectionRecord = record;
    if (!readOnly && (record.Status !== "DONE" || isVoidedServerInspectionRecord(record)))
        startInspectionGpsWatch();
    else
        stopInspectionGpsWatch();
    if (!readOnly && (record.Status !== "DONE" || isVoidedServerInspectionRecord(record))) {
        await cleanupInspectionPhotosByRequirement(record.LocalInspectionID,
            getInspectionPhotoRequirement(record));
    }
    const photosAtOpen = await getInspectionPhotos(record.LocalInspectionID);
    inspectionPhotoBaseline = photosAtOpen.map(photo => Object.assign({}, photo));
    showInspectionInputScreen();
    applyInspectionPhotoRequirement(record);
    const isVoidedServerRecord = isVoidedServerInspectionRecord(record);
    currentInspectionReadOnly = !isVoidedServerRecord && (!!readOnly || record.Status === "DONE");
    document.getElementById("inspectionEditorTabs").classList.remove("d-none");
    const mapTabButton = document.getElementById("btnInspectionMapTab");
    if (mapTabButton && mapTabButton.closest("li"))
        mapTabButton.closest("li").classList.toggle("d-none", !isInspectionMapMode(record.InspectionMode));
    document.getElementById("inspectionStartButtonRow").classList.add("d-none");
    document.getElementById("inspectionStartPanel").classList.remove("d-none");
    document.getElementById("inspectionFormPanel").classList.remove("d-none");
    await populateInspectionParameters(record);
    showInspectionEditorTab(initialTab || "checklist");
    const canDeleteVoidedInspection = isVoidedServerRecord;
    const canDeleteConflictInspection = record.SyncStatus === "CONFLICT";
    const canDeleteDraft = canDeleteVoidedInspection || canDeleteConflictInspection || (!currentInspectionReadOnly &&
        record.Status === "DRAFT" && record.SyncStatus !== "SYNCED" &&
        record.SyncStatus !== "CONFLICT" && record.SyncStatus !== "DELETE_PENDING" &&
        inspectionRecords.some(item => item.LocalInspectionID === record.LocalInspectionID));
    document.getElementById("btnDeleteInspectionDraft").classList.toggle("d-none", !canDeleteDraft);
    const canDeleteBatchDraft = isInspectionMapMode(record.InspectionMode) &&
        !currentInspectionReadOnly && record.Status === "DRAFT" &&
        record.SyncStatus !== "SYNCED" && record.SyncStatus !== "CONFLICT" &&
        record.SyncStatus !== "DELETE_PENDING" &&
        !!record.LocalInspectionID;
    const batchDeleteButton = document.getElementById("btnDeleteInspectionBatchDraft");
    if (batchDeleteButton) batchDeleteButton.classList.toggle("d-none", !canDeleteBatchDraft);
    document.getElementById("btnSaveInspectionDraft").classList.toggle("d-none", currentInspectionReadOnly);
    document.getElementById("btnCompleteInspection").classList.toggle("d-none", currentInspectionReadOnly);
    const transactionNo = record.InspectionNo
        ? record.InspectionNo
        : "TEMP-" + String(record.LocalInspectionID || "").replace(/-/g, "").substring(0, 8).toUpperCase();
    const startTime = formatInspectionClock(record.StartDateTime);
    const endTime = formatInspectionClock(record.EndDateTime);
    const technicianId = record.OwnerEmployeeID || record.InspectionOwnerID || "";
    const technicianName = record.TechnicianName ||
        (technicianId === inspectionLogin.employeeid ? inspectionTechnicianName : "");
    const tenantName = await resolveInspectionTenantName(record.TenantID, record.TenantName);
    if (!record.TenantName && tenantName) record.TenantName = tenantName;
    setInspectionFormHeader(transactionNo, [
        (record.InspectionTypeName || "Inspection") + " — " + (record.InspectionTypeDetailName || ""),
        formatInspectionTenantSuiteInfo(record.TenantID, tenantName, record.SuiteNo),
        "Teknisi: " + formatInspectionEmployeeLabel(technicianName, technicianId),
        (record.TemplateNo || "-") + " / v" + (record.TemplateVersion || "-"),
        "Jadwal " + (record.ScheduledTime || "-") + " • " + (formatInspectionDateDMY(record.InspectionDate) || ""),
        startTime + " - " + endTime,
        "Status: " + getInspectionRecordGridStatus(record, record.Status === "DONE").label
    ]);
    renderInspectionApprovalWorkflowCards(record);
    const summaryInput = document.getElementById("txtInspectionSummary");
    if (summaryInput) {
        // This shared field may still carry readOnly=true from the server-submitted detail view.
        // Reset it for the technician form; currentInspectionReadOnly controls actual access.
        summaryInput.readOnly = false;
        summaryInput.value = record.Summary || "";
    }
    const followUpValue = record.FollowUp === "Recommend Follow Up" ? "Recommend Follow Up" : "No Follow Up";
    const existingFollowUpWONo = String(record.FollowUpWONo || "").trim();
    let followUpWONoPanel = document.getElementById("inspectionFollowUpWONoPanel");
    if (existingFollowUpWONo) {
        if (!followUpWONoPanel) {
            followUpWONoPanel = document.createElement("div");
            followUpWONoPanel.id = "inspectionFollowUpWONoPanel";
            followUpWONoPanel.className = "alert alert-success d-flex align-items-center gap-2 mt-3 mb-3";
            followUpWONoPanel.innerHTML = '<i class="bi bi-file-earmark-check-fill fs-5"></i><div><div class="small text-muted">Generated Follow Up WO No.</div><div class="fw-bold" id="inspectionFollowUpWONoValue"></div></div>';
            const followUpPanel = document.getElementById("inspectionFollowUpPanel");
            if (followUpPanel) followUpPanel.insertAdjacentElement("afterend", followUpWONoPanel);
        }
        const woValue = document.getElementById("inspectionFollowUpWONoValue");
        if (woValue) woValue.textContent = existingFollowUpWONo;
        if (followUpWONoPanel) followUpWONoPanel.classList.remove("d-none");
    } else if (followUpWONoPanel) {
        followUpWONoPanel.classList.add("d-none");
    }
    document.getElementById("inspectionFollowUpNo").checked = followUpValue === "No Follow Up";
    document.getElementById("inspectionFollowUpYes").checked = followUpValue === "Recommend Follow Up";
    const followUpSection = document.getElementById("inspectionFollowUpSection");
    followUpSection.innerHTML = '<option value="">Pilih section tujuan...</option>' +
        inspectionFollowUpSections.map(section => '<option value="' + escInspection(section.Code) + '">' +
            escInspection(section.Code + " - " + section.Name) + '</option>').join("");
    followUpSection.value = record.FollowUpSection || "";
    const sectionIcons = { ACON: "bi-fan", COMM: "bi-broadcast", MECH: "bi-gear", ELEC: "bi-lightning-charge", CIVIL: "bi-building", PFIT: "bi-hammer", PHKP: "bi-brush", PSEC: "bi-shield-check" };
    const sectionGroup = document.getElementById("inspectionFollowUpSectionGroup");
    if (sectionGroup) {
        sectionGroup.innerHTML = inspectionFollowUpSections.map(section =>
            '<input type="radio" class="btn-check" name="inspectionFollowUpSectionChoice" id="inspectionFollowUpSection_' + escInspection(section.Code) + '" value="' + escInspection(section.Code) + '"' +
            (String(record.FollowUpSection || "") === section.Code ? ' checked' : '') + (currentInspectionReadOnly ? ' disabled' : '') + '>' +
            '<label class="btn btn-outline-primary rounded-3 inspection-followup-section-btn" for="inspectionFollowUpSection_' + escInspection(section.Code) + '">' +
            '<i class="bi ' + sectionIcons[section.Code] + '"></i><div class="fw-semibold">' + escInspection(section.Code) + '</div><small class="text-muted">' + escInspection(section.Name) + '</small></label>'
        ).join("");
        sectionGroup.querySelectorAll('input[name="inspectionFollowUpSectionChoice"]').forEach(radio => radio.addEventListener("change", () => {
            followUpSection.value = radio.value;
            scheduleInspectionAutosave();
        }));
    }
    const followUpRemarkInput = document.getElementById("txtInspectionFollowUpRemark");
    followUpRemarkInput.readOnly = false;
    followUpRemarkInput.value = record.FollowUpRemark || "";
    document.querySelectorAll('input[name="inspectionFollowUp"]').forEach(input => input.disabled = currentInspectionReadOnly);
    followUpSection.disabled = currentInspectionReadOnly;
    document.getElementById("txtInspectionFollowUpRemark").disabled = currentInspectionReadOnly;
    updateInspectionFollowUpPanel();

    const template = record.TemplateSnapshot || {};
    const summaryTemplate = inspectionTemplates.find(x =>
        Number(x.IDTemplate) === Number(record.IDTemplate) &&
        Number(x.IDVersion) === Number(record.IDVersion)
    ) || {};
    const summarySampleText = template.SummarySampleText || template.summarySampleText ||
        (template.VersionInfo && template.VersionInfo.SummarySampleText) ||
        summaryTemplate.SummarySampleText || summaryTemplate.summarySampleText || "";
    if (summaryInput) summaryInput.placeholder = summarySampleText;
    const savedItems = record.Items || [];
    const host = document.getElementById("inspectionChecklistHost");
    const reasonVoidPanel = String(record.ReasonVoid || "").trim()
        ? '<div class="accordion-item mt-3 border-danger">' +
            '<div class="accordion-header">' +
                '<div class="accordion-button bg-danger text-white">' +
                    '<i class="bi bi-x-circle-fill me-2"></i> REASON VOID' +
                '</div>' +
            '</div>' +
            '<div class="accordion-body p-3">' +
                '<textarea class="form-control form-control-sm" disabled rows="4">' +
                    escInspection(record.ReasonVoid) +
                '</textarea>' +
            '</div>' +
          '</div>'
        : "";
    host.innerHTML = renderInspectionSections(template, savedItems, currentInspectionReadOnly, "inspectionSection");


    document.getElementById("btnSaveInspectionDraft").classList.toggle("d-none", currentInspectionReadOnly);
    document.getElementById("btnCompleteInspection").classList.toggle("d-none", currentInspectionReadOnly);
    updateInspectionRemarkPanels();
    const summaryCounter = document.getElementById("inspectionSummaryCounter");
    if (summaryCounter) summaryCounter.textContent = String((record.Summary || "").length) + " / 500";
    const followUpCounter = document.getElementById("inspectionFollowUpRemarkCounter");
    if (followUpCounter) followUpCounter.textContent = String((record.FollowUpRemark || "").length) + " / 300";
    await renderInspectionPhotos();
    await updateInspectionChecklistGate();
    // Keep REASON VOID outside inspectionChecklistHost and place it after the full Summary panel.
    const summaryPanel = document.getElementById("inspectionSummaryPanel");
    if (summaryPanel && reasonVoidPanel) {
        const existingReasonVoid = document.getElementById("inspectionReasonVoidPanel");
        if (existingReasonVoid) existingReasonVoid.remove();
        const reasonVoidElement = document.createElement("div");
        reasonVoidElement.innerHTML = reasonVoidPanel;
        const reasonVoidNode = reasonVoidElement.firstElementChild;
        if (reasonVoidNode) {
            reasonVoidNode.id = "inspectionReasonVoidPanel";
            summaryPanel.insertAdjacentElement("afterend", reasonVoidNode);
        }
    }
    if (typeof window.mountInspectionBatchSummary === "function")
        window.mountInspectionBatchSummary(record);
}

function updateInspectionFollowUpPanel() {
    const selected = document.querySelector('input[name="inspectionFollowUp"]:checked');
    const recommend = !!selected && selected.value === "Recommend Follow Up";
    document.getElementById("inspectionFollowUpDetails").classList.toggle("d-none", !recommend);
    if (!recommend) {
        document.getElementById("inspectionFollowUpSection").value = "";
        document.querySelectorAll('input[name="inspectionFollowUpSectionChoice"]').forEach(radio => radio.checked = false);
        document.getElementById("txtInspectionFollowUpRemark").value = "";
    }
}

function collectInspectionFollowUp() {
    if (!inspectionTemplateRequiresFollowUp(currentInspectionRecord && currentInspectionRecord.TemplateSnapshot))
        return { FollowUp: "No Follow Up", FollowUpSection: "", FollowUpRemark: "" };
    const selected = document.querySelector('input[name="inspectionFollowUp"]:checked');
    const followUp = selected ? selected.value : "No Follow Up";
    return {
        FollowUp: followUp,
        FollowUpSection: followUp === "Recommend Follow Up" ? document.getElementById("inspectionFollowUpSection").value : "",
        FollowUpRemark: followUp === "Recommend Follow Up" ? document.getElementById("txtInspectionFollowUpRemark").value.trim() : ""
    };
}

function updateInspectionRemarkPanels() {
    document.querySelectorAll("#inspectionChecklistHost .inspection-item[data-item-id]").forEach(function(container) {
        const options = String(container.dataset.remarkOptions || "").split(";").map(x => x.trim()).filter(Boolean);
        const selected = container.querySelector('[data-role="value"][type="radio"]:checked');
        const optionRequires = container.dataset.itemType === "OPTION" && !!selected && options.includes(String(selected.value).trim());
        const versionRemark1Enabled = container.dataset.remark1VersionEnabled === "1";
        const versionRemark2Enabled = container.dataset.remark2VersionEnabled === "1";
        const isBatchRemarkMode = isInspectionMapMode(currentInspectionRecord && currentInspectionRecord.InspectionMode);
        const baseRemark1Required = container.dataset.remark1BaseRequired === "1";
        const baseRemark2Required = container.dataset.remark2BaseRequired === "1";
        // Batch snapshot item flags are already ANDed with the template-version flag by the server.
        // Do not gate those required item flags a second time; standard inspections keep legacy gating.
        const showRemark1 = (isBatchRemarkMode && baseRemark1Required) ||
            (versionRemark1Enabled && (baseRemark1Required || optionRequires));
        const showRemark2 = (isBatchRemarkMode && baseRemark2Required) ||
            (versionRemark2Enabled && (baseRemark2Required || optionRequires));
        const wrap = container.querySelector('[data-role="remark1-wrap"]');
        const input = container.querySelector('[data-role="remark1"]');
        const wrap2 = container.querySelector('[data-role="remark2-wrap"]');
        const input2 = container.querySelector('[data-role="remark2"]');
        if (wrap) {
            wrap.style.display = showRemark1 ? "" : "none";
            const label = wrap.querySelector("label");
            if (label) label.textContent =
                (optionRequires && container.dataset.remark1BaseRequired !== "1"
                    ? (container.dataset.remark1VersionText || "Remark")
                    : (container.dataset.remark1ItemText || "Remark")) +
                (showRemark1 && (container.dataset.remark1Mandatory === "1" || optionRequires) ? " (wajib)" : "");
        }
        if (input) input.required = showRemark1 && (container.dataset.remark1Mandatory === "1" || optionRequires);
        if (wrap2) {
            wrap2.style.display = showRemark2 ? "" : "none";
            const label2 = wrap2.querySelector("label");
            if (label2) label2.textContent =
                (optionRequires && container.dataset.remark2BaseRequired !== "1"
                    ? (container.dataset.remark2VersionText || "Remark")
                    : (container.dataset.remark2ItemText || "Remark")) +
                (showRemark2 && (container.dataset.remark2Mandatory === "1" || optionRequires) ? " (wajib)" : "");
        }
        if (input2) input2.required = showRemark2 && (container.dataset.remark2Mandatory === "1" || optionRequires);
    });
}

function renderInspectionSections(template, savedItems, readOnly, idPrefix) {
    if (!template || !Array.isArray(template.sections) || !template.sections.length) {
        return '<div class="alert alert-warning small">Struktur checklist template tidak tersedia pada record ini.</div>';
    }
    const prefix = idPrefix || "inspectionSection";
    const navPrefix = "inspectionNav_" + prefix.replace(/[^a-zA-Z0-9_-]/g, "_");
    const navTabs = template.sections.map((section, sectionIndex) => {
        const targetId = navPrefix + "_" + sectionIndex;
        const label = section.sectionName || section.SectionName || ("Section " + (sectionIndex + 1));
        return '<a class="inspection-section-tab' + (sectionIndex === 0 ? ' active' : '') + '" href="#' + targetId +
            '" title="' + escInspection(label) + '" style="scroll-margin-top:120px" onclick="handleInspectionSectionNav(event, this)">' +
            escInspection(label) + '</a>';
    }).join("");
    const navDropdown = template.sections.map((section, sectionIndex) => {
        const targetId = navPrefix + "_" + sectionIndex;
        const label = section.sectionName || section.SectionName || ("Section " + (sectionIndex + 1));
        return '<li><a class="dropdown-item inspection-section-dropdown-item' + (sectionIndex === 0 ? ' active' : '') +
            '" href="#' + targetId + '" onclick="handleInspectionSectionNav(event, this)">' +
            (sectionIndex + 1) + '. ' + escInspection(label) + '</a></li>';
    }).join("");
    const navHtml = '<div class="inspection-section-nav d-flex align-items-center gap-2 mb-3 p-2 bg-body border rounded shadow-sm">' +
        '<div class="inspection-section-nav-tabs flex-grow-1"><div class="d-inline-flex">' + navTabs + '</div></div>' +
        '<div class="dropdown flex-shrink-0"><button type="button" class="btn btn-outline-secondary rounded-circle p-0 d-flex align-items-center justify-content-center" ' +
        'data-bs-toggle="dropdown" data-bs-boundary="viewport" aria-label="Pilih section checklist" title="Pilih section checklist" style="width:34px;height:34px">' +
        '<i class="bi bi-list text-primary"></i></button><ul class="dropdown-menu dropdown-menu-end shadow border-0">' + navDropdown + '</ul></div></div>';
    wireInspectionSectionNavigation();
    const sectionsHtml = template.sections.map((section, sectionIndex) => {
        const items = section.items || [];
        const subsectionGroups = new Map();
        items.forEach(item => {
            const subId = Number(item.idSubSection || item.IDSubSection || 0);
            if (subId > 0) {
                if (!subsectionGroups.has(subId)) subsectionGroups.set(subId, []);
                subsectionGroups.get(subId).push(item);
            }
        });
        const elements = [];
        items.filter(item => !Number(item.idSubSection || item.IDSubSection || 0))
            .forEach(item => elements.push({
                type: "item",
                order: Number(item.itemOrder || item.DisplayOrder || 0),
                item
            }));
        subsectionGroups.forEach((groupItems, subId) => {
            const first = groupItems[0];
            elements.push({
                type: "subsection",
                order: Number(first.subSectionOrder || first.SubSectionOrder || 0),
                name: first.subSectionName || first.SubSectionName || "Sub-section",
                subId: subId,
                items: groupItems.sort((a, b) =>
                    Number(a.itemOrder || a.DisplayOrder || 0) - Number(b.itemOrder || b.DisplayOrder || 0))
            });
        });
        elements.sort((a, b) => a.order - b.order);
        const sectionCollapseId = prefix + "_" + String(section.idSection || section.IDSection || sectionIndex).replace(/[^a-zA-Z0-9_-]/g, "_") + "_" + sectionIndex;
        const contentHtml = elements.map(element => {
            if (element.type === "subsection") {
                const subsectionCollapseId = sectionCollapseId + "_sub_" + String(element.subId).replace(/[^a-zA-Z0-9_-]/g, "_");
                return '<div class="inspection-subsection-heading border rounded mb-2">' +
                    '<button type="button" class="btn btn-light text-start w-100 fw-semibold text-secondary" data-bs-toggle="collapse" data-bs-target="#' + subsectionCollapseId + '" aria-expanded="true" aria-controls="' + subsectionCollapseId + '">' +
                    '<i class="bi bi-folder2-open me-2"></i>' + escInspection(element.name) + '<i class="bi bi-chevron-down float-end"></i></button>' +
                    '<div id="' + subsectionCollapseId + '" class="collapse show px-2 pb-2">' +
                    element.items.map(item => renderInspectionItem(item, savedItems, readOnly, prefix === "inspectionApprovalSection" ? "approval" : "inspection")).join("") +
                    '</div></div>';
            }
            return renderInspectionItem(element.item, savedItems, readOnly, prefix === "inspectionApprovalSection" ? "approval" : "inspection");
        }).join("");
        const sectionTargetId = navPrefix + "_" + sectionIndex;
        return '<section id="' + sectionTargetId + '" class="inspection-checklist-section mb-4 border rounded p-2" style="scroll-margin-top:120px">' +
            '<button type="button" class="btn btn-light text-start w-100 fw-bold mb-2" data-bs-toggle="collapse" data-bs-target="#' + sectionCollapseId + '" aria-expanded="true" aria-controls="' + sectionCollapseId + '">' +
            (sectionIndex + 1) + '. ' + escInspection(section.sectionName || section.SectionName || "Checklist") + '<i class="bi bi-chevron-down float-end"></i></button>' +
            '<div id="' + sectionCollapseId + '" class="collapse show">' + contentHtml + '</div></section>';
    }).join("");
    if (prefix === "inspectionSection" || prefix === "serverSubmittedInspectionSection" || prefix === "inspectionApprovalSection") {
        const isApproval = prefix === "inspectionApprovalSection";
        const navHostId = isApproval ? "inspectionApprovalSectionNavHost" : "inspectionSectionNavHost";
        const navHost = document.getElementById(navHostId);
        if (navHost) {
            navHost.innerHTML = navHtml;
            navHost.classList.toggle("d-none", isApproval
                ? !document.getElementById("inspectionApprovalChecklistTab").classList.contains("active")
                : (document.getElementById("btnInspectionMapTab").classList.contains("active") ||
                   document.getElementById("btnInspectionParamTab").classList.contains("active")));
        }
        return sectionsHtml;
    }
    return navHtml + sectionsHtml;
}

function wireInspectionSectionNavigation() {
    if (document.documentElement.dataset.inspectionSectionNavWired) return;
    document.documentElement.dataset.inspectionSectionNavWired = "1";
    window.addEventListener("scroll", updateInspectionSectionNavActive, { passive: true });
}

function handleInspectionSectionNav(event, link) {
    event.preventDefault();
    const targetId = (link.getAttribute("href") || "").slice(1);
    const target = targetId ? document.getElementById(targetId) : null;
    if (!target) return;
    // Account for the sticky detail header so the selected section lands just beneath it.
    target.scrollIntoView({ behavior: "smooth", block: "start" });
    window.setTimeout(() => {
        const stickyHeader = target.closest("#inspectionApprovalDetailPanel")
            ? document.getElementById("inspectionApprovalStickyHeader")
            : document.getElementById("inspectionEditorStickyHeader");
        if (!stickyHeader || !stickyHeader.getClientRects().length) return;
        const targetTop = target.getBoundingClientRect().top;
        const stickyBottom = stickyHeader.getBoundingClientRect().bottom;
        const delta = targetTop - stickyBottom - 8;
        if (Math.abs(delta) > 2) window.scrollBy({ top: delta, behavior: "smooth" });
    }, 220);
    const nav = link.closest(".inspection-section-nav");
    if (nav) {
        nav.querySelectorAll(".inspection-section-tab, .inspection-section-dropdown-item").forEach(item => {
            item.classList.toggle("active", item.getAttribute("href") === "#" + targetId);
        });
        const dropdownButton = nav.querySelector('[data-bs-toggle="dropdown"]');
        if (dropdownButton && window.bootstrap && bootstrap.Dropdown) {
            const dropdown = bootstrap.Dropdown.getInstance(dropdownButton);
            if (dropdown) dropdown.hide();
        }
    }
}

function updateInspectionSectionNavActive() {
    const sections = Array.from(document.querySelectorAll(".inspection-checklist-section"))
        .filter(section => section.getClientRects().length > 0);
    if (!sections.length) return;
    const stickyHeader = document.getElementById("inspectionEditorStickyHeader");
    const approvalStickyHeader = document.getElementById("inspectionApprovalStickyHeader");
    const activeStickyHeader = approvalStickyHeader && approvalStickyHeader.getClientRects().length
        ? approvalStickyHeader
        : stickyHeader;
    const activationLine = activeStickyHeader && activeStickyHeader.getClientRects().length
        ? activeStickyHeader.getBoundingClientRect().bottom + 20
        : 180;
    let currentId = sections[0].id;
    sections.forEach(section => {
        if (section.getBoundingClientRect().top <= activationLine) currentId = section.id;
    });
    document.querySelectorAll(".inspection-section-nav").forEach(nav => {
        nav.querySelectorAll(".inspection-section-tab, .inspection-section-dropdown-item").forEach(item => {
            item.classList.toggle("active", item.getAttribute("href") === "#" + currentId);
        });
    });
}

function renderInspectionItem(item, savedItems, readOnly, idPrefix) {
    if (!document.documentElement.dataset.inspectionRepeatActionsWired) {
        document.documentElement.dataset.inspectionRepeatActionsWired = "1";
        document.addEventListener("click", function(event) {
            const button=event.target.closest("[data-inspection-repeat-action]");
            if(!button)return;
            const host=button.closest(".inspection-item");
            if(!host)return;
            const rows=Array.from(host.querySelectorAll(".inspection-repeat-object"));
            const min=Number(button.dataset.minCount||0);
            const max=button.dataset.maxCount===""?Number.MAX_SAFE_INTEGER:Number(button.dataset.maxCount);
            if(button.dataset.inspectionRepeatAction==="add"){
                if(rows.length>=max)return;
                if(!rows.length){
                    const itemId=Number(host.dataset.itemId);
                    const templateItem=findInspectionTemplateItem(itemId);
                    if(!templateItem)return;
                    const savedItems=[{
                        IDItem:itemId,
                        Value:"",
                        Remark1:host.querySelector('[data-role="remark1"]')?.value||"",
                        Remark2:host.querySelector('[data-role="remark2"]')?.value||"",
                        RepeatValues:[{ObjectIndex:0,Values:{}}]
                    }];
                    const holder=document.createElement("div");
                    holder.innerHTML=renderInspectionItem(templateItem,savedItems,false,"inspection");
                    const replacement=holder.firstElementChild;
                    if(replacement)host.replaceWith(replacement);
                    return;
                }
                const clone=rows[rows.length-1].cloneNode(true);
                const nextIndex=rows.length;
                clone.dataset.objectIndex=String(nextIndex);
                const heading=clone.querySelector(".inspection-repeat-object-title");
                if(heading)heading.textContent=String(heading.dataset.label||"Object")+" "+(nextIndex+1);
                clone.querySelectorAll("input,select,textarea").forEach(input=>{if(input.tagName==="SELECT")input.selectedIndex=0;else input.value="";});
                button.closest(".inspection-repeat-actions").before(clone);
            } else if(button.dataset.inspectionRepeatAction==="remove" && rows.length>min) {
                rows[rows.length-1].remove();
            }
            const actions=host.querySelector(".inspection-repeat-actions");
            if(actions){
                const remaining=host.querySelectorAll(".inspection-repeat-object").length;
                let removeButton=actions.querySelector('[data-inspection-repeat-action="remove"]');
                if(remaining>min && !removeButton){
                    removeButton=document.createElement("button");
                    removeButton.type="button"; removeButton.className="btn btn-sm btn-outline-secondary";
                    removeButton.dataset.inspectionRepeatAction="remove";
                    removeButton.dataset.minCount=String(min); removeButton.dataset.maxCount=String(max);
                    removeButton.textContent="Remove last"; actions.appendChild(removeButton);
                } else if(remaining<=min && removeButton) removeButton.remove();
            }
        });
    }
    const saved = savedItems.find(x => Number(x.IDItem) === Number(item.idItem)) || {};
    const type = String(item.type || "").toUpperCase();
    const id = Number(item.idItem);
    const controlPrefix = idPrefix || "inspection";
    const disabled = readOnly ? " disabled" : "";
    const required = item.isValueRequired ? " required" : "";
    let control = "";

    if (type === "OPTION") {
        const options = String(item.optionList || "").split(";").map(x => x.trim()).filter(Boolean);
        control = '<div class="inspection-option-list d-flex flex-wrap gap-2" data-role="option-list">' + options.map((option, index) => {
            const optionId = controlPrefix + "_opt_" + id + "_" + index;
            return '<input class="btn-check" type="radio" data-role="value" name="' + controlPrefix + "_opt_" + id + '" id="' + optionId + '" value="' + escInspection(option) + '"' +
                (String(saved.Value || "") === option ? " checked" : "") + disabled + required + '><label class="btn btn-outline-primary inspection-option-choice" for="' + optionId + '">' + escInspection(option) + '</label>';
        }).join("") + '</div>';
    } else if (type === "REPEAT") {
        const cfg=item.repeat||{};
        const fields=Array.isArray(item.repeatFields)?item.repeatFields:[];
        const mode=String(cfg.repeatMode||"FIELDS").toUpperCase();
        const savedObjects=Array.isArray(saved.RepeatValues)?saved.RepeatValues:[];
        const configuredMin=cfg.minCount==null?0:Math.max(0,Number(cfg.minCount));
        let count=mode==="FIELDS"?1:(String(cfg.countMode||"FLEX").toUpperCase()==="FIXED"?Number(cfg.fixedCount||1):Math.max(configuredMin,savedObjects.length));
        if(mode==="OBJECTS"&&cfg.maxCount)count=Math.min(count,Number(cfg.maxCount));
        const objects=[];
        for(let oi=0;oi<count;oi++){
            const old=savedObjects.find(x=>Number(x.ObjectIndex)===oi);
            const objectValues=old&&old.Values?old.Values:{};
            let lastGroup="";
            const fieldHtml=fields.map(field=>{
                const key=String(field.idRepeat||field.IDRepeat||"");
                const label=String(field.fieldLabel||field.FieldLabel||key);
                const group=String(field.groupName||field.GroupName||"");
                const heading=group&&group!==lastGroup?'<div class="col-12 mt-2 small fw-bold text-secondary" style="flex:0 0 100%;width:100%;max-width:100%">'+escInspection(group)+'</div>':"";
                lastGroup=group;
                const fieldValue=objectValues[key]==null?"":objectValues[key];
                const fieldRequired=(field.isRequired||field.IsRequired)?' required aria-required="true"':"";
                let input="";
                if(String(field.fieldType||field.FieldType||"").toUpperCase()==="OPTION"){
                    const rawOptions=field.optionList!=null?field.optionList:field.OptionList;
                    const options=Array.isArray(rawOptions)?rawOptions:String(rawOptions||"").split(";");
                    input='<select class="form-select form-select-sm" data-role="repeat-value" data-repeat-id="'+escInspection(key)+'"'+fieldRequired+disabled+'><option value="">-- Select --</option>'+options.map(option=>'<option value="'+escInspection(option)+'" '+(String(fieldValue)===String(option)?"selected":"")+'>'+escInspection(option)+'</option>').join("")+'</select>';
                }else{
                    const textType=String(field.fieldType||field.FieldType||"").toUpperCase()==="TEXT";
                    const minValue=field.min!=null?field.min:field.MinValue;
                    const maxValue=field.max!=null?field.max:field.MaxValue;
                    const minInclusive=field.minInclusive!==undefined?field.minInclusive!==false:field.MinInclusive!==false;
                    const maxInclusive=field.maxInclusive!==undefined?field.maxInclusive!==false:field.MaxInclusive!==false;
                    const constraints=(minValue!=null?' data-min-value="'+escInspection(minValue)+'" data-min-inclusive="'+(minInclusive?'1':'0')+'"':'')+
                        (maxValue!=null?' data-max-value="'+escInspection(maxValue)+'" data-max-inclusive="'+(maxInclusive?'1':'0')+'"':'');
                    input='<input type="'+(textType?"text":"number")+'" '+(textType?'maxlength="500"':'step="any"'+constraints)+' class="form-control form-control-sm" data-role="repeat-value" data-repeat-id="'+escInspection(key)+'" value="'+escInspection(fieldValue)+'"'+fieldRequired+disabled+'>';
                }
                return heading+'<div class="'+(mode==="FIELDS"?'col':'col-12 col-md-6')+'"><label class="inspection-muted">'+escInspection(label+((field.unit||field.Unit)?" ("+(field.unit||field.Unit)+")":""))+'</label>'+input+'</div>';
            }).join("");
            objects.push('<div class="inspection-repeat-object border rounded p-2 mb-2" data-object-index="'+oi+'">'+(mode==="OBJECTS"?'<div class="small fw-semibold mb-2 inspection-repeat-object-title" data-label="'+escInspection(cfg.objectLabel||"Object")+'">'+escInspection((cfg.objectLabel||"Object")+" "+(oi+1))+'</div>':"")+'<div class="row g-2 '+(mode==="FIELDS"?'row-cols-1 row-cols-md-'+Math.max(1,Math.min(6,Number(cfg.columnCount||3))):'')+'">'+fieldHtml+'</div></div>');
        }
        control=objects.join("");
        if(mode==="OBJECTS" && String(cfg.countMode||"FLEX").toUpperCase()==="FLEX" && !readOnly){
            const minCount=Number(cfg.minCount||0), maxCount=cfg.maxCount==null?"":Number(cfg.maxCount);
            control+='<div class="inspection-repeat-actions d-flex gap-2 mb-2"><button type="button" class="btn btn-sm btn-outline-primary" data-inspection-repeat-action="add" data-min-count="'+minCount+'" data-max-count="'+maxCount+'">+ Add '+escInspection(cfg.objectLabel||"Object")+'</button>'+(count>minCount?'<button type="button" class="btn btn-sm btn-outline-secondary" data-inspection-repeat-action="remove" data-min-count="'+minCount+'" data-max-count="'+maxCount+'">Remove last</button>':"")+'</div>';
        }
    } else if (type === "GROUP") {
        const values = saved.Values || {};
        const groups = item.groups || [];
        control = groups.map(group => {
            const fields = String(group.fieldList || "").split(";").map(x => x.trim()).filter(Boolean);
            return '<div class="mb-2 inspection-group-value-set" data-group-name="' +
                escInspection(group.groupName || "Values") + '"><div class="small fw-semibold mb-1">' +
                escInspection(group.groupName || "Values") + '</div><div class="row g-2">' +
                fields.map(field => '<div class="col-6 col-md-4"><label class="inspection-muted">' +
                    escInspection(field + (group.unit ? " (" + group.unit + ")" : "")) +
                    '</label><input type="number" step="any" class="form-control form-control-sm" data-role="group-value" data-field="' +
                    escInspection(field) + '" value="' + escInspection(values[field] == null ? "" : values[field]) +
                    '"' + disabled + '></div>').join("") +
                '</div></div>';
        }).join("");
    } else if (type === "TEXT") {
        control = '<input type="text" maxlength="50" data-role="value" class="form-control form-control-sm" value="' +
            escInspection(saved.Value == null ? "" : saved.Value) + '"' + disabled + required + '>';
    } else if (type === "RANGE") {
        const hint = item.min != null || item.max != null
            ? '<div class="inspection-muted mb-1">Rentang acuan: ' + escInspection(item.min == null ? "-" : item.min) +
              ' sampai ' + escInspection(item.max == null ? "-" : item.max) + (item.showUnitInRange && item.unit ? " " + escInspection(item.unit) : "") + '</div>'
            : "";
        control = hint + '<div class="input-group input-group-sm"><input type="number" step="any" data-role="value" class="form-control" value="' +
            escInspection(saved.Value == null ? "" : saved.Value) + '"' + disabled + required + '>' +
            (item.unit ? '<span class="input-group-text">' + escInspection(item.unit) + '</span>' : "") + '</div>';
    } else {
        control = '<div class="input-group input-group-sm"><input type="' +
            ((item.unit || item.min != null || item.max != null) ? "number" : "text") +
            '" step="any" data-role="value" class="form-control" value="' +
            escInspection(saved.Value == null ? "" : saved.Value) + '"' + disabled + required + '>' +
            (item.unit ? '<span class="input-group-text">' + escInspection(item.unit) + '</span>' : "") + '</div>';
    }

    const rawRemarkOptions = item.remarkRequiredOptions || item.RemarkRequiredOptions || [];
    const remarkOptions = Array.isArray(rawRemarkOptions) ? rawRemarkOptions.map(x => String(x).trim()) :
        String(rawRemarkOptions || "").split(";").map(x => x.trim()).filter(Boolean);
    const selectedOptionRequiresRemark = type === "OPTION" && remarkOptions.includes(String(saved.Value || "").trim());
    const versionRemark1Enabled = isInspectionVersionRemarkEnabled(item, 1);
    const versionRemark2Enabled = isInspectionVersionRemarkEnabled(item, 2);
    const itemRemark1Required = isInspectionFlagEnabled(item.isRemark1Required != null ? item.isRemark1Required : item.IsRemark1Required, false);
    const itemRemark2Required = isInspectionFlagEnabled(item.isRemark2Required != null ? item.isRemark2Required : item.IsRemark2Required, false);
    const itemRemark1Mandatory = isInspectionFlagEnabled(item.isRemark1Mandatory != null ? item.isRemark1Mandatory : item.IsRemark1Mandatory, false);
    const itemRemark2Mandatory = isInspectionFlagEnabled(item.isRemark2Mandatory != null ? item.isRemark2Mandatory : item.IsRemark2Mandatory, false);
    const itemRemark1Text = itemRemark1Required ? (item.remark1Text || item.Remark1Text || "Remark") : "";
    const itemRemark2Text = itemRemark2Required ? (item.remark2Text || item.Remark2Text || "Remark") : "";
    const versionRemark1Text = versionRemark1Enabled ? (item.versionRemark1Text || item.VersionRemark1Text || "Remark") : "";
    const versionRemark2Text = versionRemark2Enabled ? (item.versionRemark2Text || item.VersionRemark2Text || "Remark") : "";
    const remark1Text = selectedOptionRequiresRemark && !itemRemark1Required ? versionRemark1Text : itemRemark1Text;
    const remark2Text = selectedOptionRequiresRemark && !itemRemark2Required ? versionRemark2Text : itemRemark2Text;
    const isBatchRemarkMode = isInspectionMapMode(currentInspectionRecord && currentInspectionRecord.InspectionMode);
    // Batch item-level required flags are already version-aware in the server snapshot.
    // Preserve the existing version gate for standard inspections.
    const showRemark1 = (isBatchRemarkMode && itemRemark1Required) ||
        (versionRemark1Enabled && (itemRemark1Required || selectedOptionRequiresRemark));
    const showRemark2 = (isBatchRemarkMode && itemRemark2Required) ||
        (versionRemark2Enabled && (itemRemark2Required || selectedOptionRequiresRemark));
    const renderRemark1 = (isBatchRemarkMode && itemRemark1Required) ||
        (versionRemark1Enabled && (itemRemark1Required || (type === "OPTION" && remarkOptions.length > 0)));
    const renderRemark2 = (isBatchRemarkMode && itemRemark2Required) ||
        (versionRemark2Enabled && (itemRemark2Required || (type === "OPTION" && remarkOptions.length > 0)));
    const remark1 = renderRemark1
        ? '<div class="mt-2" data-role="remark1-wrap" style="' + (showRemark1 ? "" : "display:none;") + '"><label class="inspection-muted">' + escInspection(remark1Text) +
          (showRemark1 && (itemRemark1Mandatory || selectedOptionRequiresRemark) ? ' (wajib)' : '') + '</label><input type="text" maxlength="500" data-role="remark1" class="form-control form-control-sm" value="' +
          escInspection(saved.Remark1 || saved.Remark || "") + '"' + disabled + (showRemark1 && (itemRemark1Mandatory || selectedOptionRequiresRemark) ? ' required' : '') + '></div>'
        : "";
    const remark2 = renderRemark2
        ? '<div class="mt-2" data-role="remark2-wrap" style="' + (showRemark2 ? "" : "display:none;") + '"><label class="inspection-muted">' + escInspection(remark2Text) +
          (showRemark2 && (itemRemark2Mandatory || selectedOptionRequiresRemark) ? ' (wajib)' : '') + '</label><input type="text" maxlength="500" data-role="remark2" class="form-control form-control-sm" value="' +
          escInspection(saved.Remark2 || "") + '"' + disabled + (showRemark2 && (itemRemark2Mandatory || selectedOptionRequiresRemark) ? ' required' : '') + '></div>'
        : "";

    return '<div class="inspection-item' + (saved.IsAnomali ? ' anomaly' : '') + '" data-item-id="' + id + '" data-item-type="' + escInspection(type) +
        '" data-min="' + escInspection(item.min == null ? "" : item.min) +
        '" data-max="' + escInspection(item.max == null ? "" : item.max) +
        '" data-required="' + (item.isValueRequired ? "1" : "0") +
        '" data-remark1-base-required="' + (itemRemark1Required ? "1" : "0") +
        '" data-remark2-base-required="' + (itemRemark2Required ? "1" : "0") +
        '" data-remark1-mandatory="' + (itemRemark1Mandatory ? "1" : "0") +
        '" data-remark2-mandatory="' + (itemRemark2Mandatory ? "1" : "0") +
        '" data-remark1-version-enabled="' + (versionRemark1Enabled ? "1" : "0") +
        '" data-remark2-version-enabled="' + (versionRemark2Enabled ? "1" : "0") +
        '" data-remark-options="' + escInspection(remarkOptions.join(";")) +
        '" data-remark1-item-text="' + escInspection(itemRemark1Text) +
        '" data-remark1-version-text="' + escInspection(versionRemark1Text) +
        '" data-remark2-item-text="' + escInspection(itemRemark2Text) +
        '" data-remark2-version-text="' + escInspection(versionRemark2Text) + '">' +
        '<label class="inspection-item-label">' + escInspection(item.label || ("Item " + id)) + '</label>' +
        control + remark1 + remark2 + '</div>';
}

function collectInspectionItems() {
    const result = [];
    document.querySelectorAll("#inspectionChecklistHost .inspection-item[data-item-id]").forEach((container, index) => {
        const itemId = Number(container.dataset.itemId);
        const type = container.dataset.itemType;
        const valueElement = type === "OPTION" ? container.querySelector('[data-role="value"]:checked') : container.querySelector('[data-role="value"]');
        const values = {};
        container.querySelectorAll('[data-role="group-value"]').forEach(field => {
            values[field.dataset.field] = field.value === "" ? null : field.value;
        });
        const repeatValues=Array.from(container.querySelectorAll(".inspection-repeat-object")).map(objectEl=>{
            const objectValues={};
            objectEl.querySelectorAll("[data-role='repeat-value']").forEach(field=>{objectValues[field.dataset.repeatId]=field.value===""?null:field.value;});
            return {ObjectIndex:Number(objectEl.dataset.objectIndex||0),Values:objectValues};
        });
        const value = (type === "GROUP" || type === "REPEAT") ? "" : (valueElement ? valueElement.value : "");
        const remark1Element = container.querySelector('[data-role="remark1"]');
        const remark2Element = container.querySelector('[data-role="remark2"]');
        const remark1 = remark1Element ? remark1Element.value.trim() : "";
        const remark2 = remark2Element ? remark2Element.value.trim() : "";
        const templateItem = findInspectionTemplateItem(itemId);
        let isAnomali = false;
        const numericValue = value === "" ? null : Number(value);
        const useTolerance = !!(templateItem && (
            templateItem.isToleranceRequired === true ||
            templateItem.isToleranceRequired === 1 ||
            templateItem.isToleranceRequired === "1" ||
            templateItem.isToleranceRequired === "true"
        ));
        if (useTolerance && numericValue !== null && !Number.isNaN(numericValue)) {
            const minTolerance = templateItem.mintol == null || String(templateItem.mintol).trim() === ""
                ? NaN : Number(templateItem.mintol);
            const maxTolerance = templateItem.maxtol == null || String(templateItem.maxtol).trim() === ""
                ? NaN : Number(templateItem.maxtol);
            let lowerLimit;
            let upperLimit;
            if (Number.isFinite(minTolerance) && Number.isFinite(maxTolerance)) {
                if (type === "RANGE") {
                    const min = templateItem.min == null || String(templateItem.min).trim() === ""
                        ? NaN : Number(templateItem.min);
                    const max = templateItem.max == null || String(templateItem.max).trim() === ""
                        ? NaN : Number(templateItem.max);
                    if (Number.isFinite(min) && Number.isFinite(max)) {
                        lowerLimit = min - minTolerance;
                        upperLimit = max + maxTolerance;
                    }
                } else if (type === "INPUT") {
                    lowerLimit = minTolerance;
                    upperLimit = maxTolerance;
                }
            }
            if (lowerLimit !== undefined && upperLimit !== undefined) {
                isAnomali = numericValue <= lowerLimit || numericValue >= upperLimit;
            }
        }
        result.push({
            IDItem: itemId,
            ItemLabel: templateItem ? templateItem.label : ("Item " + itemId),
            Type: type,
            Value: value,
            Remark1: remark1,
            Remark2: remark2,
            IsAnomali: isAnomali,
            DisplayOrder: index + 1,
            Values: type === "GROUP" ? values : null,
            RepeatValues: type === "REPEAT" ? repeatValues : null
        });
    });
    return result;
}

function findInspectionTemplateItem(itemId) {
    const template = currentInspectionRecord && currentInspectionRecord.TemplateSnapshot;
    for (const section of ((template && template.sections) || [])) {
        const item = (section.items || []).find(x => Number(x.idItem) === Number(itemId));
        if (item) return item;
    }
    return null;
}

function isInspectionVersionRemarkEnabled(item, remarkNumber) {
    const key = remarkNumber === 1 ? "versionIsRemark1Required" : "versionIsRemark2Required";
    const pascalKey = remarkNumber === 1 ? "VersionIsRemark1Required" : "VersionIsRemark2Required";
    if (item && (item[key] != null || item[pascalKey] != null))
        return isInspectionFlagEnabled(item[key], false) || isInspectionFlagEnabled(item[pascalKey], false);
    const snapshot = currentInspectionRecord && currentInspectionRecord.TemplateSnapshot;
    const versionInfo = snapshot && (snapshot.VersionInfo || snapshot.versionInfo || snapshot);
    const snapshotKey = remarkNumber === 1 ? "IsRemark1Required" : "IsRemark2Required";
    const versionKey = remarkNumber === 1 ? "VersionIsRemark1Required" : "VersionIsRemark2Required";
    const camelKey = snapshotKey.charAt(0).toLowerCase() + snapshotKey.slice(1);
    const camelVersionKey = versionKey.charAt(0).toLowerCase() + versionKey.slice(1);
    if (versionInfo && versionInfo[versionKey] !== undefined)
        return isInspectionFlagEnabled(versionInfo[versionKey], false);
    if (versionInfo && versionInfo[camelVersionKey] !== undefined)
        return isInspectionFlagEnabled(versionInfo[camelVersionKey], false);
    return isInspectionFlagEnabled(versionInfo && (versionInfo[snapshotKey] !== undefined
        ? versionInfo[snapshotKey] : versionInfo[camelKey]), false);
}

function validateInspectionItemsAll(items) {
    const sourceItems = Array.isArray(items) ? items : [];
    const template = currentInspectionRecord && currentInspectionRecord.TemplateSnapshot;
    const templateItems = [];
    (template && Array.isArray(template.sections) ? template.sections : []).forEach(section =>
        (section.items || []).forEach(item => templateItems.push(item)));
    if (!templateItems.length) {
        sourceItems.forEach(answer => {
            const templateItem = findInspectionTemplateItem(answer.IDItem);
            if (templateItem) templateItems.push(templateItem);
        });
    }
    const errors = [];
    const answers = new Map(sourceItems.map(item => [Number(item.IDItem), item]));
    templateItems.forEach(templateItem => {
        const itemId = Number(templateItem.idItem || templateItem.IDItem);
        if (!itemId) return;
        const answer = answers.get(itemId) || {
            IDItem: itemId, ItemLabel: templateItem.label || ("Item " + itemId),
            Type: String(templateItem.type || "").toUpperCase(), Value: "", Remark1: "", Remark2: "", Values: {}
        };
        const itemType = String(templateItem.type || answer.Type || "").toUpperCase();
        const label = answer.ItemLabel || templateItem.label || ("Item " + itemId);
        const invalid = (message, role) => errors.push({ message, itemId, role: role || "value" });
        if (itemType === "REPEAT") {
            const cfg=templateItem.repeat||{};
            const fields=Array.isArray(templateItem.repeatFields)?templateItem.repeatFields:[];
            const objects=Array.isArray(answer.RepeatValues)?answer.RepeatValues:[];
            const mode=String(cfg.repeatMode||"FIELDS").toUpperCase();
            if(!fields.length) invalid("REPEAT belum memiliki child field: "+label,"repeat-value");
            if(mode==="FIELDS" && objects.length!==1) invalid("REPEAT FIELDS harus memiliki satu record: "+label,"repeat-value");
            if(mode==="OBJECTS"){
                if(String(cfg.countMode||"FLEX").toUpperCase()==="FIXED" && objects.length!==Number(cfg.fixedCount||0))
                    invalid("Jumlah object "+label+" harus "+cfg.fixedCount,"repeat-value");
                if(cfg.minCount!=null && objects.length<Number(cfg.minCount)) invalid("Jumlah object "+label+" kurang dari minimum","repeat-value");
                if(cfg.maxCount!=null && objects.length>Number(cfg.maxCount)) invalid("Jumlah object "+label+" melebihi maksimum","repeat-value");
            }
            objects.forEach((objectRow,index)=>{
                const values=objectRow&&objectRow.Values?objectRow.Values:{};
                fields.forEach(field=>{
                    const key=String(field.idRepeat||field.IDRepeat||"");
                    const raw=values[key]==null?"":String(values[key]).trim();
                    if((field.isRequired||field.IsRequired) && !raw) invalid((field.fieldLabel||field.FieldLabel||key)+" wajib diisi pada "+label,"repeat-value");
                    if(raw && ["NUMBER","RANGE"].includes(String(field.fieldType||field.FieldType||"").toUpperCase())){
                        const number=Number(raw);
                        if(!Number.isFinite(number)) invalid((field.fieldLabel||key)+" harus berupa angka","repeat-value");
                        const minValue=field.min!=null?field.min:field.MinValue;
                        const maxValue=field.max!=null?field.max:field.MaxValue;
                        const minInclusive=field.minInclusive!==undefined?field.minInclusive!==false:field.MinInclusive!==false;
                        const maxInclusive=field.maxInclusive!==undefined?field.maxInclusive!==false:field.MaxInclusive!==false;
                        if(minValue!=null && (number<Number(minValue) || (!minInclusive && number===Number(minValue))))
                            invalid((field.fieldLabel||field.FieldLabel||key)+" di bawah batas minimum","repeat-value");
                        if(maxValue!=null && (number>Number(maxValue) || (!maxInclusive && number===Number(maxValue))))
                            invalid((field.fieldLabel||field.FieldLabel||key)+" melebihi batas maksimum","repeat-value");
                    }
                    if(raw && String(field.fieldType||field.FieldType||"").toUpperCase()==="OPTION"){
                        const options=Array.isArray(field.optionList)?field.optionList:String(field.optionList||"").split(";");
                        if(!options.some(option=>String(option).trim().toUpperCase()===raw.toUpperCase()))
                            invalid("Option "+(field.fieldLabel||key)+" tidak valid","repeat-value");
                    }
                });
            });
        }
        if (isInspectionFlagEnabled(templateItem.isValueRequired, false)) {
            if (itemType === "GROUP") {
                const groups = templateItem.groups || [];
                if (!groups.length) invalid("GROUP tidak memiliki kolom input: " + label, "group-value");
                groups.forEach(group => {
                    const fields = String(group.fieldList || "").split(";").map(field => field.trim()).filter(Boolean);
                    const filledCount = fields.filter(field => answer.Values && answer.Values[field] != null &&
                        String(answer.Values[field]).trim() !== "").length;
                    if (fields.length > 3)
                        invalid("Maksimal 3 kolom untuk GROUP " + (group.groupName || "") + " pada " + label, "group-value");
                    else if (fields.length < 2 || filledCount < 2)
                        invalid("Minimal 2 kolom harus diisi untuk GROUP " + (group.groupName || "") + " pada " + label, "group-value");
                });
            } else if (itemType === "REPEAT") {
                const hasRepeatValue = (Array.isArray(answer.RepeatValues) ? answer.RepeatValues : []).some(objectRow =>
                    objectRow && objectRow.Values && Object.keys(objectRow.Values).some(key =>
                        objectRow.Values[key] != null && String(objectRow.Values[key]).trim() !== ""));
                if (!hasRepeatValue) invalid("Minimal satu nilai pada REPEAT wajib diisi: " + label, "repeat-value");
            } else if (answer.Value == null || String(answer.Value).trim() === "") {
                invalid((itemType === "OPTION" ? "Pilih salah satu option: " : "Nilai wajib diisi: ") + label, "value");
            }
        }
        const versionInfo = template && (template.VersionInfo || template.versionInfo || template);
        if (itemType === "OPTION" && String(answer.Value || "").trim()) {
            const itemOptions = Array.isArray(templateItem.optionList)
                ? templateItem.optionList
                : String(templateItem.optionList || "").split(";");
            const versionOptions = Array.isArray(versionInfo && versionInfo.StatusOption)
                ? versionInfo.StatusOption
                : String(versionInfo && versionInfo.StatusOption || "").split(";");
            const allowedOptions = itemOptions.map(value => String(value).trim()).filter(Boolean);
            if (!allowedOptions.length && isInspectionFlagEnabled(templateItem.useDefaultOption, false))
                allowedOptions.push.apply(allowedOptions, versionOptions.map(value => String(value).trim()).filter(Boolean));
            if (allowedOptions.length && !allowedOptions.some(value =>
                value.toUpperCase() === String(answer.Value).trim().toUpperCase()))
                invalid("Option '" + answer.Value + "' tidak tersedia di Master Version: " + label, "value");
        }
        const rawRequiredOptionRemarks = templateItem.remarkRequiredOptions || templateItem.RemarkRequiredOptions || [];
        const requiredOptionRemarks = []
            .concat(Array.isArray(rawRequiredOptionRemarks) ? rawRequiredOptionRemarks : String(rawRequiredOptionRemarks || "").split(";"))
            .concat(Array.isArray(versionInfo && versionInfo.RemarkRequiredOptions) ? versionInfo.RemarkRequiredOptions : [])
            .map(value => String(value).trim());
        const selectedOptionRequiresRemark = itemType === "OPTION" &&
            requiredOptionRemarks.includes(String(answer.Value || "").trim());
        const versionRemark1Enabled = isInspectionVersionRemarkEnabled(templateItem, 1);
        const versionRemark2Enabled = isInspectionVersionRemarkEnabled(templateItem, 2);
        const itemRemark1Enabled = isInspectionFlagEnabled(templateItem.isRemark1Required != null ? templateItem.isRemark1Required : templateItem.IsRemark1Required, false);
        const itemRemark2Enabled = isInspectionFlagEnabled(templateItem.isRemark2Required != null ? templateItem.isRemark2Required : templateItem.IsRemark2Required, false);
        const itemRemark1Mandatory = isInspectionFlagEnabled(templateItem.isRemark1Mandatory != null ? templateItem.isRemark1Mandatory : templateItem.IsRemark1Mandatory, false);
        const itemRemark2Mandatory = isInspectionFlagEnabled(templateItem.isRemark2Mandatory != null ? templateItem.isRemark2Mandatory : templateItem.IsRemark2Mandatory, false);
        const remark1Required = versionRemark1Enabled &&
            ((itemRemark1Enabled && itemRemark1Mandatory) || selectedOptionRequiresRemark);
        const remark2Required = versionRemark2Enabled &&
            ((itemRemark2Enabled && itemRemark2Mandatory) || selectedOptionRequiresRemark);
        const remark1Title = selectedOptionRequiresRemark && !itemRemark1Enabled
            ? (templateItem.versionRemark1Text || templateItem.VersionRemark1Text || "Remark")
            : (templateItem.remark1Text || templateItem.Remark1Text || "Remark");
        const remark2Title = selectedOptionRequiresRemark && !itemRemark2Enabled
            ? (templateItem.versionRemark2Text || templateItem.VersionRemark2Text || "Remark")
            : (templateItem.remark2Text || templateItem.Remark2Text || "Remark");
        if (remark1Required && !String(answer.Remark1 || "").trim())
            invalid(remark1Title + " wajib diisi: " + label, "remark1");
        if (remark2Required && !String(answer.Remark2 || "").trim())
            invalid(remark2Title + " wajib diisi: " + label, "remark2");
    });
    return errors;
}
function validateInspectionItems(items) {
    const errors = validateInspectionItemsAll(items);
    return errors.length ? errors[0] : null;
}

function focusInvalidInspectionItem(error) {
    document.querySelectorAll("#inspectionChecklistHost .inspection-validation-error").forEach(el => {
        el.classList.remove("inspection-validation-error", "border", "border-danger", "rounded", "p-2");
    });
    if (!error || !error.itemId) return;
    const item = document.querySelector('#inspectionChecklistHost .inspection-item[data-item-id="' + error.itemId + '"]');
    if (!item) return;
    let parent = item.parentElement;
    while (parent && parent.id !== "inspectionChecklistHost") {
        if (parent.classList.contains("collapse")) {
            parent.classList.add("show");
            const toggle = document.querySelector('[data-bs-target="#' + parent.id + '"]');
            if (toggle) toggle.setAttribute("aria-expanded", "true");
        }
        parent = parent.parentElement;
    }
    const control = error.role === "remark1" ? item.querySelector('[data-role="remark1"]') :
        error.role === "remark2" ? item.querySelector('[data-role="remark2"]') :
        error.role === "group-value" ? item.querySelector('[data-role="group-value"]') :
        error.role === "value" && item.dataset.itemType === "OPTION"
            ? item.querySelector('[data-role="value"]') || item.querySelector(".inspection-option-choice")
            : item.querySelector('[data-role="value"]');
    item.classList.add("inspection-validation-error", "border", "border-danger", "rounded", "p-2");
    if (control) {
        control.classList.add("is-invalid");
        if (control.matches('input[type="radio"]')) {
            const label = item.querySelector('label[for="' + control.id + '"]');
            if (label) label.classList.add("border-danger", "text-danger");
        }
        control.scrollIntoView({ behavior: "smooth", block: "center" });
        if (!control.matches('input[type="radio"]')) {
            window.setTimeout(() => { try { control.focus({ preventScroll: true }); } catch (_) { control.focus(); } }, 250);
        }
    } else item.scrollIntoView({ behavior: "smooth", block: "center" });
}
function getActiveInspectionPoint() {
    if (!currentInspectionRecord || !isInspectionMapMode(currentInspectionRecord.InspectionMode))
        return null;
    const scheduleTime = String(currentInspectionRecord.InspectionMode).toUpperCase() === "LIGHTNING"
        ? String(activeInspectionScheduleTime || currentInspectionRecord.ActiveScheduleTime || "")
        : "";
    return (currentInspectionRecord.Points || []).find(point =>
        Number(point.InspectionPointID) === Number(currentInspectionRecord.ActiveInspectionPointID) &&
        String(point.ScheduleTime || "") === scheduleTime
    ) || null;
}

function getActiveInspectionPointPhotoID() {
    const point = getActiveInspectionPoint();
    return point ? String(point.ClientPointID || "") : "";
}

async function getCurrentInspectionPhotos() {
    if (!currentInspectionRecord) return [];
    return getInspectionPhotos(currentInspectionRecord.LocalInspectionID,
        isInspectionMapMode(currentInspectionRecord.InspectionMode)
            ? getActiveInspectionPointPhotoID() : null);
}

function focusBatchValidationTarget(error) {
    if (!error) return;
    if (error.itemId) {
        focusInvalidInspectionItem(error);
        return;
    }
    const targetMap = {
        "photo-before": "#btnAddInspectionBeforePhoto",
        "photo-after": "#btnAddInspectionAfterPhoto",
        "condition": "#inspectionPointConditionPanel",
        "abnormal-remark": "#inspectionPointConditionPanel textarea",
        "point-complete": "#btnCompleteInspection",
        "summary": "#txtInspectionSummary",
        "followup-section": "#inspectionFollowUpSection",
        "followup-remark": "#txtInspectionFollowUpRemark"
    };
    const selector = targetMap[error.target];
    const target = selector && document.querySelector(selector);
    if (target) {
        target.scrollIntoView({ behavior: "smooth", block: "center" });
        if (target.focus && !target.matches("button")) {
            window.setTimeout(() => { try { target.focus({ preventScroll: true }); } catch (_) { target.focus(); } }, 250);
        }
        if (target.matches("textarea,input,select")) target.classList.add("is-invalid");
        else target.classList.add("inspection-validation-error", "border", "border-danger", "rounded", "p-2");
    }
}

function mountBatchValidationNavigator() {
    const host = document.getElementById("inspectionChecklistHost");
    if (!host || !inspectionBatchValidationState.errors.length || currentInspectionReadOnly) return;
    let nav = document.getElementById("inspectionBatchValidationNavigator");
    if (nav) nav.remove();
    nav = document.createElement("div");
    nav.id = "inspectionBatchValidationNavigator";
    nav.className = "alert alert-warning d-flex flex-wrap align-items-center justify-content-between gap-2 py-2 mb-3";
    nav.innerHTML = '<div class="small"><strong>Mode perbaikan validasi</strong><div class="text-muted" id="inspectionBatchValidationPosition"></div></div>' +
        '<button type="button" class="btn btn-sm btn-outline-primary" id="btnNextBatchValidationIssue"><i class="bi bi-arrow-right-circle me-1"></i>Temuan berikutnya</button>';
    host.insertBefore(nav, host.firstChild);
    const updatePosition = function () {
        const label = document.getElementById("inspectionBatchValidationPosition");
        if (label) label.textContent = (inspectionBatchValidationState.index + 1) + " dari " +
            inspectionBatchValidationState.errors.length + " temuan awal";
    };
    updatePosition();
    const nextIssueButton = nav.querySelector("#btnNextBatchValidationIssue");
    if (nextIssueButton) {
        nextIssueButton.addEventListener("click", async function () {
            await goToNextBatchValidationIssue();
        });
    }
}

async function goToNextBatchValidationIssue() {
    const errors = inspectionBatchValidationState.errors || [];
    if (!errors.length) return;
    const currentPoint = getActiveInspectionPoint();
    if (currentPoint) {
        currentPoint.Items = collectInspectionItems();
        const liveErrors = validateInspectionItemsAll(currentPoint.Items);
        errors.forEach(error => {
            if (Number(error.pointId) === Number(currentPoint.InspectionPointID) && error.itemId) {
                error._resolved = !liveErrors.some(item => Number(item.itemId) === Number(error.itemId) &&
                    String(item.role || "") === String(error.role || ""));
            }
        });
    }
    let nextIndex = inspectionBatchValidationState.index + 1;
    while (nextIndex < errors.length && errors[nextIndex]._resolved) nextIndex++;
    if (nextIndex >= errors.length) {
        showToast("Semua temuan checklist yang sedang dinavigasi sudah diperbaiki. Jalankan validasi ulang untuk memastikan.", "success");
        const nav = document.getElementById("inspectionBatchValidationNavigator");
        if (nav) nav.remove();
        return;
    }
    const nextError = errors[nextIndex];
    const activeId = Number(currentInspectionRecord && currentInspectionRecord.ActiveInspectionPointID || 0);
    if (nextError.pointId && activeId === Number(nextError.pointId)) {
        inspectionBatchValidationState.index = nextIndex;
        focusBatchValidationTarget(nextError);
        const position = document.getElementById("inspectionBatchValidationPosition");
        if (position) position.textContent = (nextIndex + 1) + " dari " + errors.length + " temuan awal";
        return;
    }
    if (currentPoint) await saveBatchInspectionPoint("DRAFT");
    inspectionBatchValidationState.index = nextIndex;
    if (nextError.pointId) {
        const masterPoint = (currentInspectionRecord.BatchMapSetup && currentInspectionRecord.BatchMapSetup.points || [])
            .find(point => Number(point.InspectionPointID) === Number(nextError.pointId));
        if (masterPoint) {
            await openBatchInspectionPointChecklist(masterPoint, nextError);
            return;
        }
    }
    if (typeof window.showInspectionMapWorkspace === "function")
        window.showInspectionMapWorkspace(currentInspectionRecord, true);
    const target = nextError.target === "summary" ? document.getElementById("txtInspectionSummary") :
        nextError.target === "followup-section" ? document.getElementById("inspectionFollowUpSection") :
        nextError.target === "followup-remark" ? document.getElementById("txtInspectionFollowUpRemark") : null;
    if (target) { target.scrollIntoView({ behavior: "smooth", block: "center" }); target.focus(); }
}

async function openBatchInspectionPointChecklist(masterPoint, validationError) {
    if (!currentInspectionRecord || !isInspectionMapMode(currentInspectionRecord.InspectionMode))
        return;
    if (!masterPoint || !masterPoint.InspectionPointID) return;
    const pointReadOnly = currentInspectionReadOnly || currentInspectionRecord.Status === "DONE";
    const scheduleTime = String(currentInspectionRecord.InspectionMode).toUpperCase() === "LIGHTNING"
        ? String(activeInspectionScheduleTime || currentInspectionRecord.ActiveScheduleTime || "")
        : "";

    let point = (currentInspectionRecord.Points || []).find(item =>
        Number(item.InspectionPointID) === Number(masterPoint.InspectionPointID) &&
        String(item.ScheduleTime || "") === scheduleTime);
    if (!point) {
        point = {
            ClientPointID: newInspectionId(),
            InspectionPointID: Number(masterPoint.InspectionPointID),
            ScheduleTime: scheduleTime,
            PointCode: String(masterPoint.PointCode || ""),
            PointName: String(masterPoint.PointName || ""),
            InspectionDateTime: localDateTimeString(new Date()),
            Status: "PENDING",
            PointCondition: "",
            AbnormalRemark: "",
            Items: [],
            NextPhotoSeqNo: 1
        };
        currentInspectionRecord.Points = currentInspectionRecord.Points || [];
        currentInspectionRecord.Points.push(point);
    }

    currentInspectionRecord.ActiveInspectionPointID = Number(masterPoint.InspectionPointID);
    currentInspectionRecord.Items = point.Items || [];
    updateInspectionParameterTabGate();
    const host = document.getElementById("inspectionChecklistHost");
    const pointSheetMount = document.getElementById("inspectionMapPointChecklistMount");
    const formPanel = document.getElementById("inspectionFormPanel");
    const sameMountedPoint = !!(pointSheetMount && formPanel && pointSheetMount.contains(formPanel) &&
        String(formPanel.getAttribute("data-map-point-id") || "") === String(point.InspectionPointID));
    if (!sameMountedPoint) {
        host.innerHTML = renderInspectionSections(
            currentInspectionRecord.TemplateSnapshot,
            point.Items || [],
            pointReadOnly,
            "inspectionSection"
        );
        renderBatchPointCondition(masterPoint, point, pointReadOnly);
    }
    if (formPanel) formPanel.setAttribute("data-map-point-id", String(point.InspectionPointID));
    // Keep the active map point identifiable in the compact mobile header.
    // The transaction info popover is extended with the point identity so the
    // technician can always confirm which plotted location owns this checklist.
    const title = document.getElementById("inspectionFormTitle");
    if (title) {
        title.textContent = point.PointCode || "Inspection Point";
        title.title = [point.PointCode, point.PointName].filter(Boolean).join(" · ");
        title.classList.remove("text-truncate");
    }
    const pointInfoTechnicianId = currentInspectionRecord.OwnerEmployeeID || currentInspectionRecord.InspectionOwnerID || "";
    const pointInfoTechnicianName = currentInspectionRecord.TechnicianName ||
        (pointInfoTechnicianId === inspectionLogin.employeeid ? inspectionTechnicianName : "");
    const pointInfoStartTime = formatInspectionClock(currentInspectionRecord.StartDateTime);
    const pointInfoEndTime = formatInspectionClock(currentInspectionRecord.EndDateTime);
    setInspectionFormInfoPopover([
        "Inspection No: " + (currentInspectionRecord.InspectionNo || "TEMP-" +
            String(currentInspectionRecord.LocalInspectionID || "").replace(/-/g, "").substring(0, 8).toUpperCase()),
        (currentInspectionRecord.InspectionTypeName || "Inspection") + " — " +
            (currentInspectionRecord.InspectionTypeDetailName || ""),
        "Teknisi: " + formatInspectionEmployeeLabel(pointInfoTechnicianName, pointInfoTechnicianId),
        (currentInspectionRecord.TemplateNo || "-") + " / v" + (currentInspectionRecord.TemplateVersion || "-"),
        "Jadwal " + (currentInspectionRecord.ScheduledTime || "-") + " • " +
            (formatInspectionDateDMY(currentInspectionRecord.InspectionDate) || "-"),
        pointInfoStartTime + " - " + pointInfoEndTime,
        "Status: " + getInspectionRecordGridStatus(currentInspectionRecord, currentInspectionRecord.Status === "DONE").label,
        "Point Code: " + (point.PointCode || "—"),
        "Point Description: " + (point.PointName || "—"),
        "Inspection Point ID: " + point.InspectionPointID,
        scheduleTime ? "Schedule: " + scheduleTime : ""
    ]);
    const followUp = document.getElementById("inspectionFollowUpPanel");
    const summary = document.getElementById("inspectionSummaryPanel");
    if (followUp) followUp.classList.add("d-none");
    if (summary) summary.classList.add("d-none");
    const beforePanel = document.querySelector("#btnAddInspectionBeforePhoto")?.closest(".inspection-photo-panel");
    if (beforePanel) beforePanel.querySelector(".fw-bold").textContent = "FIELD DOCUMENTATION BEFORE · " + point.PointCode;
    const afterPanel = document.getElementById("inspectionAfterPhotoPanel");
    if (afterPanel) afterPanel.querySelector(".fw-bold").textContent = "FIELD DOCUMENTATION AFTER · " + point.PointCode;
    const saveButton = document.getElementById("btnSaveInspectionDraft");
    const completeButton = document.getElementById("btnCompleteInspection");
    if (saveButton) {
        saveButton.innerHTML = '<i class="bi bi-save"></i> Save Point';
        saveButton.classList.toggle("d-none", pointReadOnly);
    }
    if (completeButton) {
        completeButton.innerHTML = '<i class="bi bi-check-circle"></i> Complete Point';
        completeButton.classList.toggle("d-none", pointReadOnly);
    }
    document.getElementById("inspectionFormPanel").classList.remove("d-none");
    await renderInspectionPhotos();
    await updateInspectionChecklistGate();
    mountBatchValidationNavigator();
    // Batch/Lightning point selection is map-first on every viewport size.
    // Keep the map visible behind the checklist dialog instead of forcing a
    // desktop tab switch; this also makes a PATH click behave the same as a
    // Point List click and a mobile map click.
    if (typeof window.showInspectionMapPointChecklistSheet === "function") {
        window.showInspectionMapPointChecklistSheet(point);
        if (validationError) window.setTimeout(() => focusBatchValidationTarget(validationError), 180);
        return;
    }
    const mapWorkspace = document.getElementById("inspectionMapWorkspace");
    if (mapWorkspace) mapWorkspace.classList.add("d-none");
    const mapTab = document.getElementById("btnInspectionMapTab");
    const checklistTab = document.getElementById("btnInspectionChecklistTab");
    if (mapTab) mapTab.classList.remove("active");
    if (checklistTab) checklistTab.classList.add("active");
    showInspectionEditorTab("checklist");
    if (validationError) window.setTimeout(() => focusBatchValidationTarget(validationError), 180);
    // Opening a map point is navigation only. The point and its parent batch
    // remain in memory until the user explicitly presses Save Point / Save Draft.
}

window.openBatchInspectionPointChecklist = openBatchInspectionPointChecklist;

let inspectionPointNavigatorState = {
    baseRecord: null, detail: null, setup: null, record: null, selectedMapId: "",
    scheduleTime: "", activeScheduleTime: "", scheduleTimes: [], allMapsRequested: false, keyword: "",
    statusFilter: "all", optionFilter: "", page: 1, pageSize: 20,
    returnScrollTop: 0, returnPointId: 0, restoreNavigatorPosition: false
};
let inspectionPointNavigatorLoadSequence = 0;

function getInspectionPointNavigatorDetails(record) {
    // The Navigator is intentionally broader than the currently selected
    // template detail: show every Inspection Detail belonging to this
    // Inspection Type and company/location so its maps can be browsed too.
    return inspectionDetails.filter(detail =>
        String(detail.InspectionTypeCode || "") === String(record.InspectionTypeCode || "") &&
        (!detail.CompanyID || String(detail.CompanyID) === String(record.CompanyID || "")) &&
        (!detail.LocationID || String(detail.LocationID) === String(record.LocationID || ""))
    ).sort((a, b) => String(a.InspectionTypeDetailName || a.InspectionTypeDetailCode || "")
        .localeCompare(String(b.InspectionTypeDetailName || b.InspectionTypeDetailCode || "")));
}

async function getInspectionPointNavigatorSetup(record, detail) {
    const key = String(detail.InspectionTypeDetailCode || "").trim().toUpperCase();
    if (String(record.InspectionTypeDetailCode || "").trim().toUpperCase() === key &&
        record.BatchMapSetup && Array.isArray(record.BatchMapSetup.points))
        return record.BatchMapSetup;

    const type = inspectionTypes.find(item =>
        String(item.InspectionTypeCode || "") === String(record.InspectionTypeCode || ""));
    if (!type) throw new Error("Inspection Type tidak ditemukan pada cache perangkat.");
    type.BatchMapSetups = type.BatchMapSetups || {};
    let setup = type.BatchMapSetups[key] || null;
    if (setup && setup.success === true && Array.isArray(setup.points)) return setup;
    if (!navigator.onLine)
        throw new Error("Map untuk detail ini belum tersimpan offline. Jalankan Sync saat online terlebih dahulu.");

    const response = await fetch("inspection.aspx/GetBatchInspectionMap", {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=utf-8" },
        body: JSON.stringify({
            inspectionTypeCode: record.InspectionTypeCode,
            inspectionTypeDetailCode: detail.InspectionTypeDetailCode,
            employeeId: inspectionLogin.employeeid,
            companyId: record.CompanyID,
            locationId: record.LocationID
        })
    });
    const payload = await response.json();
    if (!response.ok)
        throw new Error((payload && (payload.Message || payload.ExceptionMessage)) || "Gagal memuat Inspection Map.");
    setup = payload && Object.prototype.hasOwnProperty.call(payload, "d") ? payload.d : payload;
    if (!setup || setup.success !== true || !Array.isArray(setup.points))
        throw new Error("Data Inspection Map untuk detail ini tidak valid.");
    type.BatchMapSetups[key] = setup;
    const storeName = db.objectStoreNames.contains("inspection_types_scoped")
        ? "inspection_types_scoped" : "inspection_types";
    try {
        await new Promise((resolve, reject) => {
            const tx = db.transaction(storeName, "readwrite");
            tx.objectStore(storeName).put(type);
            tx.oncomplete = resolve;
            tx.onerror = () => reject(tx.error || new Error("Gagal menyimpan cache Inspection Map."));
            tx.onabort = () => reject(tx.error || new Error("Penyimpanan cache Inspection Map dibatalkan."));
        });
    } catch (cacheError) {
        console.warn("Inspection Point Navigator map cache could not be persisted:", cacheError);
    }
    return setup;
}

function getInspectionPointNavigatorRecords(baseRecord, detail) {
    const candidates = inspectionRecords.filter(record =>
        !record.ServerOnly &&
        record.OwnerEmployeeID === baseRecord.OwnerEmployeeID &&
        record.CompanyID === baseRecord.CompanyID &&
        record.LocationID === baseRecord.LocationID &&
        record.SectionID === baseRecord.SectionID &&
        String(record.InspectionTypeCode || "") === String(baseRecord.InspectionTypeCode || "") &&
        String(record.InspectionTypeDetailCode || "").toUpperCase() ===
            String(detail.InspectionTypeDetailCode || "").toUpperCase() &&
        Number(record.IDTemplate) === Number(baseRecord.IDTemplate) &&
        Number(record.IDVersion) === Number(baseRecord.IDVersion) &&
        parseInspectionDate(record.InspectionDate) === parseInspectionDate(baseRecord.InspectionDate) &&
        String(record.InspectionMode || "").toUpperCase() === String(baseRecord.InspectionMode || "").toUpperCase() &&
        record.SyncStatus !== "DELETE_PENDING"
    );
    if (String(baseRecord.InspectionTypeDetailCode || "").toUpperCase() ===
        String(detail.InspectionTypeDetailCode || "").toUpperCase() &&
        !candidates.some(record => record.LocalInspectionID === baseRecord.LocalInspectionID))
        candidates.push(baseRecord);
    return candidates.sort((a, b) => String(b.UpdatedAt || b.StartDateTime || "")
        .localeCompare(String(a.UpdatedAt || a.StartDateTime || "")));
}

function getInspectionPointNavigatorOptionValue(point, record, scheduleTime, optionFilter) {
    const wanted = String(optionFilter || "").trim().toUpperCase();
    if (!wanted) return false;
    const lightning = String(record && record.InspectionMode || "").toUpperCase() === "LIGHTNING";
    const transaction = record && (record.Points || []).find(item =>
        Number(item.InspectionPointID) === Number(point.InspectionPointID) &&
        (!lightning || String(item.ScheduleTime || "") === String(scheduleTime || "")));
    const items = transaction && Array.isArray(transaction.Items) ? transaction.Items : [];
    const template = record && record.TemplateSnapshot;
    const sections = template && Array.isArray(template.sections) ? template.sections : [];
    for (const section of sections) {
        for (const item of (section.items || [])) {
            if (String(item.type || "").toUpperCase() !== "OPTION") continue;
            const itemId = item.idItem != null ? item.idItem : item.IDItem;
            const answer = items.find(entry => Number(entry.IDItem) === Number(itemId));
            const value = String(answer && answer.Value || "").trim().toUpperCase();
            if (value === wanted) return true;
        }
    }
    return false;
}

function getInspectionPointNavigatorStatus(point, record, scheduleTime) {
    const lightning = String(record && record.InspectionMode || "").toUpperCase() === "LIGHTNING";
    const transaction = record && (record.Points || []).find(item =>
        Number(item.InspectionPointID) === Number(point.InspectionPointID) &&
        (!lightning || String(item.ScheduleTime || "") === String(scheduleTime || "")));
    const status = String(transaction && transaction.Status || "PENDING").toUpperCase();
    if (status === "DONE" || status === "INSPECTED") return { key: "DONE", label: "Sudah diinspeksi", badge: "text-bg-success" };
    if (status === "ABNORMAL") return { key: "ABNORMAL", label: "Sudah diinspeksi · Abnormal", badge: "text-bg-danger" };
    if (status === "INCOMPLETE") return { key: "INCOMPLETE", label: "Draft / belum lengkap", badge: "text-bg-warning" };
    return { key: "PENDING", label: "Belum diinspeksi", badge: "text-bg-secondary" };
}

function selectInspectionPointNavigatorRecord(detail) {
    const state = inspectionPointNavigatorState;
    const base = state.baseRecord;
    const candidates = getInspectionPointNavigatorRecords(base, detail);
    const lightning = String(base.InspectionMode || "").toUpperCase() === "LIGHTNING";
    const sameDetail = String(detail.InspectionTypeDetailCode || "").toUpperCase() ===
        String(base.InspectionTypeDetailCode || "").toUpperCase();

    if (lightning) {
        state.record = candidates.find(record =>
            String(record.LocalInspectionID || "") === String(base.LocalInspectionID || "")) ||
            candidates[0] || (sameDetail ? base : null);

        const preferred = String(state.activeScheduleTime ||
            (sameDetail ? (base.ActiveScheduleTime || base.ScheduledTime || "") :
                (base.ActiveScheduleTime || state.record && state.record.ActiveScheduleTime || "")));
        const availableSchedules = (state.record && Array.isArray(state.record.Schedules)
            ? state.record.Schedules : []).map(item => String(item.ScheduleTime || item));
        const pointSchedules = (state.record && Array.isArray(state.record.Points)
            ? state.record.Points : []).map(item => String(item.ScheduleTime || "")).filter(Boolean);
        const scheduleOptions = availableSchedules.concat(pointSchedules)
            .filter((value, index, all) => value && all.indexOf(value) === index);
        state.scheduleTime = scheduleOptions.indexOf(preferred) >= 0
            ? preferred
            : (String(state.record && state.record.ActiveScheduleTime || "") ||
                scheduleOptions[0] || preferred);
        return;
    }

    const wanted = sameDetail
        ? String(base.ScheduledTime || "")
        : String(state.scheduleTime || "");
    state.record = candidates.find(record => String(record.ScheduledTime || "") === wanted) ||
        candidates[0] || (sameDetail ? base : null);
    state.scheduleTime = String(state.record && state.record.ScheduledTime || wanted || "");
}
function renderInspectionPointNavigatorPointControls(point) {
    const state = inspectionPointNavigatorState, record = state.record;
    if (!record) return '<div class="inspection-point-navigator-unavailable small text-muted">Belum ada transaksi untuk detail ini. Pilih Lihat Denah untuk memulai inspeksi.</div>';
    const snapshot = record.TemplateSnapshot || state.baseRecord && state.baseRecord.TemplateSnapshot || {};
    const optionItems = [];
    (Array.isArray(snapshot.sections) ? snapshot.sections : []).forEach(section => (section.items || []).forEach(item => {
        if (String(item.type || item.Type || "").toUpperCase() === "OPTION") optionItems.push(item);
    }));
    if (!optionItems.length) return "";
    const schedule = String(record.InspectionMode || "").toUpperCase() === "LIGHTNING" ? String(state.scheduleTime || record.ActiveScheduleTime || "") : "";
    const transaction = (record.Points || []).find(item => Number(item.InspectionPointID) === Number(point.InspectionPointID) && String(item.ScheduleTime || "") === schedule);
    const savedItems = transaction && Array.isArray(transaction.Items) ? transaction.Items : [];
    const readOnly = String(record.Status || "").toUpperCase() === "DONE" || (record === currentInspectionRecord && currentInspectionReadOnly);
    const groups = optionItems.map(item => {
        const id = Number(item.idItem || item.IDItem || 0), saved = savedItems.find(answer => Number(answer.IDItem) === id);
        const selected = String(saved && saved.Value || "");
        const options = String(item.optionList || item.OptionList || "").split(";").map(value => value.trim()).filter(Boolean);
        if (!options.length) return "";
        const raw = item.remarkRequiredOptions || item.RemarkRequiredOptions || [];
        const remarkOptions = Array.isArray(raw) ? raw.map(value => String(value).trim()) : String(raw || "").split(";").map(value => value.trim()).filter(Boolean);
        const version = snapshot.VersionInfo || snapshot.versionInfo || snapshot;
        let remarks = "";
        [1,2].forEach(number => {
            const field = number === 1 ? "Remark1" : "Remark2";
            const itemRequired = isInspectionFlagEnabled(number === 1 ? (item.isRemark1Required || item.IsRemark1Required) : (item.isRemark2Required || item.IsRemark2Required), false);
            const versionRequired = isInspectionFlagEnabled(number === 1 ? (item.versionIsRemark1Required || item.VersionIsRemark1Required || version.VersionIsRemark1Required || version.IsRemark1Required) : (item.versionIsRemark2Required || item.VersionIsRemark2Required || version.VersionIsRemark2Required || version.IsRemark2Required), false);
            if (!(itemRequired || (versionRequired && remarkOptions.length))) return;
            const visible = itemRequired || (versionRequired && remarkOptions.includes(selected.trim()));
            const mandatory = isInspectionFlagEnabled(number === 1 ? (item.isRemark1Mandatory || item.IsRemark1Mandatory) : (item.isRemark2Mandatory || item.IsRemark2Mandatory), false);
            const label = number === 1 ? (item.remark1Text || item.Remark1Text || "Remark 1") : (item.remark2Text || item.Remark2Text || "Remark 2");
            remarks += '<label class="inspection-point-navigator-remark ' + (visible ? "" : "d-none") + '"><span>' + escInspection(label) +
                (visible && (mandatory || remarkOptions.includes(selected.trim())) ? ' <b>*</b>' : '') + '</span><input type="text" maxlength="500" class="form-control form-control-sm" data-nav-point-remark="' + id +
                '" data-nav-point-remark-field="' + number + '" data-nav-point-id="' + escInspection(point.InspectionPointID) +
                '" value="' + escInspection(saved && saved[field] || "") + '"' + (readOnly ? " disabled" : "") + '></label>';
        });
        return '<div class="inspection-point-navigator-option-group"><div class="small text-muted mb-1">' + escInspection(item.label || item.Label || "Checklist") +
            '</div><div class="inspection-point-navigator-options">' + options.map(option => '<button type="button" class="btn btn-sm ' +
            (selected === option ? "btn-primary" : "btn-outline-primary") + '" data-nav-point-option="' + id + '" data-nav-point-value="' +
            escInspection(option) + '" data-nav-point-id="' + escInspection(point.InspectionPointID) + '"' + (readOnly ? " disabled" : "") + '>' +
            escInspection(option) + '</button>').join("") + '</div>' + remarks + '</div>';
    }).join("");
    return groups ? '<div class="inspection-point-navigator-controls">' + groups + '</div>' : "";
}

function renderInspectionPointNavigatorList() {
    const state = inspectionPointNavigatorState;
    const host = document.getElementById("inspectionPointNavigatorList");
    const summary = document.getElementById("inspectionPointNavigatorSummary");
    if (!host || !state.setup) return;

    const maps = Array.isArray(state.setup.maps) ? state.setup.maps : [];
    const keyword = String(state.keyword || "").trim().toLowerCase();
    const statusFor = point => getInspectionPointNavigatorStatus(point, state.record, state.scheduleTime);
    let points = (state.setup.points || []).filter(point => {
        const matchesMap = !state.selectedMapId || String(point.MapID || "") === String(state.selectedMapId);
        const activeSchedule = String(state.scheduleTime || "");
        const pointSchedule = String(point.ScheduleTime || "");
        const matchesSchedule = !activeSchedule || !pointSchedule || pointSchedule === activeSchedule;
        const matchesKeyword = !keyword ||
            String(point.PointCode || "").toLowerCase().indexOf(keyword) >= 0 ||
            String(point.PointName || "").toLowerCase().indexOf(keyword) >= 0;
        const status = statusFor(point).key;
        const matchesStatus = state.statusFilter === "all" ||
            (state.statusFilter === "unfilled" && (status === "PENDING" || status === "INCOMPLETE")) ||
            (state.statusFilter === "pending" && status === "PENDING") ||
            (state.statusFilter === "incomplete" && status === "INCOMPLETE") ||
            (state.statusFilter === "done" && status === "DONE") ||
            (state.statusFilter === "abnormal" && status === "ABNORMAL");
        const matchesOption = !state.optionFilter ||
            getInspectionPointNavigatorOptionValue(point, state.record, state.scheduleTime, state.optionFilter);
        return matchesMap && matchesSchedule && matchesKeyword && matchesStatus && matchesOption;
    });

    // Keep the Inspection Point master order; the optional Sort By control is removed.
    points.sort((a, b) => Number(a.DisplayOrder || 0) - Number(b.DisplayOrder || 0) ||
        String(a.PointCode || "").localeCompare(String(b.PointCode || "")));

    const all = (state.setup.points || []).filter(point => {
        const matchesMap = !state.selectedMapId || String(point.MapID || "") === String(state.selectedMapId);
        const activeSchedule = String(state.scheduleTime || "");
        const pointSchedule = String(point.ScheduleTime || "");
        return matchesMap && (!activeSchedule || !pointSchedule || pointSchedule === activeSchedule);
    });
    const counts = { DONE: 0, ABNORMAL: 0, INCOMPLETE: 0, PENDING: 0 };
    all.forEach(point => { counts[statusFor(point).key]++; });
    summary.innerHTML =
        '<span class="badge text-bg-light border text-dark">Total ' + all.length + '</span>' +
        '<span class="badge text-bg-success">Selesai ' + (counts.DONE + counts.ABNORMAL) + '</span>' +
        '<span class="badge text-bg-warning">Belum lengkap ' + counts.INCOMPLETE + '</span>' +
        '<span class="badge text-bg-secondary">Belum diperiksa ' + counts.PENDING + '</span>' +
        '<span class="small text-muted ms-auto">' + points.length + ' hasil filter</span>';

    const pageSize = Math.max(1, Math.min(500, Number(state.pageSize) || 20));
    const pageCount = Math.max(1, Math.ceil(points.length / pageSize));
    state.pageSize = pageSize;
    state.page = Math.min(Math.max(1, Number(state.page) || 1), pageCount);
    const startIndex = (state.page - 1) * pageSize;
    const pageRows = points.slice(startIndex, startIndex + pageSize);

    if (!points.length) {
        host.innerHTML = '<div class="text-muted small text-center py-4">' +
            (all.length ? "Tidak ada Inspection Point yang cocok dengan filter." : "Belum ada Inspection Point pada detail ini.") +
            '</div>';
        return;
    }

    const rowsHtml = pageRows.map(point => {
        const status = statusFor(point), map = maps.find(item => Number(item.MapID) === Number(point.MapID));
        return '<div class="inspection-point-navigator-row" data-point-navigator-row="' + escInspection(point.InspectionPointID) + '"><div class="inspection-point-navigator-heading"><div class="inspection-point-navigator-main">' +
            '<div class="inspection-point-navigator-code">' + escInspection(point.PointCode || "—") + '</div>' +
            '<div class="inspection-point-navigator-name">' + escInspection(point.PointName || "Inspection Point") + '</div>' +
            '<div class="inspection-point-navigator-map">' + escInspection(map && map.MapName || point.MapCode || "Map tidak diketahui") +
            '</div></div><span class="badge ' + status.badge + '">' +
            escInspection(status.label) + '</span></div>' + renderInspectionPointNavigatorPointControls(point) +
            '<div class="inspection-point-navigator-actions"><button type="button" class="btn btn-sm btn-outline-primary" data-point-navigator-checklist="' +
            escInspection(point.InspectionPointID) + '"><i class="bi bi-list-check me-1"></i>Checklist</button>' +
            '<button type="button" class="btn btn-sm btn-outline-secondary" data-point-navigator-open="' + escInspection(point.InspectionPointID) +
            '"><i class="bi bi-map me-1"></i>Lihat Denah</button></div></div>';
    }).join("");

    let pagerHtml = "";
    if (points.length > pageSize) {
        const firstRow = startIndex + 1;
        const lastRow = Math.min(startIndex + pageSize, points.length);
        pagerHtml =
            '<div class="inspection-point-navigator-pager border-top pt-2 mt-2">' +
                '<div class="d-flex flex-wrap align-items-center justify-content-between gap-2 small text-muted mb-2">' +
                    '<span>Menampilkan ' + firstRow + '–' + lastRow + ' dari ' + points.length + ' point</span>' +
                    '<span>Halaman ' + state.page + ' / ' + pageCount + '</span>' +
                '</div>' +
                '<div class="d-flex flex-wrap align-items-center gap-1">' +
                    '<div class="btn-group btn-group-sm" role="group" aria-label="Navigasi halaman">' +
                        '<button type="button" class="btn btn-outline-secondary" data-point-navigator-page="first" ' + (state.page <= 1 ? 'disabled' : '') + '>&laquo;</button>' +
                        '<button type="button" class="btn btn-outline-secondary" data-point-navigator-page="prev" ' + (state.page <= 1 ? 'disabled' : '') + '>&lsaquo;</button>' +
                        '<button type="button" class="btn btn-outline-secondary" data-point-navigator-page="next" ' + (state.page >= pageCount ? 'disabled' : '') + '>&rsaquo;</button>' +
                        '<button type="button" class="btn btn-outline-secondary" data-point-navigator-page="last" ' + (state.page >= pageCount ? 'disabled' : '') + '>&raquo;</button>' +
                    '</div>' +
                    '<label class="small ms-sm-2" for="inspectionPointNavigatorGoto">Go to</label>' +
                    '<input type="number" id="inspectionPointNavigatorGoto" class="form-control form-control-sm" min="1" max="' + pageCount + '" value="' + state.page + '" style="width:72px" />' +
                    '<button type="button" class="btn btn-sm btn-primary" data-point-navigator-page="goto">Go</button>' +
                '</div>' +
            '</div>';
    }

    host.innerHTML = rowsHtml + pagerHtml;
}
async function loadInspectionPointNavigatorDetail(detailCode) {
    const state = inspectionPointNavigatorState;
    const sequence = ++inspectionPointNavigatorLoadSequence;
    const host = document.getElementById("inspectionPointNavigatorList");
    const summary = document.getElementById("inspectionPointNavigatorSummary");
    const detail = getInspectionPointNavigatorDetails(state.baseRecord)
        .find(item => String(item.InspectionTypeDetailCode || "").toUpperCase() === String(detailCode || "").toUpperCase());
    if (!detail) return;

    state.detail = detail;
    state.setup = null;
    state.record = null;
    state.page = 1;
    state.scheduleTimes = getInspectionScheduleTimes(detail);
    state.keyword = document.getElementById("inspectionPointNavigatorSearch").value || "";
    host.innerHTML = '<div class="text-muted small text-center py-4"><span class="spinner-border spinner-border-sm me-2"></span>Memuat Inspection Point...</div>';
    summary.innerHTML = "";

    const sameDetail = String(state.baseRecord.InspectionTypeDetailCode || "").toUpperCase() ===
        String(detail.InspectionTypeDetailCode || "").toUpperCase();
    const preferredSchedule = String(state.activeScheduleTime ||
        state.baseRecord.ActiveScheduleTime || state.baseRecord.ScheduledTime || "");
    state.scheduleTime = state.scheduleTimes.indexOf(preferredSchedule) >= 0
        ? preferredSchedule : (state.scheduleTimes[0] || preferredSchedule);

    try {
        const setup = await getInspectionPointNavigatorSetup(state.baseRecord, detail);
        if (sequence !== inspectionPointNavigatorLoadSequence) return;
        state.setup = setup;
        selectInspectionPointNavigatorRecord(detail);
        if (state.record && state.record.BatchMapSetup && Array.isArray(state.record.BatchMapSetup.points))
            state.setup = state.record.BatchMapSetup;
        if (state.record) state.record.BatchMapSetup = state.setup;

        const navigatorSubtitle = document.getElementById("inspectionPointNavigatorSubtitle");
        if (navigatorSubtitle) {
            navigatorSubtitle.textContent =
                String(state.record && state.record.InspectionMode || "").toUpperCase() === "LIGHTNING"
                    ? "Jadwal aktif: " + (state.scheduleTime || "-") + (state.optionFilter ? " · Filter hasil: " + state.optionFilter : "") + " · Status dan input mengikuti jadwal ini."
                    : "Semua titik tetap ditampilkan" + (state.optionFilter ? " · Filter hasil: " + state.optionFilter : "") + ".";
        }

        const mapSelect = document.getElementById("inspectionPointNavigatorMap");
        const maps = Array.isArray(state.setup.maps) ? state.setup.maps : [];
        const preferredMapId = String(state.baseRecord.ActiveMapID || state.baseRecord.MapID || "");
        const firstMappedMapId = String((maps.find(map =>
            (state.setup.points || []).some(point => String(point.MapID) === String(map.MapID))) || maps[0] || {}).MapID || "");
        state.selectedMapId = state.allMapsRequested ? "" :
            (maps.some(map => String(map.MapID) === preferredMapId) ? preferredMapId : firstMappedMapId);
        mapSelect.innerHTML = '<option value="">All Maps</option>' + maps.map(map =>
            '<option value="' + escInspection(map.MapID) + '">' +
            escInspection((map.MapCode ? map.MapCode + " · " : "") + (map.MapName || "Inspection Map")) + '</option>'
        ).join("");
        mapSelect.value = state.selectedMapId;
        mapSelect.disabled = !maps.length;
        renderInspectionPointNavigatorList();
    } catch (error) {
        if (sequence !== inspectionPointNavigatorLoadSequence) return;
        host.innerHTML = '<div class="alert alert-warning small mb-0">' + escInspection(error.message || error) + '</div>';
    }
}
async function persistInspectionBeforePointNavigatorSwitch() {
    const record = currentInspectionRecord;
    if (!record || currentInspectionReadOnly) return true;

    const activePoint = getActiveInspectionPoint();
    if (activePoint) {
        const stable = value => {
            if (Array.isArray(value)) return value.map(stable);
            if (value && typeof value === "object") {
                const result = {};
                Object.keys(value).sort().forEach(key => { result[key] = stable(value[key]); });
                return result;
            }
            return value;
        };
        let liveItems = [];
        try { liveItems = collectInspectionItems(); } catch (_) { liveItems = activePoint.Items || []; }
        const liveCondition = document.querySelector('input[name="inspectionPointCondition"]:checked')?.value ||
            String(activePoint.PointCondition || "");
        const liveRemark = document.querySelector("#inspectionPointConditionPanel textarea")?.value ||
            String(activePoint.AbnormalRemark || "");
        const unchanged = JSON.stringify(stable({
            Items: activePoint.Items || [], PointCondition: activePoint.PointCondition || "",
            AbnormalRemark: activePoint.AbnormalRemark || ""
        })) === JSON.stringify(stable({
            Items: liveItems || [], PointCondition: liveCondition || "", AbnormalRemark: liveRemark || ""
        }));
        const currentPhotos = await getCurrentInspectionPhotos();
        const baselinePhotos = (inspectionPhotoBaseline || []).filter(photo =>
            String(photo.PointID || "") === String(activePoint.ClientPointID || ""));
        const photoIds = photos => photos.map(photo => String(photo.ID || "")).sort().join("|");
        const photosUnchanged = photoIds(currentPhotos) === photoIds(baselinePhotos);
        await saveBatchInspectionPoint("DRAFT", {
            silent: true,
            preserveCompletedStatus: unchanged && photosUnchanged
        });
        if (Number(record.ActiveInspectionPointID || 0) > 0) return false;
    } else {
        const summary = document.getElementById("txtInspectionSummary");
        if (summary) record.Summary = summary.value || "";
        try { Object.assign(record, collectInspectionFollowUp()); } catch (_) { }
        const hasParentData = String(record.Summary || "").trim() ||
            String(record.FollowUp || "") !== "No Follow Up" ||
            String(record.FollowUpSection || "").trim() || String(record.FollowUpRemark || "").trim();
        const persisted = await isInspectionRecordPersisted(record.LocalInspectionID);
        if (persisted || hasParentData || (record.Points || []).length) {
            record.SyncStatus = "PENDING";
            record.UpdatedAt = new Date().toISOString();
            await persistInspectionRecord(record);
        }
    }

    const index = inspectionRecords.findIndex(item => item.LocalInspectionID === record.LocalInspectionID);
    if (index >= 0) inspectionRecords[index] = record;
    else if (await isInspectionRecordPersisted(record.LocalInspectionID)) inspectionRecords.unshift(record);
    return true;
}

function wireInspectionPointNavigator() {
    const modal = document.getElementById("inspectionPointNavigatorModal");
    if (!modal || modal.dataset.wired === "1") return;
    modal.dataset.wired = "1";
    // Bootstrap applies aria-hidden during modal teardown. If a Navigator
    // button still owns focus at that moment, Chrome warns and blocks the
    // accessibility state change. Move focus out before Bootstrap hides it.
    modal.addEventListener("hide.bs.modal", function () {
        if (modal.contains(document.activeElement)) {
            try { document.activeElement.blur(); } catch (_) { }
        }
    });
    modal.addEventListener("shown.bs.modal", function () {
        const state = inspectionPointNavigatorState;
        if (!state.restoreNavigatorPosition) return;
        const body = modal.querySelector(".modal-body");
        if (body) body.scrollTop = state.returnScrollTop || 0;
        if (state.returnPointId) {
            const row = modal.querySelector('[data-point-navigator-row="' + String(state.returnPointId).replace(/"/g, '\\"') + '"]');
            if (row && body) {
                const rowTop = row.getBoundingClientRect().top - body.getBoundingClientRect().top + body.scrollTop;
                if (rowTop < body.scrollTop || rowTop + row.offsetHeight > body.scrollTop + body.clientHeight)
                    body.scrollTop = Math.max(0, rowTop - Math.max(12, (body.clientHeight - row.offsetHeight) / 2));
            }
        }
        state.restoreNavigatorPosition = false;
    });
    document.getElementById("inspectionPointNavigatorMap").addEventListener("change", function () {
        inspectionPointNavigatorState.selectedMapId = this.value || "";
        inspectionPointNavigatorState.page = 1;
        renderInspectionPointNavigatorList();
    });
    document.getElementById("inspectionPointNavigatorSearch").addEventListener("input", function () {
        inspectionPointNavigatorState.keyword = this.value || "";
        inspectionPointNavigatorState.page = 1;
        renderInspectionPointNavigatorList();
    });
    document.getElementById("inspectionPointNavigatorStatusFilter").addEventListener("change", function () {
        inspectionPointNavigatorState.statusFilter = this.value || "all";
        inspectionPointNavigatorState.page = 1;
        renderInspectionPointNavigatorList();
    });
    document.getElementById("inspectionPointNavigatorPageSize").addEventListener("change", function () {
        inspectionPointNavigatorState.pageSize = Math.max(1, Math.min(500, Number(this.value) || 20));
        inspectionPointNavigatorState.page = 1;
        renderInspectionPointNavigatorList();
    });
    document.getElementById("inspectionPointNavigatorList").addEventListener("click", async function (event) {
        const state = inspectionPointNavigatorState;
        const optionButton = event.target.closest("[data-nav-point-option]");
        if (optionButton) {
            if (!state.record || optionButton.disabled) return;
            optionButton.disabled = true;
            try {
                await window.setBatchInspectionPointOption(optionButton.getAttribute("data-nav-point-id"), optionButton.getAttribute("data-nav-point-option"), optionButton.getAttribute("data-nav-point-value"), state.record);
                renderInspectionPointNavigatorList();
            } catch (error) { showToast(error.message || "Pilihan point gagal disimpan.", "warning"); }
            finally { optionButton.disabled = false; }
            return;
        }
        const checklistButton = event.target.closest("[data-point-navigator-checklist]");
        if (checklistButton) {
            await openInspectionPointNavigatorTarget(Number(checklistButton.getAttribute("data-point-navigator-checklist")), true);
            return;
        }
        const pageButton = event.target.closest("[data-point-navigator-page]");
        if (pageButton) {
            const state = inspectionPointNavigatorState;
            const action = pageButton.getAttribute("data-point-navigator-page");
            const pageCount = Math.max(1, Math.ceil((state.setup && state.setup.points || []).filter(point => {
                const matchMap = !state.selectedMapId || String(point.MapID || "") === String(state.selectedMapId);
                const keyword = String(state.keyword || "").trim().toLowerCase();
                const matchKeyword = !keyword || String(point.PointCode || "").toLowerCase().includes(keyword) ||
                    String(point.PointName || "").toLowerCase().includes(keyword);
                const status = getInspectionPointNavigatorStatus(point, state.record, state.scheduleTime).key;
                const matchStatus = state.statusFilter === "all" ||
                    (state.statusFilter === "unfilled" && (status === "PENDING" || status === "INCOMPLETE")) ||
                    (state.statusFilter === "pending" && status === "PENDING") ||
                    (state.statusFilter === "incomplete" && status === "INCOMPLETE") ||
                    (state.statusFilter === "done" && status === "DONE") ||
                    (state.statusFilter === "abnormal" && status === "ABNORMAL");
                const matchOption = !state.optionFilter ||
                    getInspectionPointNavigatorOptionValue(point, state.record, state.scheduleTime, state.optionFilter);
                return matchMap && matchKeyword && matchStatus && matchOption;
            }).length / Math.max(1, state.pageSize)));
            if (action === "first") state.page = 1;
            else if (action === "prev") state.page--;
            else if (action === "next") state.page++;
            else if (action === "last") state.page = pageCount;
            else if (action === "goto") {
                const input = document.getElementById("inspectionPointNavigatorGoto");
                state.page = Math.max(1, Math.min(pageCount, Number(input && input.value) || 1));
            }
            renderInspectionPointNavigatorList();
            return;
        }
        const optionButton = event.target.closest("[data-open-inspection-option]");
        if (optionButton) {
            event.preventDefault();
            event.stopPropagation();
            if (typeof window.openInspectionPointNavigator === "function")
                window.openInspectionPointNavigator({
                    mapId: "all",
                    optionFilter: optionButton.getAttribute("data-open-inspection-option") || ""
                });
            return;
        }
        const button = event.target.closest("[data-point-navigator-open]");
        if (!button) return;
        openInspectionPointNavigatorTarget(Number(button.getAttribute("data-point-navigator-open")));
    });
    document.getElementById("inspectionPointNavigatorList").addEventListener("change", async function (event) {
        const input = event.target.closest("[data-nav-point-remark]"), state = inspectionPointNavigatorState;
        if (!input || !state.record || input.disabled) return;
        input.disabled = true;
        try {
            await window.setBatchInspectionPointRemark(input.getAttribute("data-nav-point-id"), input.getAttribute("data-nav-point-remark"),
                input.getAttribute("data-nav-point-remark-field"), input.value, state.record);
            renderInspectionPointNavigatorList();
        } catch (error) { showToast(error.message || "Remark point gagal disimpan.", "warning"); input.disabled = false; }
    });
}

window.openInspectionPointNavigator = async function (options) {
    options = options || {};
    const record = currentInspectionRecord;
    if (!record || !isInspectionMapMode(record.InspectionMode)) return;
    const modal = document.getElementById("inspectionPointNavigatorModal");
    if (!modal || !window.bootstrap || !bootstrap.Modal) {
        showToast("Point Navigator belum tersedia. Refresh aplikasi setelah update.", "warning");
        return;
    }
    wireInspectionPointNavigator();
    try {
        const all = await readInspectionStore("inspection_records");
        inspectionRecords = all.filter(item =>
            !item.ServerOnly && item.OwnerEmployeeID === inspectionLogin.employeeid &&
            item.CompanyID === inspectionCompanyID && item.LocationID === inspectionLocationID
        ).sort((a, b) => String(b.UpdatedAt || b.StartDateTime || "")
            .localeCompare(String(a.UpdatedAt || a.StartDateTime || "")));
    } catch (error) {
        console.warn("Point Navigator could not refresh local inspection records:", error);
    }

    const state = inspectionPointNavigatorState;
    state.baseRecord = currentInspectionRecord;
    state.detail = null;
    state.setup = null;
    state.record = null;
    state.selectedMapId = "";
    state.allMapsRequested = String(options.mapId || "").toLowerCase() === "all";
    state.activeScheduleTime = String(
        (typeof window.getActiveInspectionScheduleTime === "function" && window.getActiveInspectionScheduleTime()) ||
        record.ActiveScheduleTime || record.ScheduledTime || ""
    ).trim();
    state.restoreNavigatorPosition = false;
    state.returnScrollTop = 0;
    state.returnPointId = 0;
    state.keyword = "";
    state.statusFilter = ["all", "pending", "incomplete", "unfilled", "done", "abnormal"].includes(String(options.statusFilter || "all"))
        ? String(options.statusFilter || "all") : "all";
    state.optionFilter = String(options.optionFilter || "").trim().toUpperCase();
    state.page = 1;
    state.pageSize = 20;
    document.getElementById("inspectionPointNavigatorSearch").value = "";
    document.getElementById("inspectionPointNavigatorStatusFilter").value = state.statusFilter;
    document.getElementById("inspectionPointNavigatorPageSize").value = "20";
    const detail = getInspectionPointNavigatorDetails(record).find(item =>
        String(item.InspectionTypeDetailCode || "").toUpperCase() ===
        String(record.InspectionTypeDetailCode || "").toUpperCase()) || {
            InspectionTypeCode: record.InspectionTypeCode,
            InspectionTypeDetailCode: record.InspectionTypeDetailCode,
            InspectionTypeDetailName: record.InspectionTypeDetailName || record.InspectionTypeDetailCode,
            CompanyID: record.CompanyID,
            LocationID: record.LocationID
        };
    bootstrap.Modal.getOrCreateInstance(modal).show();
    await loadInspectionPointNavigatorDetail(detail.InspectionTypeDetailCode);
}
async function openInspectionPointNavigatorTarget(pointId, openChecklist) {
    const state = inspectionPointNavigatorState;
    const baseRecord = state.baseRecord;
    const masterPoint = (state.setup && state.setup.points || []).find(point =>
        Number(point.InspectionPointID) === Number(pointId));
    if (!baseRecord || !masterPoint || !state.detail) return;

    const modal = document.getElementById("inspectionPointNavigatorModal");
    const instance = window.bootstrap && bootstrap.Modal ? bootstrap.Modal.getInstance(modal) : null;
    if (instance) {
        if (openChecklist) {
            const modalBody = modal.querySelector(".modal-body");
            state.returnScrollTop = modalBody ? modalBody.scrollTop : 0;
            state.returnPointId = Number(pointId) || 0;
            state.restoreNavigatorPosition = true;
        } else {
            state.restoreNavigatorPosition = false;
        }
        const hidden = new Promise(resolve => modal.addEventListener("hidden.bs.modal", resolve, { once: true }));
        instance.hide();
        await hidden;
    }

    const sameDetail = String(baseRecord.InspectionTypeDetailCode || "").toUpperCase() ===
        String(state.detail.InspectionTypeDetailCode || "").toUpperCase();
    const sameBatchSchedule = String(baseRecord.InspectionMode || "").toUpperCase() !== "LIGHTNING" &&
        String(baseRecord.ScheduledTime || "") !== String(state.scheduleTime || "");
    const sameTransaction = sameDetail && !sameBatchSchedule;
    if (!sameTransaction) {
        if (currentInspectionReadOnly && !state.record) {
            showToast("Detail ini belum memiliki transaksi inspeksi yang dapat dibuka dari record read-only.", "warning");
            return;
        }
        const saved = await persistInspectionBeforePointNavigatorSwitch();
        if (!saved) {
            showToast("Checklist point yang sedang dibuka belum berhasil disimpan. Detail tidak diganti.", "warning");
            return;
        }

        let targetRecord = state.record;
        if (targetRecord) {
            targetRecord.BatchMapSetup = state.setup;
            if (String(targetRecord.InspectionMode || "").toUpperCase() === "LIGHTNING" &&
                state.scheduleTimes.indexOf(state.scheduleTime) >= 0)
                targetRecord.ActiveScheduleTime = state.scheduleTime;
            await openSavedInspection(targetRecord.LocalInspectionID);
        } else {
            const previousRecord = currentInspectionRecord;
            const typeSelect = document.getElementById("selInspectionType");
            const templateSelect = document.getElementById("selInspectionTemplate");
            const detailSelect = document.getElementById("selInspectionDetail");
            const scheduleSelect = document.getElementById("selInspectionScheduleTime");
            typeSelect.value = baseRecord.InspectionTypeCode;
            onInspectionTypeChanged();
            templateSelect.value = String(baseRecord.IDTemplate);
            templateSelect.dispatchEvent(new Event("change"));
            detailSelect.value = state.detail.InspectionTypeDetailCode;
            onInspectionDetailChanged();
            if (String(baseRecord.InspectionMode || "").toUpperCase() !== "LIGHTNING" && state.scheduleTimes.length)
                scheduleSelect.value = state.scheduleTime;
            refreshInspectionScheduleOptions();
            await startNewInspection();
            if (currentInspectionRecord === previousRecord ||
                String(currentInspectionRecord && currentInspectionRecord.InspectionTypeDetailCode || "").toUpperCase() !==
                    String(state.detail.InspectionTypeDetailCode || "").toUpperCase()) {
                if (previousRecord) {
                    await populateInspectionParameters(previousRecord);
                    if (typeof window.showInspectionMapWorkspace === "function")
                        window.showInspectionMapWorkspace(previousRecord, true);
                }
                return;
            }
        }
    }

    const activeRecord = currentInspectionRecord;
    if (!activeRecord || String(activeRecord.InspectionTypeDetailCode || "").toUpperCase() !==
        String(state.detail.InspectionTypeDetailCode || "").toUpperCase()) return;
    if (String(activeRecord.InspectionMode || "").toUpperCase() === "LIGHTNING") {
        const schedules = (activeRecord.Schedules || []).map(item => String(item.ScheduleTime || item));
        if (schedules.indexOf(state.scheduleTime) >= 0) {
            activeRecord.ActiveScheduleTime = state.scheduleTime;
            activeInspectionScheduleTime = state.scheduleTime;
            if (typeof window.setInspectionActiveScheduleTime === "function")
                window.setInspectionActiveScheduleTime(state.scheduleTime);
        }
    }
    if (typeof window.showInspectionMapWorkspace === "function")
        window.showInspectionMapWorkspace(activeRecord, true);
    if (typeof window.refreshInspectionMapPointStatuses === "function")
        window.refreshInspectionMapPointStatuses();
    // Checklist editing does not depend on map coordinates. Only the
    // "Lihat Denah" action should attempt to focus the marker and warn if
    // the map geometry is unavailable.
    if (openChecklist) {
        const checklistPoint = (activeRecord.BatchMapSetup && activeRecord.BatchMapSetup.points || state.setup.points || [])
            .find(point => Number(point.InspectionPointID) === Number(pointId));
        if (checklistPoint) {
            window.inspectionReturnToPointNavigator = true;
            await window.openBatchInspectionPointChecklist(checklistPoint);
        }
    } else {
        window.inspectionReturnToPointNavigator = false;
        const focused = typeof window.focusInspectionMapPoint === "function"
            ? await window.focusInspectionMapPoint(pointId) : false;
        if (!focused && typeof showToast === "function")
            showToast("Titik ditemukan, tetapi denah/koordinat map belum tersedia. Gunakan daftar Inspection Point.", "warning");
    }
}


window.setBatchInspectionPointRemark = async function (pointId, itemId, remarkNumber, value, targetRecord) {
    const record = targetRecord || currentInspectionRecord;
    if (!record || !isInspectionMapMode(record.InspectionMode))
        throw new Error("Batch/Lightning inspection tidak sedang aktif.");
    if ((record === currentInspectionRecord && currentInspectionReadOnly) || String(record.Status || "").toUpperCase() === "DONE")
        throw new Error("Batch yang sudah disubmit bersifat read-only.");

    const templateItems = [];
    (record.TemplateSnapshot && Array.isArray(record.TemplateSnapshot.sections) ? record.TemplateSnapshot.sections : [])
        .forEach(section => (section.items || []).forEach(item => templateItems.push(item)));
    const templateItem = templateItems.find(item =>
        String(item.type || "").toUpperCase() === "OPTION" && Number(item.idItem) === Number(itemId));
    if (!templateItem) throw new Error("Checklist OPTION tidak ditemukan pada template batch.");
    const field = Number(remarkNumber) === 2 ? "Remark2" : "Remark1";

    record.Points = Array.isArray(record.Points) ? record.Points : [];
    const scheduleTime = String(record.InspectionMode || "").toUpperCase() === "LIGHTNING"
        ? String(inspectionPointNavigatorState.record === record ? inspectionPointNavigatorState.scheduleTime : (activeInspectionScheduleTime || record.ActiveScheduleTime || "")) : "";
    let point = record.Points.find(item =>
        Number(item.InspectionPointID) === Number(pointId) &&
        String(item.ScheduleTime || "") === scheduleTime);
    if (!point) {
        const masterPoint = (record.BatchMapSetup && record.BatchMapSetup.points || []).find(item =>
            Number(item.InspectionPointID) === Number(pointId));
        if (!masterPoint) throw new Error("Inspection Point tidak ditemukan.");
        point = {
            ClientPointID: newInspectionId(),
            InspectionPointID: Number(masterPoint.InspectionPointID),
            ScheduleTime: scheduleTime,
            PointCode: String(masterPoint.PointCode || ""),
            PointName: String(masterPoint.PointName || ""),
            InspectionDateTime: localDateTimeString(new Date()),
            Status: "PENDING",
            PointCondition: "",
            AbnormalRemark: "",
            Items: [],
            NextPhotoSeqNo: 1
        };
        record.Points.push(point);
    }

    point.Items = Array.isArray(point.Items) ? point.Items : [];
    let answer = point.Items.find(item => Number(item.IDItem) === Number(itemId));
    if (!answer) {
        answer = {
            IDItem: Number(itemId),
            ItemLabel: templateItem.label || ("Item " + itemId),
            Type: "OPTION",
            Value: "",
            Remark1: "",
            Remark2: "",
            IsAnomali: false,
            DisplayOrder: templateItems.indexOf(templateItem) + 1,
            Values: null
        };
        point.Items.push(answer);
    }
    answer[field] = String(value == null ? "" : value).trim();
    point.UpdatedAt = new Date().toISOString();
    point.InspectionDateTime = point.InspectionDateTime || localDateTimeString(new Date());

    const validationErrors = validateInspectionItemsAll(point.Items);
    const hasValue = point.Items.some(item =>
        String(item.Value || "").trim() !== "" ||
        Object.keys(item.Values || {}).some(key => String(item.Values[key] == null ? "" : item.Values[key]).trim() !== "") ||
        (Array.isArray(item.RepeatValues) && item.RepeatValues.some(objectRow =>
            Object.keys((objectRow && objectRow.Values) || {}).some(key =>
                String(objectRow.Values[key] == null ? "" : objectRow.Values[key]).trim() !== ""))));
    if (hasValue) {
        if (validationErrors.length) point.Status = "INCOMPLETE";
        else point.Status = point.Items.some(item =>
            /^(OFF|MATI|NO|RUSAK|ABNORMAL|TIDAK|NOT OK)$/.test(String(item.Value || "").trim().toUpperCase()) ||
            (Array.isArray(item.RepeatValues) && item.RepeatValues.some(objectRow =>
                Object.keys((objectRow && objectRow.Values) || {}).some(key =>
                    /^(OFF|MATI|NO|RUSAK|ABNORMAL|TIDAK|NOT OK)$/.test(String(objectRow.Values[key] == null ? "" : objectRow.Values[key]).trim().toUpperCase())))))
            ? "ABNORMAL" : "DONE";
    } else if (validationErrors.length) {
        point.Status = "INCOMPLETE";
    }
    point.ValidationIssueCount = validationErrors.length;
    const masterPoint = (record.BatchMapSetup && record.BatchMapSetup.points || []).find(item =>
        Number(item.InspectionPointID) === Number(pointId));
    if (masterPoint) masterPoint.ValidationIssueCount = validationErrors.length;

    record.Items = [];
    record.ActiveInspectionPointID = 0;
    record.SyncStatus = "PENDING";
    record.UpdatedAt = new Date().toISOString();
    await persistInspectionRecord(record);
    return true;
};

window.setBatchInspectionPointOption = async function (pointId, itemId, value, targetRecord) {
    const record = targetRecord || currentInspectionRecord;
    if (!record || !isInspectionMapMode(record.InspectionMode))
        throw new Error("Batch/Lightning inspection tidak sedang aktif.");
    if ((record === currentInspectionRecord && currentInspectionReadOnly) || String(record.Status || "").toUpperCase() === "DONE")
        throw new Error("Batch yang sudah disubmit bersifat read-only.");

    const quickOptionBlockReason = record === currentInspectionRecord ? getBatchPointQuickOptionBlockReason({ InspectionPointID: pointId }) : "";
    if (quickOptionBlockReason) throw new Error(quickOptionBlockReason);

    const templateItems = [];
    (record.TemplateSnapshot && Array.isArray(record.TemplateSnapshot.sections) ? record.TemplateSnapshot.sections : [])
        .forEach(section => (section.items || []).forEach(item => templateItems.push(item)));
    const templateItem = templateItems.find(item =>
        String(item.type || "").toUpperCase() === "OPTION" && Number(item.idItem) === Number(itemId));
    if (!templateItem) throw new Error("Checklist OPTION tidak ditemukan pada template batch.");

    record.Points = Array.isArray(record.Points) ? record.Points : [];
    const scheduleTime = String(record.InspectionMode || "").toUpperCase() === "LIGHTNING"
        ? String(inspectionPointNavigatorState.record === record ? inspectionPointNavigatorState.scheduleTime : (activeInspectionScheduleTime || record.ActiveScheduleTime || "")) : "";
    let point = record.Points.find(item =>
        Number(item.InspectionPointID) === Number(pointId) &&
        String(item.ScheduleTime || "") === scheduleTime);
    if (!point) {
        const masterPoint = (record.BatchMapSetup && record.BatchMapSetup.points || []).find(item =>
            Number(item.InspectionPointID) === Number(pointId));
        if (!masterPoint) throw new Error("Inspection Point tidak ditemukan.");
        point = {
            ClientPointID: newInspectionId(),
            InspectionPointID: Number(masterPoint.InspectionPointID),
            ScheduleTime: scheduleTime,
            PointCode: String(masterPoint.PointCode || ""),
            PointName: String(masterPoint.PointName || ""),
            InspectionDateTime: localDateTimeString(new Date()),
            Status: "PENDING",
            PointCondition: "",
            AbnormalRemark: "",
            Items: [],
            NextPhotoSeqNo: 1
        };
        record.Points.push(point);
    }

    point.Items = Array.isArray(point.Items) ? point.Items : [];
    let answer = point.Items.find(item => Number(item.IDItem) === Number(itemId));
    const selectedValue = String(value == null ? "" : value);
    if (!answer) {
        answer = {
            IDItem: Number(itemId),
            ItemLabel: templateItem.label || ("Item " + itemId),
            Type: "OPTION",
            Value: "",
            Remark1: "",
            Remark2: "",
            IsAnomali: false,
            DisplayOrder: templateItems.indexOf(templateItem) + 1,
            Values: null
        };
        point.Items.push(answer);
    }
    answer.Value = String(answer.Value || "") === selectedValue ? "" : selectedValue;
    point.UpdatedAt = new Date().toISOString();
    point.InspectionDateTime = point.InspectionDateTime || localDateTimeString(new Date());

    const validationErrors = validateInspectionItemsAll(point.Items || []);
    const hasAnyAnswer = (point.Items || []).some(item =>
        String(item.Value || "").trim() !== "" ||
        Object.keys(item.Values || {}).some(key => String(item.Values[key] == null ? "" : item.Values[key]).trim() !== "") ||
        (Array.isArray(item.RepeatValues) && item.RepeatValues.some(objectRow =>
            Object.keys((objectRow && objectRow.Values) || {}).some(key =>
                String(objectRow.Values[key] == null ? "" : objectRow.Values[key]).trim() !== "")))
    );
    if (!hasAnyAnswer) point.Status = "PENDING";
    else if (validationErrors.length) point.Status = "INCOMPLETE";
    else {
        const abnormal = (point.Items || []).some(item =>
            /^(OFF|MATI|NO|RUSAK|ABNORMAL|TIDAK|NOT OK)$/.test(String(item.Value || "").trim().toUpperCase())
        );
        point.Status = abnormal ? "ABNORMAL" : "DONE";
    }

    record.Items = [];
    record.ActiveInspectionPointID = 0;
    record.SyncStatus = "PENDING";
    record.UpdatedAt = new Date().toISOString();
    await persistInspectionRecord(record);
    return true;
};

async function saveBatchInspectionPoint(status, options) {
    options = options || {};
    const record = currentInspectionRecord;
    const point = getActiveInspectionPoint();
    if (!record || !point) { showToast("Pilih Inspection Point terlebih dahulu.", "warning"); return; }
    const items = collectInspectionItems();
    const photos = await getCurrentInspectionPhotos();
    const masterPoint = (record.BatchMapSetup && record.BatchMapSetup.points || []).find(item =>
        Number(item.InspectionPointID) === Number(point.InspectionPointID));
    const conditionRequired = isInspectionFlagEnabled(masterPoint && masterPoint.IsNormalAbnormalRequired, false);
    const errors = [];
    if (status === "DONE" && conditionRequired) {
        const condition = document.querySelector('input[name="inspectionPointCondition"]:checked')?.value ||
            String(point.PointCondition || "").toUpperCase();
        const abnormalRemark = String(document.querySelector("#inspectionPointConditionPanel textarea")?.value ||
            point.AbnormalRemark || "").trim();
        if (condition !== "NORMAL" && condition !== "ABNORMAL") errors.push({ message: "Pilih kondisi NORMAL atau ABNORMAL." });
        else if (condition === "ABNORMAL" && !abnormalRemark) errors.push({ message: "Abnormal Remark wajib diisi." });
        else { point.PointCondition = condition; point.AbnormalRemark = condition === "ABNORMAL" ? abnormalRemark : ""; }
    }
    if (status === "DONE") {
        validateInspectionItemsAll(items).forEach(error => errors.push(error));
        const requirement = getInspectionPhotoRequirement(record);
        const hasBefore = photos.some(photo => String(photo.Type || "").toUpperCase() === "BEFORE");
        const hasAfter = photos.some(photo => String(photo.Type || "").toUpperCase() === "AFTER");
        if ((requirement === "BEFORE" || requirement === "BOTH") && !hasBefore)
            errors.push({ message: "Foto BEFORE wajib diambil (minimal 1 foto)." });
        if ((requirement === "AFTER" || requirement === "BOTH") && !hasAfter)
            errors.push({ message: "Foto AFTER wajib diambil (minimal 1 foto)." });
        if (errors.length) {
            point.Status = "INCOMPLETE";
            showToast(point.PointCode + ": " + errors.slice(0, 3).map(error => error.message).join(" · ") +
                (errors.length > 3 ? " · +" + (errors.length - 3) + " kewajiban lainnya." : ""), "warning");
            const firstItemError = errors.find(error => error.itemId);
            if (firstItemError) focusInvalidInspectionItem(firstItemError);
            else if (errors.some(error => /Foto BEFORE/.test(error.message))) {
                const panel = document.getElementById("btnAddInspectionBeforePhoto")?.closest(".inspection-photo-panel");
                if (panel) panel.scrollIntoView({ behavior: "smooth", block: "center" });
            } else if (errors.some(error => /Foto AFTER/.test(error.message))) {
                const panel = document.getElementById("inspectionAfterPhotoPanel");
                if (panel) panel.scrollIntoView({ behavior: "smooth", block: "center" });
            }
            return;
        }
        const isAbnormalRepeatValue = value =>
            /^(OFF|MATI|NO|RUSAK|ABNORMAL|TIDAK|NOT OK)$/.test(String(value == null ? "" : value).trim().toUpperCase());
        const hasAbnormalRepeatValue = items.some(item => {
            if (isAbnormalRepeatValue(item.Value)) return true;
            const repeatRows = Array.isArray(item.RepeatValues) ? item.RepeatValues : [];
            return repeatRows.some(objectRow => {
                const values = objectRow && objectRow.Values ? objectRow.Values : {};
                return Object.keys(values).some(key => isAbnormalRepeatValue(values[key]));
            });
        });
        const hasAnomalousItem = items.some(item =>
            item.IsAnomali === true || item.IsAnomali === 1 || String(item.IsAnomali || "") === "1");
        point.Status = String(point.PointCondition || "").toUpperCase() === "ABNORMAL" ||
            hasAnomalousItem || hasAbnormalRepeatValue ? "ABNORMAL" : "DONE";
    } else {
        const hasAnyPointValue = items.some(item => {
            if (String(item.Value || "").trim()) return true;
            const values = item.Values || {};
            if (Object.keys(values).some(key => String(values[key] == null ? "" : values[key]).trim())) return true;
            const repeatRows = Array.isArray(item.RepeatValues) ? item.RepeatValues : [];
            return repeatRows.some(objectRow => {
                const repeatFields = objectRow && objectRow.Values ? objectRow.Values : {};
                return Object.keys(repeatFields).some(key => String(repeatFields[key] == null ? "" : repeatFields[key]).trim());
            });
        });
        const originalPointStatus = String(point.Status || "").toUpperCase();
        point.Status = options.preserveCompletedStatus &&
            ["DONE", "ABNORMAL"].indexOf(originalPointStatus) >= 0
            ? originalPointStatus
            : (hasAnyPointValue || photos.length ? "INCOMPLETE" : "PENDING");
    }
    point.Items = items;
    let validationIssueCount = status === "DONE" ? errors.length : validateInspectionItemsAll(items).length;
    if (status !== "DONE") {
        const requirement = getInspectionPhotoRequirement(record);
        const hasBefore = photos.some(photo => String(photo.Type || "").toUpperCase() === "BEFORE");
        const hasAfter = photos.some(photo => String(photo.Type || "").toUpperCase() === "AFTER");
        if ((requirement === "BEFORE" || requirement === "BOTH") && !hasBefore) validationIssueCount++;
        if ((requirement === "AFTER" || requirement === "BOTH") && !hasAfter) validationIssueCount++;
        if (conditionRequired) {
            const condition = String(point.PointCondition || "").toUpperCase();
            if (condition !== "NORMAL" && condition !== "ABNORMAL") validationIssueCount++;
            else if (condition === "ABNORMAL" && !String(point.AbnormalRemark || "").trim()) validationIssueCount++;
        }
    }
    point.ValidationIssueCount = validationIssueCount;
    if (masterPoint) masterPoint.ValidationIssueCount = validationIssueCount;
    point.UpdatedAt = new Date().toISOString();
    point.InspectionDateTime = point.InspectionDateTime || localDateTimeString(new Date());
    record.Items = [];
    record.ActiveInspectionPointID = 0;
    record.SyncStatus = "PENDING";
    record.UpdatedAt = new Date().toISOString();
    if (inspectionAutoSaveTimer) clearTimeout(inspectionAutoSaveTimer);
    await persistInspectionRecord(record);
    const followUp = document.getElementById("inspectionFollowUpPanel");
    const summary = document.getElementById("inspectionSummaryPanel");
    if (followUp) followUp.classList.toggle("d-none", !inspectionTemplateRequiresFollowUp(record.TemplateSnapshot));
    if (summary) summary.classList.toggle("d-none", !inspectionTemplateRequiresSummary(record.TemplateSnapshot));
    const saveButton = document.getElementById("btnSaveInspectionDraft");
    const completeButton = document.getElementById("btnCompleteInspection");
    if (saveButton) saveButton.innerHTML = '<i class="bi bi-save"></i> Save Draft';
    if (completeButton) completeButton.innerHTML = '<i class="bi bi-check-circle"></i> Submit';
    if (typeof window.closeInspectionMapPointChecklistSheet === "function")
        window.closeInspectionMapPointChecklistSheet(true);
    document.getElementById("inspectionChecklistPane").classList.add("d-none");
    if (typeof showInspectionMapWorkspace === "function") showInspectionMapWorkspace(record, true);
    if (typeof refreshInspectionMapPointStatuses === "function") refreshInspectionMapPointStatuses();
    if (!options.silent) showToast(point.PointCode + " tersimpan dengan status " + point.Status + ".", "success");
}


function getBatchValidationCategory(error) {
    const message = String(error && error.message || "").toLowerCase();
    if (/remark/.test(message)) return "Remark belum lengkap";
    if (/foto|photo/.test(message)) return "Dokumentasi foto";
    if (/summary/.test(message)) return "Final Inspection Summary";
    if (/follow up|responsible section/.test(message)) return "Follow Up";
    if (/normal|abnormal/.test(message)) return "Kondisi point";
    if (/point belum|belum diinspeksi|master map/.test(message)) return "Status Inspection Point";
    return "Checklist belum lengkap";
}

function showInspectionBatchValidationReport(errors) {
    const list = Array.isArray(errors) ? errors : [];
    const record = currentInspectionRecord;
    const masterPoints = record && record.BatchMapSetup && record.BatchMapSetup.points || [];
    const affected = new Set(list.map(error => Number(error.pointId)).filter(Boolean));
    const totalPoints = masterPoints.length;
    const completedPoints = Math.max(0, totalPoints - affected.size);
    inspectionBatchValidationState = { errors: list.map(error => Object.assign({}, error)), index: -1 };
    (record && record.Points || []).forEach(point => {
        const count = list.filter(error => Number(error.pointId) === Number(point.InspectionPointID)).length;
        point.ValidationIssueCount = count;
        if (count && !["ABNORMAL"].includes(String(point.Status || "").toUpperCase())) point.Status = "INCOMPLETE";
        if (!count) point.ValidationIssueCount = 0;
    });
    masterPoints.forEach(point => {
        point.ValidationIssueCount = list.filter(error => Number(error.pointId) === Number(point.InspectionPointID)).length;
    });
    if (typeof window.refreshInspectionMapPointStatuses === "function")
        window.refreshInspectionMapPointStatuses();

    const categories = new Map();
    list.forEach((error, index) => {
        const key = getBatchValidationCategory(error);
        if (!categories.has(key)) categories.set(key, []);
        categories.get(key).push({ error, index });
    });
    const root = document.createElement("div");
    root.className = "modal fade inspection-batch-validation-modal";
    root.tabIndex = -1;
    const progress = totalPoints ? Math.round(completedPoints / totalPoints * 100) : 0;
    root.innerHTML = '<div class="modal-dialog modal-lg modal-dialog-scrollable"><div class="modal-content">' +
        '<div class="modal-header"><div><h5 class="modal-title mb-1"><i class="bi bi-clipboard2-check text-warning me-2"></i>Validasi Inspection Batch</h5>' +
        '<div class="small text-muted">Ada input yang perlu dilengkapi sebelum batch dapat disubmit.</div></div>' +
        '<button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button></div>' +
        '<div class="modal-body"><div class="row g-2 mb-3">' +
        '<div class="col-4"><div class="inspection-validation-stat"><strong>' + affected.size + '</strong><span>Point bermasalah</span></div></div>' +
        '<div class="col-4"><div class="inspection-validation-stat"><strong>' + list.length + '</strong><span>Input kurang</span></div></div>' +
        '<div class="col-4"><div class="inspection-validation-stat"><strong>' + completedPoints + '</strong><span>Point tanpa temuan</span></div></div></div>' +
        '<div class="d-flex justify-content-between small text-muted mb-1"><span>Progres point</span><strong>' + progress + '%</strong></div>' +
        '<div class="progress mb-3" style="height:8px"><div class="progress-bar bg-success" role="progressbar" style="width:' + progress + '%"></div></div>' +
        '<div class="small text-muted mb-2">Pilih kategori, lalu tekan <strong>Perbaiki</strong> pada temuan. Sistem akan membuka point dan mengarahkan langsung ke input yang bermasalah.</div>' +
        '<div class="inspection-batch-validation-categories"></div></div>' +
        '<div class="modal-footer"><button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Tutup</button></div></div></div>';
    const host = root.querySelector(".inspection-batch-validation-categories");
    categories.forEach((items, category) => {
        const details = document.createElement("details");
        details.className = "inspection-validation-category mb-2";
        const summary = document.createElement("summary");
        summary.innerHTML = '<span>' + escInspection(category) + '</span><span class="badge text-bg-warning">' + items.length + '</span>';
        details.appendChild(summary);
        const listHost = document.createElement("div");
        listHost.className = "inspection-validation-category-items";
        items.forEach(entry => {
            const error = entry.error;
            const row = document.createElement("div");
            row.className = "inspection-validation-issue";
            const detail = document.createElement("div");
            detail.className = "inspection-validation-issue-text";
            const pointLabel = error.pointCode || "Kelengkapan Batch";
            detail.innerHTML = '<strong>' + escInspection(pointLabel) + '</strong><span>' + escInspection(error.message) + '</span>';
            const button = document.createElement("button");
            button.type = "button";
            button.className = "btn btn-sm btn-outline-primary flex-shrink-0";
            button.textContent = "Perbaiki";
            button.setAttribute("data-validation-index", String(entry.index));
            row.appendChild(detail);
            row.appendChild(button);
            listHost.appendChild(row);
        });
        details.appendChild(listHost);
        host.appendChild(details);
    });
    document.body.appendChild(root);
    if (!window.bootstrap || !window.bootstrap.Modal) {
        window.alert(list.map(error => (error.pointCode ? error.pointCode + ": " : "") + error.message).join("\n"));
        root.remove();
        return;
    }
    const modal = new window.bootstrap.Modal(root);
    root.addEventListener("click", event => {
        const button = event.target.closest("[data-validation-index]");
        if (!button) return;
        const index = Number(button.getAttribute("data-validation-index"));
        const error = inspectionBatchValidationState.errors[index];
        if (!error) return;
        inspectionBatchValidationState.index = index;
        if (error.ScheduleTime && String(currentInspectionRecord && currentInspectionRecord.InspectionMode || "").toUpperCase() === "LIGHTNING") {
            activeInspectionScheduleTime = String(error.ScheduleTime);
            currentInspectionRecord.ActiveScheduleTime = activeInspectionScheduleTime;
            if (typeof window.setInspectionActiveScheduleTime === "function")
                window.setInspectionActiveScheduleTime(activeInspectionScheduleTime);
        }
        modal.hide();
        if (error.pointId) {
            const masterPoint = masterPoints.find(point => Number(point.InspectionPointID) === Number(error.pointId));
            if (masterPoint) window.setTimeout(() => {
                if (typeof window.showInspectionMapWorkspace === "function")
                    window.showInspectionMapWorkspace(currentInspectionRecord, true);
                openBatchInspectionPointChecklist(masterPoint, error);
            }, 180);
        } else {
            window.setTimeout(() => {
                if (typeof window.showInspectionMapWorkspace === "function")
                    window.showInspectionMapWorkspace(currentInspectionRecord, true);
                const target = error.target === "summary" ? document.getElementById("txtInspectionSummary") :
                    error.target === "followup-section" ? document.getElementById("inspectionFollowUpSection") :
                    error.target === "followup-remark" ? document.getElementById("txtInspectionFollowUpRemark") : null;
                if (target) {
                    target.scrollIntoView({ behavior: "smooth", block: "center" });
                    target.focus();
                    target.classList.add("is-invalid");
                }
            }, 180);
        }
    });
    root.addEventListener("hidden.bs.modal", () => root.remove(), { once: true });
    modal.show();
}

window.submitInspectionBatch = async function () {
    const record = currentInspectionRecord;
    if (!record || !isInspectionMapMode(record.InspectionMode)) return;
    if (String(record.Status || "").toUpperCase() === "DONE") {
        showToast("Inspeksi ini sudah disubmit dan seluruh jadwal terkunci.", "warning");
        return;
    }

    const lightning = String(record.InspectionMode || "").toUpperCase() === "LIGHTNING";
    const schedules = lightning
        ? (Array.isArray(record.Schedules) ? record.Schedules.map(item => String(item.ScheduleTime || item).trim()).filter(Boolean) : [])
        : [""];
    const masterPoints = record.BatchMapSetup && record.BatchMapSetup.points || [];
    const points = Array.isArray(record.Points) ? record.Points : [];
    if (!masterPoints.length) {
        showToast("Master Inspection Point belum tersedia.", "danger");
        return;
    }
    if (lightning && !schedules.length) {
        showToast("ScheduleTime Lightning belum tersedia. Sinkronkan master jadwal terlebih dahulu.", "danger");
        return;
    }

    const errors = [];
    const requirement = getInspectionPhotoRequirement(record);
    let completedPointCount = 0;
    for (const scheduleTime of schedules) {
        for (const masterPoint of masterPoints) {
            const pointId = Number(masterPoint.InspectionPointID);
            const point = points.find(item =>
                Number(item.InspectionPointID) === pointId &&
                String(item.ScheduleTime || "") === scheduleTime);
            const requireAll = masterPoint.RequireAllPoints == null
                ? true : isInspectionFlagEnabled(masterPoint.RequireAllPoints, true);
            const pointCode = String(masterPoint.PointCode || ("Point " + pointId));
            const errorBase = { pointCode, pointId, ScheduleTime: scheduleTime };
            if (!point) {
                if (requireAll) errors.push(Object.assign({}, errorBase, {
                    message: "Belum diinspeksi pada jadwal " + (scheduleTime || "-") + ".",
                    target: "point-complete"
                }));
                continue;
            }
            completedPointCount++;
            const photos = await getInspectionPhotos(record.LocalInspectionID, String(point.ClientPointID || ""));
            const items = Array.isArray(point.Items) ? point.Items : [];
            const touched = items.length > 0 || photos.length > 0 ||
                String(point.PointCondition || "").trim() !== "" ||
                String(point.AbnormalRemark || "").trim() !== "" ||
                !["", "PENDING"].includes(String(point.Status || "").toUpperCase());
            if (!requireAll && !touched) continue;

            validateInspectionItemsAll(items).forEach(error => errors.push(Object.assign({}, errorBase, {
                message: error.message, itemId: error.itemId, role: error.role
            })));
            const hasBefore = photos.some(photo => String(photo.Type || "").toUpperCase() === "BEFORE");
            const hasAfter = photos.some(photo => String(photo.Type || "").toUpperCase() === "AFTER");
            if ((requirement === "BEFORE" || requirement === "BOTH") && !hasBefore)
                errors.push(Object.assign({}, errorBase, { message: "Foto BEFORE belum dilampirkan.", target: "photo-before" }));
            if ((requirement === "AFTER" || requirement === "BOTH") && !hasAfter)
                errors.push(Object.assign({}, errorBase, { message: "Foto AFTER belum dilampirkan.", target: "photo-after" }));
            if (isInspectionFlagEnabled(masterPoint.IsNormalAbnormalRequired, false)) {
                const condition = String(point.PointCondition || "").toUpperCase();
                if (condition !== "NORMAL" && condition !== "ABNORMAL")
                    errors.push(Object.assign({}, errorBase, { message: "Kondisi NORMAL/ABNORMAL belum dipilih.", target: "condition" }));
                if (condition === "ABNORMAL" && !String(point.AbnormalRemark || "").trim())
                    errors.push(Object.assign({}, errorBase, { message: "Abnormal Remark belum diisi.", target: "abnormal-remark" }));
            }
            if (!["DONE", "ABNORMAL"].includes(String(point.Status || "").toUpperCase()))
                errors.push(Object.assign({}, errorBase, { message: "Point belum diselesaikan melalui Complete Point.", target: "point-complete" }));
        }
    }

    points.forEach(point => {
        const scheduleTime = String(point.ScheduleTime || "");
        const scheduleIsValid = !lightning || schedules.indexOf(scheduleTime) >= 0;
        if (!scheduleIsValid || !masterPoints.some(master =>
            Number(master.InspectionPointID) === Number(point.InspectionPointID))) {
            errors.push({
                pointCode: String(point.PointCode || ("Point " + point.InspectionPointID)),
                pointId: Number(point.InspectionPointID),
                ScheduleTime: scheduleTime,
                message: "Point tidak termasuk Master Map aktif pada jadwal ini."
            });
        }
    });

    if (!completedPointCount)
        errors.push({ pointCode: "Kelengkapan Inspeksi", message: "Belum ada Inspection Point yang diselesaikan." });

    const summary = String(document.getElementById("txtInspectionSummary")?.value || record.Summary || "").trim();
    if (inspectionTemplateRequiresSummary(record.TemplateSnapshot) && !summary)
        errors.push({ pointCode: "Kelengkapan Inspeksi", message: "Final Inspection Summary wajib diisi.", target: "summary" });
    const followUp = collectInspectionFollowUp();
    if (inspectionTemplateRequiresFollowUp(record.TemplateSnapshot) && followUp.FollowUp === "Recommend Follow Up" &&
        (!followUp.FollowUpSection || !followUp.FollowUpRemark))
        errors.push({
            pointCode: "Kelengkapan Inspeksi",
            message: "Responsible Section dan Follow Up Remark wajib diisi.",
            target: !followUp.FollowUpSection ? "followup-section" : "followup-remark"
        });

    if (errors.length) {
        showInspectionBatchValidationReport(errors);
        return;
    }

    const scheduleCount = lightning ? schedules.length : 1;
    const confirmed = await showConfirmation({
        title: lightning ? "Submit Lightning Daily Inspection" : "Submit Inspection Batch",
        message: lightning
            ? "Submit seluruh " + scheduleCount + " jadwal dan " + points.length +
                " point dalam satu transaksi harian? Setelah Submit, semua jadwal akan terkunci."
            : "Submit " + points.length + " titik? Checklist, foto, kondisi titik, dan pengaturan Master Version sudah lolos validasi.",
        yesText: lightning ? "Submit Semua Jadwal" : "Submit Batch"
    });
    if (!confirmed) return;

    await ensureInspectionGpsBeforeSubmit(record);
    applyLatestInspectionGps(record);
    record.Items = [];
    record.Summary = summary;
    Object.assign(record, followUp);
    record.ActiveInspectionPointID = 0;
    record.Status = "DONE";
    record.EndDateTime = localDateTimeString(new Date());
    record.SyncStatus = "PENDING";
    record.UpdatedAt = new Date().toISOString();
    await persistInspectionRecord(record);
    showToast(lightning
        ? "Lightning daily inspection tersimpan offline. Seluruh jadwal akan dikirim sebagai satu transaksi saat Sync."
        : "Inspection Batch tersimpan offline. Jalankan Sync untuk mengirim seluruh point, checklist, dan foto.", "success");
    await refreshSavedInspectionList();
    await closeInspectionForm();
};
async function saveInspection(status) {
    // Wait for any photo compression/IndexedDB write started by the photo picker.
    // This prevents Save/Submit from capturing a partially populated inspection_photos store.
    if (inspectionPhotoWritePromise) await inspectionPhotoWritePromise;

    if (currentInspectionRecord && isInspectionMapMode(currentInspectionRecord.InspectionMode)) {
        if (Number(currentInspectionRecord.ActiveInspectionPointID || 0) > 0) {
            await saveBatchInspectionPoint(status);
            return;
        }
        if (status === "DONE") {
            await window.submitInspectionBatch();
            return;
        }
        currentInspectionRecord.Summary = document.getElementById("txtInspectionSummary").value.trim();
        Object.assign(currentInspectionRecord, collectInspectionFollowUp());
        currentInspectionRecord.SyncStatus = "PENDING";
        await persistInspectionRecord(currentInspectionRecord);
        showToast("Draft batch tersimpan offline.", "success");
        return;
    }

    if (!currentInspectionRecord) return;
    const login = getLoginData();
    if (!login || currentInspectionRecord.OwnerEmployeeID !== login.employeeid) {
        showToast("Data ini bukan milik akun yang sedang login. Penyimpanan dibatalkan.", "danger");
        return;
    }
    if (currentInspectionRecord.Status === "DONE" && !isVoidedServerInspectionRecord(currentInspectionRecord)) {
        showToast("Inspeksi yang sudah Complete bersifat read-only.", "warning");
        return;
    }

    if (!await applyInspectionParameters()) return;

    const items = collectInspectionItems();
    const photos = await getCurrentInspectionPhotos();
    if (status === "DONE") {
        const error = validateInspectionItems(items);
        if (error) {
            showToast(error.message + ". Periksa kembali item yang ditandai merah.", "warning");
            showInspectionEditorTab("checklist");
            focusInvalidInspectionItem(error);
            return;
        }
        if (inspectionTemplateRequiresSummary(currentInspectionRecord.TemplateSnapshot) &&
            !String(document.getElementById("txtInspectionSummary").value || "").trim()) {
            showToast("Final Summary wajib diisi.", "warning");
            const summaryPanel = document.getElementById("inspectionSummaryPanel");
            if (summaryPanel) summaryPanel.scrollIntoView({ behavior: "smooth", block: "center" });
            document.getElementById("txtInspectionSummary").focus();
            return;
        }
        const followUp = collectInspectionFollowUp();
        if (inspectionTemplateRequiresFollowUp(currentInspectionRecord.TemplateSnapshot) && followUp.FollowUp === "Recommend Follow Up" && (!followUp.FollowUpSection || !followUp.FollowUpRemark)) {
            showToast("Pilih Responsible Section dan isi deskripsi pekerjaan untuk Follow Up.", "warning");
            return;
        }
        const requirement = getInspectionPhotoRequirement(currentInspectionRecord);
        const hasBefore = photos.some(p => String(p.Type || "").toUpperCase() === "BEFORE");
        const hasAfter = photos.some(p => String(p.Type || "").toUpperCase() === "AFTER");
        const missingBefore = (requirement === "BEFORE" || requirement === "BOTH") && !hasBefore;
        const missingAfter = (requirement === "AFTER" || requirement === "BOTH") && !hasAfter;
        if (missingBefore || missingAfter) {
            showToast(missingBefore && missingAfter
                ? "Foto BEFORE dan AFTER wajib diisi (minimal 1 foto untuk masing-masing)."
                : missingBefore ? "Foto BEFORE wajib diisi (minimal 1 foto)." : "Foto AFTER wajib diisi (minimal 1 foto).", "warning");
            showInspectionEditorTab("checklist");
            const target = document.getElementById(missingBefore ? "inspectionPhotoBeforeInput" : "inspectionPhotoAfterInput");
            if (target) target.scrollIntoView({ behavior: "smooth", block: "center" });
            return;
        }
    } else {
        const draftRequirement = getInspectionPhotoRequirement(currentInspectionRecord);
        if ((draftRequirement === "BEFORE" || draftRequirement === "BOTH") &&
            !photos.some(p => String(p.Type || "").toUpperCase() === "BEFORE")) {
            showToast("Foto BEFORE wajib diambil sebelum checklist dapat disimpan.", "warning");
            showInspectionEditorTab("checklist");
            return;
        }
    }

    // Ask for explicit confirmation only after all Submit validations pass.
    if (status === "DONE") {
        const confirmed = await showConfirmation({
            title: "Confirm Submit",
            message: "Are you sure you want to submit this data?",
            yesText: "Submit"
        });
        if (!confirmed) return;
    }

    await ensureInspectionGpsBeforeSubmit(currentInspectionRecord);
    applyLatestInspectionGps(currentInspectionRecord);
    currentInspectionRecord.Items = items;
    currentInspectionRecord.Summary = document.getElementById("txtInspectionSummary").value.trim();
    Object.assign(currentInspectionRecord, collectInspectionFollowUp());
    currentInspectionRecord.Status = status;
    currentInspectionRecord.SyncStatus = "PENDING";
    currentInspectionRecord.UpdatedAt = new Date().toISOString();
    // A voided inspection is being corrected, not restarted; preserve its original timestamps.
    if (status === "DONE" && !String(currentInspectionRecord.ReasonVoid || "").trim()) {
        currentInspectionRecord.EndDateTime = localDateTimeString(new Date());
    }

    if (inspectionAutoSaveTimer) clearTimeout(inspectionAutoSaveTimer);
    await persistInspectionRecord(currentInspectionRecord);
    inspectionPhotoBaseline = null;

    showToast(status === "DONE"
        ? "Inspeksi selesai dan tersimpan offline. Tekan Sync untuk mengirimnya."
        : "Draft tersimpan offline.", "success");
    await refreshSavedInspectionList();
    closeInspectionForm();
}

function scheduleInspectionAutosave() {
    // Kept as a no-op for existing input/photo event wiring.
    // Inspection records are persisted only by explicit Save Draft or Complete.
    if (inspectionAutoSaveTimer) {
        clearTimeout(inspectionAutoSaveTimer);
        inspectionAutoSaveTimer = null;
    }
}

function isInspectionRecordPersisted(localId) {
    return new Promise((resolve, reject) => {
        const tx = db.transaction("inspection_records", "readonly");
        const request = tx.objectStore("inspection_records").get(localId);
        request.onsuccess = () => resolve(!!request.result);
        request.onerror = () => reject(request.error || tx.error);
    });
}

function deleteInspectionPhotosForLocalRecord(localId) {
    return new Promise((resolve, reject) => {
        const tx = db.transaction("inspection_photos", "readwrite");
        const request = tx.objectStore("inspection_photos").index("LocalInspectionID")
            .openCursor(IDBKeyRange.only(localId));
        request.onsuccess = () => {
            const cursor = request.result;
            if (!cursor) return;
            cursor.delete();
            cursor.continue();
        };
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error || new Error("Gagal membersihkan foto inspeksi sementara."));
    });
}

function persistInspectionRecord(record) {
    return new Promise((resolve, reject) => {
        const tx = db.transaction("inspection_records", "readwrite");
        tx.objectStore("inspection_records").put(record);
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error || new Error("Gagal menyimpan inspeksi."));
    });
}

async function refreshSavedInspectionList() {
    const submittedTab = document.getElementById("inspectionSubmittedTab");
    const submittedActive = !!(submittedTab && submittedTab.classList.contains("active"));
    const fromInput = document.getElementById("txtSubmittedFrom");
    const thruInput = document.getElementById("txtSubmittedThru");
    const rawFromDate = fromInput ? fromInput.value : "";
    const rawThruDate = thruInput ? thruInput.value : "";
    const parsedFromDate = parseInspectionDateFilter(rawFromDate);
    const parsedThruDate = parseInspectionDateFilter(rawThruDate);
    if (submittedActive && (!parsedFromDate || !parsedThruDate || parsedFromDate > parsedThruDate)) {
        showToast("Tanggal From/Thru tidak valid. Pastikan From tidak melewati Thru.", "warning");
        return;
    }
    // Draft is a work queue, not a date-based report. Keep a harmless date
    // range for the Submitted server request, but never use it to filter Draft.
    const today = localDateString(new Date());
    const fromDate = parsedFromDate || today;
    const thruDate = parsedThruDate || fromDate;
    const all = await readInspectionStore("inspection_records");
    serverSlotRecords = all.filter(record => record.ServerOnly && record.CompanyID === inspectionCompanyID &&
        record.LocationID === inspectionLocationID);
    inspectionRecords = all.filter(record =>
        !record.ServerOnly &&
        record.OwnerEmployeeID === inspectionLogin.employeeid &&
        record.CompanyID === inspectionCompanyID &&
        record.LocationID === inspectionLocationID
    ).sort((a, b) => String(b.UpdatedAt || b.StartDateTime || "").localeCompare(String(a.UpdatedAt || a.StartDateTime || "")));
    updateInspectionConflictBadge();
    refreshInspectionScheduleOptions();

    serverSubmittedInspectionRecords = [];
    if (navigator.onLine) {
        try {
            const response = await fetch("inspection.aspx/GetInspectionEntryList", {
                method: "POST",
                headers: { "Content-Type": "application/json; charset=utf-8" },
                body: JSON.stringify({
                    employeeId: inspectionLogin.employeeid,
                    companyId: inspectionCompanyID,
                    locationId: inspectionLocationID,
                    fromDate: fromDate,
                    thruDate: thruDate
                })
            });
            const payload = await response.json();
            if (!response.ok) throw new Error((payload && payload.Message) || "Gagal memuat daftar submitted.");
            const result = payload && Object.prototype.hasOwnProperty.call(payload, "d") ? payload.d : payload;
            if (result.technicianName) {
                inspectionTechnicianName = result.technicianName;
                inspectionRecords.forEach(record => {
                    if (!record.TechnicianName || record.TechnicianName === record.OwnerEmployeeID) record.TechnicianName = inspectionTechnicianName;
                });
            }
            serverSubmittedInspectionRecords = result.data || [];
        } catch (err) {
            console.warn("Unable to refresh submitted inspections from server:", err);
        }
    }

    let returnedServerInspectionRecords = [];
    if (navigator.onLine) {
        try {
            const returnedResult = await inspectionApprovalPost("GetReturnedInspections", {
                employeeId: inspectionLogin.employeeid,
                companyId: inspectionCompanyID,
                locationId: inspectionLocationID
            });
            returnedServerInspectionRecords = returnedResult.data || [];
        } catch (returnedError) {
            console.warn("Unable to refresh returned inspections:", returnedError);
        }
    }

    // Conflicts must remain visible even when the rejected transaction was completed
    // for a prior date; otherwise technicians would have no way to resolve it.
    const drafts = inspectionRecords.filter(record =>
        record.Status === "DRAFT" || record.SyncStatus === "CONFLICT" || record.SyncStatus === "DELETE_PENDING");
    returnedServerInspectionRecords.forEach(record => {
        const local = inspectionRecords.find(item =>
            (record.ClientInspectionID && String(item.ClientInspectionID || "") === String(record.ClientInspectionID)) ||
            (record.InspectionID != null && Number(item.ServerInspectionID || item.InspectionID || 0) === Number(record.InspectionID)));
        if (local && (local.Status === "DRAFT" || local.SyncStatus !== "SYNCED")) return;
        drafts.push(Object.assign({}, record, {
            ServerOnly: true,
            ReturnedServerOnly: true,
            ServerInspectionID: Number(record.InspectionID)
        }));
    });

    // Submitted must only contain sections assigned to the currently logged-in employee.
    // Local IndexedDB may retain completed records created under an older section assignment.
    const allowedSectionIds = new Set(
        String(inspectionLogin.section || "").split(";")
            .map(section => section.trim().toUpperCase())
            .filter(Boolean)
    );

    // Keep completed local transactions visible until sync succeeds, regardless of InspectionDate.
    // Synced local copies follow the selected date range; the server remains the source for synced rows.
    // Apply the current employee section authorization before adding either local or server rows.
    const submittedCandidates = inspectionRecords.filter(record =>
        allowedSectionIds.has(String(record.SectionID || "").trim().toUpperCase()) &&
        record.Status === "DONE" &&
        record.SyncStatus !== "CONFLICT" &&
        record.SyncStatus !== "DELETE_PENDING" &&
        (record.SyncStatus !== "SYNCED" ||
            isInspectionWithinSubmittedRange(record, fromDate, thruDate)));

    serverSubmittedInspectionRecords.forEach(record => {
        if (!allowedSectionIds.has(String(record.SectionID || "").trim().toUpperCase())) return;

        // Server rows appear in Submitted by the server-side approval/void date range.
        const syncDate = parseInspectionDate(record && record.SyncDate);
        if (!syncDate || syncDate < fromDate || syncDate > thruDate) return;

        // Match server rows to local counterparts using stable IDs first, then transaction number.
        const local = inspectionRecords.find(item =>
            (record.ClientInspectionID && item.LocalInspectionID === record.ClientInspectionID) ||
            (record.InspectionID != null && item.ServerInspectionID != null &&
                String(item.ServerInspectionID) === String(record.InspectionID)) ||
            (record.InspectionNo && item.InspectionNo &&
                String(item.InspectionNo).trim().toLowerCase() === String(record.InspectionNo).trim().toLowerCase())
        );
        if (local && (local.SyncStatus === "CONFLICT" || local.SyncStatus === "DELETE_PENDING")) return;

        // A local pending version must win over the stale server copy for the same transaction.
        if (local && local.Status === "DONE" && local.SyncStatus !== "SYNCED") {
            if (!local.InspectionNo && record.InspectionNo) local.InspectionNo = record.InspectionNo;
            if (!local.ServerInspectionID && record.InspectionID) local.ServerInspectionID = Number(record.InspectionID);
            return;
        }
        submittedCandidates.push(local ? Object.assign({}, local, record, {
            LocalInspectionID: local.LocalInspectionID,
            InspectionNo: record.InspectionNo || local.InspectionNo || "",
            TechnicianName: record.TechnicianName || local.TechnicianName || ""
        }) : record);
    });

    // One row per transaction number. Prefer pending local data; otherwise prefer the server row.
    const submittedById = new Map();
    submittedCandidates.forEach(record => {
        const number = String(record.InspectionNo || "").trim().toLowerCase();
        const key = number
            ? "NO:" + number
            : "ID:" + String(record.LocalInspectionID || record.ClientInspectionID || record.ServerInspectionID || record.InspectionID || "");
        const existing = submittedById.get(key);
        const isPendingLocal = record.LocalInspectionID && record.SyncStatus !== "SYNCED" && !record.ServerOnly;
        const existingIsPendingLocal = existing && existing.LocalInspectionID &&
            existing.SyncStatus !== "SYNCED" && !existing.ServerOnly;
        if (!existing || isPendingLocal || !existingIsPendingLocal) submittedById.set(key, record);
    });

    renderInspectionRecordTable(drafts, document.getElementById("inspectionDraftList"), false);
    const submittedRows = Array.from(submittedById.values());
    populateTechnicianSubmittedFilters(submittedRows);
    const filteredSubmittedRows = submittedRows.filter(record => {
        const type = document.getElementById("selSubmittedType").value;
        const detail = document.getElementById("selSubmittedDetail").value;
        const schedule = document.getElementById("selSubmittedScheduleTime").value;
        return (!type || String(record.InspectionTypeCode || "") === type) &&
            (!detail || String(record.InspectionTypeDetailCode || "") === detail) &&
            (!schedule || String(record.ScheduledTime || "") === schedule);
    });
    renderInspectionRecordTable(filteredSubmittedRows, document.getElementById("inspectionSubmittedList"), true);

    if (!returnedInspectionDeepLinkHandled && window.location && window.location.search) {
        const query = new URLSearchParams(window.location.search);
        const requestedInspectionId = Number(query.get("inspectionId") || 0);
        if (requestedInspectionId > 0) {
            const returned = returnedServerInspectionRecords.find(item => Number(item.InspectionID) === requestedInspectionId);
            if (returned) {
                returnedInspectionDeepLinkHandled = true;
                window.setTimeout(() => openServerReturnedInspection(requestedInspectionId), 120);
            }
        }
    }
}

async function populateTechnicianSubmittedFilters(records) {
    const specs = [
        { id: "selSubmittedType", key: "InspectionTypeCode", label: "InspectionTypeName", all: "All types" },
        { id: "selSubmittedDetail", key: "InspectionTypeDetailCode", label: "InspectionTypeDetailName", all: "All details" },
        { id: "selSubmittedScheduleTime", key: "ScheduledTime", label: "ScheduledTime", all: "All schedules" }
    ];
    const currentType = document.getElementById("selSubmittedType").value;
    const currentDetail = document.getElementById("selSubmittedDetail").value;
    specs.forEach(spec => {
        const select = document.getElementById(spec.id);
        const previous = select.value;
        const applicable = records.filter(row => {
            if (spec.id !== "selSubmittedType" && currentType && String(row.InspectionTypeCode || "") !== currentType) return false;
            if (spec.id === "selSubmittedScheduleTime" && currentDetail && String(row.InspectionTypeDetailCode || "") !== currentDetail) return false;
            return true;
        });
        const values = new Map();
        applicable.forEach(row => {
            const value = String(row[spec.key] == null ? "" : row[spec.key]);
            if (value && !values.has(value)) values.set(value, spec.id === "selSubmittedDetail" ? (value + " - " + String(row[spec.label] || value)) : String(row[spec.label] || value));
        });
        select.innerHTML = '<option value="">' + spec.all + '</option>' +
            Array.from(values.entries()).sort((a,b) => a[1].localeCompare(b[1])).map(pair =>
                '<option value="' + escInspection(pair[0]) + '">' + escInspection(pair[1]) + '</option>'
            ).join("");
        select.value = values.has(previous) ? previous : "";
    });
    document.getElementById("selSubmittedDetail").disabled = !currentType;
}

async function openServerReturnedInspection(inspectionId) {
    if (!inspectionId || !navigator.onLine) {
        showToast("Koneksi diperlukan untuk membuka inspeksi yang dikembalikan.", "warning");
        return;
    }
    try {
        const returnedResult = await inspectionApprovalPost("GetReturnedInspections", {
            employeeId: inspectionLogin.employeeid,
            companyId: inspectionCompanyID,
            locationId: inspectionLocationID
        });
        const serverRecord = (returnedResult.data || []).find(item => Number(item.InspectionID) === Number(inspectionId));
        if (!serverRecord) throw new Error("Inspeksi yang dikembalikan tidak ditemukan atau sudah berubah status.");

        const local = inspectionRecords.find(item =>
            (serverRecord.ClientInspectionID && String(item.ClientInspectionID || "") === String(serverRecord.ClientInspectionID)) ||
            Number(item.ServerInspectionID || item.InspectionID || 0) === Number(inspectionId));
        if (local && local.SyncStatus !== "SYNCED") {
            await openSavedInspection(local.LocalInspectionID);
            return;
        }

        const localId = local ? local.LocalInspectionID : (serverRecord.ClientInspectionID || newInspectionId());
        const type = inspectionTypes.find(item => String(item.InspectionTypeCode || "") === String(serverRecord.InspectionTypeCode || ""));
        const detailKey = String(serverRecord.InspectionTypeDetailCode || "").toUpperCase();
        const mapSetup = type && type.BatchMapSetups ? type.BatchMapSetups[detailKey] || null : null;
        const record = Object.assign({}, local || {}, serverRecord, {
            LocalInspectionID: localId,
            ClientInspectionID: serverRecord.ClientInspectionID || (local && local.ClientInspectionID) || localId,
            InspectionID: Number(serverRecord.InspectionID),
            ServerInspectionID: Number(serverRecord.InspectionID),
            InspectionMode: String(serverRecord.InspectionMode || "STANDARD").toUpperCase(),
            BatchMapSetup: mapSetup,
            Status: "DRAFT",
            SyncStatus: "SYNCED",
            ReasonVoid: String(serverRecord.ReasonVoid || ""),
            Points: Array.isArray(serverRecord.Points) ? serverRecord.Points : [],
            Schedules: Array.isArray(serverRecord.Schedules) ? serverRecord.Schedules : [],
            ActiveScheduleTime: serverRecord.ActiveScheduleTime ||
                (serverRecord.Schedules && serverRecord.Schedules.length
                    ? String(serverRecord.Schedules[0].ScheduleTime || serverRecord.Schedules[0]) : ""),
            ActiveInspectionPointID: 0,
            UpdatedAt: new Date().toISOString()
        });
        if (!record.TemplateSnapshot) {
            const template = inspectionTemplates.find(item =>
                Number(item.IDTemplate) === Number(record.IDTemplate) &&
                Number(item.IDVersion) === Number(record.IDVersion));
            if (template) record.TemplateSnapshot = template;
        }

        const photoResult = await inspectionApprovalPost("GetReturnedInspectionPhotos", {
            clientInspectionId: record.ClientInspectionID,
            employeeId: inspectionLogin.employeeid,
            companyId: inspectionCompanyID,
            locationId: inspectionLocationID
        });
        const serverPhotos = photoResult.data || [];
        await deleteInspectionPhotosForLocalRecord(localId);
        for (const photo of serverPhotos) {
            if (!photo.Data) continue;
            const blob = await (await fetch(photo.Data)).blob();
            await new Promise((resolve, reject) => {
                const tx = db.transaction("inspection_photos", "readwrite");
                tx.objectStore("inspection_photos").add({
                    LocalInspectionID: localId,
                    PointID: String(photo.PointID || ""),
                    Type: String(photo.Type || photo.PhotoType || "").toUpperCase(),
                    FileName: String(photo.FileName || "inspection.jpg"),
                    Blob: blob,
                    SeqNo: Number(photo.SeqNo || 1),
                    CreatedAt: new Date().toISOString()
                });
                tx.oncomplete = resolve;
                tx.onerror = () => reject(tx.error || new Error("Gagal menyimpan foto inspeksi yang dikembalikan."));
                tx.onabort = () => reject(tx.error || new Error("Penyimpanan foto inspeksi yang dikembalikan dibatalkan."));
            });
        }
        record.NextPhotoSeqNo = serverPhotos.reduce((max, photo) => Math.max(max, Number(photo.SeqNo || 0)), 0) + 1;
        await persistInspectionRecord(record);
        await refreshSavedInspectionList();
        await openSavedInspection(localId);
        showToast("Inspeksi dikembalikan berhasil dibuka. Perbaiki data lalu Submit ulang.", "warning");
    } catch (error) {
        showToast(error.message || "Gagal membuka inspeksi yang dikembalikan.", "danger");
    }
}

function getInspectionConflictDisplayReason(record) {
    const value = String(record && record.ConflictReason || "").trim();
    const lower = value.toLowerCase();
    const duplicateInspection =
        lower.includes("an inspection already exists for this date") ||
        lower.includes("already exists for this date") ||
        (lower.includes("duplicate") && lower.includes("inspection") &&
         (lower.includes("schedule") || lower.includes("template"))) ||
        lower.includes("sudah lebih dulu disimpan") ||
        lower.includes("jadwal inspeksi ini sudah dipakai");
    const hasTenantSuite = (lower.includes("tenant") && lower.includes("suite")) ||
        !!(record && String(record.TenantID || "").trim() && String(record.SuiteNo || "").trim());
    if (duplicateInspection && hasTenantSuite)
        return "Inspeksi untuk Tenant dan Suite yang sama sudah lebih dulu disimpan dari perangkat lain dengan jadwal dan template tersebut. Draft ini belum masuk ke data utama. Jika ini duplikat, klik Hapus Draft Ini. Bila ragu, tanyakan ke SPV.";
    if (duplicateInspection)
        return "Inspeksi dengan pilihan dan jadwal yang sama sudah lebih dulu disimpan dari perangkat lain. Draft ini belum masuk ke data utama. Jika ini duplikat, klik Hapus Draft Ini. Bila ragu, tanyakan ke SPV.";

    // Older drafts may still contain the technical exception text from earlier sync versions.
    const technicalMarkers = [
        "system.exception", "sqlexception", "uncommittable transaction",
        "stack trace", "tahap:", "procedure", "line ", " at inspec."
    ];
    if (technicalMarkers.some(marker => lower.includes(marker)) || value.length > 300)
        return "Data inspeksi ini bentrok dengan data yang sudah ada. Periksa kembali jadwal dan pilihan inspeksinya. Jika masih ragu, hubungi SPV.";

    return value || "Data inspeksi ini belum dapat dikirim karena ada bentrok data. Hubungi SPV bila perlu pengecekan.";
}

function getInspectionRecordGridStatus(record, submitted) {
    const status = String(record && record.Status || "").trim().toUpperCase();
    const syncStatus = String(record && record.SyncStatus || "").trim().toUpperCase();
    const hasVoidReason = [
        record && record.ReasonVoid,
        record && record.ReasonVoid1,
        record && record.ReasonVoid2
    ].some(value => String(value || "").trim() !== "");

    if (syncStatus === "CONFLICT")
        return { label: "Konflik Data", badge: "text-bg-danger" };
    if (syncStatus === "DELETE_PENDING")
        return { label: "Pending Delete", badge: "text-bg-warning" };
    if (status === "DRAFT" && hasVoidReason)
        return { label: "Returned", badge: "text-bg-warning" };
    if (!submitted || status === "DRAFT")
        return { label: "Draft", badge: "text-bg-secondary" };

    const pendingLocalSync = !record.ServerOnly && !!syncStatus && syncStatus !== "SYNCED";
    if (pendingLocalSync)
        return { label: "Pending Sync", badge: "text-bg-warning" };

    if (isInspectionFlagEnabled(record && record.IsApproved2, false))
        return { label: "Approved 2", badge: "text-bg-success" };
    if (isInspectionFlagEnabled(record && record.IsApproved1, false))
        return { label: "Approved 1", badge: "text-bg-success" };
    if (isInspectionFlagEnabled(record && record.IsApproved, false))
        return { label: "SPV Approved", badge: "text-bg-success" };
    if (isInspectionFlagEnabled(record && record.IsSubmitted, status === "DONE"))
        return { label: "Submitted", badge: "text-bg-primary" };

    return { label: status === "DONE" ? "Submitted" : "Draft", badge: "text-bg-primary" };
}

function renderInspectionRecordTable(records, host, submitted) {
    if (!records.length) {
        host.innerHTML = '<div class="text-muted py-2">' +
            (submitted ? "Belum ada inspeksi submitted." : "Belum ada draft inspeksi.") +
            '</div>';
        return;
    }
    const columns = [
        { key: "inspectionNo", label: "Inspection No." },
        { key: "inspectionDate", label: "Inspection Date/Time" },
        { key: "startEnd", label: "Start/End" },
        { key: "inspectionType", label: "Inspection Type" },
        { key: "locationArea", label: "Location/Area" },
        { key: "technician", label: "Technician" },
        { key: "status", label: "Status" }
    ];
    const header = '<thead><tr>' + columns.map(column => {
        const active = inspectionGridSort.key === column.key;
        const indicatorClass = active ? (inspectionGridSort.direction === "asc" ? "is-asc" : "is-desc") : "";
        return '<th class="text-nowrap" role="button" tabindex="0" data-inspection-sort="' + column.key + '" aria-sort="' +
            (active ? (inspectionGridSort.direction === "asc" ? "ascending" : "descending") : "none") + '">' +
            column.label + '<span class="inspection-sort-indicator ' + indicatorClass + '" aria-hidden="true"></span></th>';
    }).join("") + '</tr></thead>';
    const sortedRecords = records.slice().sort((a, b) => {
        const value = record => {
            switch (inspectionGridSort.key) {
                case "inspectionNo": return String(record.InspectionNo || record.LocalInspectionID || "");
                case "startEnd": return String(record.StartDateTime || "") + "|" + String(record.EndDateTime || "");
                case "inspectionType": return String(record.InspectionTypeName || "");
                case "locationArea": return String(record.InspectionTypeDetailName || "");
                case "technician": return String(record.TechnicianName || (record.OwnerEmployeeID === inspectionLogin.employeeid ? inspectionTechnicianName : "") || "");
                case "status": return getInspectionRecordGridStatus(record, submitted).label;
                case "inspectionDate": default: return String(parseInspectionDate(record.InspectionDate) || "") + "|" + String(record.ScheduledTime || "");
            }
        };
        const result = value(a).localeCompare(value(b), undefined, { numeric: true, sensitivity: "base" });
        return inspectionGridSort.direction === "asc" ? result : -result;
    });
    const rows = sortedRecords.map(record => {
        const localId = record.LocalInspectionID || record.ClientInspectionID || "";
        const number = record.InspectionNo ||
            (localId ? "TEMP-" + String(localId).substring(0, 8).toUpperCase() : "—");
        const start = formatInspectionClockTime(record.StartDateTime);
        const end = formatInspectionClockTime(record.EndDateTime);
        const date = parseInspectionDate(record.InspectionDate);
        const inspectionDateTime = date ? formatInspectionDateDMY(date) + (record.ScheduledTime ? " " + record.ScheduledTime : "") : (record.ScheduledTime || "—");
        const startEnd = (start || "—") + " - " + end;
        const localExists = !!inspectionRecords.find(item => item.LocalInspectionID === localId);
        const serverId = record.InspectionID || record.ServerInspectionID || "";
        const numberHtml = record.ReturnedServerOnly && serverId
            ? '<button type="button" class="btn btn-link btn-sm p-0 text-nowrap" data-open-returned-inspection="' + escInspection(serverId) + '">' + escInspection(number) + '</button>'
            : (localExists
                ? '<button type="button" class="btn btn-link btn-sm p-0 text-nowrap" data-open-inspection="' + escInspection(localId) + '">' + escInspection(number) + '</button>'
                : (submitted && serverId
                    ? '<button type="button" class="btn btn-link btn-sm p-0 text-nowrap" data-open-server-inspection="' + escInspection(serverId) + '">' + escInspection(number) + '</button>'
                    : escInspection(number)));
        const conflictHtml = record.SyncStatus === "CONFLICT"
            ? '<div class="text-danger small mt-1"><strong>Konflik data:</strong> ' + escInspection(getInspectionConflictDisplayReason(record)) + '</div>'
            : record.SyncStatus === "DELETE_PENDING"
                ? '<div class="text-warning small mt-1">' +
                    (record.DeleteOriginalSyncStatus === "VOIDED"
                        ? 'Menunggu server menonaktifkan inspeksi void sebelum data lokal dihapus.'
                        : 'Menunggu arsip server sebelum transaksi lokal dihapus.') +
                  (record.DeleteReasonCancel ? '<div>Reason Cancel: ' + escInspection(record.DeleteReasonCancel) + '</div>' : '') +
                  (record.DeleteArchiveError ? '<div class="text-danger">Sync terakhir: ' + escInspection(record.DeleteArchiveError) + '</div>' : '') +
                  '</div>'
                : "";
        const returnedHtml = record.ReturnedServerOnly && String(record.ReasonVoid || "").trim()
            ? '<div class="text-warning small mt-1"><strong>Returned:</strong> ' + escInspection(record.ReasonVoid) + '</div>'
            : "";
        const deleteHtml = record.SyncStatus === "CONFLICT"
            ? '<button type="button" class="btn btn-sm btn-outline-danger mt-1" data-delete-conflict="' + escInspection(localId) + '">Hapus Draft Ini</button>'
            : (record.SyncStatus === "DELETE_PENDING" && record.DeleteOriginalSyncStatus === "VOIDED"
                ? '<button type="button" class="btn btn-sm btn-outline-secondary mt-1" data-edit-delete-reason="' + escInspection(localId) + '">Reason Cancel</button>'
                : "");
        const technicianName = record.TechnicianName && record.TechnicianName !== record.OwnerEmployeeID
            ? record.TechnicianName
            : (record.OwnerEmployeeID === inspectionLogin.employeeid ? inspectionTechnicianName : "");
        const gridStatus = getInspectionRecordGridStatus(record, submitted);
        const statusHtml = '<span class="badge rounded-pill ' + gridStatus.badge + '">' +
            escInspection(gridStatus.label) + '</span>';
        const mainRow = '<tr class="inspection-record-main-row">' +
            '<td data-label="Inspection No.">' + numberHtml + '</td>' +
            '<td data-label="Inspection Date/Time">' + escInspection(inspectionDateTime) + '</td>' +
            '<td data-label="Start/End">' + escInspection(startEnd) + '</td>' +
            '<td data-label="Inspection Type">' + escInspection(record.InspectionTypeName || "—") + '</td>' +
            '<td data-label="Location/Area">' + escInspection(record.InspectionTypeDetailName || "—") +
                (record.TenantID && record.SuiteNo ? '<div class="small text-muted">Tenant: ' + escInspection(record.TenantID) +
                    ' / Suite ' + escInspection(record.SuiteNo) + '</div>' : '') + '</td>' +
            '<td data-label="Technician">' + escInspection(technicianName || "—") + deleteHtml + '</td>' +
            '<td data-label="Status">' + statusHtml + '</td>' +
            '</tr>';
        const messageRow = conflictHtml || returnedHtml
            ? '<tr class="inspection-grid-message-row"><td colspan="7" class="small" style="white-space:normal;overflow-wrap:anywhere;word-break:break-word;padding-top:0.25rem;padding-bottom:0.5rem;">' + conflictHtml + returnedHtml + '</td></tr>'
            : "";
        return mainRow + messageRow;
    }).join("");
    host.innerHTML = '<div class="table-responsive inspection-record-table-wrap"><table class="table table-sm table-hover align-middle mb-0 inspection-record-table">' +
        header + '<tbody>' + rows + '</tbody></table></div>';
    if (!host.dataset.sortWired) {
        host.dataset.sortWired = "1";
        const sortFromEvent = event => {
            const th = event.target.closest("[data-inspection-sort]");
            if (!th || !host.contains(th)) return;
            const key = th.dataset.inspectionSort;
            if (inspectionGridSort.key === key) inspectionGridSort.direction = inspectionGridSort.direction === "asc" ? "desc" : "asc";
            else { inspectionGridSort.key = key; inspectionGridSort.direction = "asc"; }
            refreshSavedInspectionList().catch(err => console.error("Unable to sort inspection list:", err));
        };
        host.addEventListener("click", sortFromEvent);
        host.addEventListener("keydown", event => {
            if ((event.key === "Enter" || event.key === " ") && event.target.matches("[data-inspection-sort]")) {
                event.preventDefault();
                sortFromEvent(event);
            }
        });
    }
}

function isInspectionWithinSubmittedRange(record, fromDate, thruDate) {
    // LastSyncAt is stored as an ISO UTC timestamp; compare its local calendar date.
    const syncValue = record && (record.LastSyncAt || record.SyncDate);
    if (!syncValue) return false;
    const parsed = new Date(syncValue);
    if (Number.isNaN(parsed.getTime())) return false;
    const syncDate = localDateString(parsed);
    return syncDate >= fromDate && syncDate <= thruDate;
}

function parseInspectionDate(value) {
    if (!value) return "";
    const asp = String(value).match(/\/Date\((\d+)/);
    if (asp) return localDateString(new Date(Number(asp[1])));
    const text = String(value);
    if (/^\d{4}-\d{2}-\d{2}/.test(text)) return text.substring(0, 10);
    const date = new Date(text);
    return Number.isNaN(date.getTime()) ? "" : localDateString(date);
}

function formatInspectionClockTime(value) {
    if (!value) return "";
    const asp = String(value).match(/\/Date\((\d+)/);
    const date = asp ? new Date(Number(asp[1])) : new Date(value);
    if (Number.isNaN(date.getTime()) || date.getFullYear() <= 1900) return "";
    return String(date.getHours()).padStart(2, "0") + ":" +
        String(date.getMinutes()).padStart(2, "0");
}

async function openServerSubmittedInspection(inspectionId) {
    if (!navigator.onLine) {
        showToast("Koneksi internet diperlukan untuk membuka detail inspeksi dari server.", "warning");
        return;
    }
    const host = document.getElementById("inspectionChecklistHost");
    if (!host) return;
    try {
        showToast("Memuat detail checklist dari server...", "info");
        const result = await inspectionApprovalPost("GetTechnicianSubmittedInspectionDetail", {
            inspectionId: Number(inspectionId), employeeId: inspectionLogin.employeeid
        });
        const h = result.header || {};
        serverInspectionPhotoPreview = Array.isArray(result.photos) ? result.photos.slice() : [];
        const template = result.template || result.TemplateSnapshot;
        if (!template || !Array.isArray(template.sections) || !template.sections.length) {
            showToast("Struktur template checklist tidak tersedia dari server.", "warning");
            return;
        }
        stopInspectionGpsWatch();
        inspectionLatestGps = null;
        currentInspectionRecord = null;
        currentInspectionReadOnly = true;
        renderInspectionApprovalWorkflowCards(null);
        inspectionPhotoBaseline = null;
        showInspectionInputScreen();
        document.getElementById("inspectionEditorTabs").classList.remove("d-none");
        // Server-submitted detail must follow the same MAP visibility rule as local records.
        const mapTabButton = document.getElementById("btnInspectionMapTab");
        if (mapTabButton && mapTabButton.closest("li")) {
            mapTabButton.closest("li").classList.toggle(
                "d-none",
                !isInspectionMapMode(h.InspectionMode)
            );
        }
        document.getElementById("inspectionStartButtonRow").classList.add("d-none");
        document.getElementById("inspectionStartPanel").classList.remove("d-none");
        // Server-only records may no longer have their masters in IndexedDB. Show the
        // transaction parameters from the server response instead of relying on local dropdown data.
        const typeSelect = document.getElementById("selInspectionType");
        const detailSelect = document.getElementById("selInspectionDetail");
        const scheduleTimeSelect = document.getElementById("selInspectionScheduleTime");
        const templateSelect = document.getElementById("selInspectionTemplate");
        typeSelect.innerHTML = '<option value="__server_type__">' + escInspection(h.InspectionTypeName || h.InspectionTypeCode || "-") + '</option>';
        typeSelect.value = "__server_type__";
        detailSelect.innerHTML = '<option value="__server_detail__">' + escInspection(h.InspectionTypeDetailName || h.InspectionTypeDetailCode || "-") + '</option>';
        detailSelect.value = "__server_detail__";
        scheduleTimeSelect.innerHTML = '<option value="' + escInspection(h.ScheduledTime || "") + '">' + escInspection(h.ScheduledTime || "Tanpa jadwal") + '</option>';
        scheduleTimeSelect.value = h.ScheduledTime || "";
        templateSelect.innerHTML = '<option value="' + escInspection(h.IDTemplate || "__server_template__") + '">' + escInspection((h.TemplateNo || "Template") + " / v" + (h.TemplateVersion || "-")) + '</option>';
        templateSelect.value = String(h.IDTemplate || "__server_template__");

        // This server-only submitted view does not call populateInspectionParameters().
        // Restore the tenant/suite fields directly from the authoritative header.
        const tenantPanel = document.getElementById("inspectionTenantPanel");
        const tenantSelect = document.getElementById("selInspectionTenant");
        const suiteSelect = document.getElementById("selInspectionSuite");
        const savedTenantID = String(h.TenantID || "").trim();
        const savedSuiteNo = String(h.SuiteNo || "").trim();
        const savedTenantName = await resolveInspectionTenantName(savedTenantID, h.TenantName);
        if (tenantPanel && tenantSelect && suiteSelect && (savedTenantID || savedSuiteNo)) {
            tenantPanel.classList.remove("d-none");
            tenantSelect.innerHTML = savedTenantID
                ? '<option value="' + escInspection(savedTenantID) + '">' +
                    escInspection(formatInspectionTenantLabel(savedTenantID, savedTenantName)) + '</option>'
                : '<option value="">-</option>';
            tenantSelect.value = savedTenantID;
            const tenantSearch = document.getElementById("txtInspectionTenantSearch");
            if (tenantSearch) {
                tenantSearch.value = "";
                tenantSearch.disabled = true;
            }
            applyInspectionTenantSearch();
            suiteSelect.innerHTML = savedSuiteNo
                ? '<option value="' + escInspection(savedSuiteNo) + '">' + escInspection(savedSuiteNo) + '</option>'
                : '<option value="">-</option>';
            suiteSelect.value = savedSuiteNo;
            tenantSelect.disabled = true;
            suiteSelect.disabled = true;
        } else {
            resetInspectionTenantSelection();
        }

        [typeSelect, detailSelect, scheduleTimeSelect, templateSelect].forEach(select => { select.disabled = true; });
        document.getElementById("txtInspectionDate").value = inspectionDateInputValue(h.InspectionDate);
        document.getElementById("txtInspectionDate").disabled = true;
        updateInspectionParameterTabGate();
        document.getElementById("inspectionFormPanel").classList.remove("d-none");
        document.getElementById("btnDeleteInspectionDraft").classList.add("d-none");
        document.getElementById("btnSaveInspectionDraft").classList.add("d-none");
        document.getElementById("btnCompleteInspection").classList.add("d-none");
        setInspectionFormHeader(h.InspectionNo || ("Inspection #" + inspectionId), [
            (h.InspectionTypeName || "Inspection") + " — " + (h.InspectionTypeDetailName || ""),
            formatInspectionTenantSuiteInfo(h.TenantID, savedTenantName, h.SuiteNo),
            "Teknisi: " + formatInspectionEmployeeLabel(h.TechnicianName || h.OwnerEmployeeName, h.OwnerEmployeeID),
            (h.TemplateNo || "-") + " / v" + (h.TemplateVersion || "-"),
            "Jadwal " + (h.ScheduledTime || "-") + " • " + (formatInspectionDateDMY(h.InspectionDate) || "-"),
            formatInspectionClock(h.StartDateTime) + " - " + formatInspectionClock(h.EndDateTime),
            "Status: " + getInspectionRecordGridStatus(h, true).label
        ]);
        renderInspectionApprovalWorkflowCards(h);
        document.getElementById("txtInspectionSummary").value = h.Summary || "";
        document.getElementById("txtInspectionSummary").readOnly = true;
        document.querySelectorAll('input[name="inspectionFollowUp"]').forEach(input => {
            input.disabled = true;
            input.checked = String(h.FollowUp || "") === input.value;
        });
        document.getElementById("inspectionFollowUpSection").disabled = true;
        document.getElementById("txtInspectionFollowUpRemark").value = h.FollowUpRemark || "";
        document.getElementById("txtInspectionFollowUpRemark").readOnly = true;
        const items = result.items || [];
        host.innerHTML = renderInspectionSections(template, items, true, "serverSubmittedInspectionSection");
        const renderPhotos = type => {
            const photos = (result.photos || []).filter(p => String(p.Type || "").toUpperCase() === type);
            return photos.length
                ? '<div class="d-flex flex-wrap gap-2">' +
                    photos.map((p,i) => '<button type="button" class="inspection-photo-item inspection-approval-photo-item" data-approval-photo-type="' + type + '" data-server-photo-index="' + i + '"><img src="' + escInspection(p.Data || "") + '" alt="Inspection ' + type + '" loading="lazy"></button>').join("") +
                  '</div>'
                : '<div class="text-muted small mb-2">Foto ' + type + ' belum tersedia.</div>';
        };
        document.getElementById("inspectionPhotoBeforeList").innerHTML = renderPhotos("BEFORE");
        document.getElementById("inspectionPhotoAfterList").innerHTML = renderPhotos("AFTER");
        document.getElementById("inspectionPhotoBeforeInput").classList.add("d-none");
        document.getElementById("inspectionPhotoAfterInput").classList.add("d-none");
        // Server-submitted detail is read-only: hide capture controls, keep preview thumbnails.
        ["btnAddInspectionBeforePhoto", "btnAddInspectionAfterPhoto"].forEach(id => {
            const button = document.getElementById(id);
            if (button) button.classList.add("d-none");
            const label = button && button.parentElement && button.parentElement.querySelector("label");
            if (label) label.classList.add("d-none");
        });
        showInspectionEditorTab("checklist");
        showToast("Detail checklist berhasil dimuat dari server (read-only).", "success");
    } catch (err) {
        showToast((err && err.message) || "Gagal membuka detail inspeksi dari server.", "warning");
        console.warn("Open server inspection detail failed:", err);
    }
}

function isVoidedServerInspectionRecord(record) {
    return !!record &&
        Number(record.ServerInspectionID) > 0 &&
        String(record.ReasonVoid || "").trim() !== "" &&
        (record.SyncStatus === "SYNCED" || record.VoidedServerInspection === true);
}

async function openSavedInspection(localId) {
    const record = inspectionRecords.find(x => x.LocalInspectionID === localId);
    if (!record) return;

    // A server-voided inspection is reopened for correction, even if its previous
    // local status was DONE. Keep the marker so Delete Draft still targets the server row
    // if the technician saves a local draft before deciding to delete it.
    if (record.SyncStatus === "SYNCED" && Number(record.ServerInspectionID) > 0 &&
        String(record.ReasonVoid || "").trim() !== "") {
        record.VoidedServerInspection = true;
    }

    // For synced inspections, use server timestamps as the source of truth.
    // The IndexedDB copy may have an empty/stale EndDateTime even though SQL Server has it.
    if (record.SyncStatus === "SYNCED" && Array.isArray(serverSubmittedInspectionRecords)) {
        const serverRecord = serverSubmittedInspectionRecords.find(item =>
            (item.ClientInspectionID && item.ClientInspectionID === record.LocalInspectionID) ||
            (item.InspectionID != null && record.ServerInspectionID != null &&
                String(item.InspectionID) === String(record.ServerInspectionID)) ||
            (item.InspectionNo && record.InspectionNo &&
                String(item.InspectionNo).trim().toLowerCase() === String(record.InspectionNo).trim().toLowerCase())
        );
        if (serverRecord) {
            if (serverRecord.StartDateTime) record.StartDateTime = serverRecord.StartDateTime;
            if (serverRecord.EndDateTime) record.EndDateTime = serverRecord.EndDateTime;
            if (serverRecord.InspectionID != null) record.ServerInspectionID = Number(serverRecord.InspectionID);
            if (serverRecord.ReasonVoid) record.ReasonVoid = serverRecord.ReasonVoid;
            if (serverRecord.IsSubmitted != null) record.IsSubmitted = serverRecord.IsSubmitted;
            if (serverRecord.SubmittedBy != null) record.SubmittedBy = serverRecord.SubmittedBy;
            if (serverRecord.SubmittedByName != null) record.SubmittedByName = serverRecord.SubmittedByName;
            if (serverRecord.SubmittedDate != null) record.SubmittedDate = serverRecord.SubmittedDate;
            if (serverRecord.IsApproved != null) record.IsApproved = serverRecord.IsApproved;
            if (serverRecord.ApprovedBy != null) record.ApprovedBy = serverRecord.ApprovedBy;
            if (serverRecord.ApprovedByName != null) record.ApprovedByName = serverRecord.ApprovedByName;
            if (serverRecord.ApprovedDate != null) record.ApprovedDate = serverRecord.ApprovedDate;
            if (serverRecord.IsApproved1 != null) record.IsApproved1 = serverRecord.IsApproved1;
            if (serverRecord.Approved1By != null) record.Approved1By = serverRecord.Approved1By;
            if (serverRecord.Approved1ByName != null) record.Approved1ByName = serverRecord.Approved1ByName;
            if (serverRecord.Approved1Date != null) record.Approved1Date = serverRecord.Approved1Date;
            if (serverRecord.IsApproved2 != null) record.IsApproved2 = serverRecord.IsApproved2;
            if (serverRecord.Approved2By != null) record.Approved2By = serverRecord.Approved2By;
            if (serverRecord.Approved2ByName != null) record.Approved2ByName = serverRecord.Approved2ByName;
            if (serverRecord.Approved2Date != null) record.Approved2Date = serverRecord.Approved2Date;
            ["TechnicianName", "SubmittedByName", "ApprovedByName", "Approved1ByName", "Approved2ByName"].forEach(function (field) {
                if (serverRecord[field] != null && String(serverRecord[field]).trim() !== "")
                    record[field] = serverRecord[field];
            });
        }
    }

    const login = getLoginData();
    if (!login || record.OwnerEmployeeID !== login.employeeid) {
        showToast("Inspeksi ini bukan milik akun yang sedang login.", "danger");
        return;
    }

    currentInspectionRecord = record;
    await renderInspectionForm(record, record.Status === "DONE" && !isVoidedServerInspectionRecord(record));
    if (isInspectionMapMode(record.InspectionMode) &&
        typeof showInspectionMapWorkspace === "function") {
        showInspectionMapWorkspace(record, true);
    }
}

function restoreInspectionMasterDropdowns() {
    const typeSelect = document.getElementById("selInspectionType");
    typeSelect.innerHTML = '<option value="">Pilih Inspection Type...</option>' +
        inspectionTypes.map(type =>
            '<option value="' + escInspection(type.InspectionTypeCode) + '">' +
            escInspection(type.InspectionTypeCode + " - " + type.InspectionTypeName) + '</option>'
        ).join("");
    typeSelect.value = "";
    typeSelect.disabled = inspectionTypes.length === 0;
    resetDetailAndTemplateOptions();
}

async function resetInspectionSelection() {
    // Sync All updates IndexedDB, but the in-memory master arrays are not refreshed
    // while this page remains open. Reload the local master cache before building
    // the New Inspection dropdowns; skip the unrelated online map-setup refresh here.
    await loadInspectionCache(false, true);

    const mapWorkspace = document.getElementById("inspectionMapWorkspace");
    if (mapWorkspace) mapWorkspace.classList.add("d-none");
    if (typeof window.resetInspectionMapWorkspace === "function")
        await window.resetInspectionMapWorkspace();
    restoreInspectionMasterDropdowns();
    showInspectionInputScreen();
    stopInspectionGpsWatch();
    inspectionLatestGps = null;
    currentInspectionRecord = null;
    currentInspectionReadOnly = false;
    renderInspectionApprovalWorkflowCards(null);
    document.getElementById("inspectionEditorTabs").classList.add("d-none");
    document.getElementById("inspectionFormPanel").classList.add("d-none");
    document.getElementById("inspectionStartPanel").classList.remove("d-none");
    document.getElementById("inspectionStartButtonRow").classList.remove("d-none");
    document.getElementById("selInspectionType").disabled = inspectionTypes.length === 0;
    document.getElementById("selInspectionDetail").disabled = true;
    document.getElementById("selInspectionScheduleTime").disabled = true;
    document.getElementById("selInspectionTemplate").disabled = true;
    document.getElementById("selInspectionType").value = "";
    resetDetailAndTemplateOptions();
    document.getElementById("txtInspectionDate").value = formatInspectionDateDMY(localDateString(new Date()));
    document.getElementById("txtInspectionDate").disabled = true;
    showInspectionEditorTab("param");
    updateStartButton();
}

async function closeInspectionForm() {
    if (typeof window.closeInspectionMapPointChecklistSheet === "function")
        window.closeInspectionMapPointChecklistSheet(true);
    if (inspectionAutoSaveTimer) {
        clearTimeout(inspectionAutoSaveTimer);
        inspectionAutoSaveTimer = null;
    }
    const closingRecord = currentInspectionRecord;
    const closingBatch = closingRecord &&
        isInspectionMapMode(closingRecord.InspectionMode);
    const batchWasSaved = closingBatch
        ? await isInspectionRecordPersisted(closingRecord.LocalInspectionID)
        : false;

    // Leaving the form/map is never an implicit Save Point or Save Draft action.
    // For an entirely new batch, also remove any photo blobs attached to its temporary ID.
    if (closingBatch && !batchWasSaved) {
        await deleteInspectionPhotosForLocalRecord(closingRecord.LocalInspectionID);
    }
    if (closingRecord && !closingBatch &&
        inspectionPhotoBaseline !== null && !currentInspectionReadOnly) {
        const baseline = inspectionPhotoBaseline;
        await new Promise((resolve, reject) => {
            const tx = db.transaction("inspection_photos", "readwrite");
            const store = tx.objectStore("inspection_photos");
            const req = store.index("LocalInspectionID")
                .openCursor(IDBKeyRange.only(closingRecord.LocalInspectionID));
            req.onsuccess = () => {
                const cursor = req.result;
                if (cursor) {
                    cursor.delete();
                    cursor.continue();
                    return;
                }
                baseline.forEach(photo => store.add(photo));
            };
            tx.oncomplete = () => resolve();
            tx.onerror = () => reject(tx.error);
            tx.onabort = () => reject(tx.error || new Error("Gagal membatalkan perubahan foto inspeksi."));
        });
    } else if (closingRecord && !closingBatch &&
        !inspectionRecords.some(r => r.LocalInspectionID === closingRecord.LocalInspectionID)) {
        await new Promise((resolve, reject) => {
            const tx = db.transaction("inspection_photos", "readwrite");
            const req = tx.objectStore("inspection_photos").index("LocalInspectionID")
                .openCursor(IDBKeyRange.only(closingRecord.LocalInspectionID));
            req.onsuccess = () => {
                const cursor = req.result;
                if (!cursor) return;
                cursor.delete();
                cursor.continue();
            };
            tx.oncomplete = () => resolve();
            tx.onerror = () => reject(tx.error);
            tx.onabort = () => reject(tx.error || new Error("Gagal membatalkan foto inspeksi."));
        });
    }
    inspectionPhotoBaseline = null;
    stopInspectionGpsWatch();
    inspectionLatestGps = null;
    currentInspectionRecord=null; currentInspectionReadOnly=false;
    const mapWorkspace = document.getElementById("inspectionMapWorkspace");
    if (mapWorkspace) mapWorkspace.classList.add("d-none");
    document.getElementById("inspectionEditorTabs").classList.add("d-none"); document.getElementById("inspectionFormPanel").classList.add("d-none");
    document.getElementById("inspectionStartPanel").classList.remove("d-none"); document.getElementById("inspectionStartButtonRow").classList.remove("d-none");
    showInspectionRecordsScreen(); await refreshSavedInspectionList();
}
function returnFromInspectionPage(){if(!document.getElementById("inspectionInputPanel").classList.contains("d-none")){closeInspectionForm();return;}window.location.href="dashboard.aspx";}
function showInspectionEditorTab(tab) {
    const p = tab === "param";
    const isBatchMode = !!(currentInspectionRecord && isInspectionMapMode(currentInspectionRecord.InspectionMode));
    const checklistTabButton = document.getElementById("btnInspectionChecklistTab");
    if (checklistTabButton && checklistTabButton.closest("li"))
        checklistTabButton.closest("li").classList.toggle("d-none", isBatchMode);
    document.body.classList.toggle("inspection-map-mobile-active", !p && !!(currentInspectionRecord && isInspectionMapMode(currentInspectionRecord.InspectionMode) && !Number(currentInspectionRecord.ActiveInspectionPointID || 0)));
    if (p) {
        const mapWorkspace = document.getElementById("inspectionMapWorkspace");
        if (mapWorkspace) mapWorkspace.classList.add("d-none");
    }
    const isBatch = currentInspectionRecord &&
        isInspectionMapMode(currentInspectionRecord.InspectionMode);
    if (!p && isBatch && !Number(currentInspectionRecord.ActiveInspectionPointID || 0)) {
        document.getElementById("inspectionParamsPane").classList.add("d-none");
        document.getElementById("inspectionChecklistPane").classList.add("d-none");
        const workspace = document.getElementById("inspectionMapWorkspace");
        if (workspace) workspace.classList.remove("d-none");
        const mapTab = document.getElementById("btnInspectionMapTab");
        const paramTab = document.getElementById("btnInspectionParamTab");
        const checklistTab = document.getElementById("btnInspectionChecklistTab");
        if (mapTab) mapTab.classList.add("active");
        if (paramTab) paramTab.classList.remove("active");
        if (checklistTab) checklistTab.classList.remove("active");
        const sectionNavHost = document.getElementById("inspectionSectionNavHost");
        if (sectionNavHost) sectionNavHost.classList.add("d-none");
        updateInspectionParameterTabGate();
        return;
    }
    if (!p && document.getElementById("btnInspectionChecklistTab").disabled) {
        document.getElementById("inspectionParamsPane").classList.remove("d-none");
        document.getElementById("inspectionChecklistPane").classList.add("d-none");
        document.getElementById("btnInspectionParamTab").classList.add("active");
        document.getElementById("btnInspectionChecklistTab").classList.remove("active");
        const sectionNavHost = document.getElementById("inspectionSectionNavHost");
        if (sectionNavHost) sectionNavHost.classList.add("d-none");
        return;
    }
    document.getElementById("inspectionParamsPane").classList.toggle("d-none", !p);
    document.getElementById("inspectionChecklistPane").classList.toggle("d-none", p);
    document.getElementById("btnInspectionParamTab").classList.toggle("active", p);
    document.getElementById("btnInspectionChecklistTab").classList.toggle("active", !p);
    const sectionNavHost = document.getElementById("inspectionSectionNavHost");
    if (sectionNavHost) sectionNavHost.classList.toggle("d-none", p);
}
function isInspectionParameterSelectionComplete() {
    const typeCode = document.getElementById("selInspectionType").value;
    const detailCode = document.getElementById("selInspectionDetail").value;
    const templateId = Number(document.getElementById("selInspectionTemplate").value);
    const type = inspectionTypes.find(x => x.InspectionTypeCode === typeCode);
    const detail = inspectionDetails.find(x =>
        x.InspectionTypeCode === typeCode && x.InspectionTypeDetailCode === detailCode
    );
    const template = inspectionTemplates.find(x => Number(x.IDTemplate) === templateId);
    const scheduleTime = document.getElementById("selInspectionScheduleTime").value || "";
    const hasScheduledTimes = getInspectionScheduleTimes(detail).length > 0;
    return !!type && !!detail && !!template &&
        (!hasScheduledTimes || !!scheduleTime) &&
        template.TemplateType === "I" &&
        template.InspectionTypeCode === typeCode &&
        isInspectionTemplateDetailAllowed(template, detailCode) &&
        template.SectionID === type.SectionID;
}
function updateInspectionParameterTabGate() {
    const button = document.getElementById("btnInspectionChecklistTab");
    if (!button) return;
    const isBatch = currentInspectionRecord &&
        isInspectionMapMode(currentInspectionRecord.InspectionMode);
    const hasSelectedPoint = !isBatch || Number(currentInspectionRecord.ActiveInspectionPointID || 0) > 0;
    const complete = (currentInspectionReadOnly || isInspectionParameterSelectionComplete()) && hasSelectedPoint;
    button.disabled = !complete;
    button.classList.toggle("disabled", !complete);
    button.setAttribute("aria-disabled", complete ? "false" : "true");
    button.title = !hasSelectedPoint
        ? "Pilih Inspection Point dari MAP terlebih dahulu."
        : (complete ? "" : "Lengkapi semua parameter inspeksi terlebih dahulu.");
}
function formatInspectionEmployeeLabel(name, employeeId) {
    const id = String(employeeId || "").trim();
    const displayName = String(name || "").trim();
    if (displayName && id && displayName.toLowerCase() !== id.toLowerCase())
        return displayName + " (" + id + ")";
    return displayName || id || "—";
}

function setInspectionFormInfoPopover(infoLines) {
    const infoButton = document.getElementById("btnInspectionFormInfo");
    if (!infoButton) return;

    if (window.bootstrap && bootstrap.Tooltip) {
        const tooltip = bootstrap.Tooltip.getInstance(infoButton);
        if (tooltip) tooltip.dispose();
    }
    if (window.bootstrap && bootstrap.Popover) {
        const existing = bootstrap.Popover.getInstance(infoButton);
        if (existing) existing.dispose();
    }
    infoButton.removeAttribute("title");

    // Match the map-option popover's root-close behavior. Pointerdown makes
    // dismissal immediate on both mouse and touch; click covers keyboard/
    // programmatic click activation. Keep clicks inside the trigger/popover.
    if (!document.documentElement.dataset.inspectionInfoPopoverOutsideClickWired) {
        document.documentElement.dataset.inspectionInfoPopoverOutsideClickWired = "1";
        const closeOnOutside = function (event) {
            const button = document.getElementById("btnInspectionFormInfo");
            if (!button || !window.bootstrap || !bootstrap.Popover) return;
            const target = event.target && event.target.nodeType === 1
                ? event.target : (event.target && event.target.parentElement);
            if (!target) return;
            const popover = bootstrap.Popover.getInstance(button);
            if (!popover) return;
            // Bootstrap 5.3 keeps the generated tip id in aria-describedby.
            // Prefer its public getter when present, then resolve that id so
            // taps inside the popover itself do not count as outside clicks.
            const describedBy = button.getAttribute("aria-describedby");
            const tip = (typeof popover.getTipElement === "function" && popover.getTipElement()) ||
                (describedBy ? document.getElementById(describedBy) : null) ||
                (popover.tip || null);
            if (button.contains(target) || (tip && tip.contains(target))) return;
            popover.hide();
        };
        document.addEventListener("pointerdown", closeOnOutside, true);
        document.addEventListener("click", closeOnOutside, true);
        document.addEventListener("keydown", function (event) {
            if (event.key !== "Escape") return;
            const button = document.getElementById("btnInspectionFormInfo");
            const popover = button && window.bootstrap && bootstrap.Popover
                ? bootstrap.Popover.getInstance(button) : null;
            if (popover) {
                popover.hide();
                button.focus();
            }
        });
    }

    const content = (infoLines || []).filter(Boolean).map(line =>
        '<div class="mb-1">' + escInspection(line) + '</div>'
    ).join("");
    infoButton.disabled = !content;
    if (!content || !window.bootstrap || !bootstrap.Popover) return;

    bootstrap.Popover.getOrCreateInstance(infoButton, {
        container: "body",
        trigger: "click",
        placement: "bottom",
        boundary: "viewport",
        fallbackPlacements: ["top", "bottom"],
        html: true,
        content: content
    });
}
function setInspectionFormHeader(transactionNo, infoLines) {
    const title = document.getElementById("inspectionFormTitle");
    if (title) title.textContent = transactionNo || "Inspection";
    setInspectionFormInfoPopover(infoLines);
}

async function populateInspectionParameters(record) {
    const typeSelect = document.getElementById("selInspectionType");
    const templateSelect = document.getElementById("selInspectionTemplate");
    const detailSelect = document.getElementById("selInspectionDetail");
    const scheduleTimeSelect = document.getElementById("selInspectionScheduleTime");

    // Submitted/synced records are read-only. Their original master rows may no longer
    // exist in this device's IndexedDB, so render the transaction's saved parameter values
    // directly instead of looking them up in the current master dropdown caches.
    if (currentInspectionReadOnly) {
        const typeCode = String(record.InspectionTypeCode || "");
        const typeName = String(record.InspectionTypeName || "");
        const detailCode = String(record.InspectionTypeDetailCode || "");
        const detailName = String(record.InspectionTypeDetailName || "");
        const templateId = record.IDTemplate != null && String(record.IDTemplate) !== ""
            ? String(record.IDTemplate) : "__server_template__";
        const templateLabel = [record.TemplateNo || "Template",
            record.TemplateVersion ? "v" + record.TemplateVersion : ""].filter(Boolean).join(" / ");

        typeSelect.innerHTML = '<option value="' + escInspection(typeCode || "__server_type__") + '">' +
            escInspection([typeCode, typeName].filter(Boolean).join(" - ") || "-") + '</option>';
        typeSelect.value = typeCode || "__server_type__";

        detailSelect.innerHTML = '<option value="' + escInspection(detailCode || "__server_detail__") + '">' +
            escInspection([detailCode, detailName].filter(Boolean).join(" - ") || "-") + '</option>';
        detailSelect.value = detailCode || "__server_detail__";

        scheduleTimeSelect.innerHTML = '<option value="' + escInspection(record.ScheduledTime || "") + '">' +
            escInspection(record.ScheduledTime || "Tanpa jadwal") + '</option>';
        scheduleTimeSelect.value = record.ScheduledTime || "";

        templateSelect.innerHTML = '<option value="' + escInspection(templateId) + '">' +
            escInspection(templateLabel || "-") + '</option>';
        templateSelect.value = templateId;

        // Submitted records are rendered from their saved header snapshot. Restore
        // the tenant identity here as well; do not depend on current master caches.
        const tenantPanel = document.getElementById("inspectionTenantPanel");
        const tenantSelect = document.getElementById("selInspectionTenant");
        const suiteSelect = document.getElementById("selInspectionSuite");
        const savedTenantID = String(record.TenantID || "").trim();
        const savedSuiteNo = String(record.SuiteNo || "").trim();
        const savedTenantName = await resolveInspectionTenantName(savedTenantID, record.TenantName);
        if (!record.TenantName && savedTenantName) record.TenantName = savedTenantName;
        if (tenantPanel && tenantSelect && suiteSelect && (savedTenantID || savedSuiteNo)) {
            tenantPanel.classList.remove("d-none");
            tenantSelect.innerHTML = savedTenantID
                ? '<option value="' + escInspection(savedTenantID) + '">' +
                    escInspection(formatInspectionTenantLabel(savedTenantID, savedTenantName)) + '</option>'
                : '<option value="">-</option>';
            tenantSelect.value = savedTenantID;
            const tenantSearch = document.getElementById("txtInspectionTenantSearch");
            if (tenantSearch) {
                tenantSearch.value = "";
                tenantSearch.disabled = true;
            }
            applyInspectionTenantSearch();
            suiteSelect.innerHTML = savedSuiteNo
                ? '<option value="' + escInspection(savedSuiteNo) + '">' + escInspection(savedSuiteNo) + '</option>'
                : '<option value="">-</option>';
            suiteSelect.value = savedSuiteNo;
            tenantSelect.disabled = true;
            suiteSelect.disabled = true;
        } else {
            resetInspectionTenantSelection();
        }

        [typeSelect, detailSelect, scheduleTimeSelect, templateSelect].forEach(select => {
            select.disabled = true;
        });
        document.getElementById("txtInspectionDate").value =
            inspectionDateInputValue(record.InspectionDate);
        document.getElementById("txtInspectionDate").disabled = true;
        updateStartButton();
        updateInspectionParameterTabGate();
        return;
    }

    typeSelect.value = record.InspectionTypeCode || "";
    onInspectionTypeChanged();

    // Detail options depend on the selected template. Populate them through the
    // same change handler used by the normal parameter-selection flow.
    templateSelect.value = String(record.IDTemplate || "");
    templateSelect.dispatchEvent(new Event("change"));

    detailSelect.value = record.InspectionTypeDetailCode || "";
    await onInspectionDetailChanged();
    const selectedDetail = inspectionDetails.find(x =>
        x.InspectionTypeCode === (record.InspectionTypeCode || "") &&
        x.InspectionTypeDetailCode === (record.InspectionTypeDetailCode || "")
    );
    if (isInspectionTenantDetail(selectedDetail) && record.TenantID) {
        const tenantSelect = document.getElementById("selInspectionTenant");
        const suiteSelect = document.getElementById("selInspectionSuite");
        if (tenantSelect && suiteSelect) {
            tenantSelect.value = String(record.TenantID || "");
            const tenantSearch = document.getElementById("txtInspectionTenantSearch");
            if (tenantSearch) {
                tenantSearch.value = "";
                tenantSearch.disabled = currentInspectionReadOnly;
            }
            applyInspectionTenantSearch();
            if (tenantSelect.value) {
                await loadInspectionTenantSuites(tenantSelect.value);
                suiteSelect.value = String(record.SuiteNo || "");
            }
        }
        const savedTenantName = await resolveInspectionTenantName(record.TenantID, record.TenantName);
        if (savedTenantName) record.TenantName = savedTenantName;
        refreshInspectionSuiteAvailability();
    }
    scheduleTimeSelect.value = record.ScheduledTime || "";
    refreshInspectionScheduleOptions();

    document.getElementById("txtInspectionDate").value = inspectionDateInputValue(record.InspectionDate || localDateString(new Date()));
    document.getElementById("txtInspectionDate").disabled = true;
    typeSelect.disabled = currentInspectionReadOnly;
    const selectedTemplate = inspectionTemplates.find(x => Number(x.IDTemplate) === Number(templateSelect.value));
    detailSelect.disabled = currentInspectionReadOnly || !templateSelect.value ||
        getInspectionTemplateDetailCodes(selectedTemplate).length === 1;
    scheduleTimeSelect.disabled = currentInspectionReadOnly || !getInspectionScheduleTimes(
        inspectionDetails.find(x => x.InspectionTypeCode === (record.InspectionTypeCode || "") &&
            x.InspectionTypeDetailCode === (record.InspectionTypeDetailCode || ""))
    ).length;
    templateSelect.disabled = currentInspectionReadOnly;
    updateStartButton();
    updateInspectionParameterTabGate();
}
function hasInspectionChecklistAnswers(items) {
    return (items || []).some(item => {
        if (item.IsAnomali === true) return true;
        if (["Value", "Remark", "Remark1", "Remark2"].some(key =>
            String(item[key] == null ? "" : item[key]).trim() !== "")) return true;
        const values = item.Values && typeof item.Values === "object" ? Object.values(item.Values) : [];
        return values.some(value => String(value == null ? "" : value).trim() !== "");
    });
}

async function clearInspectionPhotos(localInspectionId) {
    return new Promise((resolve, reject) => {
        const tx = db.transaction("inspection_photos", "readwrite");
        const store = tx.objectStore("inspection_photos");
        const req = store.index("LocalInspectionID").openCursor(IDBKeyRange.only(localInspectionId));
        req.onsuccess = () => {
            const cursor = req.result;
            if (!cursor) return;
            cursor.delete();
            cursor.continue();
        };
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error || new Error("Gagal mereset foto checklist."));
    });
}

async function applyInspectionParameters() {
    if (!currentInspectionRecord || currentInspectionReadOnly) return true;

    const typeCode = document.getElementById("selInspectionType").value;
    const detailCode = document.getElementById("selInspectionDetail").value;
    const scheduledTime = document.getElementById("selInspectionScheduleTime").value || "";
    const templateId = Number(document.getElementById("selInspectionTemplate").value);
    const type = inspectionTypes.find(x => x.InspectionTypeCode === typeCode);
    const detail = inspectionDetails.find(x =>
        x.InspectionTypeCode === typeCode && x.InspectionTypeDetailCode === detailCode
    );
    const selectedTemplate = inspectionTemplates.find(x => Number(x.IDTemplate) === templateId);
    const pinnedTemplate = currentInspectionRecord.TemplateSnapshot;
    const template = pinnedTemplate &&
        Number(pinnedTemplate.IDTemplate) === templateId &&
        Number(pinnedTemplate.IDVersion) === Number(currentInspectionRecord.IDVersion)
        ? pinnedTemplate : selectedTemplate;

    if (!type || !detail || !template ||
        template.TemplateType !== "I" ||
        template.InspectionTypeCode !== typeCode ||
        !isInspectionTemplateDetailAllowed(template, detailCode) ||
        template.SectionID !== type.SectionID) {
        showToast("Pilih Inspection Type, detail, dan template Inspection yang sesuai.", "warning");
        updateInspectionParameterTabGate();
        return false;
    }

    const duplicate = inspectionRecords.find(r =>
        r.LocalInspectionID !== currentInspectionRecord.LocalInspectionID &&
        r.CompanyID === inspectionCompanyID &&
        r.LocationID === inspectionLocationID &&
        parseInspectionDate(r.InspectionDate) === currentInspectionRecord.InspectionDate &&
        r.SectionID === type.SectionID &&
        r.InspectionTypeCode === typeCode &&
        r.InspectionTypeDetailCode === detailCode &&
        String(r.ScheduledTime || "") === scheduledTime &&
        Number(r.IDTemplate) === Number(template.IDTemplate) &&
        r.SyncStatus !== "DELETE_PENDING"
    );
    if (duplicate) {
        showToast("Kombinasi parameter ini sudah dipakai transaksi lain. Draft tidak diubah.", "warning");
        await populateInspectionParameters(currentInspectionRecord);
        updateInspectionParameterTabGate();
        return false;
    }

    const record = currentInspectionRecord;
    const inspectionMode = ["BATCH", "LIGHTNING"].includes(
        String(type.InspectionMode || "STANDARD").trim().toUpperCase()
    ) ? String(type.InspectionMode).trim().toUpperCase() : "STANDARD";
    const tenantId = isInspectionTenantDetail(detail) ? getSelectedInspectionTenantID() : "";
    const suiteNo = isInspectionTenantDetail(detail) ? getSelectedInspectionSuiteNo() : "";
    const selectedTenant = inspectionTenants.find(row =>
        String(row.TenantID || "").trim() === tenantId);
    const tenantName = selectedTenant ? String(selectedTenant.TenantName || "").trim() : "";
    const changed = String(record.SectionID || "") !== String(type.SectionID || "") ||
        String(record.InspectionTypeCode || "") !== String(type.InspectionTypeCode || "") ||
        String(record.TenantID || "") !== tenantId ||
        String(record.SuiteNo || "") !== suiteNo ||
        String(record.InspectionMode || "STANDARD").trim().toUpperCase() !== inspectionMode ||
        String(record.InspectionTypeDetailCode || "") !== String(detail.InspectionTypeDetailCode || "") ||
        String(record.ScheduledTime || "") !== String(scheduledTime || "") ||
        Number(record.IDTemplate) !== Number(template.IDTemplate) ||
        Number(record.IDVersion) !== Number(template.IDVersion) ||
        getInspectionPhotoRequirement(record) !== getInspectionPhotoRequirement(template);
    if (!changed) return true;

    const photos = await getInspectionPhotos(record.LocalInspectionID);
    // Include unsaved form values as well as the last persisted checklist snapshot.
    let liveChecklistItems = [];
    try { liveChecklistItems = collectInspectionItems(); } catch (_) { /* no rendered checklist yet */ }
    const hasPreviousData = photos.length > 0 ||
        hasInspectionChecklistAnswers(record.Items) ||
        hasInspectionChecklistAnswers(liveChecklistItems);
    if (hasPreviousData) {
        const confirmed = await showConfirmation({
            title: "Reset Checklist?",
            message: "Parameter inspeksi akan berubah. Semua jawaban checklist dan seluruh foto BEFORE/AFTER akan dihapus dari transaksi ini. Jika transaksi pernah tersinkron, foto lama di server juga akan diganti saat Sync berikutnya. Do you want to continue?",
            yesText: "Yes, Reset Checklist",
            noText: "No, Keep Existing Data"
        });
        if (!confirmed) {
            await populateInspectionParameters(record);
            updateInspectionParameterTabGate();
            return false;
        }
    }

    Object.assign(record, {
        SectionID: type.SectionID,
        InspectionTypeCode: type.InspectionTypeCode,
        InspectionTypeName: type.InspectionTypeName,
        InspectionMode: inspectionMode,
        InspectionTypeDetailCode: detail.InspectionTypeDetailCode,
        InspectionTypeDetailName: detail.InspectionTypeDetailName,
        TenantID: tenantId,
        TenantName: tenantName,
        SuiteNo: suiteNo,
        ScheduledTime: scheduledTime,
        IDTemplate: Number(template.IDTemplate),
        IDVersion: Number(template.IDVersion),
        TemplateNo: template.TemplateNo,
        TemplateName: template.TemplateName,
        TemplateVersion: String(template.Version || ""),
        TemplateSnapshot: JSON.parse(JSON.stringify(template)),
        PhotoRequirement: getInspectionPhotoRequirement(template),
        SyncStatus: "PENDING",
        UpdatedAt: new Date().toISOString()
    });

    // Clear local photo blobs before persisting the new parameter set. The next successful
    // full-transaction sync replaces server photo metadata and removes superseded server files.
    await clearInspectionPhotos(record.LocalInspectionID);
    inspectionPhotoBaseline = null;
    record.Items = [];
    record.NextPhotoSeqNo = 1;

    const host = document.getElementById("inspectionChecklistHost");
    applyInspectionPhotoRequirement(record);
    host.innerHTML = renderInspectionSections(template, [], currentInspectionReadOnly, "inspectionSection");
    updateInspectionRemarkPanels();
    await renderInspectionPhotos();
    await updateInspectionChecklistGate();
    // Selecting/changing parameters while starting a new BATCH is not a save action.
    // Existing locally-saved batch drafts may still be updated when parameters change.
    if (!isInspectionMapMode(inspectionMode) ||
        await isInspectionRecordPersisted(record.LocalInspectionID)) {
        await persistInspectionRecord(record);
    }
    return true;
}

let inspectionReasonCancelResolve = null;

function wireInspectionReasonCancelDialog() {
    const modal = document.getElementById("inspectionReasonCancelModal");
    const confirmButton = document.getElementById("btnConfirmInspectionReasonCancel");
    const input = document.getElementById("txtInspectionReasonCancel");
    const error = document.getElementById("inspectionReasonCancelError");
    if (!modal || modal.dataset.wired === "1") return;
    modal.dataset.wired = "1";

    confirmButton.addEventListener("click", function () {
        const reason = String(input.value || "").trim();
        if (!reason) {
            error.textContent = "Reason Cancel wajib diisi.";
            error.classList.remove("d-none");
            input.focus();
            return;
        }
        if (reason.length > 500) {
            error.textContent = "Reason Cancel maksimal 500 karakter.";
            error.classList.remove("d-none");
            input.focus();
            return;
        }
        error.classList.add("d-none");
        const resolve = inspectionReasonCancelResolve;
        inspectionReasonCancelResolve = null;
        if (resolve) resolve(reason);
        bootstrap.Modal.getOrCreateInstance(modal).hide();
    });
    modal.addEventListener("hidden.bs.modal", function () {
        if (inspectionReasonCancelResolve) {
            const resolve = inspectionReasonCancelResolve;
            inspectionReasonCancelResolve = null;
            resolve(null);
        }
    });
}

function showInspectionReasonCancelDialog(title, initialValue) {
    const modal = document.getElementById("inspectionReasonCancelModal");
    if (!modal) {
        showToast("Dialog Reason Cancel tidak tersedia. Refresh aplikasi setelah update.", "danger");
        return Promise.resolve(null);
    }
    wireInspectionReasonCancelDialog();
    document.getElementById("inspectionReasonCancelTitle").textContent = title || "Reason Cancel";
    const input = document.getElementById("txtInspectionReasonCancel");
    input.value = String(initialValue || "").substring(0, 500);
    document.getElementById("inspectionReasonCancelError").classList.add("d-none");
    return new Promise(resolve => {
        inspectionReasonCancelResolve = resolve;
        bootstrap.Modal.getOrCreateInstance(modal).show();
        window.setTimeout(() => input.focus(), 150);
    });
}

async function deleteLocalInspectionDraft(localId) {
    const record = inspectionRecords.find(item => item.LocalInspectionID === localId);
    if (!record) {
        showToast("Transaksi inspeksi tidak ditemukan di perangkat.", "warning");
        return;
    }
    const isConflict = record.SyncStatus === "CONFLICT";
    const isVoidedServerRecord = isVoidedServerInspectionRecord(record);
    const isPureLocalDraft = record.Status === "DRAFT" && record.SyncStatus !== "SYNCED" &&
        record.SyncStatus !== "CONFLICT" && record.SyncStatus !== "DELETE_PENDING";
    if (!isConflict && !isVoidedServerRecord && !isPureLocalDraft) {
        showToast("Delete Draft hanya tersedia untuk draft lokal, transaksi conflict, atau inspeksi yang sudah di-void SPV.", "warning");
        return;
    }
    const title = isConflict ? "Hapus Transaksi Conflict" : (isVoidedServerRecord ? "Hapus Draft Inspeksi Void" : "Hapus Draft Inspeksi");
    let reasonCancel = "";
    if (isConflict || isVoidedServerRecord) {
        reasonCancel = await showInspectionReasonCancelDialog(
            "Reason Cancel",
            isVoidedServerRecord ? String(record.DeleteReasonCancel || "").trim() : ""
        );
        if (reasonCancel === null) return;
    }
    const message = isConflict
        ? "Hapus transaksi yang gagal disinkronkan ini? Data inspeksi dan checklist akan diarsipkan ke server saat Sync berikutnya. Data lokal dan foto tetap disimpan sampai server mengonfirmasi."
        : (isVoidedServerRecord
            ? "Hapus salinan lokal inspeksi yang sudah di-void SPV? Alasan pembatalan akan disimpan ke server dan data lokal beserta foto dibersihkan setelah server mengonfirmasi."
            : "Hapus draft " + (record.InspectionNo || ("TEMP-" + String(localId).substring(0, 8).toUpperCase())) +
              " beserta foto BEFORE/AFTER dari perangkat? Draft ini belum pernah di-Done dan tidak akan disimpan ke tabel server.");
    const confirmed = await showConfirmation({ title: title, message: message, yesText: "Hapus" });
    if (!confirmed) return;

    if (isConflict || isVoidedServerRecord) {
        record.DeleteOriginalSyncStatus = isConflict ? "CONFLICT" : "VOIDED";
        record.DeleteReasonCancel = reasonCancel;
        record.SyncStatus = "DELETE_PENDING";
        record.DeleteQueuedAt = new Date().toISOString();
        record.UpdatedAt = record.DeleteQueuedAt;
        delete record.DeleteArchiveError;
        await persistInspectionRecord(record);

        // Queue only: never invoke uploadPendingInspections here. Server changes must
        // happen exclusively when the technician explicitly presses the global Sync button.
        // Return from the checklist to the records grid immediately while retaining the
        // DELETE_PENDING row and its local photos until Sync confirms the server operation.
        if (currentInspectionRecord && currentInspectionRecord.LocalInspectionID === localId) {
            stopInspectionGpsWatch();
            inspectionLatestGps = null;
            currentInspectionRecord = null;
            currentInspectionReadOnly = false;
            inspectionPhotoBaseline = null;
            document.getElementById("inspectionEditorTabs").classList.add("d-none");
            document.getElementById("inspectionFormPanel").classList.add("d-none");
            document.getElementById("inspectionStartPanel").classList.remove("d-none");
            document.getElementById("inspectionStartButtonRow").classList.remove("d-none");
            showInspectionRecordsScreen();
        }
        await refreshSavedInspectionList();
        showToast(
            isConflict
                ? "Penghapusan conflict masuk antrean. Snapshot dan data lokal tetap disimpan sampai lo klik Sync."
                : "Penghapusan masuk antrean. Data dan foto lokal tetap disimpan; klik Sync untuk mengubah IsActive menjadi 0 dan menyimpan Reason Cancel ke server.",
            "warning"
        );
        return;
    }
    await new Promise((resolve, reject) => {
        const tx = db.transaction(["inspection_records", "inspection_photos"], "readwrite");
        tx.objectStore("inspection_records").delete(localId);
        const req = tx.objectStore("inspection_photos").index("LocalInspectionID").openCursor(IDBKeyRange.only(localId));
        req.onsuccess = () => { const cursor = req.result; if (!cursor) return; cursor.delete(); cursor.continue(); };
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error || new Error("Hapus draft gagal."));
    });
    if (currentInspectionRecord && currentInspectionRecord.LocalInspectionID === localId) {
        stopInspectionGpsWatch();
        inspectionLatestGps = null;
        currentInspectionRecord = null;
        currentInspectionReadOnly = false;
        inspectionPhotoBaseline = null;
        document.getElementById("inspectionEditorTabs").classList.add("d-none");
        document.getElementById("inspectionFormPanel").classList.add("d-none");
        document.getElementById("inspectionStartPanel").classList.remove("d-none");
        document.getElementById("inspectionStartButtonRow").classList.remove("d-none");
        showInspectionRecordsScreen();
    }
    await refreshSavedInspectionList();
    showToast("Draft lokal beserta fotonya sudah dihapus tanpa membuat record server.", "success");
}

async function getInspectionPhotos(localId, pointId){return new Promise((resolve,reject)=>{const tx=db.transaction("inspection_photos","readonly"),req=tx.objectStore("inspection_photos").index("LocalInspectionID").getAll(IDBKeyRange.only(localId));req.onsuccess=()=>resolve((req.result||[]).filter(photo=>pointId==null||String(photo.PointID||"")===String(pointId)).sort((a,b)=>String(a.Type).localeCompare(String(b.Type))||Number(a.SeqNo||a.OrderNo||0)-Number(b.SeqNo||b.OrderNo||0)));req.onerror=()=>reject(req.error);});}
async function renderInspectionPhotos() {
    if (!currentInspectionRecord) return;
    const photos = await getCurrentInspectionPhotos();
    const requirement = getInspectionPhotoRequirement(currentInspectionRecord);
    const beforeRequired = requirement === "BEFORE" || requirement === "BOTH";
    const afterRequired = requirement === "AFTER" || requirement === "BOTH";
    const hasBeforePhoto = photos.some(photo => String(photo.Type || "").toUpperCase() === "BEFORE");
    for (const type of ["BEFORE", "AFTER"]) {
        const host = document.getElementById(type === "BEFORE" ? "inspectionPhotoBeforeList" : "inspectionPhotoAfterList");
        host.innerHTML = "";
        photos.filter(photo => String(photo.Type || "").toUpperCase() === type).forEach(photo => {
            const wrapper = document.createElement("div");
            wrapper.className = "inspection-photo-item";
            wrapper.dataset.photoId = photo.ID;
            wrapper.dataset.photoType = type;
            wrapper.setAttribute("role", "button");
            wrapper.setAttribute("tabindex", "0");
            wrapper.setAttribute("aria-label", "Lihat foto " + type + " nomor " + (photo.SeqNo || photo.OrderNo || ""));
            const image = document.createElement("img");
            image.src = URL.createObjectURL(photo.Blob);
            image.alt = "Inspection " + type;
            image.loading = "lazy";
            wrapper.appendChild(image);
            if (!currentInspectionReadOnly) {
                const removeButton = document.createElement("button");
                removeButton.type = "button";
                removeButton.className = "btn btn-sm btn-danger inspection-photo-delete";
                removeButton.dataset.deleteInspectionPhoto = photo.ID;
                removeButton.setAttribute("aria-label", "Hapus foto");
                removeButton.textContent = "×";
                wrapper.appendChild(removeButton);
            }
            host.appendChild(wrapper);
        });
        const count = photos.filter(photo => String(photo.Type || "").toUpperCase() === type).length;
        const input = document.getElementById(type === "BEFORE" ? "inspectionPhotoBeforeInput" : "inspectionPhotoAfterInput");
        const enabled = type === "BEFORE" ? beforeRequired : (afterRequired && (!beforeRequired || hasBeforePhoto));
        input.disabled = currentInspectionReadOnly || !enabled;
        const addButton = document.getElementById(type === "BEFORE" ? "btnAddInspectionBeforePhoto" : "btnAddInspectionAfterPhoto");
        addButton.disabled = input.disabled;
        // Submitted/read-only inspections retain their gallery, but never offer camera capture.
        addButton.classList.toggle("d-none", currentInspectionReadOnly);
        const captureLabel = addButton.parentElement && addButton.parentElement.querySelector("label");
        if (captureLabel) captureLabel.classList.toggle("d-none", currentInspectionReadOnly);
        document.getElementById(type === "BEFORE" ? "inspectionBeforePhotoCount" : "inspectionAfterPhotoCount").textContent = count + " foto";
    }
}

async function handleInspectionPhotoListClick(event) {
    const deleteButton = event.target.closest("[data-delete-inspection-photo]");
    if (deleteButton) {
        await handleInspectionPhotoDelete(event);
        return;
    }
    const serverPhotoItem = event.target.closest("[data-approval-photo-type][data-server-photo-index]");
    if (serverPhotoItem) {
        const type = String(serverPhotoItem.dataset.approvalPhotoType || "").toUpperCase();
        const photos = serverInspectionPhotoPreview.filter(photo =>
            String(photo.Type || "").toUpperCase() === type);
        const index = Number(serverPhotoItem.dataset.serverPhotoIndex);
        if (["BEFORE", "AFTER"].includes(type) && Number.isInteger(index) && index >= 0 && index < photos.length)
            openInspectionPhotoViewerFromData(type, photos, index);
        return;
    }
    const photoItem = event.target.closest(".inspection-photo-item");
    if (!photoItem) return;
    await openInspectionPhotoViewer(photoItem.dataset.photoType, photoItem.dataset.photoId);
}

async function openInspectionPhotoViewer(type, photoId) {
    if (type !== "BEFORE" && type !== "AFTER") return;
    if (!currentInspectionRecord) {
        const photos = serverInspectionPhotoPreview.filter(photo =>
            String(photo.Type || "").toUpperCase() === type);
        const index = photos.findIndex(photo => String(photo.ID) === String(photoId));
        if (index >= 0) openInspectionPhotoViewerFromData(type, photos, index);
        return;
    }
    const allPhotos = await getCurrentInspectionPhotos();
    const photos = allPhotos.filter(photo => String(photo.Type || "").toUpperCase() === type);
    const index = photos.findIndex(photo => String(photo.ID) === String(photoId));
    if (index < 0) return;
    openInspectionPhotoViewerFromData(type, photos, index);
}

function openInspectionPhotoViewerFromData(type, photos, index) {
    if ((type !== "BEFORE" && type !== "AFTER") || !Array.isArray(photos) || index < 0 || index >= photos.length) return;
    inspectionPhotoViewerState.type = type;
    inspectionPhotoViewerState.photos = photos;
    inspectionPhotoViewerState.index = index;
    const viewer = document.getElementById("inspectionPhotoViewer");
    viewer.classList.remove("d-none");
    viewer.setAttribute("aria-hidden", "false");
    document.body.classList.add("inspection-photo-viewer-open");
    renderInspectionPhotoViewerCurrent();
    document.getElementById("inspectionPhotoViewerClose").focus();
}

function renderInspectionPhotoViewerCurrent() {
    const state = inspectionPhotoViewerState;
    const photo = state.photos[state.index];
    if (!photo) return closeInspectionPhotoViewer();
    if (state.objectUrl) URL.revokeObjectURL(state.objectUrl);
    state.objectUrl = photo.Blob ? URL.createObjectURL(photo.Blob) : null;
    const image = document.getElementById("inspectionPhotoViewerImage");
    image.src = state.objectUrl || photo.Data || "";
    image.alt = "Foto " + state.type + " " + (state.index + 1);
    document.getElementById("inspectionPhotoViewerTitle").textContent = "FIELD DOCUMENTATION " + state.type;
    document.getElementById("inspectionPhotoViewerCount").textContent = (state.index + 1) + " / " + state.photos.length;
    document.getElementById("inspectionPhotoViewerPrev").disabled = state.photos.length < 2;
    document.getElementById("inspectionPhotoViewerNext").disabled = state.photos.length < 2;
}

function stepInspectionPhotoViewer(direction) {
    const state = inspectionPhotoViewerState;
    if (!state.photos.length) return;
    state.index = (state.index + direction + state.photos.length) % state.photos.length;
    renderInspectionPhotoViewerCurrent();
}

function closeInspectionPhotoViewer() {
    const viewer = document.getElementById("inspectionPhotoViewer");
    if (!viewer || viewer.classList.contains("d-none")) return;
    viewer.classList.add("d-none");
    viewer.setAttribute("aria-hidden", "true");
    document.body.classList.remove("inspection-photo-viewer-open");
    document.getElementById("inspectionPhotoViewerImage").removeAttribute("src");
    if (inspectionPhotoViewerState.objectUrl) URL.revokeObjectURL(inspectionPhotoViewerState.objectUrl);
    inspectionPhotoViewerState = { type: "", photos: [], index: 0, objectUrl: null, touchStartX: null };
}

function handleInspectionPhotoViewerKeydown(event) {
    const viewer = document.getElementById("inspectionPhotoViewer");
    if (!viewer || viewer.classList.contains("d-none")) return;
    if (event.key === "Escape") {
        event.preventDefault();
        closeInspectionPhotoViewer();
    } else if (event.key === "ArrowLeft") {
        event.preventDefault();
        stepInspectionPhotoViewer(-1);
    } else if (event.key === "ArrowRight") {
        event.preventDefault();
        stepInspectionPhotoViewer(1);
    }
}

async function getInspectionPhotoCaptureDate(file) {
    const fallback = file && Number(file.lastModified) > 0
        ? new Date(file.lastModified) : new Date();
    if (!file || !/jpe?g/i.test(String(file.type || "")) || typeof file.arrayBuffer !== "function")
        return fallback;
    try {
        const buffer = await file.arrayBuffer();
        const view = new DataView(buffer);
        if (view.byteLength < 12 || view.getUint16(0, false) !== 0xFFD8) return fallback;
        let offset = 2;
        while (offset + 4 < view.byteLength) {
            if (view.getUint8(offset) !== 0xFF) break;
            const marker = view.getUint8(offset + 1);
            const segmentLength = view.getUint16(offset + 2, false);
            if (segmentLength < 2 || offset + 2 + segmentLength > view.byteLength) break;
            if (marker === 0xE1 && segmentLength >= 10) {
                const exifHeader = String.fromCharCode(
                    view.getUint8(offset + 4), view.getUint8(offset + 5),
                    view.getUint8(offset + 6), view.getUint8(offset + 7),
                    view.getUint8(offset + 8), view.getUint8(offset + 9)
                );
                if (exifHeader === "Exif\0\0") {
                    const tiff = offset + 10;
                    const byteOrder = view.getUint16(tiff, false);
                    const little = byteOrder === 0x4949;
                    if (!little && byteOrder !== 0x4D4D) return fallback;
                    const read16 = position => view.getUint16(position, little);
                    const read32 = position => view.getUint32(position, little);
                    const ifd0 = tiff + read32(tiff + 4);
                    const count0 = read16(ifd0);
                    let exifIfd = 0;
                    for (let i = 0; i < count0; i++) {
                        const entry = ifd0 + 2 + i * 12;
                        if (read16(entry) === 0x8769) { exifIfd = tiff + read32(entry + 8); break; }
                    }
                    if (exifIfd) {
                        const countExif = read16(exifIfd);
                        for (let i = 0; i < countExif; i++) {
                            const entry = exifIfd + 2 + i * 12;
                            if (read16(entry) !== 0x9003) continue;
                            const count = read32(entry + 4);
                            const textOffset = count <= 4 ? entry + 8 : tiff + read32(entry + 8);
                            let value = "";
                            for (let j = 0; j < Math.min(count, 32); j++) {
                                const ch = view.getUint8(textOffset + j);
                                if (!ch) break;
                                value += String.fromCharCode(ch);
                            }
                            const match = value.match(/^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$/);
                            if (match) {
                                const captured = new Date(
                                    Number(match[1]), Number(match[2]) - 1, Number(match[3]),
                                    Number(match[4]), Number(match[5]), Number(match[6])
                                );
                                if (!isNaN(captured.getTime())) return captured;
                            }
                        }
                    }
                }
            }
            offset += 2 + segmentLength;
        }
    } catch (error) {
        console.warn("Unable to read camera EXIF capture time; using file timestamp:", error);
    }
    return fallback;
}

async function stampInspectionPhotoTimestamp(sourceBlob, capturedAt) {
    let bitmap = null, image = null, objectUrl = null;
    try {
        if (typeof createImageBitmap === "function") {
            bitmap = await createImageBitmap(sourceBlob);
        } else {
            objectUrl = URL.createObjectURL(sourceBlob);
            image = await new Promise((resolve, reject) => {
                const element = new Image();
                element.onload = () => resolve(element);
                element.onerror = () => reject(new Error("Foto tidak dapat dibaca untuk menempelkan timestamp."));
                element.src = objectUrl;
            });
        }
        const width = bitmap ? bitmap.width : image.naturalWidth;
        const height = bitmap ? bitmap.height : image.naturalHeight;
        if (!width || !height) throw new Error("Dimensi foto tidak valid.");
        const canvas = document.createElement("canvas");
        canvas.width = width;
        canvas.height = height;
        const context = canvas.getContext("2d");
        if (!context) throw new Error("Canvas foto tidak tersedia.");
        context.drawImage(bitmap || image, 0, 0, width, height);

        const date = capturedAt instanceof Date && !isNaN(capturedAt.getTime()) ? capturedAt : new Date();
        const pad = value => String(value).padStart(2, "0");
        const stamp = "CAPTURED " + pad(date.getDate()) + "/" + pad(date.getMonth() + 1) + "/" +
            date.getFullYear() + " " + pad(date.getHours()) + ":" + pad(date.getMinutes()) + ":" + pad(date.getSeconds());
        const fontSize = Math.max(12, Math.round(width * 0.022));
        const margin = Math.max(8, Math.round(width * 0.018));
        context.font = "bold " + fontSize + "px Arial, sans-serif";
        const textWidth = context.measureText(stamp).width;
        const boxHeight = fontSize + margin * 1.35;
        const boxWidth = textWidth + margin * 2;
        const x = margin;
        const y = height - margin - boxHeight;
        context.fillStyle = "rgba(0,0,0,.68)";
        context.fillRect(x, y, boxWidth, boxHeight);
        context.fillStyle = "#ffffff";
        context.textBaseline = "middle";
        context.fillText(stamp, x + margin, y + boxHeight / 2);

        const stamped = await new Promise((resolve, reject) => {
            canvas.toBlob(blob => blob && blob.size
                ? resolve(blob) : reject(new Error("Gagal membuat foto dengan timestamp.")), "image/jpeg", 0.9);
        });
        return stamped;
    } finally {
        if (bitmap && typeof bitmap.close === "function") bitmap.close();
        if (objectUrl) URL.revokeObjectURL(objectUrl);
    }
}

async function handleInspectionPhotoInput(event, type) {
    const input = event.target;
    const files = Array.from(input.files || []);
    input.value = "";
    if (!currentInspectionRecord || currentInspectionReadOnly || !files.length) return;

    // Prevent Save/Submit from racing an in-progress photo compression + IndexedDB write.
    // Without this guard, a user can select multiple photos and immediately press Save;
    // the inspection record may then be persisted before the remaining photo writes finish.
    const photoWritePromise = (async function () {
        const saveButton = document.getElementById("btnSaveInspectionDraft");
        const completeButton = document.getElementById("btnCompleteInspection");
        const previousSaveDisabled = saveButton ? saveButton.disabled : false;
        const previousCompleteDisabled = completeButton ? completeButton.disabled : false;
        if (saveButton) saveButton.disabled = true;
        if (completeButton) completeButton.disabled = true;

        try {
            const requirement = getInspectionPhotoRequirement(currentInspectionRecord);
            const beforeRequired = requirement === "BEFORE" || requirement === "BOTH";
            const afterRequired = requirement === "AFTER" || requirement === "BOTH";
            if ((type === "BEFORE" && !beforeRequired) || (type === "AFTER" && !afterRequired)) {
                showToast("Foto " + type + " tidak diaktifkan pada Template Version ini.", "warning");
                return;
            }

            const existing = await getCurrentInspectionPhotos();
            const hasBeforePhoto = existing.some(photo => String(photo.Type || "").toUpperCase() === "BEFORE");
            if (type === "AFTER" && beforeRequired && !hasBeforePhoto) {
                showToast("Ambil minimal satu foto BEFORE terlebih dahulu.", "warning");
                return;
            }

            let nextSeq = Math.max(Number(currentInspectionRecord.NextPhotoSeqNo || 1),
                existing.reduce((max, photo) => Math.max(max, Number(photo.SeqNo || photo.OrderNo || 0)), 0) + 1);
            let added = 0;

            for (const file of files) {
                if (!file.type.startsWith("image/")) {
                    showToast("File harus berupa gambar.", "warning");
                    continue;
                }
                try {
                    if (typeof compressImage !== "function")
                        throw new Error("Fungsi kompresi foto belum tersedia. Refresh aplikasi sebelum mencoba lagi.");

                    const captureDate = await getInspectionPhotoCaptureDate(file);
                    const compressedBlob = await compressImage(file, {
                        maxWidth: 640, maxHeight: 640, maxSize: 100 * 1024, quality: .70, minQuality: .25
                    });
                    if (!compressedBlob || typeof compressedBlob.size !== "number" || compressedBlob.size <= 0)
                        throw new Error("Hasil kompresi foto kosong.");
                    const stampedBlob = await stampInspectionPhotoTimestamp(compressedBlob, captureDate);
                    const blob = await compressImage(stampedBlob, {
                        maxWidth: 640, maxHeight: 640, maxSize: 100 * 1024, quality: .70, minQuality: .25
                    });
                    if (!blob || typeof blob.size !== "number" || blob.size <= 0)
                        throw new Error("Foto bertimestamp gagal dikompresi.");

                    const baseName = (file.name || ("inspection-" + type.toLowerCase())).replace(/\\.[^.]+$/, "");
                    await new Promise((resolve, reject) => {
                        const tx = db.transaction("inspection_photos", "readwrite");
                        tx.objectStore("inspection_photos").add({
                            LocalInspectionID: currentInspectionRecord.LocalInspectionID,
                            PointID: getActiveInspectionPointPhotoID(),
                            Type: type,
                            FileName: baseName + ".jpg",
                            Blob: blob,
                            SeqNo: nextSeq,
                            CapturedAt: captureDate.toISOString(),
                            CreatedAt: new Date().toISOString()
                        });
                        tx.oncomplete = () => resolve();
                        tx.onerror = () => reject(tx.error);
                        tx.onabort = () => reject(tx.error || new Error("Gagal menyimpan foto."));
                    });
                    nextSeq++;
                    added++;
                } catch (error) {
                    console.error(error);
                    showToast("Foto gagal disimpan: " + (error.message || error), "danger");
                }
            }

            if (added) {
                currentInspectionRecord.NextPhotoSeqNo = nextSeq;
                currentInspectionRecord.SyncStatus = "PENDING";
                currentInspectionRecord.UpdatedAt = new Date().toISOString();
            }
            await renderInspectionPhotos();
            await updateInspectionChecklistGate();
            scheduleInspectionAutosave();
        } finally {
            if (saveButton) saveButton.disabled = previousSaveDisabled;
            if (completeButton) completeButton.disabled = previousCompleteDisabled;
        }
    })();

    inspectionPhotoWritePromise = photoWritePromise;
    try {
        await photoWritePromise;
    } finally {
        if (inspectionPhotoWritePromise === photoWritePromise)
            inspectionPhotoWritePromise = null;
    }
}


async function handleInspectionPhotoDelete(event){const b=event.target.closest("[data-delete-inspection-photo]");if(!b||!currentInspectionRecord||currentInspectionReadOnly)return;const confirmed=await showConfirmation({title:"Hapus Foto",message:"Hapus foto ini?",yesText:"Hapus"});if(!confirmed)return;const existing=await getCurrentInspectionPhotos();const nextSeq=Math.max(Number(currentInspectionRecord.NextPhotoSeqNo||1),existing.reduce((max,p)=>Math.max(max,Number(p.SeqNo||p.OrderNo||0)),0)+1);currentInspectionRecord.NextPhotoSeqNo=nextSeq;currentInspectionRecord.SyncStatus="PENDING";currentInspectionRecord.UpdatedAt=new Date().toISOString();await new Promise((resolve,reject)=>{const tx=db.transaction("inspection_photos","readwrite");tx.objectStore("inspection_photos").delete(Number(b.dataset.deleteInspectionPhoto));tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error);tx.onabort=()=>reject(tx.error||new Error("Hapus foto gagal."));});await renderInspectionPhotos();await updateInspectionChecklistGate();scheduleInspectionAutosave();}
async function updateInspectionChecklistGate() {
    updateInspectionParameterTabGate();
    if (!currentInspectionRecord) return;
    const photos = await getCurrentInspectionPhotos();
    const requirement = getInspectionPhotoRequirement(currentInspectionRecord);
    const beforeRequired = requirement === "BEFORE" || requirement === "BOTH";
    const afterRequired = requirement === "AFTER" || requirement === "BOTH";
    const before = photos.some(photo => String(photo.Type || "").toUpperCase() === "BEFORE");
    const checklistLocked = beforeRequired && !before;
    document.querySelectorAll("#inspectionChecklistHost input, #inspectionChecklistHost select, #inspectionChecklistHost textarea")
        .forEach(element => { element.disabled = currentInspectionReadOnly || checklistLocked; });
    document.querySelectorAll("#inspectionPointConditionPanel input, #inspectionPointConditionPanel textarea")
        .forEach(element => { element.disabled = currentInspectionReadOnly || checklistLocked; });
    // Summary and Follow Up must follow the same BEFORE-photo prerequisite as checklist entry.
    document.getElementById("txtInspectionSummary").disabled = currentInspectionReadOnly || checklistLocked;
    document.getElementById("txtInspectionFollowUpRemark").disabled = currentInspectionReadOnly || checklistLocked;
    document.getElementById("inspectionFollowUpSection").disabled = currentInspectionReadOnly || checklistLocked;
    document.querySelectorAll('input[name="inspectionFollowUpSectionChoice"]').forEach(element => {
        element.disabled = currentInspectionReadOnly || checklistLocked;
    });
    document.querySelectorAll('input[name="inspectionFollowUp"]').forEach(element => {
        element.disabled = currentInspectionReadOnly || checklistLocked;
    });
    const afterInput = document.getElementById("inspectionPhotoAfterInput");
    const afterEnabled = afterRequired && (!beforeRequired || before);
    afterInput.disabled = currentInspectionReadOnly || !afterEnabled;
    document.getElementById("btnAddInspectionAfterPhoto").disabled = afterInput.disabled;
    document.getElementById("inspectionChecklistGateMessage").textContent = checklistLocked
        ? "Ambil minimal satu foto BEFORE untuk membuka checklist."
        : afterRequired
            ? "Foto yang diwajibkan Template Version harus tersedia sebelum point dapat diselesaikan."
            : "Lengkapi item checklist sesuai konfigurasi Template Version.";
}

function showInspectionInputScreen() {
    document.body.classList.remove("inspection-map-mobile-active");
    document.getElementById("inspectionRecordsPanel").classList.add("d-none");
    document.getElementById("inspectionInputPanel").classList.remove("d-none");
    document.getElementById("btnBackToInspectionRecords").classList.remove("d-none");
    document.getElementById("btnBackToInspectionApprovalList").classList.add("d-none");
}

function showInspectionRecordsScreen() {
    document.body.classList.remove("inspection-map-mobile-active");
    document.getElementById("inspectionInputPanel").classList.add("d-none");
    document.getElementById("inspectionRecordsPanel").classList.remove("d-none");
    document.getElementById("btnBackToInspectionRecords").classList.add("d-none");
    document.getElementById("btnBackToInspectionApprovalList").classList.add("d-none");
}

function updateInspectionConflictBadge() {
    const badge = document.getElementById("inspectionConflictBadge");
    if (!badge) return;
    // DELETE_PENDING includes supervisor-voided records awaiting server deactivation;
    // these are queued deletions, not inspection conflicts.
    const count = inspectionRecords.filter(record =>
        record.SyncStatus === "CONFLICT").length;
    badge.textContent = count ? String(count) : "!";
    badge.classList.toggle("d-none", count === 0);
    if (typeof window.updateGlobalInspectionConflictBadge === "function") {
        window.updateGlobalInspectionConflictBadge();
    }
}

async function queueConflictInspectionDelete(localId) {
    await deleteLocalInspectionDraft(localId);
}

function newInspectionId() {
    if (window.crypto && typeof window.crypto.randomUUID === "function") return window.crypto.randomUUID();
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
        const r = Math.random() * 16 | 0;
        const v = c === "x" ? r : (r & 0x3 | 0x8);
        return v.toString(16);
    });
}

function localDateString(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return year + "-" + month + "-" + day;
}

function localDateTimeString(date) {
    return localDateString(date) + "T" +
        String(date.getHours()).padStart(2, "0") + ":" +
        String(date.getMinutes()).padStart(2, "0") + ":" +
        String(date.getSeconds()).padStart(2, "0");
}



function getInspectionScrollTarget() {
    return window;
}

function updateInspectionScrollTools() {
    const tools = document.getElementById("inspectionScrollTools");
    const scrollUp = document.getElementById("inspectionScrollUp");
    const scrollDown = document.getElementById("inspectionScrollDown");
    if (!tools || !scrollUp || !scrollDown) return;

    const target = getInspectionScrollTarget();
    const modalTarget = target !== window;
    const scrollingElement = document.scrollingElement || document.documentElement;
    const scrollTop = modalTarget ? target.scrollTop : Math.max(window.scrollY || 0, scrollingElement.scrollTop || 0);
    const clientHeight = modalTarget ? target.clientHeight : window.innerHeight;
    const scrollHeight = modalTarget ? target.scrollHeight : scrollingElement.scrollHeight;
    const maxScroll = Math.max(0, scrollHeight - clientHeight);
    const canScroll = maxScroll > 4;
    const atTop = scrollTop <= 4;
    const atBottom = maxScroll - scrollTop <= 4;
    const modalShown = !!document.querySelector("#inspectionApprovalActionModal.show");
    tools.classList.toggle("d-none", !canScroll || (modalShown && !modalTarget));

    // Hide only the direction that cannot move farther; show both while between the ends.
    scrollUp.classList.toggle("d-none", atTop);
    scrollDown.classList.toggle("d-none", atBottom);
}

function wireInspectionEditorStickyHeader() {
    const panel = document.getElementById("inspectionInputPanel");
    const header = document.getElementById("inspectionEditorStickyHeader");
    const masterNav = document.querySelector(".top-navbar");
    if (!panel || !header || header.dataset.fixedScrollWired === "1") return;
    header.dataset.fixedScrollWired = "1";

    let spacer = null;
    let anchorTop = null;

    function clearFixedState() {
        header.style.position = "";
        header.style.top = "";
        header.style.left = "";
        header.style.width = "";
        header.style.zIndex = "";
        if (spacer) spacer.style.display = "none";
    }

    function updateFixedHeader() {
        if (panel.classList.contains("d-none") || !header.getClientRects().length) {
            clearFixedState();
            anchorTop = null;
            return;
        }

        if (!spacer) {
            anchorTop = header.getBoundingClientRect().top + window.pageYOffset;
            spacer = document.createElement("div");
            spacer.className = "inspection-editor-sticky-spacer";
            spacer.style.display = "none";
            header.parentNode.insertBefore(spacer, header);
        } else if (anchorTop === null) {
            anchorTop = header.getBoundingClientRect().top + window.pageYOffset;
        }

        const navBottom = masterNav && masterNav.getClientRects().length
            ? Math.max(0, masterNav.getBoundingClientRect().bottom)
            : 0;
        const shouldFix = window.pageYOffset >= anchorTop - navBottom;

        if (!shouldFix) {
            clearFixedState();
            return;
        }

        spacer.style.display = "block";
        spacer.style.height = header.offsetHeight + "px";
        const reference = spacer.getBoundingClientRect();
        header.style.position = "fixed";
        header.style.top = navBottom + "px";
        header.style.left = reference.left + "px";
        header.style.width = reference.width + "px";
        header.style.zIndex = "1045";
    }

    // The master sidebar changes #content's margin-left with a CSS transition.
    // This header becomes position:fixed while scrolling, so it no longer follows
    // that layout shift by itself. Re-measure it throughout the sidebar transition.
    const sidebar = document.getElementById("sidebar");
    const pageContent = document.getElementById("content");
    let sidebarSyncFrame = 0;
    let sidebarSyncUntil = 0;

    function getCssTransitionMs(element) {
        if (!element) return 0;
        const style = window.getComputedStyle(element);
        const durations = String(style.transitionDuration || "0s").split(",");
        const delays = String(style.transitionDelay || "0s").split(",");
        const toMs = value => {
            const v = String(value || "0s").trim();
            const n = parseFloat(v) || 0;
            return v.endsWith("ms") ? n : n * 1000;
        };
        return durations.reduce((max, duration, index) =>
            Math.max(max, toMs(duration) + toMs(delays[index % delays.length])), 0);
    }

    function updateInspectionInfoPopoverPosition() {
        const infoButton = document.getElementById("btnInspectionFormInfo");
        if (!infoButton || !window.bootstrap || !bootstrap.Popover) return;
        const infoPopover = bootstrap.Popover.getInstance(infoButton);
        if (infoPopover && typeof infoPopover.update === "function")
            infoPopover.update();
    }

    function syncHeaderDuringSidebarTransition(now) {
        updateFixedHeader();
        updateInspectionInfoPopoverPosition();
        if (now < sidebarSyncUntil) {
            sidebarSyncFrame = window.requestAnimationFrame(syncHeaderDuringSidebarTransition);
        } else {
            sidebarSyncFrame = 0;
            updateFixedHeader();
            updateInspectionInfoPopoverPosition();
        }
    }

    function handleSidebarLayoutChange() {
        const transitionMs = Math.max(
            getCssTransitionMs(sidebar),
            getCssTransitionMs(pageContent)
        );
        sidebarSyncUntil = performance.now() + transitionMs + 80;
        if (!sidebarSyncFrame)
            sidebarSyncFrame = window.requestAnimationFrame(syncHeaderDuringSidebarTransition);
    }

    const sidebarLayoutObserver = new MutationObserver(handleSidebarLayoutChange);
    if (sidebar)
        sidebarLayoutObserver.observe(sidebar, { attributes: true, attributeFilter: ["class"] });
    if (pageContent)
        sidebarLayoutObserver.observe(pageContent, { attributes: true, attributeFilter: ["class"] });

    window.addEventListener("scroll", updateFixedHeader, { passive: true });
    window.addEventListener("resize", updateFixedHeader);
    document.addEventListener("shown.bs.tab", updateFixedHeader);

    const panelObserver = new MutationObserver(function () {
        anchorTop = null;
        window.requestAnimationFrame(updateFixedHeader);
    });
    panelObserver.observe(panel, { attributes: true, attributeFilter: ["class"] });

    if (typeof ResizeObserver !== "undefined") {
        const headerObserver = new ResizeObserver(function () {
            if (spacer && spacer.style.display !== "none") {
                spacer.style.height = header.offsetHeight + "px";
                updateFixedHeader();
            }
        });
        headerObserver.observe(header);
    }

    updateFixedHeader();
}

function wireInspectionScrollTools() {
    const scrollUp = document.getElementById("inspectionScrollUp");
    const scrollDown = document.getElementById("inspectionScrollDown");
    if (!scrollUp || !scrollDown) return;

    const scrollToPosition = position => {
        const target = getInspectionScrollTarget();
        if (target === window) {
            window.scrollTo({ top: position === "top" ? 0 : Math.max(document.body.scrollHeight, document.documentElement.scrollHeight), behavior: "smooth" });
        } else {
            target.scrollTo({ top: position === "top" ? 0 : target.scrollHeight, behavior: "smooth" });
        }
    };

    scrollUp.addEventListener("click", () => scrollToPosition("top"));
    scrollDown.addEventListener("click", () => scrollToPosition("bottom"));
    window.addEventListener("scroll", updateInspectionScrollTools, { passive: true });
    document.addEventListener("scroll", event => {
        if (event.target && event.target.classList && event.target.classList.contains("modal-body")) updateInspectionScrollTools();
    }, true);
    document.addEventListener("shown.bs.modal", updateInspectionScrollTools);
    document.addEventListener("hidden.bs.modal", updateInspectionScrollTools);
    window.addEventListener("resize", updateInspectionScrollTools);
    updateInspectionScrollTools();
}

function escInspection(value) {
    return String(value == null ? "" : value)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}


let selectedInspectionApproval = null;
let inspectionApprovalRows = [];
let currentInspectionApprovalTab = "OUTSTANDING";
let inspectionApprovalLoadSequence = 0;
let inspectionApprovalSort = { key: "InspectionDate", direction: "asc" };
const INSPECTION_APPROVAL_DEFAULT_PAGE_SIZE = 25;
const INSPECTION_APPROVAL_PAGE_SIZE_KEY = "inspectionApprovalPageSize";
let inspectionApprovalPage = 1;
let inspectionApprovalPageSize = INSPECTION_APPROVAL_DEFAULT_PAGE_SIZE;
// Excel preview is generated server-side and opened with a short-lived Session token.

function addInspectionApprovalListener(id, eventName, handler) {
    const element = document.getElementById(id);
    if (!element) {
        console.error("Inspection Approval: elemen #" + id + " tidak ditemukan; event " + eventName + " dilewati.");
        return false;
    }
    element.addEventListener(eventName, handler);
    return true;
}

function wireInspectionApprovalEvents() {
    wireInspectionPhotoViewerEvents();
    const approvalDetail = document.getElementById("inspectionApprovalDetail");
    if (approvalDetail && !approvalDetail.dataset.approvalPhotoWired) {
        approvalDetail.dataset.approvalPhotoWired = "1";
        approvalDetail.addEventListener("click", function (event) {
            const button = event.target.closest("[data-approval-photo-type]");
            if (!button) return;
            const type = button.dataset.approvalPhotoType;
            const index = Number(button.dataset.approvalPhotoIndex);
            const stagePhotos = (window.currentInspectionApprovalPhotos || []).filter(photo => String(photo.Type || "").toUpperCase() === type);
            openInspectionPhotoViewerFromData(type, stagePhotos, index);
        });
    }
    addInspectionApprovalListener("btnRefreshInspectionApproval", "click", loadInspectionApprovalQueue);
    addInspectionApprovalListener("btnBackToInspectionApprovalList", "click", showInspectionApprovalQueueView);
    addInspectionApprovalListener("btnInspectionApprovalOutstanding", "click", () => setInspectionApprovalTab("OUTSTANDING"));
    addInspectionApprovalListener("btnInspectionApprovalApproved", "click", () => setInspectionApprovalTab("APPROVED"));
    addInspectionApprovalListener("btnInspectionApprovalVoid", "click", () => setInspectionApprovalTab("VOID"));
    addInspectionApprovalListener("inspectionApprovalQueue", "click", function (event) {
        const link = event.target.closest("[data-approval-id]");
        if (link) openInspectionApprovalDetail(Number(link.dataset.approvalId));
    });
    addInspectionApprovalListener("inspectionApprovalQueue", "change", function (event) {
        if (event.target.matches("[data-approval-select]")) updateInspectionApprovalSelectAll();
    });
    addInspectionApprovalListener("inspectionApprovalTable", "click", function (event) {
        const header = event.target.closest("[data-approval-sort]");
        if (!header) return;
        const key = header.dataset.approvalSort;
        if (inspectionApprovalSort.key === key) inspectionApprovalSort.direction = inspectionApprovalSort.direction === "asc" ? "desc" : "asc";
        else { inspectionApprovalSort.key = key; inspectionApprovalSort.direction = "asc"; }
        inspectionApprovalPage = 1;
        renderInspectionApprovalQueue();
    });
    addInspectionApprovalListener("inspectionApprovalTable", "keydown", function (event) {
        if ((event.key === "Enter" || event.key === " ") && event.target.matches("[data-approval-sort]")) {
            event.preventDefault(); event.target.click();
        }
    });
    addInspectionApprovalListener("btnInspectionApprovalPreview", "click", previewSelectedInspections);
    addInspectionApprovalListener("inspectionApprovalChecklistTab", "shown.bs.tab", function () {
        const navHost = document.getElementById("inspectionApprovalSectionNavHost");
        if (navHost) navHost.classList.remove("d-none");
    });
    addInspectionApprovalListener("inspectionApprovalParamTab", "shown.bs.tab", function () {
        const navHost = document.getElementById("inspectionApprovalSectionNavHost");
        if (navHost) navHost.classList.add("d-none");
    });
    addInspectionApprovalListener("selApprovalType", "change", function () {
        document.getElementById("selApprovalDetail").value = "";
        document.getElementById("selApprovalTemplate").value = "";
        document.getElementById("selApprovalScheduleTime").value = "";
        loadInspectionApprovalQueue();
    });
    addInspectionApprovalListener("selApprovalDetail", "change", function () {
        document.getElementById("selApprovalTemplate").value = "";
        document.getElementById("selApprovalScheduleTime").value = "";
        loadInspectionApprovalQueue();
    });
    ["selApprovalTemplate", "selApprovalScheduleTime", "txtApprovalDateFrom", "txtApprovalDateThru"].forEach(id =>
        addInspectionApprovalListener(id, "change", loadInspectionApprovalQueue));
    addInspectionApprovalListener("btnApprovalSelectAll", "click", function () {
        document.querySelectorAll("#inspectionApprovalQueue [data-approval-select]").forEach(box => { box.checked = true; });
        updateInspectionApprovalSelectAll();
    });
    addInspectionApprovalListener("chkAllInspectionApproval", "change", function () {
        document.querySelectorAll("#inspectionApprovalQueue [data-approval-select]").forEach(box => { box.checked = this.checked; });
        updateInspectionApprovalSelectAll();
    });
    ["inspectionApprovalPageSize", "inspectionApprovalPageSizeTop"].forEach(id =>
        addInspectionApprovalListener(id, "change", function () {
            const size = Number(this.value);
            if (!Number.isFinite(size) || size <= 0) return;
            inspectionApprovalPageSize = size;
            inspectionApprovalPage = 1;
            document.querySelectorAll("#inspectionApprovalPageSize, #inspectionApprovalPageSizeTop").forEach(select => {
                select.value = String(size);
            });
            try { localStorage.setItem(INSPECTION_APPROVAL_PAGE_SIZE_KEY, String(size)); } catch (e) {}
            renderInspectionApprovalQueue();
        }));
    ["inspectionApprovalPrevPage", "inspectionApprovalPrevPageTop"].forEach(id =>
        addInspectionApprovalListener(id, "click", function () {
            if (inspectionApprovalPage > 1) {
                inspectionApprovalPage--;
                renderInspectionApprovalQueue();
            }
        }));
    ["inspectionApprovalNextPage", "inspectionApprovalNextPageTop"].forEach(id =>
        addInspectionApprovalListener(id, "click", function () {
            const pageCount = getInspectionApprovalPageCount();
            if (inspectionApprovalPage < pageCount) {
                inspectionApprovalPage++;
                renderInspectionApprovalQueue();
            }
        }));
    addInspectionApprovalListener("btnBatchApproveInspection", "click", () => openInspectionApprovalAction("APPROVE", true));
    addInspectionApprovalListener("btnBatchVoidInspection", "click", () => openInspectionApprovalAction("VOID", true));
    addInspectionApprovalListener("btnApproveInspection", "click", () => processInspectionApproval("APPROVE"));
    addInspectionApprovalListener("btnVoidInspection", "click", () => openInspectionApprovalAction("VOID", false));
    addInspectionApprovalListener("btnConfirmInspectionApprovalAction", "click", confirmInspectionApprovalAction);

    try {
        const savedPageSize = Number(localStorage.getItem(INSPECTION_APPROVAL_PAGE_SIZE_KEY));
        if ([10, 25, 50, 100].includes(savedPageSize)) inspectionApprovalPageSize = savedPageSize;
    } catch (e) {}
    document.querySelectorAll("#inspectionApprovalPageSize, #inspectionApprovalPageSizeTop").forEach(select => {
        select.value = String(inspectionApprovalPageSize);
    });

    const today = localDateString(new Date());
    ["txtApprovalDateFrom", "txtApprovalDateThru"].forEach(id => {
        const input = document.getElementById(id);
        if (input && !input.value) input.value = formatInspectionDateDMY(today);
    });
    wireInspectionDatePicker("txtApprovalDateFrom", "pickerApprovalDateFrom");
    wireInspectionDatePicker("txtApprovalDateThru", "pickerApprovalDateThru");
    setInspectionApprovalTab(currentInspectionApprovalTab, false);
}

function setInspectionApprovalTab(tab, reload) {
    currentInspectionApprovalTab = ["APPROVED", "VOID"].includes(tab) ? tab : "OUTSTANDING";
    const outstanding = currentInspectionApprovalTab === "OUTSTANDING";
    const approved = currentInspectionApprovalTab === "APPROVED";
    const voided = currentInspectionApprovalTab === "VOID";
    [
        ["btnInspectionApprovalOutstanding", outstanding],
        ["btnInspectionApprovalApproved", approved],
        ["btnInspectionApprovalVoid", voided]
    ].forEach(pair => {
        const button = document.getElementById(pair[0]);
        if (button) {
            button.classList.toggle("active", pair[1]);
            button.setAttribute("aria-selected", pair[1] ? "true" : "false");
        }
    });
    const batchActions = document.getElementById("inspectionApprovalBatchActions");
    if (batchActions) batchActions.classList.toggle("d-none", voided);
    ["btnBatchApproveInspection", "btnBatchVoidInspection"].forEach(id => {
        const button = document.getElementById(id);
        if (button) button.classList.toggle("d-none", !outstanding);
    });
    const selectAllHeader = document.getElementById("thInspectionApprovalSelectAll");
    if (selectAllHeader) selectAllHeader.classList.toggle("d-none", voided);
    const dateFilters = document.getElementById("inspectionApprovalDateFilters");
    if (dateFilters) dateFilters.classList.toggle("d-none", !approved);
    if (reload === false) renderInspectionApprovalQueue();
    else loadInspectionApprovalQueue();
}

function updateInspectionApprovalCounts(counts) {
    if (!counts) return;
    const outstandingElement = document.getElementById("inspectionApprovalOutstandingCount");
    const approvedElement = document.getElementById("inspectionApprovalApprovedCount");
    const voidElement = document.getElementById("inspectionApprovalVoidCount");
    if (outstandingElement) outstandingElement.textContent = String(Number(counts.outstanding) || 0);
    if (approvedElement) approvedElement.textContent = String(Number(counts.approved) || 0);
    if (voidElement) voidElement.textContent = String(Number(counts.voided) || 0);
}

function isInspectionApprovalApproved(row) {
    if (!row) return false;
    // Lightning has two approval stages; it is final only after Chief Security.
    const value = String(row.InspectionMode || "").toUpperCase() === "LIGHTNING" ? row.IsApproved2 : row.IsApproved;
    return value === true || value === 1 || String(value).toLowerCase() === "true" || String(value) === "1";
}

function isInspectionApprovalVoided(row) {
    return !!row &&
        String(row.Status || "").toUpperCase() === "DRAFT" &&
        [row.ReasonVoid, row.ReasonVoid1, row.ReasonVoid2].some(value => String(value || "").trim() !== "") &&
        (row.IsSubmitted === false || row.IsSubmitted === 0 || String(row.IsSubmitted) === "0");
}

async function inspectionApprovalPost(method, args) {
    const response = await fetch("inspection.aspx/" + method, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=utf-8" },
        body: JSON.stringify(args)
    });
    const payload = await response.json();
    if (!response.ok) {
        const message = payload && payload.Message ? payload.Message : "Request approval gagal.";
        throw new Error(message);
    }
    const result = payload && Object.prototype.hasOwnProperty.call(payload, "d") ? payload.d : payload;
    if (result && result.success === false) throw new Error(result.message || "Request approval gagal.");
    return result;
}

async function loadInspectionApprovalQueue() {
    showInspectionApprovalQueueView();
    const requestSequence = ++inspectionApprovalLoadSequence;
    const host = document.getElementById("inspectionApprovalQueue");
    if (!host) return;
    host.innerHTML = '<tr><td colspan="10" class="text-muted py-2">Memuat dari server...</td></tr>';
    inspectionApprovalPage = 1;
    selectedInspectionApproval = null;
    if (!navigator.onLine) {
        showToast("Approval Supervisor memerlukan koneksi ke server. Mode approval offline belum didukung.", "warning");
        host.innerHTML = '<tr><td colspan="10" class="text-muted py-2">Hubungkan internet lalu tekan Refresh.</td></tr>';
        document.getElementById("inspectionApprovalDetail").innerHTML = '<div class="text-muted">Detail approval hanya dapat dibuka saat online.</div>';
        return;
    }
    document.getElementById("inspectionApprovalDetail").innerHTML = '<div class="text-muted">Pilih inspeksi untuk melihat detail checklist.</div>';
    try {
        const dateFrom = document.getElementById("txtApprovalDateFrom");
        const dateThru = document.getElementById("txtApprovalDateThru");
        if (currentInspectionApprovalTab === "APPROVED" &&
            ((dateFrom && dateFrom.value && !parseInspectionDateFilter(dateFrom.value)) ||
             (dateThru && dateThru.value && !parseInspectionDateFilter(dateThru.value)))) {
            showToast("Tanggal From/Thru tidak valid. Periksa rentang tanggal yang dipilih.", "warning");
            return;
        }
        const queueParameters = {
            employeeId: inspectionLogin.employeeid,
            companyId: inspectionCompanyID,
            locationId: inspectionLocationID,
            approvalTab: currentInspectionApprovalTab,
            // Date range is relevant only to Approved history. Outstanding is
            // an action queue and must always return every pending transaction.
            dateFrom: currentInspectionApprovalTab === "APPROVED" && dateFrom
                ? (parseInspectionDateFilter(dateFrom.value) || "") : "",
            dateThru: currentInspectionApprovalTab === "APPROVED" && dateThru
                ? (parseInspectionDateFilter(dateThru.value) || "") : "",
            inspectionTypeCode: document.getElementById("selApprovalType").value,
            inspectionTypeDetailCode: document.getElementById("selApprovalDetail").value,
            templateId: document.getElementById("selApprovalTemplate").value,
            scheduleTime: document.getElementById("selApprovalScheduleTime").value
        };
        // Refresh all tab badges independently from the active grid tab.
        // Counts intentionally ignore Type/Detail/Template/Schedule filters so
        // they remain total counts for the current employee and location.
        const countParameters = {
            employeeId: inspectionLogin.employeeid,
            companyId: inspectionCompanyID,
            locationId: inspectionLocationID,
            dateFrom: dateFrom ? (parseInspectionDateFilter(dateFrom.value) || "") : "",
            dateThru: dateThru ? (parseInspectionDateFilter(dateThru.value) || "") : ""
        };
        const countRequest = inspectionApprovalPost("GetInspectionApprovalCounts", countParameters)
            .catch(countError => {
                console.warn("Unable to refresh Inspection approval tab counts:", countError);
                return null;
            });
        const queueRequests = Promise.all([
            inspectionApprovalPost("GetInspectionApprovalQueue", queueParameters),
            inspectionApprovalPost("GetLightningInspectionApprovalQueue", queueParameters)
        ]);
        const [queueResults, countResult] = await Promise.all([queueRequests, countRequest]);
        if (requestSequence !== inspectionApprovalLoadSequence) return;
        const standardResult = queueResults[0] || {};
        const lightningResult = queueResults[1] || {};
        inspectionApprovalRows = (standardResult.data || []).concat(lightningResult.data || []);
        if (countResult) updateInspectionApprovalCounts(countResult);
        const filterMap = new Map();
        (standardResult.filters || []).concat(lightningResult.filters || []).forEach(row => {
            const key = [row.InspectionTypeCode,row.InspectionTypeDetailCode,row.IDTemplate,row.ScheduledTime].join("|");
            if (!filterMap.has(key)) filterMap.set(key, row);
        });
        populateInspectionApprovalFilters(Array.from(filterMap.values()));
        renderInspectionApprovalQueue();
        if (!approvalInspectionDeepLinkHandled && window.location && window.location.search) {
            const query = new URLSearchParams(window.location.search);
            const requestedId = Number(query.get("inspectionId") || 0);
            if (requestedId > 0 && inspectionApprovalRows.some(row => Number(row.InspectionID) === requestedId)) {
                approvalInspectionDeepLinkHandled = true;
                window.setTimeout(() => openInspectionApprovalDetail(requestedId), 120);
            }
        }
    } catch (err) {
        if (requestSequence !== inspectionApprovalLoadSequence) return;
        host.innerHTML = '<tr><td colspan="9" class="text-danger py-2">' + escInspection(err.message || "Gagal memuat antrean approval.") + '</td></tr>';
    }
}

function populateInspectionApprovalFilters(filterRows) {
    const specs = [
        { id: "selApprovalType", key: "InspectionTypeCode", label: "InspectionTypeName", all: "All types" },
        { id: "selApprovalDetail", key: "InspectionTypeDetailCode", label: "InspectionTypeDetailName", all: "All details" },
        { id: "selApprovalTemplate", key: "IDTemplate", label: "TemplateNo", all: "All templates" },
        { id: "selApprovalScheduleTime", key: "ScheduledTime", label: "ScheduledTime", all: "All schedules" }
    ];
    const rows = Array.isArray(filterRows) ? filterRows : [];
    const selectedType = document.getElementById("selApprovalType").value;
    const selectedDetail = document.getElementById("selApprovalDetail").value;
    const selectedTemplate = document.getElementById("selApprovalTemplate").value;
    specs.forEach(spec => {
        const select = document.getElementById(spec.id);
        if (!select) return;
        const previous = select.value;
        const applicableRows = rows.filter(row => {
            if (spec.id !== "selApprovalType" && selectedType && String(row.InspectionTypeCode || "") !== selectedType) return false;
            if (["selApprovalTemplate", "selApprovalScheduleTime"].includes(spec.id) && selectedDetail && String(row.InspectionTypeDetailCode || "") !== selectedDetail) return false;
            if (spec.id === "selApprovalScheduleTime" && selectedTemplate && String(row.IDTemplate || "") !== selectedTemplate) return false;
            return true;
        });
        const values = new Map();
        applicableRows.forEach(row => {
            const key = String(row[spec.key] == null ? "" : row[spec.key]);
            if (key && !values.has(key)) values.set(key, spec.id === "selApprovalDetail" ? (key + " - " + String(row[spec.label] || key)) : String(row[spec.label] || key));
        });
        select.innerHTML = '<option value="">' + spec.all + '</option>' +
            Array.from(values.entries()).sort((a, b) => a[1].localeCompare(b[1])).map(pair =>
                '<option value="' + escInspection(pair[0]) + '">' + escInspection(pair[1]) + '</option>'
            ).join("");
        if (values.has(previous)) select.value = previous;
        else select.value = "";
    });
    document.getElementById("selApprovalDetail").disabled = !selectedType;
    document.getElementById("selApprovalTemplate").disabled = !selectedType;
}

function getInspectionApprovalPageCount() {
    const rows = inspectionApprovalRows.filter(row => {
        if (currentInspectionApprovalTab === "APPROVED") return isInspectionApprovalApproved(row);
        if (currentInspectionApprovalTab === "VOID") return isInspectionApprovalVoided(row);
        return !isInspectionApprovalApproved(row) && !isInspectionApprovalVoided(row);
    });
    return Math.max(1, Math.ceil(rows.length / inspectionApprovalPageSize));
}

function updateInspectionApprovalPager(totalRows, pageCount) {
    [
        ["inspectionApprovalPageInfo", "inspectionApprovalPrevPage", "inspectionApprovalNextPage", "inspectionApprovalTotalRows"],
        ["inspectionApprovalPageInfoTop", "inspectionApprovalPrevPageTop", "inspectionApprovalNextPageTop", "inspectionApprovalTotalRowsTop"]
    ].forEach(ids => {
        const info = document.getElementById(ids[0]);
        const prev = document.getElementById(ids[1]);
        const next = document.getElementById(ids[2]);
        const total = document.getElementById(ids[3]);
        if (info) info.textContent = totalRows ? ("Page " + inspectionApprovalPage + " of " + pageCount) : "Page 1 of 1";
        if (total) total.textContent = totalRows + " record" + (totalRows === 1 ? "" : "s");
        if (prev) prev.disabled = inspectionApprovalPage <= 1 || totalRows === 0;
        if (next) next.disabled = inspectionApprovalPage >= pageCount || totalRows === 0;
    });
}

function renderInspectionApprovalQueue() {
    const host = document.getElementById("inspectionApprovalQueue");
    if (!host) return;
    const rows = inspectionApprovalRows.filter(row => {
        if (currentInspectionApprovalTab === "APPROVED") return isInspectionApprovalApproved(row);
        if (currentInspectionApprovalTab === "VOID") return isInspectionApprovalVoided(row);
        return !isInspectionApprovalApproved(row) && !isInspectionApprovalVoided(row);
    });
    const hasSelectionColumn = currentInspectionApprovalTab === "OUTSTANDING" || currentInspectionApprovalTab === "APPROVED";
    const pageCount = Math.max(1, Math.ceil(rows.length / inspectionApprovalPageSize));
    if (inspectionApprovalPage > pageCount) inspectionApprovalPage = pageCount;
    updateInspectionApprovalPager(rows.length, pageCount);
    if (!rows.length) {
        host.innerHTML = '<tr><td colspan="' + (hasSelectionColumn ? "10" : "9") + '" class="text-muted py-3 text-center">Tidak ada inspeksi untuk filter ini.</td></tr>';
        const selectAll = document.getElementById("chkAllInspectionApproval");
        if (selectAll) selectAll.checked = false;
        updateInspectionApprovalSelectAll();
        return;
    }
    const sortedRows = rows.slice().sort((left, right) => {
        const key = inspectionApprovalSort.key;
        let a = left[key], b = right[key];
        if (key === "InspectionDate" || key === "StartDateTime" || key === "EndDateTime") {
            const toSortTimestamp = value => {
                if (value == null || value === "") return 0;
                if (typeof value === "string") {
                    if (value.indexOf("/Date(") === 0) {
                        const milliseconds = Number(value.slice(6).split(")")[0]);
                        if (Number.isFinite(milliseconds)) return milliseconds;
                    }
                }
                const parsed = new Date(value).getTime();
                return Number.isFinite(parsed) ? parsed : 0;
            };
            a = toSortTimestamp(a); b = toSortTimestamp(b);
        } else if (key === "ScheduledTime") {
            a = String(a || ""); b = String(b || "");
        } else { a = String(a == null ? "" : a).toLocaleLowerCase(); b = String(b == null ? "" : b).toLocaleLowerCase(); }
        const cmp = a < b ? -1 : (a > b ? 1 : 0);
        return inspectionApprovalSort.direction === "asc" ? cmp : -cmp;
    });
    document.querySelectorAll("#inspectionApprovalTable [data-approval-sort]").forEach(th => {
        const active = th.dataset.approvalSort === inspectionApprovalSort.key;
        const indicator = th.querySelector(".approval-sort-indicator");
        if (indicator) {
            indicator.classList.toggle("is-asc", active && inspectionApprovalSort.direction === "asc");
            indicator.classList.toggle("is-desc", active && inspectionApprovalSort.direction === "desc");
        }
        th.setAttribute("aria-sort", active ? (inspectionApprovalSort.direction === "asc" ? "ascending" : "descending") : "none");
    });
    const pageStart = (inspectionApprovalPage - 1) * inspectionApprovalPageSize;
    const pageRows = sortedRows.slice(pageStart, pageStart + inspectionApprovalPageSize);
    host.innerHTML = pageRows.map((row, pageIndex) => {
        const id = Number(row.InspectionID);
        const rowNumber = pageStart + pageIndex + 1;
        const start = formatInspectionClock(row.StartDateTime);
        const end = formatInspectionClock(row.EndDateTime);
        const range = (start && start !== "-" ? start : "-") + " – " + (end && end !== "-" ? end : "-");
        const selectCell = hasSelectionColumn
            ? '<td class="approval-select-cell"><input type="checkbox" class="form-check-input" data-approval-select value="' + id + '" aria-label="Select inspection ' + escInspection(row.InspectionNo || id) + '"></td>'
            : '';
        const statusLabel = row.WorkflowStatus || (isInspectionApprovalVoided(row) ? "VOID" : (isInspectionApprovalApproved(row) ? "APPROVED" : "PENDING"));
        const statusHtml = '<span class="badge rounded-pill ' + (statusLabel === "VOID" ? "text-bg-warning" : (statusLabel === "APPROVED" || statusLabel === "ACKNOWLEDGE 2" ? "text-bg-success" : "text-bg-primary")) + '">' + escInspection(statusLabel) + '</span>';
        return '<tr>' +
            '<td data-label="No." class="text-center text-muted fw-semibold">' + rowNumber + '</td>' +
            selectCell +
            '<td data-label="Transaction No."><button type="button" class="btn btn-link p-0 text-wrap fw-semibold" data-approval-id="' + id + '">' + escInspection(row.InspectionNo || ("Inspection #" + id)) + '</button></td>' +
            '<td data-label="Inspection Type">' + escInspection(row.InspectionTypeName || row.InspectionTypeCode || "") + '</td>' +
            '<td data-label="Inspection Detail">' + escInspection(row.InspectionTypeDetailName || row.InspectionTypeDetailCode || "") +
                (row.TenantID && row.SuiteNo ? '<div class="small text-muted">Tenant: ' + escInspection(row.TenantID) +
                    ' / Suite ' + escInspection(row.SuiteNo) + '</div>' : '') + '</td>' +
            '<td data-label="Date">' + escInspection(formatInspectionDateDMY(row.InspectionDate) || "") + '</td>' +
            '<td data-label="Scheduled">' + escInspection(row.ScheduledTime || "-") + '</td>' +
            '<td data-label="Start – End">' + escInspection(range) + '</td>' +
            '<td data-label="Technician">' + escInspection(formatInspectionEmployeeLabel(row.TechnicianName || row.OwnerEmployeeName, row.OwnerEmployeeID)) + '</td>' +
            '<td data-label="Status">' + statusHtml + '</td>' +
            '</tr>';
    }).join("");
    updateInspectionApprovalSelectAll();
}

function getSelectedInspectionApprovalRows() {
    const ids = new Set(Array.from(document.querySelectorAll("#inspectionApprovalQueue [data-approval-select]:checked"))
        .map(box => Number(box.value)).filter(id => id > 0));
    return inspectionApprovalRows.filter(row => ids.has(Number(row.InspectionID)));
}

function validateSelectedInspectionApprovalType(rows) {
    rows = rows || [];
    if (!rows.length) {
        showToast("Pilih minimal satu inspeksi terlebih dahulu.", "warning");
        return false;
    }
    const types = Array.from(new Set(rows.map(row => String(row.InspectionTypeCode || "").trim().toUpperCase()).filter(Boolean)));
    if (types.length !== 1 || rows.some(row => !String(row.InspectionTypeCode || "").trim())) {
        showToast("Inspection Type tidak boleh dicampur. Pilih transaksi dari satu Inspection Type saja.", "warning");
        return false;
    }
    return true;
}

function updateInspectionApprovalSelectAll() {
    const boxes = Array.from(document.querySelectorAll("#inspectionApprovalQueue [data-approval-select]"));
    const selectedBoxes = boxes.filter(box => box.checked);
    const all = document.getElementById("chkAllInspectionApproval");
    if (all) all.checked = boxes.length > 0 && selectedBoxes.length === boxes.length;
    const preview = document.getElementById("btnInspectionApprovalPreview");
    if (preview) preview.disabled = !["OUTSTANDING", "APPROVED"].includes(currentInspectionApprovalTab) || selectedBoxes.length === 0;
}

async function previewSelectedInspections() {
    const rows = getSelectedInspectionApprovalRows();
    if (!validateSelectedInspectionApprovalType(rows)) return;
    if (!navigator.onLine) {
        showToast("Preview report memerlukan koneksi ke server.", "warning");
        return;
    }

    const previewButton = document.getElementById("btnInspectionApprovalPreview");
    if (previewButton && previewButton.dataset.processing === "1") return;

    // Show visible progress while the server validates the selection and builds the Excel workbook.
    let progressOverlay = null;
    let progressTimer = null;
    let originalButtonHtml = "";
    const progressMessages = [
        "Mengumpulkan data inspeksi yang dipilih...",
        "Memvalidasi transaksi dan hak akses...",
        "Mengambil detail checklist dan hasil inspeksi...",
        "Menyusun lembar kerja Excel...",
        "Memformat dan merapikan laporan...",
        "Memeriksa hasil akhir file report..."
    ];
    let messageIndex = 0;

    function showReportProgress() {
        if (previewButton) {
            originalButtonHtml = previewButton.innerHTML;
            previewButton.dataset.processing = "1";
            previewButton.disabled = true;
            previewButton.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Processing...';
        }

        progressOverlay = document.createElement("div");
        progressOverlay.setAttribute("role", "status");
        progressOverlay.setAttribute("aria-live", "polite");
        progressOverlay.style.cssText = "position:fixed;inset:0;z-index:3000;display:flex;align-items:center;justify-content:center;padding:1rem;background:rgba(15,23,42,.58);backdrop-filter:blur(3px);";
        progressOverlay.innerHTML =
            '<div style="width:min(430px,100%);padding:1.5rem;border-radius:1rem;background:var(--bs-body-bg,#fff);color:var(--bs-body-color,#212529);box-shadow:0 1rem 3rem rgba(0,0,0,.25);text-align:center;">' +
                '<div class="mb-3"><div class="spinner-border text-primary" style="width:2.8rem;height:2.8rem;" role="status"><span class="visually-hidden">Processing...</span></div></div>' +
                '<div class="fw-bold fs-5 mb-1">Generating Inspection Report</div>' +
                '<div class="small text-muted mb-3">Mohon tunggu, sistem sedang memproses data inspeksi.</div>' +
                '<div class="progress mb-3" style="height:7px;"><div class="progress-bar progress-bar-striped progress-bar-animated" style="width:100%;"></div></div>' +
                '<div data-report-progress-message class="small fw-semibold text-primary">' + progressMessages[0] + '</div>' +
                '<div class="small text-muted mt-2">' + rows.length + ' transaksi diproses</div>' +
                '<div class="small text-muted mt-3">Jangan tutup atau refresh halaman ini.</div>' +
            '</div>';
        document.body.appendChild(progressOverlay);

        progressTimer = window.setInterval(function () {
            messageIndex = (messageIndex + 1) % progressMessages.length;
            const message = progressOverlay && progressOverlay.querySelector("[data-report-progress-message]");
            if (message) message.textContent = progressMessages[messageIndex];
        }, 1800);
    }

    function hideReportProgress() {
        if (progressTimer) {
            window.clearInterval(progressTimer);
            progressTimer = null;
        }
        if (progressOverlay && progressOverlay.parentNode)
            progressOverlay.parentNode.removeChild(progressOverlay);
        progressOverlay = null;

        if (previewButton) {
            delete previewButton.dataset.processing;
            previewButton.innerHTML = originalButtonHtml || '<i class="bi bi-file-earmark-excel me-1"></i>Preview';
            previewButton.disabled = !["OUTSTANDING", "APPROVED"].includes(currentInspectionApprovalTab) ||
                getSelectedInspectionApprovalRows().length === 0;
        }
    }

    showReportProgress();
    try {
        const response = await fetch("inspection.aspx/GenerateReport", {
            method: "POST",
            headers: { "Content-Type": "application/json; charset=utf-8" },
            body: JSON.stringify({
                inspectionIds: rows.map(row => Number(row.InspectionID)),
                employeeId: inspectionLogin.employeeid,
                companyId: inspectionCompanyID,
                locationId: inspectionLocationID
            })
        });
        const payload = await response.json();
        const result = payload && Object.prototype.hasOwnProperty.call(payload, "d") ? payload.d : payload;
        if (!response.ok || !result || !result.success || !result.filePath)
            throw new Error(result && result.message ? result.message : "Server gagal membuat file Excel.");

        showToast("Report berhasil dibuat: " + result.fileName, "success");
        hideReportProgress();
        window.location.href = result.filePath;
    } catch (err) {
        hideReportProgress();
        showToast(err.message || "Gagal membuat preview report.", "warning");
    }
}

function openInspectionApprovalDetail(inspectionId) {
    const detailPanel = document.getElementById("inspectionApprovalDetailPanel");
    if (!detailPanel || !inspectionId) return;
    const listView = document.getElementById("inspectionApprovalListView");
    const listHeader = document.getElementById("inspectionApprovalListHeader");
    if (listView) listView.classList.add("d-none");
    if (listHeader) listHeader.classList.add("d-none");
    detailPanel.classList.remove("d-none");
    document.getElementById("btnBackToInspectionApprovalList").classList.remove("d-none");
    document.getElementById("btnBackToInspectionRecords").classList.add("d-none");
    selectedInspectionApproval = null;
    document.getElementById("inspectionApprovalDetailSubtitle").textContent = "";
    document.getElementById("inspectionApprovalParameters").innerHTML = "";
    document.getElementById("inspectionApprovalDetail").innerHTML = '<div class="text-muted">Memuat checklist...</div>';
    document.getElementById("btnApproveInspection").disabled = true;
    document.getElementById("btnVoidInspection").disabled = true;
    loadInspectionApprovalDetail(inspectionId);
    detailPanel.scrollIntoView({ behavior: "smooth", block: "start" });
    updateInspectionScrollTools();
}

function showInspectionApprovalQueueView() {
    const detailPanel = document.getElementById("inspectionApprovalDetailPanel");
    if (detailPanel) detailPanel.classList.add("d-none");
    document.getElementById("btnBackToInspectionApprovalList").classList.add("d-none");
    document.getElementById("btnBackToInspectionRecords").classList.add("d-none");
    const listView = document.getElementById("inspectionApprovalListView");
    const listHeader = document.getElementById("inspectionApprovalListHeader");
    if (listView) listView.classList.remove("d-none");
    if (listHeader) listHeader.classList.remove("d-none");
    selectedInspectionApproval = null;
    updateInspectionScrollTools();
}

function openInspectionApprovalAction(action, batch) {
    const ids = batch
        ? Array.from(document.querySelectorAll("#inspectionApprovalQueue [data-approval-select]:checked")).map(box => Number(box.value)).filter(id => id > 0)
        : (selectedInspectionApproval ? [Number(selectedInspectionApproval.InspectionID)] : []);
    if (!ids.length) {
        showToast(batch ? "Pilih minimal satu inspeksi terlebih dahulu." : "Pilih inspeksi terlebih dahulu.", "warning");
        return;
    }
    if (batch && !validateSelectedInspectionApprovalType(getSelectedInspectionApprovalRows())) return;
    if (!navigator.onLine) {
        showToast("Approval memerlukan koneksi ke server.", "warning");
        return;
    }
    window.pendingInspectionApprovalAction = { action: action, batch: batch, ids: ids };
    document.getElementById("inspectionApprovalActionTitle").textContent =
        (action === "APPROVE" ? "Approve" : "Void") + (batch ? " " + ids.length + " inspeksi" : " inspeksi");
    document.getElementById("inspectionApprovalActionDescription").textContent = batch
        ? "Satu " + (action === "VOID" ? "alasan void" : "remark approval") + " akan diterapkan ke semua inspeksi terpilih."
        : (action === "VOID" ? "Masukkan alasan void. Alasan ini akan ditampilkan kepada teknisi." : "Remark approval bersifat opsional.");
    document.getElementById("lblInspectionApprovalActionRemark").textContent = action === "VOID" ? "Reason Void (wajib)" : "Remark Supervisor (opsional)";
    const input = document.getElementById("txtInspectionApprovalActionRemark");
    input.value = (batch || action === "VOID") ? "" : (document.getElementById("txtInspectionApprovalRemark").value || "");
    input.maxLength = action === "VOID" ? 255 : 500;
    document.getElementById("inspectionApprovalActionError").classList.add("d-none");
    document.getElementById("btnConfirmInspectionApprovalAction").textContent = action === "APPROVE" ? "Approve" : "Void";
    document.getElementById("btnConfirmInspectionApprovalAction").className = "btn " + (action === "APPROVE" ? "btn-success" : "btn-danger");
    bootstrap.Modal.getOrCreateInstance(document.getElementById("inspectionApprovalActionModal")).show();
}

async function confirmInspectionApprovalAction() {
    const pending = window.pendingInspectionApprovalAction;
    if (!pending) return;
    const remark = document.getElementById("txtInspectionApprovalActionRemark").value.trim();
    const error = document.getElementById("inspectionApprovalActionError");
    if (pending.action === "VOID" && !remark) {
        error.textContent = "Reason Void wajib diisi.";
        error.classList.remove("d-none");
        return;
    }
    if (remark.length > (pending.action === "VOID" ? 255 : 500)) {
        error.textContent = "Teks terlalu panjang.";
        error.classList.remove("d-none");
        return;
    }
    const confirmed = await showConfirmation({
        title: pending.action === "APPROVE" ? "Konfirmasi Approve" : "Konfirmasi Void",
        message: (pending.action === "APPROVE" ? "Approve " : "Void ") + pending.ids.length + " inspeksi?",
        yesText: pending.action === "APPROVE" ? "Approve" : "Void"
    });
    if (!confirmed) return;
    bootstrap.Modal.getOrCreateInstance(document.getElementById("inspectionApprovalActionModal")).hide();
    if (!pending.batch && pending.action === "APPROVE") {
        document.getElementById("txtInspectionApprovalRemark").value = remark;
        await processInspectionApproval("APPROVE");
        return;
    }
    await executeInspectionApprovalAction(pending.ids, pending.action, remark);
}

function getLightningApprovalEmailToken(inspectionId) {
    var search = (window.location && window.location.search) || "";
    var tokenMatch = /(?:^|[?&])approvalToken=([^&]*)/i.exec(search);
    var idMatch = /(?:^|[?&])inspectionId=([^&]*)/i.exec(search);
    if (!tokenMatch || !idMatch) return "";
    var linkedId = parseInt(decodeURIComponent(idMatch[1]), 10);
    if (!linkedId || linkedId !== Number(inspectionId)) return "";
    return decodeURIComponent(tokenMatch[1] || "");
}

async function executeInspectionApprovalAction(ids, action, remark) {
    const isSingleVoid = action === "VOID" && ids.length === 1 &&
        selectedInspectionApproval && Number(selectedInspectionApproval.InspectionID) === Number(ids[0]);
    try {
        const lightningIds = ids.filter(id => {
            const row = inspectionApprovalRows.find(item => Number(item.InspectionID) === Number(id));
            return row && String(row.InspectionMode || "").toUpperCase() === "LIGHTNING";
        });
        const standardIds = ids.filter(id => lightningIds.indexOf(id) < 0);
        const lightningResults = [];
        for (const id of lightningIds) {
            lightningResults.push(await inspectionApprovalPost("ProcessLightningInspectionApproval", {
                inspectionId: Number(id), action: action,
                employeeId: inspectionLogin.employeeid, companyId: inspectionCompanyID,
                locationId: inspectionLocationID, remark: remark,
                approvalToken: getLightningApprovalEmailToken(id)
            }));
        }
        let standardResult = null;
        if (standardIds.length) {
            standardResult = await inspectionApprovalPost("ProcessInspectionApprovalBatch", {
                inspectionIds: standardIds,
                action: action,
                employeeId: inspectionLogin.employeeid,
                companyId: inspectionCompanyID,
                locationId: inspectionLocationID,
                remark: remark
            });
        }
        if (isSingleVoid) showInspectionApprovalQueueView();
        await loadInspectionApprovalQueue();
        const processedCount = (standardResult && standardResult.count) || (standardIds.length + lightningResults.length);
        const lightningStatus = lightningResults.length
            ? " Lightning: " + lightningResults.map(item => item.workflowStatus || action).join(", ") + "."
            : "";
        const emailPending = lightningResults.some(item => item.emailDispatch && (item.emailDispatch.configured !== false && (Number(item.emailDispatch.failed || 0) > 0 || Number(item.emailDispatch.pending || 0) > 0))) ||
            !!(standardResult && Array.isArray(standardResult.results) &&
                standardResult.results.some(item => item.emailDispatch && (item.emailDispatch.configured !== false && (Number(item.emailDispatch.failed || 0) > 0 || Number(item.emailDispatch.pending || 0) > 0))));
        showToast(processedCount + " inspeksi berhasil diproses." + lightningStatus, emailPending ? "warning" : "success");
        if (emailPending) showToast("Approval tersimpan, tetapi ada email yang belum terkirim. Periksa email pengirim di M_HRD_Employee dan konfigurasi SMTP aplikasi; email akan dicoba kembali dari outbox.", "warning");
    } catch (err) {
        showToast(err.message || "Gagal memproses approval.", "warning");
        await loadInspectionApprovalQueue();
    }
}
async function processBatchInspectionApproval(action) {
    openInspectionApprovalAction(action, true);
}

function renderInspectionApprovalBatchPoints(template, points, photos) {
    window._inspectionApprovalBatchData = {
        template: template,
        points: Array.isArray(points) ? points : [],
        photos: Array.isArray(photos) ? photos : []
    };
    if (!points || !points.length)
        return '<div class="alert alert-warning small">Batch ini belum memiliki Inspection Point transaction.</div>';
    return "";
}

window.renderInspectionApprovalSelectedPoint = function (pointId) {
    const data = window._inspectionApprovalBatchData;
    const host = document.getElementById("inspectionApprovalSelectedPointHost");
    if (!data || !host) return;
    const point = data.points.find(item =>
        String(item.InspectionPointTransactionID) === String(pointId));
    if (!point) return;

    const id = String(point.InspectionPointTransactionID || "");
    const status = String(point.Status || "PENDING").toUpperCase();
    const pointItems = Array.isArray(point.Items) ? point.Items : [];
    const conditionRequired = isInspectionFlagEnabled(point && point.IsNormalAbnormalRequired, false);
    const isAbnormal = conditionRequired && (status === "ABNORMAL" ||
        String(point.AbnormalRemark || "").trim() !== "" ||
        pointItems.some(item => item.IsAnomali === true || item.IsAnomali === 1 || String(item.IsAnomali || "") === "1"));
    const statusLabel = conditionRequired
        ? (isAbnormal ? "ABNORMAL" : (status === "DONE" ? "NORMAL" : status))
        : (status === "DONE" ? "SELESAI" : status);
    const statusClass = isAbnormal ? "text-bg-danger" :
        status === "DONE" ? "text-bg-success" :
        status === "INCOMPLETE" ? "text-bg-warning" : "text-bg-secondary";
    const pointPhotos = data.photos.filter(photo => String(photo.PointID || "") === id);
    const photoStage = type => {
        const rows = pointPhotos.filter(photo => String(photo.Type || "").toUpperCase() === type);
        return '<div class="inspection-photo-panel mb-3"><div class="fw-bold mb-2"><i class="bi bi-camera-fill me-2"></i>FIELD DOCUMENTATION ' + type + '</div>' +
            (rows.length ? '<div class="d-flex flex-wrap gap-2">' + rows.map(photo =>
                '<div class="inspection-photo-item"><img src="' + escInspection(photo.Data || "") + '" alt="Inspection ' + type + '" loading="lazy"></div>'
            ).join("") + '</div>' : '<div class="inspection-muted">Foto ' + type + ' belum tersedia.</div>') + '</div>';
    };
    const checklist = data.template && Array.isArray(data.template.sections) && data.template.sections.length
        ? renderInspectionSections(data.template, point.Items || [], true, "inspectionApprovalPoint_" + id.replace(/[^a-zA-Z0-9_-]/g, "_"))
        : '<div class="alert alert-danger small">Template version tidak tersedia.</div>';
    host.innerHTML = '<div class="card border mb-3" id="inspectionApprovalPoint_' + escInspection(id) + '">' +
        '<div class="card-header d-flex align-items-center justify-content-between gap-2 flex-wrap">' +
            '<div><div class="fw-bold">' + escInspection(point.PointCode || "Inspection Point") + ' · ' + escInspection(point.PointName || "") + '</div>' +
            '<small class="text-muted">' + escInspection(point.PointObjectType || "GENERAL") + ' · ' + escInspection(point.InspectionDateTime || "") + '</small></div>' +
            '<span class="badge ' + statusClass + '">' + escInspection(statusLabel) + '</span>' +
        '</div><div class="card-body">' +
            (isAbnormal ? '<div class="alert alert-danger py-2 small"><strong>ABNORMAL REMARK</strong><div class="mt-1" style="white-space:pre-wrap">' + escInspection(point.AbnormalRemark) + '</div></div>' : '') +
            photoStage("BEFORE") + checklist + photoStage("AFTER") + '</div></div>';
};

async function renderInspectionApprovalBatchMap(maps, points, schedules, workflowHeader) {
    const host = document.getElementById("inspectionApprovalBatchMap");
    if (!host) return;
    maps = Array.isArray(maps) ? maps : [];
    points = Array.isArray(points) ? points : [];
    schedules = Array.isArray(schedules) ? schedules : [];
    const isLightning = schedules.length > 0;
    let activeScheduleTime = isLightning ? String(schedules[0].ScheduleTime || schedules[0]) : "";
    const visiblePoints = function () {
        return isLightning ? points.filter(point => String(point.ScheduleTime || "") === activeScheduleTime) : points;
    };
    const workflowData = workflowHeader && typeof workflowHeader === "object" ? workflowHeader : {};
    const workflow = String((workflowData.WorkflowStatus || workflowHeader) || "CHECKED").toUpperCase();
    const workflowCards = isLightning ? (function () {
        const stages = [
            { status: "CHECKED", label: "CHECKED BY", description: "Technician submitted", by: workflowData.SubmittedByName || workflowData.SubmittedBy, date: workflowData.SubmittedDate },
            { status: "VERIFIED", label: "VERIFIED BY", description: "SPV approved", by: workflowData.ApprovedByName || workflowData.ApprovedBy, date: workflowData.ApprovedDate },
            { status: "ACKNOWLEDGE 1", label: "ACKNOWLEDGE 1", description: "Chief Engineering approved", by: workflowData.Approved1ByName || workflowData.Approved1By, date: workflowData.Approved1Date },
            { status: "ACKNOWLEDGE 2", label: "ACKNOWLEDGE 2", description: "Chief Security approved", by: workflowData.Approved2ByName || workflowData.Approved2By, date: workflowData.Approved2Date }
        ];
        const completed = workflow === "ACKNOWLEDGE 2" ? 4 : workflow === "ACKNOWLEDGE 1" ? 3 : workflow === "VERIFIED" ? 2 : workflow === "CHECKED" ? 1 : 0;
        return '<div class="row g-2 mb-3">' + stages.map((stage, index) => {
            const done = index < completed;
            const bgClass = done ? "bg-" + (index === 0 ? "primary" : index === 1 ? "warning" : "success") + "-subtle" : "bg-body-secondary";
            const borderClass = done ? "border-" + (index === 0 ? "primary" : index === 1 ? "warning" : "success") : "border-secondary-subtle";
            const textClass = done ? "text-" + (index === 1 ? "warning" : index === 2 ? "success" : "primary") + "-emphasis" : "text-secondary";
            const returned = workflow === "VOID";
            return '<div class="col-12 col-md-4"><div class="border rounded-3 p-2 h-100 ' +
                bgClass + ' ' + borderClass + '">' +
                '<div class="small fw-bold ' + textClass + '">' + escInspection(stage.label) + '</div>' +
                '<div class="small ' + textClass + '">' + escInspection(returned ? "Returned for correction" :
                    done ? ("Completed" + (stage.by ? " · " + escInspection(stage.by) : "") +
                    (stage.date ? " · " + escInspection(formatInspectionDateDMY(stage.date) + " " + formatInspectionClockTime(stage.date)) : "")) :
                    current ? "Waiting for this stage" : stage.description) + '</div></div></div>';
        }).join("") + '</div>';
    })() : "";
    if (!points.length) { host.innerHTML = ""; return; }

    const hasAnyFloorPlan = maps.some(map => !!String(map.MapUrl || "").trim());
    host.innerHTML = '<div class="border rounded-3 p-3 mb-3">' +
        workflowCards +
        (isLightning ? '<div id="inspectionApprovalLightningSchedules" class="inspection-lightning-schedule-tabs nav nav-tabs mb-3" role="tablist" aria-label="Jadwal Lightning">' +
            schedules.map(item => {
                const time = String(item.ScheduleTime || item);
                const count = points.filter(point => String(point.ScheduleTime || "") === time &&
                    ["DONE", "ABNORMAL"].indexOf(String(point.Status || "").toUpperCase()) >= 0).length;
                return '<button type="button" class="nav-link' + (time === activeScheduleTime ? ' active' : '') +
                    '" data-approval-schedule="' + escInspection(time) + '">' + escInspection(time) +
                    ' <span class="small opacity-75">' + count + '/' +
                    points.filter(point => String(point.ScheduleTime || "") === time).length + '</span></button>';
            }).join("") + '</div>' : '') +
        '<div class="d-flex align-items-center justify-content-between gap-2 mb-3 flex-wrap">' +
            '<div><div class="fw-bold"><i class="bi bi-clipboard2-check me-2"></i>' +
                (isLightning ? 'LIGHTNING DAILY REVIEW' : 'BATCH INSPECTION REVIEW') +
                '</div><small class="text-muted">' + (isLightning ? schedules.length + ' schedule(s)' : points.length + ' inspected point(s)') + '</small></div>' +
            (maps.length > 1 ? '<select id="inspectionApprovalMapSelect" class="form-select form-select-sm" style="max-width:260px">' +
                maps.slice().sort((a, b) =>
                    Number(a.GroupSequence || 0) - Number(b.GroupSequence || 0) ||
                    Number(a.MapGroupID || 0) - Number(b.MapGroupID || 0) ||
                    String(a.MapCode || "").localeCompare(String(b.MapCode || "")))
                    .map(map => '<option value="' + escInspection(map.MapID) + '">' +
                        escInspection((map.GroupName ? map.GroupName + " / " : "") + map.MapCode + " - " + map.MapName) +
                        '</option>').join("") +
             '</select>' : '') +
        '</div>' +
        '<div class="row g-3 align-items-start">' +
            '<div class="col-12 col-lg-7">' +
                (hasAnyFloorPlan
                    ? '<div id="inspectionApprovalMapStage" class="inspection-map-pdf-stage"><canvas id="inspectionApprovalMapCanvas"></canvas><div id="inspectionApprovalMapPoints" class="inspection-map-points"></div></div>'
                    : '<div class="alert alert-light small">Batch ini tidak menggunakan file denah. Seluruh hasil diperiksa melalui daftar Inspection Point.</div>') +
            '</div>' +
            '<div class="col-12 col-lg-5">' +
                '<div id="inspectionApprovalPointCounters"></div>' +
                '<div class="d-flex flex-wrap gap-2 align-items-center mb-2"><div class="btn-group btn-group-sm flex-wrap" id="inspectionApprovalPointFilters" role="group" aria-label="Filter status point">' +
                    '<button type="button" class="btn btn-outline-secondary active" data-approval-filter="ALL" aria-pressed="true">Semua</button>' +
                    (points.some(point => isInspectionFlagEnabled(point.IsNormalAbnormalRequired, false)) ? '<button type="button" class="btn btn-outline-danger" data-approval-filter="ABNORMAL" aria-pressed="false">Abnormal</button><button type="button" class="btn btn-outline-success" data-approval-filter="NORMAL" aria-pressed="false">Normal</button>' : '') +
                    (points.some(point => !isInspectionFlagEnabled(point.IsNormalAbnormalRequired, false)) ? '<button type="button" class="btn btn-outline-primary" data-approval-filter="DONE" aria-pressed="false">Selesai</button>' : '') +
                    '<button type="button" class="btn btn-outline-warning" data-approval-filter="INCOMPLETE" aria-pressed="false">Belum lengkap</button>' +
                '</div><div class="inspection-point-list-tools flex-grow-1"><input type="search" id="inspectionApprovalPointSearch" class="form-control form-control-sm" placeholder="Cari Point Code / Name..."></div></div>' +
                '<div id="inspectionApprovalPointList" class="border rounded overflow-hidden"></div>' +
                '<div class="mt-3" id="inspectionApprovalSelectedPointHost"></div>' +
            '</div>' +
        '</div>' +
    '</div>';

    const listHost = document.getElementById("inspectionApprovalPointList");
    const photos = window._inspectionApprovalBatchData && Array.isArray(window._inspectionApprovalBatchData.photos)
        ? window._inspectionApprovalBatchData.photos : [];
    let approvalPage = 1;
    let approvalFilter = "ALL";
    let selectedPointId = visiblePoints().length ? String(visiblePoints()[0].InspectionPointTransactionID) : "";
    const approvalPageSize = 30;

    const pointState = function (point) {
        const status = String(point.Status || "PENDING").toUpperCase();
        const conditionRequired = isInspectionFlagEnabled(point && point.IsNormalAbnormalRequired, false);
        const items = Array.isArray(point.Items) ? point.Items : [];
        const abnormalItems = items.filter(item =>
            item.IsAnomali === true || item.IsAnomali === 1 || String(item.IsAnomali || "") === "1");
        if (!conditionRequired) {
            return { status: status === "DONE" ? "DONE" : "INCOMPLETE", abnormalItems: [] };
        }
        const abnormal = status === "ABNORMAL" || !!String(point.AbnormalRemark || "").trim() || abnormalItems.length > 0;
        const incomplete = !abnormal && status !== "DONE";
        return { status: abnormal ? "ABNORMAL" : (incomplete ? "INCOMPLETE" : "NORMAL"), abnormalItems: abnormalItems };
    };
    const getPointPhotoCount = function (point) {
        const id = String(point.InspectionPointTransactionID || "");
        return photos.filter(photo => String(photo.PointID || "") === id).length;
    };
    const getPointSummary = function (point, state) {
        if (String(point.AbnormalRemark || "").trim()) return String(point.AbnormalRemark).trim();
        const sourceItems = state.abnormalItems.length ? state.abnormalItems : (Array.isArray(point.Items) ? point.Items : []);
        const summaries = sourceItems.map(item => {
            const label = String(item.ItemLabel || item.Label || "Checklist");
            const values = item.Values && typeof item.Values === "object"
                ? Object.keys(item.Values).map(key => String(item.Values[key] == null ? "" : item.Values[key])).filter(value => value.trim() !== "")
                : [];
            const value = String(item.Value == null ? "" : item.Value).trim();
            const displayValue = value || values.join(" / ");
            return displayValue ? label + ": " + displayValue : (state.abnormalItems.length ? label : "");
        }).filter(value => value !== "");
        if (summaries.length) return summaries.slice(0, 2).join(" · ") + (summaries.length > 2 ? " +" + (summaries.length - 2) : "");
        if (state.status === "INCOMPLETE") return "Perlu pemeriksaan / data belum lengkap";
        return "Tidak ada temuan abnormal";
    };

    const renderList = function () {
        const searchInput = document.getElementById("inspectionApprovalPointSearch");
        const q = String(searchInput ? searchInput.value : "").trim().toLowerCase();
        const schedulePoints = visiblePoints();
        const filtered = schedulePoints.filter(point => {
            const state = pointState(point);
            const matchesFilter = approvalFilter === "ALL" || state.status === approvalFilter;
            const matchesSearch = !q ||
                String(point.PointCode || "").toLowerCase().indexOf(q) >= 0 ||
                String(point.PointName || "").toLowerCase().indexOf(q) >= 0;
            return matchesFilter && matchesSearch;
        });
        const pageCount = Math.max(1, Math.ceil(filtered.length / approvalPageSize));
        approvalPage = Math.min(Math.max(1, approvalPage), pageCount);
        const startIndex = (approvalPage - 1) * approvalPageSize;
        const rows = filtered.slice(startIndex, startIndex + approvalPageSize);
        const counters = { ALL: schedulePoints.length, ABNORMAL: 0, NORMAL: 0, DONE: 0, INCOMPLETE: 0 };
        schedulePoints.forEach(point => counters[pointState(point).status]++);

        const counterHost = document.getElementById("inspectionApprovalPointCounters");
        if (counterHost) {
            const hasNormalAbnormal = schedulePoints.some(point => isInspectionFlagEnabled(point.IsNormalAbnormalRequired, false));
            const hasDoneOnly = schedulePoints.some(point => !isInspectionFlagEnabled(point.IsNormalAbnormalRequired, false));
            counterHost.innerHTML =
                '<div class="row g-2 mb-2">' +
                '<div class="col-6 col-md-3"><div class="border rounded p-2 h-100"><small class="text-muted d-block">TOTAL POINT</small><strong>' + counters.ALL + '</strong></div></div>' +
                (hasNormalAbnormal ? '<div class="col-6 col-md-3"><div class="border rounded p-2 h-100"><small class="text-muted d-block">NORMAL</small><strong class="text-success">' + counters.NORMAL + '</strong></div></div>' +
                    '<div class="col-6 col-md-3"><div class="border rounded p-2 h-100"><small class="text-muted d-block">ABNORMAL</small><strong class="text-danger">' + counters.ABNORMAL + '</strong></div></div>' : '') +
                (hasDoneOnly ? '<div class="col-6 col-md-3"><div class="border rounded p-2 h-100"><small class="text-muted d-block">SELESAI</small><strong class="text-primary">' + counters.DONE + '</strong></div></div>' : '') +
                '<div class="col-6 col-md-3"><div class="border rounded p-2 h-100"><small class="text-muted d-block">INCOMPLETE</small><strong class="text-warning">' + counters.INCOMPLETE + '</strong></div></div></div>';
        }

        const rowsHtml = rows.map(point => {
            const id = String(point.InspectionPointTransactionID || "");
            const state = pointState(point);
            const photoCount = getPointPhotoCount(point);
            const summary = getPointSummary(point, state);
            const badgeClass = state.status === "ABNORMAL" ? "text-bg-danger" :
                state.status === "NORMAL" ? "text-bg-success" : "text-bg-warning";
            return '<tr class="' + (id === selectedPointId ? 'table-active' : '') + '">' +
                '<td style="width:18%;overflow-wrap:anywhere"><button type="button" class="btn btn-link btn-sm p-0 fw-semibold text-decoration-none text-start" data-approval-point-target="' + escInspection(id) + '">' + escInspection(point.PointCode || "-") + '</button></td>' +
                '<td style="width:22%;overflow-wrap:anywhere"><button type="button" class="btn btn-link btn-sm p-0 text-start text-decoration-none text-body" data-approval-point-target="' + escInspection(id) + '">' + escInspection(point.PointName || "-") + '</button></td>' +
                '<td style="width:15%;overflow-wrap:anywhere"><span class="badge ' + badgeClass + '">' + state.status + '</span></td>' +
                '<td class="small text-muted" style="width:35%;overflow-wrap:anywhere">' + escInspection(summary) + '</td>' +
                '<td class="small text-center" style="width:10%">' + (photoCount ? '<i class="bi bi-camera-fill text-primary"></i> ' + photoCount : '<span class="text-muted">—</span>') + '</td>' +
                '</tr>';
        }).join("");

        listHost.innerHTML =
            '<div class="table-responsive"><table class="table table-sm table-hover align-middle mb-0" style="width:100%;table-layout:fixed"><thead><tr>' +
            '<th style="width:18%">Point Code</th><th style="width:22%">Inspection Point</th><th style="width:15%">Status</th><th style="width:35%">Ringkasan</th><th style="width:10%">Foto</th>' +
            '</tr></thead><tbody>' + (rowsHtml || '<tr><td colspan="5" class="text-center text-muted py-3">Tidak ada point yang cocok.</td></tr>') +
            '</tbody></table></div>' +
            '<div class="d-flex align-items-center justify-content-between small text-muted mt-2 px-2 pb-2">' +
            '<span>' + (filtered.length ? (startIndex + 1) + '-' + Math.min(startIndex + approvalPageSize, filtered.length) : 0) + ' dari ' + filtered.length + ' point</span>' +
            '<div class="btn-group btn-group-sm"><button type="button" id="inspectionApprovalPointPrev" class="btn btn-outline-secondary" ' + (approvalPage <= 1 ? 'disabled' : '') + '><i class="bi bi-chevron-left"></i></button>' +
            '<span class="btn btn-outline-secondary disabled">' + approvalPage + ' / ' + pageCount + '</span>' +
            '<button type="button" id="inspectionApprovalPointNext" class="btn btn-outline-secondary" ' + (approvalPage >= pageCount ? 'disabled' : '') + '><i class="bi bi-chevron-right"></i></button></div></div>';

        listHost.querySelectorAll("[data-approval-point-target]").forEach(button => button.addEventListener("click", function () {
            selectedPointId = String(this.getAttribute("data-approval-point-target") || "");
            if (typeof window.renderInspectionApprovalSelectedPoint === "function")
                window.renderInspectionApprovalSelectedPoint(selectedPointId);
            renderList();
        }));
        const prev = document.getElementById("inspectionApprovalPointPrev");
        const next = document.getElementById("inspectionApprovalPointNext");
        if (prev) prev.addEventListener("click", function () { approvalPage--; renderList(); });
        if (next) next.addEventListener("click", function () { approvalPage++; renderList(); });
    };

    const search = document.getElementById("inspectionApprovalPointSearch");
    if (search) search.addEventListener("input", function () { approvalPage = 1; renderList(); });
    const filterHost = document.getElementById("inspectionApprovalPointFilters");
    if (filterHost) filterHost.querySelectorAll("[data-approval-filter]").forEach(button =>
        button.addEventListener("click", function () {
            approvalFilter = this.getAttribute("data-approval-filter") || "ALL";
            approvalPage = 1;
            filterHost.querySelectorAll("[data-approval-filter]").forEach(item => {
                item.classList.toggle("active", item === this);
                item.setAttribute("aria-pressed", item === this ? "true" : "false");
            });
            renderList();
        }));

    renderList();
    if (typeof window.renderInspectionApprovalSelectedPoint === "function")
        window.renderInspectionApprovalSelectedPoint(selectedPointId);

    const select = document.getElementById("inspectionApprovalMapSelect");
    const canRenderMap = maps.length > 0 && hasAnyFloorPlan;
    const renderMap = async function (map) {
        const canvas = document.getElementById("inspectionApprovalMapCanvas");
        const overlay = document.getElementById("inspectionApprovalMapPoints");
        const stage = document.getElementById("inspectionApprovalMapStage");
        if (!canvas || !overlay || !stage || !map) return;
        let mapMessage = stage.querySelector(".inspection-approval-map-message");
        if (!String(map.MapUrl || "").trim()) {
            canvas.style.display = "none";
            overlay.innerHTML = "";
            if (!mapMessage) {
                mapMessage = document.createElement("div");
                mapMessage.className = "inspection-approval-map-message alert alert-light small mb-0";
                stage.appendChild(mapMessage);
            }
            mapMessage.textContent = "Denah untuk " + String(map.MapCode || "Map") +
                " tidak tersedia. Periksa hasil melalui daftar Inspection Point.";
            return;
        }
        if (mapMessage) mapMessage.remove();
        canvas.style.display = "block";
        try {
            const response = await fetch(map.MapUrl, { credentials: "same-origin" });
            if (!response.ok) throw new Error("HTTP " + response.status);
            const blob = await response.blob();
            const mime = String(blob.type || "").toLowerCase();
            const path = String(map.MapUrl).split("?")[0].toLowerCase();
            const isJpeg = mime.indexOf("image/jpeg") === 0 || /\.(jpg|jpeg)$/.test(path);
            let width, height;
            if (isJpeg) {
                let image = stage.querySelector("img.inspection-map-image");
                if (!image) {
                    image = document.createElement("img");
                    image.className = "inspection-map-image";
                    image.alt = "Inspection floor plan";
                    image.draggable = false;
                    stage.insertBefore(image, overlay);
                }
                canvas.style.display = "none";
                image.style.display = "block";
                const objectUrl = URL.createObjectURL(blob);
                if (image.dataset.objectUrl) URL.revokeObjectURL(image.dataset.objectUrl);
                image.dataset.objectUrl = objectUrl;
                image.src = objectUrl;
                await new Promise((resolve, reject) => {
                    if (image.complete && image.naturalWidth) return resolve();
                    image.onload = resolve;
                    image.onerror = () => reject(new Error("Gambar JPG/JPEG tidak dapat dibuka."));
                });
                width = image.naturalWidth;
                height = image.naturalHeight;
                image.style.width = Math.min(1100, Math.max(300, host.clientWidth - 32)) + "px";
                image.style.height = "auto";
                stage.style.width = image.style.width;
            } else {
                if (!window.pdfjsLib) throw new Error("PDF.js belum termuat.");
                const pdf = await window.pdfjsLib.getDocument({ data: new Uint8Array(await blob.arrayBuffer()) }).promise;
                const page = await pdf.getPage(1);
                const base = page.getViewport({ scale: 1 });
                const targetWidth = Math.max(300, Math.min(1100, host.clientWidth - 32));
                const ratio = Math.min(window.devicePixelRatio || 1, 1.5);
                const viewport = page.getViewport({ scale: (targetWidth / base.width) * ratio });
                canvas.width = Math.floor(viewport.width);
                canvas.height = Math.floor(viewport.height);
                canvas.style.width = Math.floor(viewport.width / ratio) + "px";
                canvas.style.height = Math.floor(viewport.height / ratio) + "px";
                canvas.style.display = "block";
                const oldImage = stage.querySelector("img.inspection-map-image");
                if (oldImage) oldImage.style.display = "none";
                stage.style.width = canvas.style.width;
                await page.render({ canvasContext: canvas.getContext("2d"), viewport: viewport }).promise;
                width = base.width;
                height = base.height;
            }
            stage.style.aspectRatio = width + " / " + height;
            const mapPoints = visiblePoints().filter(point =>
                Number(point.MapID) === Number(map.MapID) && point.MapX != null && point.MapY != null);
            const approvalShapeSvg = [];
            const pointButtons = mapPoints.map(point => {
                const x = Math.max(0, Math.min(100, Number(point.MapX) || 0));
                const y = Math.max(0, Math.min(100, Number(point.MapY) || 0));
                const shapeType = String(point.ShapeType || "CIRCLE").toUpperCase();
                let shape = {};
                try {
                    shape = typeof point.ShapeAttributes === "string"
                        ? JSON.parse(point.ShapeAttributes || "{}") : (point.ShapeAttributes || {});
                } catch (_) { shape = {}; }
                if (shapeType === "PATH" && String(point.SvgPathData || "").trim()) {
                    const renderMode = String(shape.renderMode || "").toUpperCase();
                    const isOrthogonal = renderMode === "ORTHOGONAL";
                    const strokeWidth = isOrthogonal ? 3.5 : Math.max(0.25, Math.min(10, Number(point.StrokeWidth) || 1.5));
                    approvalShapeSvg.push('<path d="' + escInspection(point.SvgPathData) +
                        '" fill="none"' +
                        '" stroke="#0d6efd" stroke-width="' + strokeWidth +
                        '" stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke"></path>');
                } else if (shapeType === "RECTANGLE") {
                    const width = Math.max(0.2, Math.min(100, Number(shape.width || shape.w || 3)));
                    const height = Math.max(0.2, Math.min(100, Number(shape.height || shape.h || 3)));
                    const left = Math.max(0, Math.min(100 - width, Number.isFinite(Number(shape.x)) ? Number(shape.x) : x - width / 2));
                    const top = Math.max(0, Math.min(100 - height, Number.isFinite(Number(shape.y)) ? Number(shape.y) : y - height / 2));
                    approvalShapeSvg.push('<rect x="' + left + '" y="' + top + '" width="' + width +
                        '" height="' + height + '" fill="rgba(13,110,253,.14)" stroke="#0d6efd" stroke-width="1.5" vector-effect="non-scaling-stroke"></rect>');
                }
                const conditionRequired = isInspectionFlagEnabled(point && point.IsNormalAbnormalRequired, false);
                const pointHasAbnormalItem = conditionRequired && Array.isArray(point.Items) && point.Items.some(item =>
                    item.IsAnomali === true || item.IsAnomali === 1 || String(item.IsAnomali || "") === "1");
                const visualStatus = conditionRequired && (
                    String(point.Status || "").toUpperCase() === "ABNORMAL" ||
                    String(point.AbnormalRemark || "").trim() || pointHasAbnormalItem)
                    ? "abnormal" : String(point.Status || "PENDING").toLowerCase();
                return '<button type="button" class="inspection-map-point ' + visualStatus +
                    '" style="left:' + x + '%;top:' + y + '%;z-index:1" data-approval-point-target="' +
                    escInspection(point.InspectionPointTransactionID) + '" title="' +
                    escInspection(point.PointCode + " - " + point.PointName) +
                    '"><span class="inspection-map-point-dot"></span><span class="inspection-map-point-label">' +
                    escInspection(point.PointCode) + '</span></button>';
            }).join("");
            overlay.innerHTML = '<svg class="inspection-approval-map-shapes" viewBox="0 0 100 100" preserveAspectRatio="none" ' +
                'style="position:absolute;inset:0;width:100%;height:100%;pointer-events:none" aria-hidden="true">' +
                approvalShapeSvg.join("") + '</svg>' + pointButtons;
            overlay.querySelectorAll("[data-approval-point-target]").forEach(button => button.addEventListener("click", function () {
                selectedPointId = String(this.dataset.approvalPointTarget || "");
                if (typeof window.renderInspectionApprovalSelectedPoint === "function")
                    window.renderInspectionApprovalSelectedPoint(selectedPointId);
                renderList();
            }));
        } catch (error) {
            console.warn("Approval BATCH map could not be rendered:", error);
            let errorMessage = stage.querySelector(".inspection-approval-map-message");
            if (!errorMessage) {
                errorMessage = document.createElement("div");
                errorMessage.className = "inspection-approval-map-message alert alert-warning small mb-0";
                stage.appendChild(errorMessage);
            }
            errorMessage.textContent = "Denah gagal dimuat. Daftar Inspection Point tetap dapat digunakan.";
        }
    };
    const selectedMap = () =>
        maps.find(map => Number(map.MapID) === Number(select ? select.value : maps[0].MapID)) || maps[0];
    if (select) select.addEventListener("change", function () { if (canRenderMap) renderMap(selectedMap()); });
    const scheduleHost = document.getElementById("inspectionApprovalLightningSchedules");
    if (scheduleHost) scheduleHost.querySelectorAll("[data-approval-schedule]").forEach(button =>
        button.addEventListener("click", function () {
            activeScheduleTime = String(this.getAttribute("data-approval-schedule") || "");
            selectedPointId = visiblePoints().length ? String(visiblePoints()[0].InspectionPointTransactionID) : "";
            approvalPage = 1;
            scheduleHost.querySelectorAll("[data-approval-schedule]").forEach(item =>
                item.classList.toggle("active", item === this));
            renderList();
            if (typeof window.renderInspectionApprovalSelectedPoint === "function")
                window.renderInspectionApprovalSelectedPoint(selectedPointId);
            if (canRenderMap) renderMap(selectedMap());
        }));
    if (canRenderMap) await renderMap(selectedMap());
}

async function loadInspectionApprovalDetail(inspectionId) {
    const checklistHost = document.getElementById("inspectionApprovalDetail");
    checklistHost.innerHTML = '<div class="text-muted">Memuat checklist...</div>';
    document.getElementById("inspectionApprovalParameters").innerHTML = "";
    document.getElementById("txtInspectionApprovalRemark").value = "";
    try {
        const result = await inspectionApprovalPost("GetInspectionApprovalDetail", {
            inspectionId: inspectionId, employeeId: inspectionLogin.employeeid
        });
        selectedInspectionApproval = result.header;
        const h = result.header || {};
        const isApproved = isInspectionApprovalApproved(h);
        const isVoided = isInspectionApprovalVoided(h);
        const isFinalized = isApproved || isVoided;
        const remarkPanel = document.getElementById("inspectionApprovalRemarkPanel");
        const initialRemark = h.ApprovalRemark || h.ReasonVoid || "";
        remarkPanel.innerHTML =
            '<div class="accordion-item border-success shadow-sm rounded-3 overflow-hidden" id="inspectionApprovalSupervisorRemarkCard">' +
                '<div class="accordion-header">' +
                    '<div class="accordion-button bg-success-subtle text-dark fw-bold">' +
                        '<i class="bi bi-person-check-fill fs-5 me-2 text-success"></i>' +
                        '<div class="d-flex flex-column"><span>SUPERVISOR REMARK</span>' +
                        '<small class="text-muted fw-normal">Catatan hasil review Supervisor.</small></div>' +
                    '</div>' +
                '</div>' +
                '<div class="accordion-body p-3">' +
                    '<div class="alert alert-success py-2 px-3 mb-3 small"><i class="bi bi-chat-left-text-fill me-1"></i>' +
                    'Tuliskan hasil pemeriksaan, alasan Approval / Void, atau catatan penting lainnya.</div>' +
                    '<textarea id="txtInspectionApprovalRemark" class="form-control" data-role="remarkspv" maxlength="500" rows="5" placeholder="Supervisor Remark...">' +
                    escInspection(initialRemark) +
                    '</textarea>' +
                    '<div class="d-flex justify-content-between align-items-center mt-2">' +
                        '<small class="text-muted"><i class="bi bi-info-circle me-1"></i>Maksimum 500 karakter.</small>' +
                        '<small class="char-counter text-muted" id="inspectionApprovalRemarkCounter">' + String(initialRemark.length) + ' / 500</small>' +
                    '</div>' +
                '</div>' +
            '</div>';
        const remarkInput = document.getElementById("txtInspectionApprovalRemark");
        remarkInput.readOnly = isFinalized;
        remarkInput.addEventListener("input", () => {
            const counter = document.getElementById("inspectionApprovalRemarkCounter");
            if (counter) counter.textContent = String(remarkInput.value.length) + " / 500";
        });
        remarkPanel.classList.toggle("d-none", isFinalized && !initialRemark);
        document.getElementById("btnApproveInspection").classList.toggle("d-none", isFinalized);
        document.getElementById("btnVoidInspection").classList.toggle("d-none", isFinalized);
        const items = result.items || [];
        const photos = result.photos || [];
        const batchPoints = result.points || [];
        const batchMaps = result.maps || [];
        const isBatchApproval = isInspectionMapMode(h.InspectionMode);
        const approvalTabButton = document.getElementById(isBatchApproval
            ? "inspectionApprovalChecklistTab" : "inspectionApprovalParamTab");
        if (approvalTabButton && window.bootstrap && bootstrap.Tab)
            bootstrap.Tab.getOrCreateInstance(approvalTabButton).show();
        window.currentInspectionApprovalPhotos = photos;
        const start = formatInspectionClock(h.StartDateTime);
        const end = formatInspectionClock(h.EndDateTime);
        const scheduleSummary = (result.schedules || []).map(item => String(item.ScheduleTime || item)).join(", ");
        const scheduledLabel = String(h.InspectionMode || "").toUpperCase() === "LIGHTNING"
            ? (scheduleSummary || h.ScheduledTime || "") : (h.ScheduledTime || "");
        document.getElementById("inspectionApprovalDetailSubtitle").textContent =
            (h.InspectionNo || ("Inspection #" + h.InspectionID)) + " • " +
            formatInspectionDateDMY(h.InspectionDate) +
            (scheduledLabel ? " • " + scheduledLabel : "") +
            " • " + start + " – " + end;
        const gpsLatitude = Number(h.GPSLatitude);
        const gpsLongitude = Number(h.GPSLongitude);
        const hasGps = String(h.GPSLatitude == null ? "" : h.GPSLatitude).trim() !== "" &&
            String(h.GPSLongitude == null ? "" : h.GPSLongitude).trim() !== "" &&
            Number.isFinite(gpsLatitude) && Number.isFinite(gpsLongitude) && Math.abs(gpsLatitude) <= 90 && Math.abs(gpsLongitude) <= 180;
        const gpsQuery = hasGps ? gpsLatitude.toFixed(7) + "," + gpsLongitude.toFixed(7) : "";
        const gpsMapHtml = hasGps && navigator.onLine
            ? '<div class="mt-2"><iframe title="Inspection GPS location" loading="lazy" referrerpolicy="no-referrer-when-downgrade" style="width:100%;height:190px;border:0;border-radius:.5rem" src="https://maps.google.com/maps?q=' + encodeURIComponent(gpsQuery) + '&z=16&output=embed"></iframe></div>'
            : (hasGps ? '<div class="small text-muted mt-2">Peta disembunyikan karena perangkat sedang offline.</div>' : '<div class="small text-muted mt-2">Koordinat GPS tidak tersedia.</div>');
        const gpsCardHtml = '<div class="border rounded p-3 mt-3"><div class="fw-semibold mb-2"><i class="bi bi-geo-alt me-1"></i>GPS Capture</div>' +
            '<div><strong>Latitude / Longitude:</strong> ' + (hasGps ? escInspection(gpsQuery) : "-") + '</div>' +
            '<div><strong>Accuracy:</strong> ' + (h.GPSAccuracy != null ? escInspection(h.GPSAccuracy + " m") : "-") + '</div>' +
            '<div><strong>Captured:</strong> ' + (h.GPSCapturedAt ? escInspection(formatInspectionDateDMY(h.GPSCapturedAt) + " " + formatInspectionClock(h.GPSCapturedAt)) : "-") + '</div>' +
            (hasGps && navigator.onLine ? '<a class="btn btn-sm btn-outline-primary mt-2" href="https://www.google.com/maps/search/?api=1&query=' + encodeURIComponent(gpsQuery) + '" target="_blank" rel="noopener">Buka di Google Maps</a>' : '') +
            gpsMapHtml + '</div>';
        document.getElementById("inspectionApprovalParameters").innerHTML =
            '<div class="row g-3">' +
            '<div class="col-12 col-md-6"><div class="border rounded p-3 h-100"><div class="fw-semibold mb-2">Inspection Parameters</div>' +
            '<div><strong>Transaction No.:</strong> ' + escInspection(h.InspectionNo || "-") + '</div>' +
            '<div><strong>Inspection Type:</strong> ' + escInspection(h.InspectionTypeName || "-") + '</div>' +
            '<div><strong>Type Detail:</strong> ' + escInspection(h.InspectionTypeDetailName || "-") + '</div>' +
            (h.TenantID && h.SuiteNo ? '<div><strong>Tenant / Suite:</strong> ' + escInspection(formatInspectionTenantLabel(h.TenantID, h.TenantName)) + ' / ' + escInspection(h.SuiteNo) + '</div>' : '') +
            '<div><strong>Date:</strong> ' + escInspection(formatInspectionDateDMY(h.InspectionDate) || "-") + '</div>' +
            (String(scheduledLabel || "").trim() ? '<div><strong>Scheduled:</strong> ' + escInspection(scheduledLabel) + '</div>' : '') +
            '<div><strong>Start – End:</strong> ' + escInspection(start) + ' – ' + escInspection(end) + '</div>' +
            '<div><strong>Technician:</strong> ' + escInspection(formatInspectionEmployeeLabel(h.TechnicianName || h.OwnerEmployeeName, h.OwnerEmployeeID)) + '</div>' +
            '<div><strong>Section:</strong> ' + escInspection(h.SectionID || "-") + '</div></div></div>' +
            '<div class="col-12 col-md-6"><div class="border rounded p-3 h-100"><div class="fw-semibold mb-2">Inspection Template</div>' +
            '<div><strong>Template:</strong> ' + escInspection(h.TemplateNo || "-") + ' / v' + escInspection(h.TemplateVersion || "-") + '</div>' +
            '</div></div></div>' + gpsCardHtml;
        const renderApprovalPhotoStage = (type, pointId) => {
            const stagePhotos = photos.filter(photo =>
                String(photo.Type || "").toUpperCase() === type &&
                (pointId == null ? !String(photo.PointID || "") : String(photo.PointID || "") === String(pointId)));
            if (!stagePhotos.length) return '<div class="inspection-muted mb-3">Foto ' + type + ' belum tersedia.</div>';
            return '<div class="inspection-photo-panel mb-3"><div class="fw-bold mb-2"><i class="bi bi-camera-fill me-2"></i>FIELD DOCUMENTATION ' + type + '</div><div class="d-flex flex-wrap gap-2">' +
                stagePhotos.map((photo, index) => '<button type="button" class="inspection-photo-item inspection-approval-photo-item" data-approval-photo-type="' + type + '" data-approval-photo-index="' + index + '" aria-label="Preview foto ' + type + ' ' + (index + 1) + '"><img src="' +
                    escInspection(photo.Data || "") + '" alt="Inspection ' + type + '" loading="lazy"></button>').join("") +
                '</div></div>';
        };
        const beforePhotoHtml = renderApprovalPhotoStage("BEFORE");
        const afterPhotoHtml = renderApprovalPhotoStage("AFTER");
        // SPV approval is online: prefer the exact server-side snapshot for this inspection's IDTemplate + IDVersion.
        // IndexedDB is only a fallback for older server responses; approval must never use a flat text-only renderer.
        const cachedTemplateCandidates = inspectionTemplates.filter(x =>
            Number(x.IDTemplate) === Number(h.IDTemplate) &&
            Array.isArray(x.sections) && x.sections.length
        );
        const cachedTemplate = cachedTemplateCandidates.find(x =>
            Number(x.IDVersion || x.VersionID || (x.VersionInfo && x.VersionInfo.IDVersion)) === Number(h.IDVersion)
        ) || cachedTemplateCandidates.find(x =>
            Number(x.Version || x.TemplateVersion) === Number(h.TemplateVersion)
        ) || null;
        const template = result.template || result.TemplateSnapshot || cachedTemplate || null;
        const templateAvailable = template && Array.isArray(template.sections) && template.sections.length;
        const checklistHtml = !templateAvailable
            ? '<div class="alert alert-danger small">Struktur checklist untuk template versi ini tidak ditemukan di server. Checklist tidak ditampilkan dalam format cadangan agar hasil approval tidak salah format. Muat ulang detail atau hubungi administrator.</div>'
            : isBatchApproval
                ? renderInspectionApprovalBatchPoints(template, batchPoints, photos)
                : renderInspectionSections(template, items, true, "inspectionApprovalSection");
        const followUpValue = String(h.FollowUp || "No Follow Up");
        const followUpWONo = String(h.FollowUpWONo || "").trim();
        const sectionIcons = { ACON: "bi-fan", COMM: "bi-broadcast", MECH: "bi-gear", ELEC: "bi-lightning-charge", CIVIL: "bi-building", PFIT: "bi-hammer", PHKP: "bi-brush", PSEC: "bi-shield-check" };
        const sectionLabels = { ACON: "Air Cond.", COMM: "Comm.", MECH: "Mechanical", ELEC: "Electrical", CIVIL: "Civil", PFIT: "Fit Out", PHKP: "Housekeeping", PSEC: "Security" };
        const followUpHtml = inspectionTemplateRequiresFollowUp(template) ? ('<div class="accordion-item border-warning shadow-sm mt-3" id="inspectionApprovalFollowUpPanel">' +
            '<div class="accordion-header"><div class="accordion-button bg-warning-subtle text-dark fw-bold"><i class="bi bi-lightbulb-fill fs-5 me-2 text-warning"></i><div class="d-flex flex-column"><span>FOLLOW UP WORK ORDER RECOMMENDATION</span><small class="text-muted fw-normal">Tentukan apakah diperlukan Work Order lanjutan.</small></div></div></div>' +
            '<div class="accordion-body p-3"><div class="alert alert-warning py-2 px-3 mb-3 small"><i class="bi bi-info-circle-fill me-1"></i>Bila ditemukan kerusakan yang memerlukan pekerjaan lanjutan, pilih <strong>Recommend Follow Up</strong>, kemudian tentukan section yang bertanggung jawab dan isi WO Remark.</div>' +
            '<div class="mb-3"><div class="btn-group w-100 shadow-sm" role="group"><input class="btn-check" type="radio" disabled ' + (followUpValue !== "Recommend Follow Up" ? 'checked' : '') + '><label class="btn btn-outline-primary">No Follow Up</label><input class="btn-check" type="radio" disabled ' + (followUpValue === "Recommend Follow Up" ? 'checked' : '') + '><label class="btn btn-outline-primary">Recommend Follow Up</label></div></div>' +
            '<div class="' + (followUpValue === "Recommend Follow Up" ? '' : 'd-none') + '" id="inspectionApprovalFollowUpDetails">' +
            '<div class="card border-warning-subtle bg-light mb-3"><div class="card-body"><label class="form-label small fw-semibold mb-2"><i class="bi bi-diagram-3-fill me-1"></i>Responsible Section</label><div class="d-flex flex-wrap gap-2">' +
            inspectionFollowUpSections.map(section => {
                const selectedSection = String(h.FollowUpSection || "") === section.Code;
                return '<span class="btn ' + (selectedSection ? 'btn-primary' : 'btn-outline-primary') + ' rounded-3 inspection-followup-section-btn disabled" aria-pressed="' + selectedSection + '"><i class="bi ' + sectionIcons[section.Code] + '"></i><span class="fw-semibold">' + escInspection(section.Code) + '</span><small class="d-block">' + escInspection(sectionLabels[section.Code]) + '</small></span>';
            }).join("") +
            '</div></div></div>' +
            '<div class="card border-warning-subtle bg-light"><div class="card-body"><label class="form-label small fw-semibold mb-2"><i class="bi bi-card-text me-1"></i>Follow Up Work Order Description</label><div class="form-control bg-body-secondary" style="min-height:5rem;white-space:pre-wrap">' + escInspection(h.FollowUpRemark || "-") + '</div><div class="d-flex justify-content-end mt-2"><small class="text-muted">' + String((h.FollowUpRemark || "").length) + ' / 300</small></div></div></div>' +
            (followUpWONo ? '<div class="alert alert-success d-flex align-items-center gap-2 mt-3 mb-0"><i class="bi bi-file-earmark-check-fill fs-5"></i><div><div class="small text-muted">Generated Follow Up WO No.</div><div class="fw-bold">' + escInspection(followUpWONo) + '</div></div></div>' : '') +
            '</div></div></div>') : "";
        const templateSummaryText = template && (template.SummarySampleText || template.summarySampleText || (template.VersionInfo && template.VersionInfo.SummarySampleText)) || "";
        const summaryRequired = !templateAvailable || inspectionTemplateRequiresSummary(template);
        const summaryHtml = summaryRequired ? '<div class="accordion-item border-info shadow-sm mt-3" id="inspectionApprovalSummaryPanel"><div class="accordion-header"><div class="accordion-button bg-info-subtle text-dark fw-bold"><i class="bi bi-clipboard2-check-fill fs-5 me-2 text-info"></i><div class="d-flex flex-column"><span>FINAL INSPECTION SUMMARY</span><small class="text-muted fw-normal">Ringkasan hasil inspeksi dan pekerjaan yang telah dilakukan.</small></div></div></div><div class="accordion-body p-3"><div class="alert alert-info py-2 px-3 mb-3 small"><i class="bi bi-info-circle-fill me-1"></i>Jelaskan secara singkat hasil pemeriksaan, tindakan yang dilakukan, serta kondisi akhir unit setelah pekerjaan selesai.</div><textarea class="form-control" rows="5" maxlength="500" disabled placeholder="' + escInspection(templateSummaryText) + '">' + escInspection(h.Summary || "") + '</textarea><div class="d-flex justify-content-between align-items-center mt-2"><small class="text-muted">Maksimum 500 karakter.</small><small class="text-muted">' + String((h.Summary || "").length) + ' / 500</small></div></div></div>' : "";
        const reasonVoidHtml = String(h.ReasonVoid || "").trim()
            ? '<div class="accordion-item border-danger shadow-sm mt-3" id="inspectionApprovalReasonVoidPanel">' +
                '<div class="accordion-header"><div class="accordion-button bg-danger text-white fw-bold"><i class="bi bi-x-circle-fill fs-5 me-2"></i><div class="d-flex flex-column"><span>REASON VOID</span><small class="text-white-50 fw-normal">Alasan inspeksi dikembalikan menjadi Draft.</small></div></div></div>' +
                '<div class="accordion-body p-3"><textarea class="form-control bg-body-tertiary" rows="4" disabled>' + escInspection(h.ReasonVoid) + '</textarea></div>' +
              '</div>'
            : "";
        checklistHost.innerHTML = (isBatchApproval ? '<div id="inspectionApprovalBatchMap"></div>' : beforePhotoHtml) +
            checklistHtml + (isBatchApproval ? "" : afterPhotoHtml) + followUpHtml + summaryHtml + reasonVoidHtml;
        if (isBatchApproval) renderInspectionApprovalBatchMap(batchMaps, batchPoints, result.schedules || [], h);
        document.getElementById("btnApproveInspection").disabled = isApproved ||
            (isBatchApproval && (!batchPoints.length || !templateAvailable));
        document.getElementById("btnVoidInspection").disabled = isApproved;
    } catch (err) {
        selectedInspectionApproval = null;
        document.getElementById("inspectionApprovalRemarkPanel").classList.remove("d-none");
        document.getElementById("txtInspectionApprovalRemark").readOnly = false;
        document.getElementById("btnApproveInspection").classList.remove("d-none");
        document.getElementById("btnVoidInspection").classList.remove("d-none");
        checklistHost.innerHTML = '<div class="alert alert-danger py-2 small">' + escInspection(err.message || "Gagal memuat detail.") + '</div>';
        document.getElementById("btnApproveInspection").disabled = true;
        document.getElementById("btnVoidInspection").disabled = true;
    }
}

async function processInspectionApproval(action) {
    if (!selectedInspectionApproval) return;
    if (!navigator.onLine) {
        showToast("Approval memerlukan koneksi ke server. Hubungkan internet lalu coba lagi.", "warning");
        return;
    }
    const isLightning = String(selectedInspectionApproval.InspectionMode || "").toUpperCase() === "LIGHTNING";
    const confirmed = await showConfirmation({
        title: isLightning ? "Approve Lightning Daily" : "Approve Inspeksi",
        message: isLightning
            ? "Approve seluruh transaksi harian dan lanjutkan ke tahap approval berikutnya?"
            : "Approve inspeksi ini?",
        yesText: "Approve"
    });
    if (!confirmed) return;
    const remark = document.getElementById("txtInspectionApprovalRemark").value.trim();
    try {
        const approvalResult = await inspectionApprovalPost(
            isLightning ? "ProcessLightningInspectionApproval" : "ProcessInspectionApproval", {
                inspectionId: Number(selectedInspectionApproval.InspectionID), action: "APPROVE",
                employeeId: inspectionLogin.employeeid, companyId: inspectionCompanyID,
                locationId: inspectionLocationID, remark: remark,
                approvalToken: getLightningApprovalEmailToken(selectedInspectionApproval.InspectionID)
            });
        showInspectionApprovalQueueView();
        const message = isLightning
            ? "Lightning daily inspection diproses. Status: " + (approvalResult.workflowStatus || "updated") +
                (approvalResult.currentStageCode ? " · tahap berikutnya " + approvalResult.currentStageCode : "") + "."
            : (approvalResult.followUpWONo
                ? "Inspection berhasil di-approve. Internal WO " + approvalResult.followUpWONo + " dibuat untuk Follow Up."
                : "Inspection berhasil di-approve.");
        const emailPending = approvalResult.emailDispatch && (approvalResult.emailDispatch.configured !== false && (Number(approvalResult.emailDispatch.failed || 0) > 0 || Number(approvalResult.emailDispatch.pending || 0) > 0));
        showToast(message, emailPending ? "warning" : "success");
        if (emailPending) showToast("Approval tersimpan, tetapi ada email yang belum terkirim. Periksa email pengirim di M_HRD_Employee dan konfigurasi SMTP aplikasi; email akan dicoba kembali dari outbox.", "warning");
        await loadInspectionApprovalQueue();
    } catch (err) {
        showToast(err.message || "Gagal memproses approval.", "warning");
    }
}

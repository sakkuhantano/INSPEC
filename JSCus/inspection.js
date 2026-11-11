let inspectionLogin = null;
let inspectionTechnicianName = "";
let inspectionCompanyID = "";
let inspectionLocationID = "";
let inspectionTypes = [];
let inspectionDetails = [];
let inspectionTemplates = [];
let inspectionRecords = [];
let serverSubmittedInspectionRecords = [];
let serverSlotRecords = [];
let currentInspectionRecord = null;
let currentInspectionReadOnly = false;
let inspectionAutoSaveTimer = null;
let inspectionPhotoViewerState = { type: "", photos: [], index: 0, objectUrl: null, touchStartX: null };
let inspectionPhotoBaseline = null;
let inspectionGridSort = { key: "inspectionDate", direction: "asc" };
let inspectionBatchValidationState = { errors: [], index: -1 };
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
        document.getElementById("txtSubmittedFrom").value = submittedToday;
        document.getElementById("txtSubmittedThru").value = submittedToday;
        document.getElementById("txtInspectionDate").value = localDateString(new Date());
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
        onInspectionDetailChanged();
        updateInspectionParameterTabGate();
    });
    document.getElementById("selInspectionScheduleTime").addEventListener("change", function () {
        updateStartButton();
        refreshInspectionScheduleOptions();
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
        populateInspectionScheduleTimeOptions(selectedDetail);
        refreshInspectionDetailAvailability();
        updateStartButton();
        refreshInspectionScheduleOptions();
        updateInspectionParameterTabGate();
    });
    document.getElementById("txtInspectionDate").addEventListener("change", refreshInspectionScheduleOptions);
    document.getElementById("btnStartInspection").addEventListener("click", startNewInspection);
    document.getElementById("btnNewInspection").addEventListener("click", resetInspectionSelection);
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
            String(currentInspectionRecord.InspectionMode || "").toUpperCase() === "BATCH";
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
            String(currentInspectionRecord.InspectionMode || "").toUpperCase() !== "BATCH") return;
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
    document.getElementById("txtInspectionSummary").addEventListener("input", function () {
        document.getElementById("inspectionSummaryCounter").textContent = this.value.length + " / 500";
    });
    document.getElementById("txtInspectionFollowUpRemark").addEventListener("input", function () {
        document.getElementById("inspectionFollowUpRemarkCounter").textContent = this.value.length + " / 300";
    });
    document.getElementById("inspectionChecklistHost").addEventListener("click", function (event) {
        const label = event.target && event.target.closest(".inspection-option-choice");
        if (!label || currentInspectionReadOnly) return;
        const input = document.getElementById(label.getAttribute("for"));
        if (!input || input.disabled || !input.checked) return;
        event.preventDefault();
        input.checked = false;
        input.dispatchEvent(new Event("change", { bubbles: true }));
    }, true);
    document.getElementById("inspectionChecklistHost").addEventListener("change", function (event) {
        if (event.target && event.target.matches('[data-role="value"][type="radio"]')) updateInspectionRemarkPanels();
        scheduleInspectionAutosave();
        updateInspectionChecklistGate();
    });
    document.getElementById("txtInspectionSummary").addEventListener("input", scheduleInspectionAutosave);
    document.querySelectorAll('input[name="inspectionFollowUp"]').forEach(input => input.addEventListener("change", function () {
        updateInspectionFollowUpPanel();
        scheduleInspectionAutosave();
    }));
    document.getElementById("inspectionFollowUpSection").addEventListener("change", scheduleInspectionAutosave);
    document.getElementById("txtInspectionFollowUpRemark").addEventListener("input", scheduleInspectionAutosave);
}

async function loadInspectionCache(includeAllTemplates) {
    inspectionTypes = await readInspectionStore(
        db.objectStoreNames.contains("inspection_types_scoped") ? "inspection_types_scoped" : "inspection_types"
    );
    inspectionDetails = await readInspectionStore("inspection_type_details");
    inspectionTemplates = await readInspectionStore("inspection_templates");

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

    const typeSelect = document.getElementById("selInspectionType");
    typeSelect.innerHTML = '<option value="">Pilih Inspection Type...</option>' +
        inspectionTypes.map(type =>
            '<option value="' + escInspection(type.InspectionTypeCode) + '">' +
            escInspection(type.InspectionTypeCode + " - " + type.InspectionTypeName) + '</option>'
        ).join("");
    resetDetailAndTemplateOptions();
}

function readInspectionStore(storeName) {
    return new Promise((resolve, reject) => {
        const tx = db.transaction(storeName, "readonly");
        const req = tx.objectStore(storeName).getAll();
        req.onsuccess = () => resolve(req.result || []);
        req.onerror = () => reject(req.error);
    });
}

function refreshInspectionDetailAvailability() {
    const detailSelect = document.getElementById("selInspectionDetail");
    const typeCode = document.getElementById("selInspectionType").value;
    const type = inspectionTypes.find(x =>
        String(x.InspectionTypeCode || "") === String(typeCode || "")
    );
    const selectedDate = document.getElementById("txtInspectionDate").value || localDateString(new Date());
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
        const slotTimes = times.length ? times : [""];
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
                    Number(record.IDTemplate) === Number(template.IDTemplate);

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
    detailSelect.innerHTML = '<option value="">Pilih detail...</option>';
    detailSelect.disabled = true;
    resetInspectionScheduleTimeOptions();
    document.getElementById("inspectionScheduleHint").textContent = type
        ? "Section: " + type.SectionID + ". Pilih template terlebih dahulu, lalu detail dan jam jadwal."
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
    populateInspectionScheduleTimeOptions(detail);
    refreshInspectionDetailAvailability();
    updateStartButton();
    refreshInspectionScheduleOptions();
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
    const selectedDate = document.getElementById("txtInspectionDate").value || localDateString(new Date());
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
            Number(record.IDTemplate) === templateId;

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
    const scheduledTime = document.getElementById("selInspectionScheduleTime").value;
    const enabled = !!typeCode && !!detail && !!detailCode && detailMatchesTemplate &&
        (!hasScheduledTimes || !!scheduledTime) && !!templateId;
    document.getElementById("btnStartInspection").disabled = !enabled;
}

async function startNewInspection() {
    const typeCode = document.getElementById("selInspectionType").value;
    const detailCode = document.getElementById("selInspectionDetail").value;
    const scheduledTime = document.getElementById("selInspectionScheduleTime").value || "";
    const templateId = Number(document.getElementById("selInspectionTemplate").value);
    const type = inspectionTypes.find(x => x.InspectionTypeCode === typeCode);
    const detail = inspectionDetails.find(x =>
        x.InspectionTypeCode === typeCode && x.InspectionTypeDetailCode === detailCode
    );
    const template = inspectionTemplates.find(x => Number(x.IDTemplate) === templateId);

    if (!type || !detail || !template ||
        !isInspectionTemplateDetailAllowed(template, detail.InspectionTypeDetailCode) ||
        (getInspectionScheduleTimes(detail).length > 0 && !scheduledTime)) {
        showToast("Pilih Inspection Type, detail, jam jadwal (jika tersedia), dan template yang valid.", "warning");
        return;
    }

    const inspectionDate = document.getElementById("txtInspectionDate").value || localDateString(new Date());
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
        Number(record.IDTemplate) === Number(template.IDTemplate)
    );
    if (duplicate) {
        if (duplicate.SyncStatus === "CONFLICT" || duplicate.SyncStatus === "DELETE_PENDING") {
            showToast("Jadwal ini punya record lokal berstatus " + duplicate.SyncStatus +
                ". Alasan: " + (duplicate.ConflictReason || "arsip/pemeriksaan konflik belum selesai.") +
                " Selesaikan konflik tersebut sebelum membuat transaksi baru.", "warning");
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
        Number(record.IDTemplate) === Number(template.IDTemplate)
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
                    inspectionDate: inspectionDate
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
                showToast("Jadwal ini sudah memiliki inspeksi " +
                    (check.InspectionNo || "di server") + " untuk tanggal dan template tersebut. Duplikat tidak dibuat.", "warning");
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

    const inspectionMode = String(type.InspectionMode || "STANDARD").trim().toUpperCase() === "BATCH"
        ? "BATCH" : "STANDARD";
    let batchMapSetup = null;
    if (inspectionMode === "BATCH") {
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
        Points: [],
        ActiveInspectionPointID: 0,
        Items: []
    };

    if (typeof window.resetInspectionMapWorkspace === "function")
        await window.resetInspectionMapWorkspace();
    await renderInspectionForm(currentInspectionRecord, false, "param");
    const mapWorkspace = document.getElementById("inspectionMapWorkspace");
    if (inspectionMode === "BATCH" && typeof showInspectionMapWorkspace === "function") {
        showInspectionMapWorkspace(currentInspectionRecord, false);
        if (mapWorkspace) mapWorkspace.classList.add("d-none");
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
    if (value == null || value === "") return "";
    const raw = String(value).trim();
    // Preserve date-only / ISO dates without timezone conversion.
    const isoDate = raw.match(/^(\\d{4})-(\\d{2})-(\\d{2})/);
    if (isoDate) return isoDate[1] + "-" + isoDate[2] + "-" + isoDate[3];
    // Handle ASP.NET JSON DateTime values such as /Date(1793232000000)/.
    const date = parseInspectionDateValue(value);
    if (!date) return "";
    return String(date.getFullYear()).padStart(4, "0") + "-" +
        String(date.getMonth() + 1).padStart(2, "0") + "-" +
        String(date.getDate()).padStart(2, "0");
}

function formatInspectionDateDMY(value) {
    if (!value) return "-";
    const raw = String(value).trim();
    const match = raw.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (match) return match[3] + "-" + match[2] + "-" + match[1];
    const date = parseInspectionDateValue(value);
    if (!date) return "-";
    return String(date.getDate()).padStart(2, "0") + "-" +
        String(date.getMonth() + 1).padStart(2, "0") + "-" +
        date.getFullYear();
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
    if (!record || String(record.InspectionMode || "").toUpperCase() !== "BATCH")
        return "Batch inspection tidak sedang aktif.";
    const requirement = getInspectionPhotoRequirement(record);
    if (requirement !== "NONE") {
        const photoText = requirement === "BOTH" ? "BEFORE dan AFTER" : requirement;
        return "Template Version mewajibkan foto " + photoText + ". Buka checklist lengkap untuk melanjutkan.";
    }
    const masterPoint = (record.BatchMapSetup && record.BatchMapSetup.points || []).find(item =>
        Number(item.InspectionPointID) === Number(point && point.InspectionPointID));
    if (isInspectionFlagEnabled(masterPoint && masterPoint.IsNormalAbnormalRequired, false))
        return "Point ini mewajibkan kondisi NORMAL/ABNORMAL dan mungkin Abnormal Remark. Buka checklist lengkap.";
    const templateItems = [];
    (record.TemplateSnapshot && Array.isArray(record.TemplateSnapshot.sections) ? record.TemplateSnapshot.sections : [])
        .forEach(section => (section.items || []).forEach(item => templateItems.push(item)));
    if (!templateItems.length || templateItems.some(item =>
        String(item.type || "").toUpperCase() !== "OPTION" &&
        isInspectionFlagEnabled(item.isValueRequired, false)))
        return "Template memiliki checklist wajib selain OPTION. Buka checklist lengkap.";
    for (const item of templateItems) {
        const r1 = isInspectionVersionRemarkEnabled(item, 1);
        const r2 = isInspectionVersionRemarkEnabled(item, 2);
        const mandatoryRemark =
            (r1 && isInspectionFlagEnabled(item.isRemark1Required, false) && isInspectionFlagEnabled(item.isRemark1Mandatory, false)) ||
            (r2 && isInspectionFlagEnabled(item.isRemark2Required, false) && isInspectionFlagEnabled(item.isRemark2Mandatory, false));
        const versionInfo = record.TemplateSnapshot &&
            (record.TemplateSnapshot.VersionInfo || record.TemplateSnapshot.versionInfo || record.TemplateSnapshot);
        const optionRemarks = (Array.isArray(item.remarkRequiredOptions) ? item.remarkRequiredOptions : [])
            .concat(Array.isArray(versionInfo && versionInfo.RemarkRequiredOptions) ? versionInfo.RemarkRequiredOptions : []);
        if (mandatoryRemark || (optionRemarks.length && (r1 || r2)))
            return "Template Version mewajibkan Remark untuk checklist ini. Buka checklist lengkap.";
    }
    return "";
}
window.getBatchPointQuickOptionBlockReason = getBatchPointQuickOptionBlockReason;

function normalizeInspectionPhotoRequirement(value) {
    const requirement = String(value || "BOTH").toUpperCase();
    return ["NONE", "BEFORE", "AFTER", "BOTH"].includes(requirement) ? requirement : "BOTH";
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

window.mountInspectionBatchSummary = function (record) {
    const host = document.getElementById("inspectionMapSummaryHost");
    const checklistPane = document.getElementById("inspectionChecklistPane");
    const followUp = document.getElementById("inspectionFollowUpPanel");
    const summary = document.getElementById("inspectionSummaryPanel");
    const reasonVoid = document.getElementById("inspectionReasonVoidPanel");
    if (!host || !checklistPane || !followUp || !summary) return;
    const isBatch = record && String(record.InspectionMode || "").toUpperCase() === "BATCH";
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
        document.getElementById("txtInspectionSummary").disabled = readOnly;
    } else {
        checklistPane.appendChild(followUp);
        checklistPane.appendChild(summary);
        if (reasonVoid) checklistPane.appendChild(reasonVoid);
        host.classList.add("d-none");
        followUp.classList.toggle("d-none", !inspectionTemplateRequiresFollowUp(record.TemplateSnapshot));
        summary.classList.toggle("d-none", !inspectionTemplateRequiresSummary(record.TemplateSnapshot));
    }
};

async function renderInspectionForm(record, readOnly, initialTab) {
    currentInspectionRecord = record;
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
        mapTabButton.closest("li").classList.toggle("d-none", String(record.InspectionMode || "STANDARD").toUpperCase() !== "BATCH");
    document.getElementById("inspectionStartButtonRow").classList.add("d-none");
    document.getElementById("inspectionStartPanel").classList.remove("d-none");
    document.getElementById("inspectionFormPanel").classList.remove("d-none");
    populateInspectionParameters(record);
    showInspectionEditorTab(initialTab || "checklist");
    const canDeleteVoidedInspection = isVoidedServerRecord;
    const canDeleteConflictInspection = record.SyncStatus === "CONFLICT";
    const canDeleteDraft = canDeleteVoidedInspection || canDeleteConflictInspection || (!currentInspectionReadOnly &&
        record.Status === "DRAFT" && record.SyncStatus !== "SYNCED" &&
        record.SyncStatus !== "CONFLICT" && record.SyncStatus !== "DELETE_PENDING" &&
        inspectionRecords.some(item => item.LocalInspectionID === record.LocalInspectionID));
    document.getElementById("btnDeleteInspectionDraft").classList.toggle("d-none", !canDeleteDraft);
    const canDeleteBatchDraft = String(record.InspectionMode || "").toUpperCase() === "BATCH" &&
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
    setInspectionFormHeader(transactionNo, [
        (record.InspectionTypeName || "Inspection") + " — " + (record.InspectionTypeDetailName || ""),
        (record.TemplateNo || "-") + " / v" + (record.TemplateVersion || "-"),
        "Jadwal " + (record.ScheduledTime || "-") + " • " + (formatInspectionDateDMY(record.InspectionDate) || "-"),
        startTime + " - " + endTime
    ]);
    document.getElementById("txtInspectionSummary").value = record.Summary || "";
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
    document.getElementById("txtInspectionFollowUpRemark").value = record.FollowUpRemark || "";
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
    document.getElementById("txtInspectionSummary").placeholder = summarySampleText;
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
        const showRemark1 = versionRemark1Enabled &&
            (container.dataset.remark1BaseRequired === "1" || optionRequires);
        const showRemark2 = versionRemark2Enabled &&
            (container.dataset.remark2BaseRequired === "1" || optionRequires);
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
                (String(saved.Value || "") === option ? " checked" : "") + disabled + '><label class="btn btn-outline-primary inspection-option-choice" for="' + optionId + '">' + escInspection(option) + '</label>';
        }).join("") + '</div>';
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
              ' sampai ' + escInspection(item.max == null ? "-" : item.max) + (item.unit ? " " + escInspection(item.unit) : "") + '</div>'
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

    const remarkOptions = Array.isArray(item.remarkRequiredOptions) ? item.remarkRequiredOptions.map(x => String(x).trim()) : [];
    const selectedOptionRequiresRemark = type === "OPTION" && remarkOptions.includes(String(saved.Value || "").trim());
    const versionRemark1Enabled = isInspectionVersionRemarkEnabled(item, 1);
    const versionRemark2Enabled = isInspectionVersionRemarkEnabled(item, 2);
    const itemRemark1Text = item.isRemark1Required ? (item.remark1Text || "Remark") : "";
    const itemRemark2Text = item.isRemark2Required ? (item.remark2Text || "Remark") : "";
    const versionRemark1Text = versionRemark1Enabled ? (item.versionRemark1Text || item.VersionRemark1Text || "Remark") : "";
    const versionRemark2Text = versionRemark2Enabled ? (item.versionRemark2Text || item.VersionRemark2Text || "Remark") : "";
    const remark1Text = selectedOptionRequiresRemark && !item.isRemark1Required ? versionRemark1Text : itemRemark1Text;
    const remark2Text = selectedOptionRequiresRemark && !item.isRemark2Required ? versionRemark2Text : itemRemark2Text;
    const showRemark1 = versionRemark1Enabled && (!!item.isRemark1Required || selectedOptionRequiresRemark);
    const showRemark2 = versionRemark2Enabled && (!!item.isRemark2Required || selectedOptionRequiresRemark);
    const renderRemark1 = versionRemark1Enabled && (!!item.isRemark1Required || (type === "OPTION" && remarkOptions.length > 0));
    const renderRemark2 = versionRemark2Enabled && (!!item.isRemark2Required || (type === "OPTION" && remarkOptions.length > 0));
    const remark1 = renderRemark1
        ? '<div class="mt-2" data-role="remark1-wrap" style="' + (showRemark1 ? "" : "display:none;") + '"><label class="inspection-muted">' + escInspection(remark1Text) +
          (showRemark1 && (!!item.isRemark1Mandatory || selectedOptionRequiresRemark) ? ' (wajib)' : '') + '</label><input type="text" maxlength="500" data-role="remark1" class="form-control form-control-sm" value="' +
          escInspection(saved.Remark1 || saved.Remark || "") + '"' + disabled + (showRemark1 && (!!item.isRemark1Mandatory || selectedOptionRequiresRemark) ? ' required' : '') + '></div>'
        : "";
    const remark2 = renderRemark2
        ? '<div class="mt-2" data-role="remark2-wrap" style="' + (showRemark2 ? "" : "display:none;") + '"><label class="inspection-muted">' + escInspection(remark2Text) +
          (showRemark2 && (!!item.isRemark2Mandatory || selectedOptionRequiresRemark) ? ' (wajib)' : '') + '</label><input type="text" maxlength="500" data-role="remark2" class="form-control form-control-sm" value="' +
          escInspection(saved.Remark2 || "") + '"' + disabled + (showRemark2 && (!!item.isRemark2Mandatory || selectedOptionRequiresRemark) ? ' required' : '') + '></div>'
        : "";

    return '<div class="inspection-item' + (saved.IsAnomali ? ' anomaly' : '') + '" data-item-id="' + id + '" data-item-type="' + escInspection(type) +
        '" data-min="' + escInspection(item.min == null ? "" : item.min) +
        '" data-max="' + escInspection(item.max == null ? "" : item.max) +
        '" data-required="' + (item.isValueRequired ? "1" : "0") +
        '" data-remark1-base-required="' + (item.isRemark1Required ? "1" : "0") +
        '" data-remark2-base-required="' + (item.isRemark2Required ? "1" : "0") +
        '" data-remark1-mandatory="' + (item.isRemark1Mandatory ? "1" : "0") +
        '" data-remark2-mandatory="' + (item.isRemark2Mandatory ? "1" : "0") +
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
        const value = type === "GROUP" ? "" : (valueElement ? valueElement.value : "");
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
            Values: type === "GROUP" ? values : null
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
    if (item && item[key] != null) return isInspectionFlagEnabled(item[key], false);
    const snapshot = currentInspectionRecord && currentInspectionRecord.TemplateSnapshot;
    const versionInfo = snapshot && (snapshot.VersionInfo || snapshot.versionInfo || snapshot);
    const snapshotKey = remarkNumber === 1 ? "IsRemark1Required" : "IsRemark2Required";
    const camelKey = snapshotKey.charAt(0).toLowerCase() + snapshotKey.slice(1);
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
        const requiredOptionRemarks = []
            .concat(Array.isArray(templateItem.remarkRequiredOptions) ? templateItem.remarkRequiredOptions : [])
            .concat(Array.isArray(versionInfo && versionInfo.RemarkRequiredOptions) ? versionInfo.RemarkRequiredOptions : [])
            .map(value => String(value).trim());
        const selectedOptionRequiresRemark = itemType === "OPTION" &&
            requiredOptionRemarks.includes(String(answer.Value || "").trim());
        const versionRemark1Enabled = isInspectionVersionRemarkEnabled(templateItem, 1);
        const versionRemark2Enabled = isInspectionVersionRemarkEnabled(templateItem, 2);
        const remark1Required = versionRemark1Enabled &&
            ((isInspectionFlagEnabled(templateItem.isRemark1Required, false) &&
              isInspectionFlagEnabled(templateItem.isRemark1Mandatory, false)) ||
             selectedOptionRequiresRemark);
        const remark2Required = versionRemark2Enabled &&
            ((isInspectionFlagEnabled(templateItem.isRemark2Required, false) &&
              isInspectionFlagEnabled(templateItem.isRemark2Mandatory, false)) ||
             selectedOptionRequiresRemark);
        const remark1Title = selectedOptionRequiresRemark && !isInspectionFlagEnabled(templateItem.isRemark1Required, false)
            ? (templateItem.versionRemark1Text || templateItem.VersionRemark1Text || "Remark")
            : (templateItem.remark1Text || "Remark");
        const remark2Title = selectedOptionRequiresRemark && !isInspectionFlagEnabled(templateItem.isRemark2Required, false)
            ? (templateItem.versionRemark2Text || templateItem.VersionRemark2Text || "Remark")
            : (templateItem.remark2Text || "Remark");
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
    if (!currentInspectionRecord || String(currentInspectionRecord.InspectionMode || "").toUpperCase() !== "BATCH")
        return null;
    return (currentInspectionRecord.Points || []).find(point =>
        Number(point.InspectionPointID) === Number(currentInspectionRecord.ActiveInspectionPointID)
    ) || null;
}

function getActiveInspectionPointPhotoID() {
    const point = getActiveInspectionPoint();
    return point ? String(point.ClientPointID || "") : "";
}

async function getCurrentInspectionPhotos() {
    if (!currentInspectionRecord) return [];
    return getInspectionPhotos(currentInspectionRecord.LocalInspectionID,
        String(currentInspectionRecord.InspectionMode || "").toUpperCase() === "BATCH"
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
    document.getElementById("btnNextBatchValidationIssue").addEventListener("click", async function () {
        await goToNextBatchValidationIssue();
    });
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
    const target = nextError.target === "summary" ? document.getElementById("txtInspectionSummary") :
        nextError.target === "followup-section" ? document.getElementById("inspectionFollowUpSection") :
        nextError.target === "followup-remark" ? document.getElementById("txtInspectionFollowUpRemark") : null;
    showInspectionEditorTab("checklist");
    if (target) { target.scrollIntoView({ behavior: "smooth", block: "center" }); target.focus(); }
}

async function openBatchInspectionPointChecklist(masterPoint, validationError) {
    if (!currentInspectionRecord || String(currentInspectionRecord.InspectionMode || "").toUpperCase() !== "BATCH")
        return;
    if (!masterPoint || !masterPoint.InspectionPointID) return;
    const pointReadOnly = currentInspectionReadOnly || currentInspectionRecord.Status === "DONE";

    let point = (currentInspectionRecord.Points || []).find(item =>
        Number(item.InspectionPointID) === Number(masterPoint.InspectionPointID));
    if (!point) {
        point = {
            ClientPointID: newInspectionId(),
            InspectionPointID: Number(masterPoint.InspectionPointID),
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
    host.innerHTML = renderInspectionSections(
        currentInspectionRecord.TemplateSnapshot,
        point.Items || [],
        pointReadOnly,
        "inspectionSection"
    );
    renderBatchPointCondition(masterPoint, point, pointReadOnly);
    const title = document.getElementById("inspectionFormTitle");
    if (title) title.textContent = point.PointCode + " · " + point.PointName;
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
    const mapWorkspace = document.getElementById("inspectionMapWorkspace");
    if (mapWorkspace) mapWorkspace.classList.add("d-none");
    const mapTab = document.getElementById("btnInspectionMapTab");
    const checklistTab = document.getElementById("btnInspectionChecklistTab");
    if (mapTab) mapTab.classList.remove("active");
    if (checklistTab) checklistTab.classList.add("active");
    showInspectionEditorTab("checklist");
    await renderInspectionPhotos();
    await updateInspectionChecklistGate();
    mountBatchValidationNavigator();
    if (validationError) window.setTimeout(() => focusBatchValidationTarget(validationError), 180);
    // Opening a map point is navigation only. The point and its parent batch
    // remain in memory until the user explicitly presses Save Point / Save Draft.
}

window.openBatchInspectionPointChecklist = openBatchInspectionPointChecklist;

window.setBatchInspectionPointOption = async function (pointId, itemId, value) {
    const record = currentInspectionRecord;
    if (!record || String(record.InspectionMode || "").toUpperCase() !== "BATCH")
        throw new Error("Batch inspection tidak sedang aktif.");
    if (currentInspectionReadOnly || String(record.Status || "").toUpperCase() === "DONE")
        throw new Error("Batch yang sudah disubmit bersifat read-only.");

    const quickOptionBlockReason = getBatchPointQuickOptionBlockReason({ InspectionPointID: pointId });
    if (quickOptionBlockReason) throw new Error(quickOptionBlockReason);

    const templateItems = [];
    (record.TemplateSnapshot && Array.isArray(record.TemplateSnapshot.sections) ? record.TemplateSnapshot.sections : [])
        .forEach(section => (section.items || []).forEach(item => templateItems.push(item)));
    const templateItem = templateItems.find(item =>
        String(item.type || "").toUpperCase() === "OPTION" && Number(item.idItem) === Number(itemId));
    if (!templateItem) throw new Error("Checklist OPTION tidak ditemukan pada template batch.");

    record.Points = Array.isArray(record.Points) ? record.Points : [];
    let point = record.Points.find(item => Number(item.InspectionPointID) === Number(pointId));
    if (!point) {
        const masterPoint = (record.BatchMapSetup && record.BatchMapSetup.points || []).find(item =>
            Number(item.InspectionPointID) === Number(pointId));
        if (!masterPoint) throw new Error("Inspection Point tidak ditemukan.");
        point = {
            ClientPointID: newInspectionId(),
            InspectionPointID: Number(masterPoint.InspectionPointID),
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
        Object.keys(item.Values || {}).some(key => String(item.Values[key] == null ? "" : item.Values[key]).trim() !== "")
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

async function saveBatchInspectionPoint(status) {
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
        point.Status = String(point.PointCondition || "").toUpperCase() === "ABNORMAL" ||
            items.some(item => item.IsAnomali === true || item.IsAnomali === 1 || String(item.IsAnomali || "") === "1" ||
                /^(OFF|MATI|NO|RUSAK|ABNORMAL|TIDAK|NOT OK)$/.test(String(item.Value || "").trim().toUpperCase()))
            ? "ABNORMAL" : "DONE";
    } else {
        point.Status = items.some(item => String(item.Value || "").trim() ||
            Object.keys(item.Values || {}).some(key => String(item.Values[key] == null ? "" : item.Values[key]).trim())) ||
            photos.length ? "INCOMPLETE" : "PENDING";
    }
    point.Items = items;
    point.ValidationIssueCount = errors.length;
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
    document.getElementById("inspectionChecklistPane").classList.add("d-none");
    if (typeof showInspectionMapWorkspace === "function") showInspectionMapWorkspace(record, true);
    if (typeof refreshInspectionMapPointStatuses === "function") refreshInspectionMapPointStatuses();
    showToast(point.PointCode + " tersimpan dengan status " + point.Status + ".", "success");
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
        modal.hide();
        if (error.pointId) {
            const masterPoint = masterPoints.find(point => Number(point.InspectionPointID) === Number(error.pointId));
            if (masterPoint) window.setTimeout(() => openBatchInspectionPointChecklist(masterPoint, error), 180);
        } else {
            window.setTimeout(() => {
                const target = error.target === "summary" ? document.getElementById("txtInspectionSummary") :
                    error.target === "followup-section" ? document.getElementById("inspectionFollowUpSection") :
                    error.target === "followup-remark" ? document.getElementById("txtInspectionFollowUpRemark") : null;
                if (target) {
                    showInspectionEditorTab("checklist");
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
    if (!record || String(record.InspectionMode || "").toUpperCase() !== "BATCH") return;
    if (String(record.Status || "").toUpperCase() === "DONE") { showToast("Batch ini sudah disubmit dan tidak dapat diubah.", "warning"); return; }
    const points = Array.isArray(record.Points) ? record.Points : [];
    const masterPoints = record.BatchMapSetup && record.BatchMapSetup.points || [];
    if (!masterPoints.length) { showToast("Master Inspection Point batch ini tidak tersedia.", "danger"); return; }
    const errors = [];
    const knownPointIDs = new Set();
    const requirement = getInspectionPhotoRequirement(record);
    for (const masterPoint of masterPoints) {
        const pointId = Number(masterPoint.InspectionPointID);
        const point = points.find(item => Number(item.InspectionPointID) === pointId);
        const requireAll = masterPoint.RequireAllPoints == null ? true : isInspectionFlagEnabled(masterPoint.RequireAllPoints, true);
        const pointCode = String(masterPoint.PointCode || ("Point " + pointId));
        if (!point) {
            if (requireAll) errors.push({ pointCode, pointId, message: "Belum diinspeksi (wajib berdasarkan Master Map)." });
            continue;
        }
        knownPointIDs.add(pointId);
        const photos = await getInspectionPhotos(record.LocalInspectionID, String(point.ClientPointID || ""));
        const items = Array.isArray(point.Items) ? point.Items : [];
        const touched = items.length > 0 || photos.length > 0 || String(point.PointCondition || "").trim() !== "" ||
            String(point.AbnormalRemark || "").trim() !== "" || !["", "PENDING"].includes(String(point.Status || "").toUpperCase());
        if (!requireAll && !touched) continue;
        validateInspectionItemsAll(items).forEach(error => errors.push({ pointCode, pointId, message: error.message, itemId: error.itemId, role: error.role }));
        const hasBefore = photos.some(photo => String(photo.Type || "").toUpperCase() === "BEFORE");
        const hasAfter = photos.some(photo => String(photo.Type || "").toUpperCase() === "AFTER");
        if ((requirement === "BEFORE" || requirement === "BOTH") && !hasBefore)
            errors.push({ pointCode, pointId, message: "Foto BEFORE belum dilampirkan.", target: "photo-before" });
        if ((requirement === "AFTER" || requirement === "BOTH") && !hasAfter)
            errors.push({ pointCode, pointId, message: "Foto AFTER belum dilampirkan.", target: "photo-after" });
        if (isInspectionFlagEnabled(masterPoint.IsNormalAbnormalRequired, false)) {
            const condition = String(point.PointCondition || "").toUpperCase();
            if (condition !== "NORMAL" && condition !== "ABNORMAL")
                errors.push({ pointCode, pointId, message: "Kondisi NORMAL/ABNORMAL belum dipilih.", target: "condition" });
            if (condition === "ABNORMAL" && !String(point.AbnormalRemark || "").trim())
                errors.push({ pointCode, pointId, message: "Abnormal Remark belum diisi.", target: "abnormal-remark" });
        }
        if (!["DONE", "ABNORMAL"].includes(String(point.Status || "").toUpperCase()))
            errors.push({ pointCode, pointId, message: "Point belum diselesaikan melalui Complete Point." });
    }
    points.forEach(point => {
        if (!masterPoints.some(master => Number(master.InspectionPointID) === Number(point.InspectionPointID)))
            errors.push({
                pointCode: String(point.PointCode || ("Point " + point.InspectionPointID)),
                pointId: Number(point.InspectionPointID),
                message: "Point tidak termasuk Master Map aktif untuk batch ini."
            });
    });
    if (!points.length || !knownPointIDs.size)
        errors.push({ pointCode: "Kelengkapan Batch", message: "Minimal satu Inspection Point harus diinspeksi." });
    const summary = String(document.getElementById("txtInspectionSummary")?.value || record.Summary || "").trim();
    if (inspectionTemplateRequiresSummary(record.TemplateSnapshot) && !summary)
        errors.push({ pointCode: "Kelengkapan Batch", message: "Final Inspection Summary wajib diisi.", target: "summary" });
    const followUp = collectInspectionFollowUp();
    if (inspectionTemplateRequiresFollowUp(record.TemplateSnapshot) && followUp.FollowUp === "Recommend Follow Up" &&
        (!followUp.FollowUpSection || !followUp.FollowUpRemark))
        errors.push({ pointCode: "Kelengkapan Batch", message: "Responsible Section dan Follow Up Remark wajib diisi.", target: !followUp.FollowUpSection ? "followup-section" : "followup-remark" });
    if (errors.length) { showInspectionBatchValidationReport(errors); return; }
    const confirmed = await showConfirmation({
        title: "Submit Inspection Batch",
        message: "Submit " + points.length + " titik? Checklist, foto, kondisi titik, dan pengaturan Master Version sudah lolos validasi.",
        yesText: "Submit Batch"
    });
    if (!confirmed) return;
    record.Items = [];
    record.Summary = summary;
    Object.assign(record, followUp);
    record.ActiveInspectionPointID = 0;
    record.Status = "DONE";
    record.EndDateTime = localDateTimeString(new Date());
    record.SyncStatus = "PENDING";
    record.UpdatedAt = new Date().toISOString();
    await persistInspectionRecord(record);
    showToast("Inspection Batch tersimpan offline. Jalankan Sync untuk mengirim seluruh point, checklist, dan foto.", "success");
    await refreshSavedInspectionList();
    await closeInspectionForm();
};

async function saveInspection(status) {
    if (currentInspectionRecord && String(currentInspectionRecord.InspectionMode || "").toUpperCase() === "BATCH") {
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
    const fromInput = document.getElementById("txtSubmittedFrom");
    const thruInput = document.getElementById("txtSubmittedThru");
    const fromDate = fromInput ? fromInput.value : localDateString(new Date());
    const thruDate = thruInput ? thruInput.value : localDateString(new Date());
    if (!fromDate || !thruDate || fromDate > thruDate) {
        showToast("Tanggal From/Thru tidak valid. Pastikan From tidak melewati Thru.", "warning");
        return;
    }
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

    // Conflicts must remain visible even when the rejected transaction was completed
    // for a prior date; otherwise technicians would have no way to resolve it.
    const drafts = inspectionRecords.filter(record =>
        record.Status === "DRAFT" || record.SyncStatus === "CONFLICT" || record.SyncStatus === "DELETE_PENDING");

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
    renderInspectionRecordTable(Array.from(submittedById.values()), document.getElementById("inspectionSubmittedList"), true);
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
        { key: "technician", label: "Technician" }
    ];
    const header = '<thead><tr>' + columns.map(column => {
        const active = inspectionGridSort.key === column.key;
        const arrow = active ? (inspectionGridSort.direction === "asc" ? " ▲" : " ▼") : " ↕";
        return '<th class="text-nowrap" role="button" tabindex="0" data-inspection-sort="' + column.key + '" aria-sort="' +
            (active ? (inspectionGridSort.direction === "asc" ? "ascending" : "descending") : "none") + '">' +
            column.label + '<span class="text-muted small">' + arrow + '</span></th>';
    }).join("") + '</tr></thead>';
    const sortedRecords = records.slice().sort((a, b) => {
        const value = record => {
            switch (inspectionGridSort.key) {
                case "inspectionNo": return String(record.InspectionNo || record.LocalInspectionID || "");
                case "startEnd": return String(record.StartDateTime || "") + "|" + String(record.EndDateTime || "");
                case "inspectionType": return String(record.InspectionTypeName || "");
                case "locationArea": return String(record.InspectionTypeDetailName || "");
                case "technician": return String(record.TechnicianName || (record.OwnerEmployeeID === inspectionLogin.employeeid ? inspectionTechnicianName : "") || "");
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
        const inspectionDateTime = date ? date + (record.ScheduledTime ? " " + record.ScheduledTime : "") : (record.ScheduledTime || "—");
        const startEnd = (start || "—") + " - " + end;
        const localExists = !!inspectionRecords.find(item => item.LocalInspectionID === localId);
        const serverId = record.InspectionID || record.ServerInspectionID || "";
        const numberHtml = localExists
            ? '<button type="button" class="btn btn-link btn-sm p-0 text-nowrap" data-open-inspection="' + escInspection(localId) + '">' + escInspection(number) + '</button>'
            : (submitted && serverId
                ? '<button type="button" class="btn btn-link btn-sm p-0 text-nowrap" data-open-server-inspection="' + escInspection(serverId) + '">' + escInspection(number) + '</button>'
                : escInspection(number));
        const conflictHtml = record.SyncStatus === "CONFLICT"
            ? '<div class="text-danger small mt-1"><strong>CONFLICT:</strong> ' + escInspection(record.ConflictReason || "Server menolak transaksi.") + '</div>'
            : record.SyncStatus === "DELETE_PENDING"
                ? '<div class="text-warning small mt-1">' +
                    (record.DeleteOriginalSyncStatus === "VOIDED"
                        ? 'Menunggu server menonaktifkan inspeksi void sebelum data lokal dihapus.'
                        : 'Menunggu arsip server sebelum transaksi lokal dihapus.') +
                  (record.DeleteReasonCancel ? '<div>Reason Cancel: ' + escInspection(record.DeleteReasonCancel) + '</div>' : '') +
                  (record.DeleteArchiveError ? '<div class="text-danger">Sync terakhir: ' + escInspection(record.DeleteArchiveError) + '</div>' : '') +
                  '</div>'
                : "";
        const deleteHtml = record.SyncStatus === "CONFLICT"
            ? '<button type="button" class="btn btn-sm btn-outline-danger mt-1" data-delete-conflict="' + escInspection(localId) + '">Delete Local Transaction</button>'
            : (record.SyncStatus === "DELETE_PENDING" && record.DeleteOriginalSyncStatus === "VOIDED"
                ? '<button type="button" class="btn btn-sm btn-outline-secondary mt-1" data-edit-delete-reason="' + escInspection(localId) + '">Reason Cancel</button>'
                : "");
        const technicianName = record.TechnicianName && record.TechnicianName !== record.OwnerEmployeeID
            ? record.TechnicianName
            : (record.OwnerEmployeeID === inspectionLogin.employeeid ? inspectionTechnicianName : "");
        const mainRow = '<tr class="inspection-record-main-row">' +
            '<td data-label="Inspection No.">' + numberHtml + '</td>' +
            '<td data-label="Inspection Date/Time">' + escInspection(inspectionDateTime) + '</td>' +
            '<td data-label="Start/End">' + escInspection(startEnd) + '</td>' +
            '<td data-label="Inspection Type">' + escInspection(record.InspectionTypeName || "—") + '</td>' +
            '<td data-label="Location/Area">' + escInspection(record.InspectionTypeDetailName || "—") + '</td>' +
            '<td data-label="Technician">' + escInspection(technicianName || "—") + deleteHtml + '</td>' +
            '</tr>';
        const messageRow = conflictHtml
            ? '<tr class="inspection-grid-message-row"><td colspan="6" class="small" style="white-space:normal;overflow-wrap:anywhere;word-break:break-word;padding-top:0.25rem;padding-bottom:0.5rem;">' + conflictHtml + '</td></tr>'
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
        const result = await inspectionApprovalPost("GetInspectionApprovalDetail", {
            inspectionId: Number(inspectionId), employeeId: inspectionLogin.employeeid
        });
        const h = result.header || {};
        const template = result.template || result.TemplateSnapshot;
        if (!template || !Array.isArray(template.sections) || !template.sections.length) {
            showToast("Struktur template checklist tidak tersedia dari server.", "warning");
            return;
        }
        currentInspectionRecord = null;
        currentInspectionReadOnly = true;
        inspectionPhotoBaseline = null;
        showInspectionInputScreen();
        document.getElementById("inspectionEditorTabs").classList.remove("d-none");
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
            (h.TemplateNo || "-") + " / v" + (h.TemplateVersion || "-"),
            "Jadwal " + (h.ScheduledTime || "-") + " • " + (formatInspectionDateDMY(h.InspectionDate) || "-"),
            formatInspectionClock(h.StartDateTime) + " - " + formatInspectionClock(h.EndDateTime)
        ]);
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
        showInspectionEditorTab("checklist");
        showToast("Detail checklist berhasil dimuat dari server (read-only).", "success");
    } catch (err) {
        showToast("Gagal membuka detail inspeksi dari server. Pastikan koneksi tersedia lalu coba lagi.", "warning");
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
            if (serverRecord.IsApprove != null) record.IsApprove = serverRecord.IsApprove;
        }
    }

    const login = getLoginData();
    if (!login || record.OwnerEmployeeID !== login.employeeid) {
        showToast("Inspeksi ini bukan milik akun yang sedang login.", "danger");
        return;
    }

    currentInspectionRecord = record;
    await renderInspectionForm(record, record.Status === "DONE" && !isVoidedServerInspectionRecord(record));
    if (String(record.InspectionMode || "").toUpperCase() === "BATCH" &&
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
    const mapWorkspace = document.getElementById("inspectionMapWorkspace");
    if (mapWorkspace) mapWorkspace.classList.add("d-none");
    if (typeof window.resetInspectionMapWorkspace === "function")
        await window.resetInspectionMapWorkspace();
    restoreInspectionMasterDropdowns();
    showInspectionInputScreen();
    showToast("Pilih Inspection Type, template, detail inspeksi, lalu jam jadwal. Data tersimpan di perangkat dan hanya disinkronkan oleh teknisi pemiliknya.", "info");
    currentInspectionRecord = null;
    currentInspectionReadOnly = false;
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
    document.getElementById("txtInspectionDate").value = localDateString(new Date());
    document.getElementById("txtInspectionDate").disabled = true;
    showInspectionEditorTab("param");
    updateStartButton();
}

async function closeInspectionForm() {
    if (inspectionAutoSaveTimer) {
        clearTimeout(inspectionAutoSaveTimer);
        inspectionAutoSaveTimer = null;
    }
    const closingRecord = currentInspectionRecord;
    const closingBatch = closingRecord &&
        String(closingRecord.InspectionMode || "").toUpperCase() === "BATCH";
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
    if (p) {
        const mapWorkspace = document.getElementById("inspectionMapWorkspace");
        if (mapWorkspace) mapWorkspace.classList.add("d-none");
    }
    const isBatch = currentInspectionRecord &&
        String(currentInspectionRecord.InspectionMode || "").toUpperCase() === "BATCH";
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
        String(currentInspectionRecord.InspectionMode || "").toUpperCase() === "BATCH";
    const hasSelectedPoint = !isBatch || Number(currentInspectionRecord.ActiveInspectionPointID || 0) > 0;
    const complete = (currentInspectionReadOnly || isInspectionParameterSelectionComplete()) && hasSelectedPoint;
    button.disabled = !complete;
    button.classList.toggle("disabled", !complete);
    button.setAttribute("aria-disabled", complete ? "false" : "true");
    button.title = !hasSelectedPoint
        ? "Pilih Inspection Point dari MAP terlebih dahulu."
        : (complete ? "" : "Lengkapi semua parameter inspeksi terlebih dahulu.");
}
function setInspectionFormHeader(transactionNo, infoLines) {
    const title = document.getElementById("inspectionFormTitle");
    const infoButton = document.getElementById("btnInspectionFormInfo");
    if (title) title.textContent = transactionNo || "Inspection";
    if (!infoButton || !window.bootstrap || !bootstrap.Popover) return;
    const existing = bootstrap.Popover.getInstance(infoButton);
    if (existing) existing.dispose();
    const content = (infoLines || []).filter(Boolean).map(line =>
        '<div class="mb-1">' + escInspection(line) + '</div>'
    ).join("");
    infoButton.disabled = !content;
    if (!content) return;
    bootstrap.Popover.getOrCreateInstance(infoButton, {
        container: "body",
        trigger: "focus",
        placement: "bottom",
        html: true,
        content: content
    });
}

function populateInspectionParameters(record) {
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
    onInspectionDetailChanged();
    scheduleTimeSelect.value = record.ScheduledTime || "";
    refreshInspectionScheduleOptions();

    document.getElementById("txtInspectionDate").value = record.InspectionDate || localDateString(new Date());
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
        populateInspectionParameters(currentInspectionRecord);
        updateInspectionParameterTabGate();
        return false;
    }

    const record = currentInspectionRecord;
    const changed = String(record.SectionID || "") !== String(type.SectionID || "") ||
        String(record.InspectionTypeCode || "") !== String(type.InspectionTypeCode || "") ||
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
            populateInspectionParameters(record);
            updateInspectionParameterTabGate();
            return false;
        }
    }

    Object.assign(record, {
        SectionID: type.SectionID,
        InspectionTypeCode: type.InspectionTypeCode,
        InspectionTypeName: type.InspectionTypeName,
        InspectionTypeDetailCode: detail.InspectionTypeDetailCode,
        InspectionTypeDetailName: detail.InspectionTypeDetailName,
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
    if (String(record.InspectionMode || "").toUpperCase() !== "BATCH" ||
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
        document.getElementById(type === "BEFORE" ? "btnAddInspectionBeforePhoto" : "btnAddInspectionAfterPhoto").disabled = input.disabled;
        document.getElementById(type === "BEFORE" ? "inspectionBeforePhotoCount" : "inspectionAfterPhotoCount").textContent = count + " foto";
    }
}

async function handleInspectionPhotoListClick(event) {
    const deleteButton = event.target.closest("[data-delete-inspection-photo]");
    if (deleteButton) {
        await handleInspectionPhotoDelete(event);
        return;
    }
    const photoItem = event.target.closest(".inspection-photo-item");
    if (!photoItem) return;
    await openInspectionPhotoViewer(photoItem.dataset.photoType, photoItem.dataset.photoId);
}

async function openInspectionPhotoViewer(type, photoId) {
    if (type !== "BEFORE" && type !== "AFTER" || !currentInspectionRecord) return;
    const allPhotos = await getCurrentInspectionPhotos();
    const photos = allPhotos.filter(photo => photo.Type === type);
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

async function handleInspectionPhotoInput(event, type) {
    const input = event.target;
    const files = Array.from(input.files || []);
    input.value = "";
    if (!currentInspectionRecord || currentInspectionReadOnly || !files.length) return;
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
            const blob = await compressImage(file, {
                maxWidth: 640, maxHeight: 640, maxSize: 100 * 1024, quality: .70, minQuality: .25
            });
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
    document.getElementById("inspectionRecordsPanel").classList.add("d-none");
    document.getElementById("inspectionInputPanel").classList.remove("d-none");
    document.getElementById("btnBackToInspectionRecords").classList.remove("d-none");
    document.getElementById("btnBackToInspectionApprovalList").classList.add("d-none");
}

function showInspectionRecordsScreen() {
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
        loadInspectionApprovalQueue();
    });
    addInspectionApprovalListener("selApprovalDetail", "change", function () {
        document.getElementById("selApprovalTemplate").value = "";
        loadInspectionApprovalQueue();
    });
    ["selApprovalTemplate", "txtApprovalDateFrom", "txtApprovalDateThru"].forEach(id =>
        addInspectionApprovalListener(id, "change", loadInspectionApprovalQueue));
    addInspectionApprovalListener("btnApprovalSelectAll", "click", function () {
        document.querySelectorAll("#inspectionApprovalQueue [data-approval-select]").forEach(box => { box.checked = true; });
        updateInspectionApprovalSelectAll();
    });
    addInspectionApprovalListener("chkAllInspectionApproval", "change", function () {
        document.querySelectorAll("#inspectionApprovalQueue [data-approval-select]").forEach(box => { box.checked = this.checked; });
        updateInspectionApprovalSelectAll();
    });
    addInspectionApprovalListener("btnBatchApproveInspection", "click", () => openInspectionApprovalAction("APPROVE", true));
    addInspectionApprovalListener("btnBatchVoidInspection", "click", () => openInspectionApprovalAction("VOID", true));
    addInspectionApprovalListener("btnApproveInspection", "click", () => processInspectionApproval("APPROVE"));
    addInspectionApprovalListener("btnVoidInspection", "click", () => openInspectionApprovalAction("VOID", false));
    addInspectionApprovalListener("btnConfirmInspectionApprovalAction", "click", confirmInspectionApprovalAction);

    const today = localDateString(new Date());
    ["txtApprovalDateFrom", "txtApprovalDateThru"].forEach(id => {
        const input = document.getElementById(id);
        if (input && !input.value) input.value = today;
    });
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
    if (batchActions) batchActions.classList.toggle("d-none", !outstanding);
    const selectAllHeader = document.getElementById("thInspectionApprovalSelectAll");
    if (selectAllHeader) selectAllHeader.classList.toggle("d-none", !outstanding);
    const dateFilters = document.getElementById("inspectionApprovalDateFilters");
    if (dateFilters) dateFilters.classList.toggle("d-none", !approved);
    if (reload === false) renderInspectionApprovalQueue();
    else loadInspectionApprovalQueue();
}

function updateInspectionApprovalCounts() {
    const outstandingCount = inspectionApprovalRows.filter(row => !isInspectionApprovalApproved(row) && !isInspectionApprovalVoided(row)).length;
    const approvedCount = inspectionApprovalRows.filter(isInspectionApprovalApproved).length;
    const voidCount = inspectionApprovalRows.filter(isInspectionApprovalVoided).length;
    const outstandingElement = document.getElementById("inspectionApprovalOutstandingCount");
    const approvedElement = document.getElementById("inspectionApprovalApprovedCount");
    const voidElement = document.getElementById("inspectionApprovalVoidCount");
    if (outstandingElement) outstandingElement.textContent = String(outstandingCount);
    if (approvedElement) approvedElement.textContent = String(approvedCount);
    if (voidElement) voidElement.textContent = String(voidCount);
}

function isInspectionApprovalApproved(row) {
    return !!row && (row.IsApprove === true || row.IsApprove === 1 || String(row.IsApprove).toLowerCase() === "true" || String(row.IsApprove) === "1");
}

function isInspectionApprovalVoided(row) {
    return !!row &&
        !isInspectionApprovalApproved(row) &&
        !!String(row.ReasonVoid || "").trim() &&
        !!String(row.ApprovedBy || "").trim() &&
        !!row.ApprovedDate &&
        String(row.ApprovedDate).indexOf("1900") !== 0;
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
    host.innerHTML = '<tr><td colspan="8" class="text-muted py-2">Memuat dari server...</td></tr>';
    selectedInspectionApproval = null;
    if (!navigator.onLine) {
        showToast("Approval Supervisor memerlukan koneksi ke server. Mode approval offline belum didukung.", "warning");
        host.innerHTML = '<tr><td colspan="8" class="text-muted py-2">Hubungkan internet lalu tekan Refresh.</td></tr>';
        document.getElementById("inspectionApprovalDetail").innerHTML = '<div class="text-muted">Detail approval hanya dapat dibuka saat online.</div>';
        return;
    }
    document.getElementById("inspectionApprovalDetail").innerHTML = '<div class="text-muted">Pilih inspeksi untuk melihat detail checklist.</div>';
    try {
        const dateFrom = document.getElementById("txtApprovalDateFrom");
        const dateThru = document.getElementById("txtApprovalDateThru");
        const result = await inspectionApprovalPost("GetInspectionApprovalQueue", {
            employeeId: inspectionLogin.employeeid,
            companyId: inspectionCompanyID,
            locationId: inspectionLocationID,
            approvalTab: currentInspectionApprovalTab,
            dateFrom: dateFrom ? dateFrom.value : "",
            dateThru: dateThru ? dateThru.value : "",
            inspectionTypeCode: document.getElementById("selApprovalType").value,
            inspectionTypeDetailCode: document.getElementById("selApprovalDetail").value,
            templateId: document.getElementById("selApprovalTemplate").value
        });
        if (requestSequence !== inspectionApprovalLoadSequence) return;
        inspectionApprovalRows = result.data || [];
        populateInspectionApprovalFilters(result.filters || []);
        updateInspectionApprovalCounts();
        renderInspectionApprovalQueue();
    } catch (err) {
        if (requestSequence !== inspectionApprovalLoadSequence) return;
        host.innerHTML = '<tr><td colspan="8" class="text-danger py-2">' + escInspection(err.message || "Gagal memuat antrean approval.") + '</td></tr>';
    }
}

function populateInspectionApprovalFilters(filterRows) {
    const specs = [
        { id: "selApprovalType", key: "InspectionTypeCode", label: "InspectionTypeName", all: "All types" },
        { id: "selApprovalDetail", key: "InspectionTypeDetailCode", label: "InspectionTypeDetailName", all: "All details" },
        { id: "selApprovalTemplate", key: "IDTemplate", label: "TemplateNo", all: "All templates" }
    ];
    const rows = Array.isArray(filterRows) ? filterRows : [];
    const selectedType = document.getElementById("selApprovalType").value;
    const selectedDetail = document.getElementById("selApprovalDetail").value;
    specs.forEach(spec => {
        const select = document.getElementById(spec.id);
        if (!select) return;
        const previous = select.value;
        const applicableRows = rows.filter(row => {
            if (spec.id !== "selApprovalType" && selectedType && String(row.InspectionTypeCode || "") !== selectedType) return false;
            if (spec.id === "selApprovalTemplate" && selectedDetail && String(row.InspectionTypeDetailCode || "") !== selectedDetail) return false;
            return true;
        });
        const values = new Map();
        applicableRows.forEach(row => {
            const key = String(row[spec.key] == null ? "" : row[spec.key]);
            if (key && !values.has(key)) values.set(key, String(row[spec.label] || key));
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

function renderInspectionApprovalQueue() {
    const host = document.getElementById("inspectionApprovalQueue");
    if (!host) return;
    const rows = inspectionApprovalRows.filter(row => {
        if (currentInspectionApprovalTab === "APPROVED") return isInspectionApprovalApproved(row);
        if (currentInspectionApprovalTab === "VOID") return isInspectionApprovalVoided(row);
        return !isInspectionApprovalApproved(row) && !isInspectionApprovalVoided(row);
    });
    const hasSelectionColumn = currentInspectionApprovalTab === "OUTSTANDING";
    if (!rows.length) {
        host.innerHTML = '<tr><td colspan="' + (hasSelectionColumn ? "8" : "7") + '" class="text-muted py-3 text-center">Tidak ada inspeksi untuk filter ini.</td></tr>';
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
        if (indicator) indicator.textContent = active ? (inspectionApprovalSort.direction === "asc" ? " ▲" : " ▼") : " ↕";
        th.setAttribute("aria-sort", active ? (inspectionApprovalSort.direction === "asc" ? "ascending" : "descending") : "none");
    });
    host.innerHTML = sortedRows.map(row => {
        const id = Number(row.InspectionID);
        const start = formatInspectionClock(row.StartDateTime);
        const end = formatInspectionClock(row.EndDateTime);
        const range = (start && start !== "-" ? start : "-") + " – " + (end && end !== "-" ? end : "-");
        const selectCell = hasSelectionColumn
            ? '<td class="approval-select-cell"><input type="checkbox" class="form-check-input" data-approval-select value="' + id + '" aria-label="Select inspection ' + escInspection(row.InspectionNo || id) + '"></td>'
            : '';
        return '<tr>' +
            selectCell +
            '<td data-label="Transaction No."><button type="button" class="btn btn-link p-0 text-wrap fw-semibold" data-approval-id="' + id + '">' + escInspection(row.InspectionNo || ("Inspection #" + id)) + '</button></td>' +
            '<td data-label="Inspection Type">' + escInspection(row.InspectionTypeName || row.InspectionTypeCode || "") + '</td>' +
            '<td data-label="Inspection Detail">' + escInspection(row.InspectionTypeDetailName || row.InspectionTypeDetailCode || "") + '</td>' +
            '<td data-label="Date">' + escInspection(formatInspectionDateDMY(row.InspectionDate) || "") + '</td>' +
            '<td data-label="Scheduled">' + escInspection(row.ScheduledTime || "-") + '</td>' +
            '<td data-label="Start – End">' + escInspection(range) + '</td>' +
            '<td data-label="Technician">' + escInspection(row.TechnicianName || row.OwnerEmployeeName || row.OwnerEmployeeID || "") + '</td>' +
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
    if (preview) preview.disabled = currentInspectionApprovalTab !== "OUTSTANDING" || selectedBoxes.length === 0;
}

async function previewSelectedInspections() {
    const rows = getSelectedInspectionApprovalRows();
    if (!validateSelectedInspectionApprovalType(rows)) return;
    if (!navigator.onLine) {
        showToast("Preview report memerlukan koneksi ke server.", "warning");
        return;
    }
    try {
        const response = await fetch("R_Reports.aspx/GenerateReport", {
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
        window.location.href = result.filePath;
    } catch (err) {
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

async function executeInspectionApprovalAction(ids, action, remark) {
    const isSingleVoid = action === "VOID" && ids.length === 1 &&
        selectedInspectionApproval && Number(selectedInspectionApproval.InspectionID) === Number(ids[0]);
    try {
        const result = await inspectionApprovalPost("ProcessInspectionApprovalBatch", {
            inspectionIds: ids,
            action: action,
            employeeId: inspectionLogin.employeeid,
            companyId: inspectionCompanyID,
            locationId: inspectionLocationID,
            remark: remark
        });
        if (isSingleVoid) showInspectionApprovalQueueView();
        await loadInspectionApprovalQueue();
        showToast((result.count || ids.length) + " inspeksi berhasil diproses.", "success");
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

async function renderInspectionApprovalBatchMap(maps, points) {
    const host = document.getElementById("inspectionApprovalBatchMap");
    if (!host) return;
    maps = Array.isArray(maps) ? maps : [];
    points = Array.isArray(points) ? points : [];
    if (!points.length) { host.innerHTML = ""; return; }

    const hasAnyFloorPlan = maps.some(map => !!String(map.MapUrl || "").trim());
    host.innerHTML = '<div class="border rounded-3 p-3 mb-3">' +
        '<div class="d-flex align-items-center justify-content-between gap-2 mb-2 flex-wrap">' +
            '<div><div class="fw-bold"><i class="bi bi-clipboard2-check me-2"></i>BATCH INSPECTION REVIEW</div><small class="text-muted">' + points.length + ' inspected point(s)</small></div>' +
            (maps.length > 1 ? '<select id="inspectionApprovalMapSelect" class="form-select form-select-sm" style="max-width:260px">' +
                maps.map(map => '<option value="' + escInspection(map.MapID) + '">' + escInspection(map.MapCode + " - " + map.MapName) + '</option>').join("") +
             '</select>' : '') +
        '</div>' +
        (hasAnyFloorPlan ? '<details class="mb-3" open><summary class="small fw-semibold text-primary py-2">Denah inspeksi (opsional)</summary><div id="inspectionApprovalMapStage" class="inspection-map-pdf-stage mt-2"><canvas id="inspectionApprovalMapCanvas"></canvas><div id="inspectionApprovalMapPoints" class="inspection-map-points"></div></div></details>' :
            '<div class="alert alert-light small">Batch ini tidak menggunakan file denah. Seluruh hasil diperiksa melalui daftar Inspection Point.</div>') +
        '<div id="inspectionApprovalPointCounters"></div>' +
        '<div class="d-flex flex-wrap gap-2 align-items-center mb-2"><div class="btn-group btn-group-sm flex-wrap" id="inspectionApprovalPointFilters" role="group" aria-label="Filter status point">' +
            '<button type="button" class="btn btn-outline-secondary active" data-approval-filter="ALL" aria-pressed="true">Semua</button>' +
            (points.some(point => isInspectionFlagEnabled(point.IsNormalAbnormalRequired, false)) ? '<button type="button" class="btn btn-outline-danger" data-approval-filter="ABNORMAL" aria-pressed="false">Abnormal</button><button type="button" class="btn btn-outline-success" data-approval-filter="NORMAL" aria-pressed="false">Normal</button>' : '') +
            (points.some(point => !isInspectionFlagEnabled(point.IsNormalAbnormalRequired, false)) ? '<button type="button" class="btn btn-outline-primary" data-approval-filter="DONE" aria-pressed="false">Selesai</button>' : '') +
            '<button type="button" class="btn btn-outline-warning" data-approval-filter="INCOMPLETE" aria-pressed="false">Belum lengkap</button>' +
        '</div><div class="inspection-point-list-tools flex-grow-1"><input type="search" id="inspectionApprovalPointSearch" class="form-control form-control-sm" placeholder="Cari Point Code / Name..."></div></div>' +
        '<div id="inspectionApprovalPointList" class="border rounded overflow-hidden"></div>' +
        '<div class="mt-3" id="inspectionApprovalSelectedPointHost"></div>' +
    '</div>';

    const listHost = document.getElementById("inspectionApprovalPointList");
    const photos = window._inspectionApprovalBatchData && Array.isArray(window._inspectionApprovalBatchData.photos)
        ? window._inspectionApprovalBatchData.photos : [];
    let approvalPage = 1;
    let approvalFilter = "ALL";
    let selectedPointId = points.length ? String(points[0].InspectionPointTransactionID) : "";
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
        const filtered = points.filter(point => {
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
        const counters = { ALL: points.length, ABNORMAL: 0, NORMAL: 0, DONE: 0, INCOMPLETE: 0 };
        points.forEach(point => counters[pointState(point).status]++);

        const counterHost = document.getElementById("inspectionApprovalPointCounters");
        if (counterHost) {
            const hasNormalAbnormal = points.some(point => isInspectionFlagEnabled(point.IsNormalAbnormalRequired, false));
            const hasDoneOnly = points.some(point => !isInspectionFlagEnabled(point.IsNormalAbnormalRequired, false));
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

    if (!maps.length || !hasAnyFloorPlan) return;
    const select = document.getElementById("inspectionApprovalMapSelect");
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
            const mapPoints = points.filter(point =>
                Number(point.MapID) === Number(map.MapID) && point.MapX != null && point.MapY != null);
            overlay.innerHTML = mapPoints.map(point => {
                const x = Math.max(0, Math.min(100, Number(point.MapX) || 0));
                const y = Math.max(0, Math.min(100, Number(point.MapY) || 0));
                const conditionRequired = isInspectionFlagEnabled(point && point.IsNormalAbnormalRequired, false);
                const pointHasAbnormalItem = conditionRequired && Array.isArray(point.Items) && point.Items.some(item =>
                    item.IsAnomali === true || item.IsAnomali === 1 || String(item.IsAnomali || "") === "1");
                const visualStatus = conditionRequired && (
                    String(point.Status || "").toUpperCase() === "ABNORMAL" ||
                    String(point.AbnormalRemark || "").trim() || pointHasAbnormalItem)
                    ? "abnormal" : String(point.Status || "PENDING").toLowerCase();
                return '<button type="button" class="inspection-map-point ' + visualStatus + '" style="left:' + x + '%;top:' + y + '%" data-approval-point-target="' + escInspection(point.InspectionPointTransactionID) + '" title="' + escInspection(point.PointCode + " - " + point.PointName) + '"><span class="inspection-map-point-dot"></span><span class="inspection-map-point-label">' + escInspection(point.PointCode) + '</span></button>';
            }).join("");
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
    if (select) select.addEventListener("change", function () { renderMap(selectedMap()); });
    await renderMap(selectedMap());
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
        const isBatchApproval = String(h.InspectionMode || "").toUpperCase() === "BATCH";
        const approvalTabButton = document.getElementById(isBatchApproval
            ? "inspectionApprovalChecklistTab" : "inspectionApprovalParamTab");
        if (approvalTabButton && window.bootstrap && bootstrap.Tab)
            bootstrap.Tab.getOrCreateInstance(approvalTabButton).show();
        window.currentInspectionApprovalPhotos = photos;
        const start = formatInspectionClock(h.StartDateTime);
        const end = formatInspectionClock(h.EndDateTime);
        document.getElementById("inspectionApprovalDetailSubtitle").textContent =
            (h.InspectionNo || ("Inspection #" + h.InspectionID)) + " • " +
            formatInspectionDateDMY(h.InspectionDate) + " • " + (h.ScheduledTime || "-") + " • " + start + " – " + end;
        document.getElementById("inspectionApprovalParameters").innerHTML =
            '<div class="row g-3">' +
            '<div class="col-12 col-md-6"><div class="border rounded p-3 h-100"><div class="fw-semibold mb-2">Inspection Parameters</div>' +
            '<div><strong>Transaction No.:</strong> ' + escInspection(h.InspectionNo || "-") + '</div>' +
            '<div><strong>Inspection Type:</strong> ' + escInspection(h.InspectionTypeName || "-") + '</div>' +
            '<div><strong>Type Detail:</strong> ' + escInspection(h.InspectionTypeDetailName || "-") + '</div>' +
            '<div><strong>Date:</strong> ' + escInspection(formatInspectionDateDMY(h.InspectionDate) || "-") + '</div>' +
            '<div><strong>Scheduled:</strong> ' + escInspection(h.ScheduledTime || "-") + '</div>' +
            '<div><strong>Start – End:</strong> ' + escInspection(start) + ' – ' + escInspection(end) + '</div>' +
            '<div><strong>Technician:</strong> ' + escInspection(h.TechnicianName || h.OwnerEmployeeName || h.OwnerEmployeeID || "-") + '</div>' +
            '<div><strong>Section:</strong> ' + escInspection(h.SectionID || "-") + '</div></div></div>' +
            '<div class="col-12 col-md-6"><div class="border rounded p-3 h-100"><div class="fw-semibold mb-2">Inspection Template</div>' +
            '<div><strong>Template:</strong> ' + escInspection(h.TemplateNo || "-") + ' / v' + escInspection(h.TemplateVersion || "-") + '</div>' +
            '</div></div></div>';
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
            (isBatchApproval ? "" : afterPhotoHtml) + checklistHtml + followUpHtml + summaryHtml + reasonVoidHtml;
        if (isBatchApproval) renderInspectionApprovalBatchMap(batchMaps, batchPoints);
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
        showToast("Approval tidak dapat diproses offline. Hubungkan internet lalu coba lagi.", "warning");
        return;
    }
    const confirmed = await showConfirmation({
        title: "Approve Inspeksi",
        message: "Approve inspeksi ini?",
        yesText: "Approve"
    });
    if (!confirmed) return;
    const remark = document.getElementById("txtInspectionApprovalRemark").value.trim();
    try {
        const approvalResult = await inspectionApprovalPost("ProcessInspectionApproval", {
            inspectionId: Number(selectedInspectionApproval.InspectionID), action: "APPROVE",
            employeeId: inspectionLogin.employeeid, companyId: inspectionCompanyID,
            locationId: inspectionLocationID, remark: remark
        });
        showInspectionApprovalQueueView();
        showToast(approvalResult.followUpWONo
            ? "Inspection berhasil di-approve. Internal WO " + approvalResult.followUpWONo + " dibuat untuk Follow Up."
            : "Inspection berhasil di-approve.", "success");
        await loadInspectionApprovalQueue();
    } catch (err) {
        showToast(err.message || "Gagal memproses approval.", "warning");
    }
}

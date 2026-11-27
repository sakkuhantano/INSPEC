# INSPEC Scheduled STANDARD Chief Batch

## Behaviour
- SQL Server Agent calls existing `Login.aspx?task=scheduledChiefBatch` via HTTPS POST. `Site1.Master` is untouched; Login.aspx has no Site1.Master.
- HMAC-SHA256, a five-minute timestamp window, and a one-use 32-hex nonce authenticate the server request and reject replay.
- Scheduler requires active INSPEC administrator NIK `sa`, scans all Company/Location/Section scopes containing eligible STANDARD inspections, and creates no browser session.
- Manual SPV and scheduled submission call one shared C# batch processor. The normal manual SPV authorization path remains in place.
- Eligibility: active, DONE, submitted, SPV-approved, STANDARD, not void, and ApprovalBatchID is NULL.
- Existing SQL batch rules limit a batch to one InspectionDate and 200 inspections. Therefore scheduler processes Company + Location + Section + InspectionDate groups in chunks of 200. Each batch still produces one XLSX per InspectionTypeCode.
- Scheduled sender is SysWebCommonValue AppID='pip', CommonGroup='AutoEmail', IsDelete=0: GroupDescription=From Name, Description=From Email. Manual sender remains the SPV employee.
- Section/date failures are isolated and logged. Batches already created are not picked again; failed notification is recorded as EmailStatus=FAILED and is not blindly auto-resent.

## Deployment order
1. Deploy updated `Login.aspx.cs`, `Secure/inspection.aspx.cs`, and merge the scheduler appSettings from repository `Web.config` into live Web.config. Do not overwrite live database/SMTP settings.
2. Run `Database/StandardInspection_ApprovalBatch.sql` (updated create procedure has @p_IsScheduled).
3. Run `Database/StandardInspection_ApprovalBatch_Void.sql` to enable Chief partial/full Void while a batch is Pending. This adds the VOID batch state and the guarded `spUTL_PIP_T_Inspection_ApprovalBatch_Void` procedure.
4. Run `Database/InspectionScheduledChiefBatch.sql` (nonce, lock and run log objects).
5. Confirm NIK `sa` is active in SysWebUser and belongs to UserGroupID='administrator'.
6. Confirm all target STANDARD workflow/Chief COMVALs and one global AutoEmail sender with valid From Name/From Email.
7. Copy both PowerShell scripts to the SQL Agent host. Run Prepare script as SQL Agent service account/job proxy to create the DPAPI encrypted secret file. Copy the one-time printed key to live Web.config key INSPECSchedulerHmacSecret. Restrict ACLs.
8. Set INSPECSchedulerAllowedIPs to the SQL Agent IP where stable/visible to IIS. Empty disables IP filtering but HMAC remains mandatory.
9. Edit HTTPS URL and file paths in Create_INSPEC_ScheduledChiefBatch_AgentJob.sql and execute in msdb. SQL Agent uses server-local time; ensure host timezone is WIB (UTC+7).

## Validation
- Invalid/missing HMAC and replayed nonce are rejected; GET is 405 and HTTP is 403.
- Review INSPEC_SchedulerRunLog and INSPEC_SchedulerSectionLog after test.
- Verify unapproved rows are not assigned, mixed InspectionTypeCode reports are separate XLSX files, and Chief recipients follow existing ProfitCenter/COMVAL.
- Verify manual SPV Submit Batch still works through normal login and SPV COMVAL.
- In a Pending batch, test Void Selected for one and multiple inspections; confirm only selected members return as technician DRAFT and remaining members stay Pending.
- Test Void Entire Batch; confirm all members return as technician DRAFT and the batch status becomes VOID.
- Approve a test batch, then verify the Void UI is hidden and the SQL procedure rejects any Void attempt against the Approved batch.
- Sync a returned DRAFT as its technician, correct checklist data, submit again, and verify it re-enters SPV approval and can be batched again.

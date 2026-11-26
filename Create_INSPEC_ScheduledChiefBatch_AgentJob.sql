/* Daily 23:00 server-local schedule. Edit deployment values before execution. */
USE msdb;
GO
DECLARE @JobName SYSNAME = N'INSPEC - Scheduled Chief Batch';
DECLARE @EndpointUrl NVARCHAR(500) = N'https://<INSPEC-HOST>/<APP-PATH>/Login.aspx?task=scheduledChiefBatch';
DECLARE @ScriptPath NVARCHAR(260) = N'C:\INSPEC\RunScheduledChiefBatch.ps1';
DECLARE @SecretFile NVARCHAR(260) = N'C:\INSPEC\INSPEC-SchedulerSecret.dpapi';
DECLARE @Command NVARCHAR(2000);
DECLARE @JobId BINARY(16);
IF @EndpointUrl LIKE N'%<INSPEC-HOST>%' OR @EndpointUrl LIKE N'%<APP-PATH>%'
BEGIN
    RAISERROR('Edit @EndpointUrl with the deployed HTTPS Login.aspx URL before creating the job.',16,1);
    RETURN;
END;
SET @Command = N'powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    @ScriptPath + N'" -Url "' + @EndpointUrl + N'" -SecretFile "' + @SecretFile + N'"';
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name=@JobName)
    EXEC dbo.sp_delete_job @job_name=@JobName, @delete_unused_schedule=1;
EXEC dbo.sp_add_job @job_name=@JobName,@enabled=1,
    @description=N'Runs INSPEC scheduled STANDARD inspection batch submission to Chief.',
    @start_step_id=1,@owner_login_name=N'sa',@job_id=@JobId OUTPUT;
EXEC dbo.sp_add_jobstep @job_id=@JobId,@step_id=1,
    @step_name=N'Call INSPEC scheduled batch gateway',@subsystem=N'CmdExec',
    @command=@Command,@on_success_action=1,@on_fail_action=2,@retry_attempts=0;
EXEC dbo.sp_add_jobschedule @job_id=@JobId,@name=N'Daily at 23:00 WIB',@enabled=1,
    @freq_type=4,@freq_interval=1,@freq_subday_type=1,@freq_subday_interval=0,
    @freq_relative_interval=0,@freq_recurrence_factor=1,@active_start_time=230000;
EXEC dbo.sp_add_jobserver @job_id=@JobId;
GO

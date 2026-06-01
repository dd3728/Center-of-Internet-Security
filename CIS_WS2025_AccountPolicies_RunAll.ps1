<#
================================================================================
SCRIPT:      CIS_WS2025_AccountPolicies_RunAll.ps1
PURPOSE:     Orchestrator - runs both CIS Section 1.1 (Password Policy) and
             Section 1.2 (Account Lockout Policy) scripts in sequence.

             Also contains GPMC-based method (via Set-GPRegistryValue / 
             GroupPolicy module) as an ALTERNATIVE for environments where 
             importing .inf files via GPMC GUI is not preferred.

TARGET:      Windows Server 2025 - Domain Controller and Member Servers
POWERSHELL:  5.1 (Build 26100, Revision 7462)

HOW TO RUN:
  Option A - Direct PowerShell (recommended for initial testing):
    1. Open PowerShell as Administrator on a DC or admin workstation
    2. Set execution policy if needed:
         Set-ExecutionPolicy RemoteSigned -Scope LocalMachine
    3. Run:
         .\CIS_WS2025_AccountPolicies_RunAll.ps1

  Option B - GPO Startup Script:
    1. Open GPMC
    2. Edit Default Domain Policy (or a dedicated CIS GPO)
    3. Computer Configuration > Policies > Windows Settings > Scripts
       > Startup > Add
    4. Browse to this script location (must be in SYSVOL or network share
       accessible to the computer account)
    5. Ensure the computer account has read rights to the script share

  Option C - Remote execution (run from admin workstation against a target DC):
    Invoke-Command -ComputerName DC01 -FilePath .\CIS_WS2025_AccountPolicies_RunAll.ps1

IMPORTANT: These scripts apply settings to the LOCAL security database.
For domain-wide effect, the generated .inf files must be imported into
the Default Domain Policy GPO via GPMC (see individual script instructions).
================================================================================
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RunnerLog = "$env:SystemRoot\Temp\CIS_RunAll_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-RunnerLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $RunnerLog -Value $line -Encoding UTF8
}

Write-RunnerLog "======================================================================"
Write-RunnerLog "CIS WS2025 Account Policies - Orchestrator Start"
Write-RunnerLog "Running as: $($env:USERDOMAIN)\$($env:USERNAME) on $($env:COMPUTERNAME)"
Write-RunnerLog "======================================================================"

# Resolve paths - assumes all three scripts are in the same directory
$ScriptDir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$PwdScript      = Join-Path $ScriptDir 'CIS_WS2025_AccountPolicies_PasswordPolicy.ps1'
$LockoutScript  = Join-Path $ScriptDir 'CIS_WS2025_AccountPolicies_LockoutPolicy.ps1'

foreach ($script in @($PwdScript, $LockoutScript)) {
    if (-not (Test-Path $script)) {
        Write-RunnerLog "FATAL: Required script not found: $script" 'ERROR'
        Write-RunnerLog "Ensure all three scripts are in the same directory." 'ERROR'
        exit 1
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Run Section 1.1 - Password Policy
# ─────────────────────────────────────────────────────────────────────────────
Write-RunnerLog "--- Running: CIS Section 1.1 Password Policy ---"
try {
    & $PwdScript
    Write-RunnerLog "Section 1.1 Password Policy script completed."
}
catch {
    Write-RunnerLog "Section 1.1 script threw an exception: $_" 'ERROR'
    Write-RunnerLog "Halting. Review the error before running Section 1.2." 'ERROR'
    exit 1
}

Start-Sleep -Seconds 2   # Brief pause between scripts

# ─────────────────────────────────────────────────────────────────────────────
# Run Section 1.2 - Account Lockout Policy
# ─────────────────────────────────────────────────────────────────────────────
Write-RunnerLog "--- Running: CIS Section 1.2 Account Lockout Policy ---"
try {
    & $LockoutScript
    Write-RunnerLog "Section 1.2 Account Lockout Policy script completed."
}
catch {
    Write-RunnerLog "Section 1.2 script threw an exception: $_" 'ERROR'
    exit 1
}

Write-RunnerLog "======================================================================"
Write-RunnerLog "CIS WS2025 Account Policies - Orchestrator Complete"
Write-RunnerLog "Runner log: $RunnerLog"
Write-RunnerLog ""
Write-RunnerLog "REMINDER - For domain-wide application of ALL settings:"
Write-RunnerLog "  1. Open GPMC on a Domain Controller"
Write-RunnerLog "  2. Edit 'Default Domain Policy'"
Write-RunnerLog "  3. Computer Configuration > Windows Settings > Security Settings"
Write-RunnerLog "  4. Right-click Security Settings > Import Policy"
Write-RunnerLog "  5. Import the generated .inf files from:"
Write-RunnerLog "       $env:SystemRoot\Temp\CIS_PasswordPolicy_*.inf"
Write-RunnerLog "       $env:SystemRoot\Temp\CIS_LockoutPolicy_*.inf"
Write-RunnerLog "  6. Verify settings in the GPME editor match CIS values"
Write-RunnerLog "  7. Run: gpupdate /force (on all targeted machines)"
Write-RunnerLog "======================================================================"

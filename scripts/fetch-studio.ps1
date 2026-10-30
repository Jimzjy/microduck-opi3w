<#
.SYNOPSIS
  按固定 commit 稀疏拉取 microduck-replica 的 software/studio（可选推到板子上）。

.DESCRIPTION
  只下载 software/studio 这一个目录，不动其余 240MB。默认落在 <本仓>/vendor/microduck-replica，
  该目录已被 .gitignore 忽略，不会进我们的仓库。
  上游许可：software/studio 是 Apache-2.0；同仓的 *.md 与 3D 网格是 CC BY-NC-SA，本脚本不拉它们。
  网络不稳会自动重试（默认 3 次，每次失败清掉半成品重来）；仍失败可换 -NoProxy 直连。

.EXAMPLE
  .\fetch-studio.ps1
  .\fetch-studio.ps1 -PushTo radxa@192.168.1.23
  .\fetch-studio.ps1 -NoProxy
#>
[CmdletBinding()]
param(
    [string]$Commit = '0b463c56d9abb649854774a9439f9b863510b643',
    [string]$Remote = 'https://github.com/fanhao375/microduck-replica.git',
    [string]$Dest   = '',
    [string]$Proxy  = 'http://127.0.0.1:10808',
    [switch]$NoProxy,
    [int]$Retries = 3,
    # user@host ；给了就顺手 scp 到板子的 home 下
    [string]$PushTo = '',
    [string]$RemoteDir = ''   # 默认 /home/<user>/studio-dev
)

$ErrorActionPreference = 'Stop'

# ---- 定位本仓根（scripts/ 的上一级）----
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Dest) { $Dest = Join-Path $repoRoot 'vendor/microduck-replica' }

function Get-GitExe {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { throw '找不到 git，先装 Git for Windows 并加入 PATH。' }
    return $git.Source
}
$gitExe = Get-GitExe

# 只接受 http(s)：--filter=blob:none 走本地路径/file:// 时 git 会退化成「每个 blob 单独起一个
# upload-pack 进程」的懒拉取，几百个进程、几分钟也拉不完（实测）。需要本地源就先把别处的
# 完整克隆当源，或改用 -Dest 指向已有仓库（脚本会走 fetch 分支）。
if ($Remote -notmatch '^(https?)://') {
    throw "Remote 必须是 http(s) 地址（当前：$Remote）。本地测试请用 -Dest 指向已有的克隆。"
}

$gitArgs = @()
if (-not $NoProxy -and $Proxy) {
    $gitArgs += @('-c', "http.proxy=$Proxy", '-c', "https.proxy=$Proxy")
    Write-Host "使用代理: $Proxy" -ForegroundColor DarkGray
}

function Invoke-Git {
    param([string[]]$ArgList)
    & $gitExe @gitArgs @ArgList
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "git $($ArgList[0]) 失败（exit $code）" }
}

# 判定一个目录是不是可用的仓库
function Test-Repo {
    param([string]$Path)
    if (-not (Test-Path (Join-Path $Path '.git'))) { return $false }
    & $gitExe -C $Path rev-parse --git-dir > $null 2>&1
    return ($LASTEXITCODE -eq 0)
}

if (Test-Repo $Dest) {
    Write-Host "已存在仓库，改为拉取更新: $Dest" -ForegroundColor Cyan
    Push-Location $Dest
    try {
        Invoke-Git @('fetch', '--filter=blob:none', 'origin', $Commit)
        Invoke-Git @('sparse-checkout', 'set', 'software/studio')
        Invoke-Git @('checkout', '--quiet', $Commit)
    } finally { Pop-Location }
} else {
    if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force }

    $ok = $false
    for ($i = 1; $i -le $Retries; $i++) {
        Write-Host "稀疏克隆到: $Dest （第 $i/$Retries 次）" -ForegroundColor Cyan
        & $gitExe @gitArgs clone --filter=blob:none --no-checkout --no-tags $Remote $Dest
        if (Test-Repo $Dest) { $ok = $true; break }
        Write-Host "  本次失败（exit $LASTEXITCODE），清理后重试…" -ForegroundColor Yellow
        if (Test-Path $Dest) { Remove-Item $Dest -Recurse -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 3
    }
    if (-not $ok) {
        throw ('克隆失败 ' + $Retries + ' 次。可能是代理不稳（Recv failure / Connection was reset）：' +
               '换 -NoProxy 直连、或重跑本脚本；也可以手动下 zip 解 software/studio。')
    }

    Push-Location $Dest
    try {
        Invoke-Git @('sparse-checkout', 'init', '--cone')
        Invoke-Git @('sparse-checkout', 'set', 'software/studio')
        Invoke-Git @('checkout', '--quiet', $Commit)
    } finally { Pop-Location }
}

# ---- 校验 ----
$studio = Join-Path $Dest 'software/studio'
$runPy  = Join-Path $studio 'run.py'
if (-not (Test-Path $runPy)) { throw "拉取完成但缺少 $runPy —— sparse 规则或上游结构变了。" }

$files = Get-ChildItem $studio -Recurse -File
$bytes = ($files | Measure-Object -Property Length -Sum).Sum
$head  = & $gitExe -C $Dest rev-parse HEAD
Write-Host ''
Write-Host "commit : $head" -ForegroundColor Green
Write-Host "studio : $($files.Count) 文件, $([math]::Round($bytes/1MB,2)) MB" -ForegroundColor Green
Write-Host "路径   : $studio" -ForegroundColor Green

# ---- 可选：推到板子 ----
if ($PushTo) {
    if (-not $RemoteDir) {
        $user = ($PushTo -split '@')[0]
        $RemoteDir = "/home/$user/studio-dev"
    }
    $scp = Get-Command scp -ErrorAction SilentlyContinue
    if (-not $scp) { throw '找不到 scp，装 OpenSSH 客户端。' }
    Write-Host ''
    Write-Host "scp -r $studio -> ${PushTo}:$RemoteDir" -ForegroundColor Cyan
    & $scp.Source -r $studio "${PushTo}:$RemoteDir"
    if ($LASTEXITCODE -ne 0) { throw "scp 失败（exit $LASTEXITCODE）" }
    Write-Host "已推送。板子上继续：" -ForegroundColor Green
    Write-Host "  cd $RemoteDir && python3 -I run.py --listen 0.0.0.0:8000"
    Write-Host "  sudo sh deploy/install.sh $($PushTo -split '@')[0]"
} else {
    Write-Host ''
    Write-Host '下一步（在板子上）：' -ForegroundColor Yellow
    Write-Host "  scp -r `"$studio`" <user>@<板子IP>:/home/<user>/studio-dev"
    Write-Host '  cd ~/studio-dev && python3 -I run.py --listen 0.0.0.0:8000'
    Write-Host '  sudo sh deploy/install.sh <user>'
    Write-Host '  详见 docs/03-software-stack.md B 节'
}

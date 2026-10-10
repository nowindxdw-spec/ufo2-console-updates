# UFO2 Console 一键安装 / 升级（在目标机上运行，走 GitHub Release 下载通道）
#
#   直接运行：powershell -File install-latest.ps1
#   指定版本：powershell -File install-latest.ps1 -Tag v1.0.1 -Force
#   只下载不装：powershell -File install-latest.ps1 -DownloadOnly
#   走内网镜像：powershell -File install-latest.ps1 -BaseUrl http://10.0.0.12:8712 -ApiKey <该机器的密钥>
#
# 流程：读 latest.json（机器可读清单）-> 比对已装版本 -> 下载安装包 -> 校验 SHA-256
#       -> 让正在跑的服务退出 -> /VERYSILENT 安装 -> 复核版本。任何一步失败都不落盘安装。
param(
    [string]$Repo = "nowindxdw-spec/ufo2-console-updates",
    [string]$Tag = "",
    [string]$Tier = "slim",
    [string]$ManifestUrl = "",
    [string]$BaseUrl = "",
    [string]$ApiKey = "",
    [switch]$Force,
    [switch]$DownloadOnly,
    [string]$DownloadDir = (Join-Path $env:TEMP "ufo2-console-download")
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
$pinnedTag = "$Tag"
$headers = @{}
if ($ApiKey) { $headers["X-API-Key"] = $ApiKey }

function Say($m) { Write-Host "[ufo2-setup] $m" }
function Die($m) { Write-Host "[ufo2-setup] x $m" -ForegroundColor Red; exit 1 }

$installDir = Join-Path $env:LOCALAPPDATA "Programs\UFO2 Console"
$exe = Join-Path $installDir "ufo2-console.exe"

function LocalVersion {
    if (-not (Test-Path -LiteralPath $exe)) { return "" }
    $v = (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion
    return ("$v" -replace "\+.*$", "")
}

# 1) 清单
if (-not $ManifestUrl -and $BaseUrl) { $ManifestUrl = ($BaseUrl.TrimEnd('/') + "/api/update/manifest") }
if (-not $ManifestUrl) { $ManifestUrl = "https://raw.githubusercontent.com/$Repo/main/latest.json" }
Say "读清单 $ManifestUrl"
try { $manifest = Invoke-RestMethod -Uri $ManifestUrl -UseBasicParsing -Headers $headers } catch { Die "读不到清单：$($_.Exception.Message)" }
if (-not $manifest.version) { Die "清单里没有 version 字段" }
if (-not $Tag) { $Tag = $manifest.tag }
# 手填 tag 时以 tag 里的版本号为准（内网镜像可以代理任意历史版本）
$wantVersion = $manifest.version
if ($pinnedTag -and ($pinnedTag -match '(\d+\.\d+\.\d+)')) { $wantVersion = $Matches[1] }

# 2) 比对
$local = LocalVersion
Say "本机版本：$(if ($local) { $local } else { "未安装" })  ·  通道版本：$($manifest.version)（$Tag，tier=$($manifest.tier)）"
if ($local -eq "$($manifest.version)" -and -not $Force -and -not $pinnedTag) { Say "已是最新，无需安装（要重装加 -Force，要回滚加 -Tag v1.2.3）"; exit 0 }
if ($local -eq "$($wantVersion)" -and -not $Force) { Say "本机已是目标版本 $wantVersion；要重装请加 -Force"; exit 0 }

# 3) 选资产
$wanted = "UFO2-Console-$($wantVersion)-$Tier-setup.exe"
$asset = @($manifest.assets | Where-Object { $_.name -eq $wanted }) | Select-Object -First 1
if (-not $asset) { $asset = @($manifest.assets | Where-Object { $_.name -like "*-setup.exe" }) | Select-Object -First 1 }
if (-not $asset) { Die "清单里没有 Windows 安装包资产（可用 -Tier 切换 slim/full）" }
Say "资产 $($asset.name)（$([math]::Round($asset.size / 1MB, 1)) MB）"
# 4) 下载：优先用清单给的地址（内网镜像会把它改写成同伴机自己的 package 端点）
if (-not (Test-Path -LiteralPath $DownloadDir)) { New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null }
$file = Join-Path $DownloadDir $asset.name
$url = "$($asset.downloadUrl)"
if (-not $url) { $url = "https://github.com/$Repo/releases/download/$Tag/$([uri]::EscapeDataString($asset.name))" }
$keyArgs = @()
if ($ApiKey) { $keyArgs = @("-H", "X-API-Key: $ApiKey") }
Say "下载到 $file"
& curl.exe -sSL --fail --retry 3 --retry-delay 3 @keyArgs -o "$file" "$url"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file)) { Die "下载失败（curl exit=$LASTEXITCODE）" }

# 5) 校验 SHA-256（清单里给的是小写十六进制）
$hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLower()
if ($asset.sha256 -and $hash -ne $asset.sha256.ToLower()) { Die "SHA-256 不匹配：清单=$($asset.sha256) 实际=$hash（文件留在 $file，请人工确认）" }
Say "SHA-256 校验通过 $hash"
if ($DownloadOnly) { Say "-DownloadOnly：不安装，安装包在 $file"; exit 0 }
# 6) 服务在跑也没关系：安装器带 CloseApplications=yes，静默模式下会自行收尾被占用的文件
$running = @(Get-Process -Name "ufo2-console" -ErrorAction SilentlyContinue)
if ($running.Count) { Say "检测到服务进程 $($running.Id -join ',')，由安装器负责收尾" }

# 7) 静默安装（per-user，不需要管理员）
Say "安装中…"
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $file
$psi.Arguments = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART"
$psi.UseShellExecute = $false
$installer = [System.Diagnostics.Process]::Start($psi)
$installer.WaitForExit()
if ($installer.ExitCode -ne 0) { Die "安装器退出码 $($installer.ExitCode)（可先 -DownloadOnly 拿到包再手工装）" }

$after = LocalVersion
Say "安装完成：$after  程序目录 $installDir"
$port = (Get-Content "$env:LOCALAPPDATA\UFO2\config\server.json" -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json).port
if (-not $port) { $port = 8712 }
Say "启动： & `"$exe`" serve --open   （本机控制台 http://127.0.0.1:$port/）"
if ($manifest.notes) { Write-Host ("`n--- 本版说明 ---`n" + $manifest.notes) -ForegroundColor DarkGray }

<#
.SYNOPSIS
    扫描 docs/ 目录下所有 .md 和 .html 文件，生成 docs/files.json 清单。
    运行后 index.html 即可自动发现新增文件，无需手动修改 index.html。

.DESCRIPTION
    - 递归扫描 docs/ 目录
    - 自动过滤 index.html、files.json 本身
    - 按文件名自动推断类型（html/md）和所属子目录
    - 输出 JSON 到 docs/files.json
    - 输出统计摘要

.EXAMPLE
    .\refresh-docs.ps1
#>

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$docsDir   = Join-Path $scriptDir 'docs'
$outputFile = Join-Path $docsDir 'files.json'

if (-not (Test-Path $docsDir)) {
    Write-Host "错误: docs/ 目录不存在: $docsDir" -ForegroundColor Red
    exit 1
}

Write-Host "扫描 docs/ 目录…" -ForegroundColor Cyan

# 递归获取所有 .md 和 .html 文件
$files = Get-ChildItem -Path $docsDir -Recurse -File |
    Where-Object { $_.Extension -match '\.(md|html)$' -and $_.Name -ne 'index.html' -and $_.Name -ne 'files.json' } |
    Sort-Object FullName

$total = $files.Count
$mdCount = 0
$htmlCount = 0
$dirs = @{}

$entries = @()

foreach ($f in $files) {
    $relPath = $f.FullName.Substring($docsDir.Length + 1) -replace '\\', '/'
    $ext = $f.Extension.ToLower() -replace '\.', ''
    $slashIdx = $relPath.IndexOf('/')
    $dir = if ($slashIdx -gt 0) { $relPath.Substring(0, $slashIdx) } else { '' }

    $entry = [ordered]@{
        name  = $f.Name
        path  = $relPath
        type  = $ext
        dir   = $dir
        title = ''
    }
    $entries += $entry

    if ($ext -eq 'md')   { $mdCount++ }
    if ($ext -eq 'html') { $htmlCount++ }
    if ($dir) { $dirs[$dir] = $true }
}

$manifest = [ordered]@{
    generated = (Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz')
    generator = 'refresh-docs.ps1'
    basePath  = 'docs'
    files     = $entries
}

$json = $manifest | ConvertTo-Json -Depth 3 -Compress
# ConvertTo-Json -Compress 会把中文转义为 \uXXXX，这里我们不做 unescape，
# 因为 PowerShell 5.1 原生不支持。但浏览器能正确解析 \uXXXX 编码。
# 如果你需要人类可读 JSON，可以用 -Compress:$false 去掉 -Compress。

$json | Out-File -FilePath $outputFile -Encoding UTF8

Write-Host ''
Write-Host ('=== 清单已生成 ===') -ForegroundColor Green
Write-Host ('输出文件 : ' + $outputFile)
Write-Host ('专题分类 : ' + $dirs.Count)
Write-Host ('文档总数 : ' + $total)
Write-Host ('Markdown : ' + $mdCount)
Write-Host ('HTML     : ' + $htmlCount)
Write-Host ('')
Write-Host ('提示：index.html 已配置为自动读取此 files.json。')
Write-Host ('      将本项目推送到 GitHub Pages 后，即使没有 files.json，')
Write-Host ('      index.html 也会通过 GitHub API 自动发现所有文件。')

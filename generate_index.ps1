param(
  [string]$RepoRoot = (Get-Location).Path
)

$AllowedExt = @(".pdf",".html",".docx",".pptx")
$SkipDirs   = @(".git",".github","node_modules")

$BaseUrlFile = Join-Path $RepoRoot "baseurl.txt"
if (-not (Test-Path -LiteralPath $BaseUrlFile)) { throw "Falta baseurl.txt en la raiz del repo." }

$BaseUrl = (Get-Content -LiteralPath $BaseUrlFile -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($BaseUrl)) { throw "baseurl.txt esta vacio." }

function Escape-Segment([string]$s) { [System.Uri]::EscapeDataString($s) }
function HtmlEncode([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }

function Get-RelPath([string]$root, [string]$full) {
  $root = $root.TrimEnd('\','/')
  $full = $full.TrimEnd('\','/')
  if ($full.Length -lt $root.Length) { return "" }
  if ($full.Substring(0, $root.Length).ToLower() -ne $root.ToLower()) { return "" }
  return $full.Substring($root.Length).TrimStart('\','/')
}

function Build-Url([string]$relDir, [string]$fileName) {
  $relDir = ($relDir -replace "\\","/").Trim("/")
  if ([string]::IsNullOrWhiteSpace($relDir)) {
    return "$BaseUrl/$(Escape-Segment $fileName)"
  }
  $segments = $relDir.Split("/") | ForEach-Object { Escape-Segment $_ }
  $escapedDir = ($segments -join "/")
  return "$BaseUrl/$escapedDir/$(Escape-Segment $fileName)"
}

function Write-Index([string]$dirPath, [string]$relDir) {
  $title = if ($relDir) { ($relDir -replace "\\"," / ") } else { "Inicio" }

  # Subcarpetas
  $dirs = Get-ChildItem -LiteralPath $dirPath -Directory |
    Where-Object { $SkipDirs -notcontains $_.Name } |
    Sort-Object Name

  $dirItems = @()
  foreach ($d in $dirs) {
    $safe = HtmlEncode $d.Name
    $href = "./$([System.Uri]::EscapeDataString($d.Name))/"
    $dirItems += "<li>[DIR] <a href='$href'>$safe</a></li>"
  }

  # Archivos
  $files = Get-ChildItem -LiteralPath $dirPath -File |
    Where-Object { $_.Name -ne "index.html" -and $AllowedExt -contains $_.Extension.ToLower() } |
    Sort-Object Name

  $fileItems = @()
  foreach ($f in $files) {
    $safeName = HtmlEncode $f.Name
    $href = Build-Url $relDir $f.Name
    $fileItems += "<li>[FILE] <a href='$href' target='_blank' rel='noopener'>$safeName</a></li>"
  }

  $contentLines = @()
  if (($dirItems.Count -eq 0) -and ($fileItems.Count -eq 0)) {
    $contentLines += "<li><em>(Sin archivos)</em></li>"
  } else {
    if ($dirItems.Count -gt 0) {
      $contentLines += "<li><strong>Carpetas</strong>"
      $contentLines += "  <ul>"
      $contentLines += $dirItems
      $contentLines += "  </ul>"
      $contentLines += "</li>"
    }
    if ($fileItems.Count -gt 0) {
      $contentLines += "<li><strong>Archivos</strong>"
      $contentLines += "  <ul>"
      $contentLines += $fileItems
      $contentLines += "  </ul>"
      $contentLines += "</li>"
    }
  }

  $htmlLines = @()
  $htmlLines += "<!doctype html>"
  $htmlLines += "<html lang='es'>"
  $htmlLines += "<head>"
  $htmlLines += "  <meta charset='utf-8'/>"
  $htmlLines += "  <meta name='viewport' content='width=device-width, initial-scale=1'/>"
  $htmlLines += "  <title>$title</title>"
  $htmlLines += "  <style>"
  $htmlLines += "    body{font-family:system-ui,Segoe UI,Arial;max-width:980px;margin:24px auto;padding:0 12px;}"
  $htmlLines += "    h1{font-size:22px;margin-bottom:12px;}"
  $htmlLines += "    ul{line-height:1.7;padding-left:18px;}"
  $htmlLines += "    .muted{color:#666;font-size:13px;margin-bottom:12px;}"
  $htmlLines += "    a{text-decoration:none;} a:hover{text-decoration:underline;}"
  $htmlLines += "  </style>"
  $htmlLines += "</head>"
  $htmlLines += "<body>"
  $htmlLines += "  <h1>$title</h1>"
  $htmlLines += "  <div class='muted'>Listado autogenerado</div>"
  $htmlLines += "  <ul>"
  $htmlLines += $contentLines
  $htmlLines += "  </ul>"
  $htmlLines += "</body>"
  $htmlLines += "</html>"

  $html = ($htmlLines -join "`n")

  $outFile = Join-Path $dirPath "index.html"
  if (Test-Path -LiteralPath $outFile) {
    $old = Get-Content -LiteralPath $outFile -Raw
    if ($old -eq $html) { return }
  }
  # Forzar LF real y escribir sin que PowerShell meta CRLF
  $htmlLf = $html -replace "`r`n", "`n"
  [System.IO.File]::WriteAllText($outFile, $htmlLf, (New-Object System.Text.UTF8Encoding($false)))
}

Write-Index $RepoRoot ""

Get-ChildItem -LiteralPath $RepoRoot -Directory -Recurse -Force |
  Where-Object { $SkipDirs -notcontains $_.Name } |
  ForEach-Object {
    $rel = Get-RelPath $RepoRoot $_.FullName
    Write-Index $_.FullName $rel
  }

Write-Host "Index generados/actualizados." -ForegroundColor Green
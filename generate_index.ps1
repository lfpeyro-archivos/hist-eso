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

function Build-DirUrlFromSegments([string[]]$segments) {
  if ($segments.Count -eq 0) { return "$BaseUrl/" }
  $escaped = $segments | ForEach-Object { Escape-Segment $_ }
  return "$BaseUrl/$($escaped -join '/')/"
}

function Build-Breadcrumb([string]$relDir) {
  $crumbs = @()
  $crumbs += "<a href='$BaseUrl/'>Inicio</a>"

  $relDir = ($relDir -replace "\\","/").Trim("/")
  if (-not [string]::IsNullOrWhiteSpace($relDir)) {
    $parts = $relDir.Split("/")
    $acc = New-Object System.Collections.Generic.List[string]

    foreach ($p in $parts) {
      $acc.Add($p)
      $safe = HtmlEncode $p
      $url  = Build-DirUrlFromSegments $acc.ToArray()
      $crumbs += "<a href='$url'>$safe</a>"
    }
  }

  return ($crumbs -join " &gt; ")
}

function Build-UpLink([string]$relDir) {
  $relDir = ($relDir -replace "\\","/").Trim("/")
  if ([string]::IsNullOrWhiteSpace($relDir)) { return "" }

  $parts = $relDir.Split("/")
  if ($parts.Count -le 1) {
    return "<div style='margin-bottom:10px;'><a href='$BaseUrl/'>Subir un nivel</a></div>"
  }

  $parentParts = $parts[0..($parts.Count-2)]
  $parentUrl = Build-DirUrlFromSegments $parentParts
  return "<div style='margin-bottom:10px;'><a href='$parentUrl'>Subir un nivel</a></div>"
}

function Write-Index([string]$dirPath, [string]$relDir) {

  $title = if ($relDir) { ($relDir -replace "\\"," / ") } else { "Inicio" }

  $breadcrumbHtml = Build-Breadcrumb $relDir
  $upLinkHtml     = Build-UpLink $relDir

  # Subcarpetas (links relativos funcionan genial en Pages)
  $dirs = Get-ChildItem -LiteralPath $dirPath -Directory |
    Where-Object { $SkipDirs -notcontains $_.Name } |
    Sort-Object Name

  $dirItems = @()
  foreach ($d in $dirs) {
    $safe = HtmlEncode $d.Name
    $href = "./$([System.Uri]::EscapeDataString($d.Name))/"
    $dirItems += "<li><strong>[DIR]</strong> <a href='$href'>$safe</a></li>"
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
    $contentLines += "<li><em>(Sin carpetas ni archivos)</em></li>"
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
  $htmlLines += "    h1{font-size:22px;margin:10px 0 12px 0;}"
  $htmlLines += "    .breadcrumb{font-size:14px;margin-bottom:10px;color:#555;}"
  $htmlLines += "    ul{line-height:1.7;padding-left:18px;}"
  $htmlLines += "    a{text-decoration:none;} a:hover{text-decoration:underline;}"
  $htmlLines += "  </style>"
  $htmlLines += "</head>"
  $htmlLines += "<body>"
  $htmlLines += "  <div class='breadcrumb'>$breadcrumbHtml</div>"
  if (-not [string]::IsNullOrWhiteSpace($upLinkHtml)) { $htmlLines += "  $upLinkHtml" }
  $htmlLines += "  <h1>$title</h1>"
  $htmlLines += "  <ul>"
  $htmlLines += $contentLines
  $htmlLines += "  </ul>"
  $htmlLines += "</body>"
  $htmlLines += "</html>"

  $html = ($htmlLines -join "`n")
  $outFile = Join-Path $dirPath "index.html"

  # Escribir tal cual en UTF-8 sin BOM
  [System.IO.File]::WriteAllText($outFile, $html, (New-Object System.Text.UTF8Encoding($false)))
}

# Raiz
Write-Index $RepoRoot ""

# Todas las carpetas
Get-ChildItem -LiteralPath $RepoRoot -Directory -Recurse -Force |
  Where-Object { $SkipDirs -notcontains $_.Name } |
  ForEach-Object {
    $rel = Get-RelPath $RepoRoot $_.FullName
    Write-Index $_.FullName $rel
  }

Write-Host "Index generados/actualizados." -ForegroundColor Green
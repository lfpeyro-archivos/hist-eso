param(
  [string]$RepoRoot = (Get-Location).Path
)

# Extensiones permitidas y orden deseado
$AllowedExt = @(".html",".pdf",".pptx",".docx",".xlsx",".txt")
$extOrder = @{
  ".html" = 1
  ".pdf"  = 2
  ".pptx" = 3
  ".docx" = 4
  ".xlsx" = 5
  ".txt"  = 6
}

# Carpetas que no deben listarse
$SkipDirs   = @(".git",".github","node_modules")

# Leer base URL
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
    return "<div class='uplink'><a href='$BaseUrl/'>Subir un nivel</a></div>"
  }

  $parentParts = $parts[0..($parts.Count-2)]
  $parentUrl = Build-DirUrlFromSegments $parentParts
  return "<div class='uplink'><a href='$parentUrl'>Subir un nivel</a></div>"
}

function Ext-Badge([string]$extLower) {
  switch ($extLower) {
    ".html" { return "<span class='badge b-html'>HTML</span>" }
    ".pdf"  { return "<span class='badge b-pdf'>PDF</span>" }
    ".pptx" { return "<span class='badge b-pptx'>PPTX</span>" }
    ".docx" { return "<span class='badge b-docx'>DOCX</span>" }
    ".xlsx" { return "<span class='badge b-xlsx'>XLSX</span>" }
    ".txt"  { return "<span class='badge b-txt'>TXT</span>" }
    default { return "<span class='badge b-oth'>FILE</span>" }
  }
}

function Write-Index([string]$dirPath, [string]$relDir) {

  $title = if ($relDir) { ($relDir -replace "\\"," / ") } else { "Inicio" }

  $breadcrumbHtml = Build-Breadcrumb $relDir
  $upLinkHtml     = Build-UpLink $relDir

  # Subcarpetas
  $dirs = Get-ChildItem -LiteralPath $dirPath -Directory |
    Where-Object { $SkipDirs -notcontains $_.Name } |
    Sort-Object Name

  $dirItems = @()
  foreach ($d in $dirs) {
    $safe = HtmlEncode $d.Name
    $href = "./$([System.Uri]::EscapeDataString($d.Name))/"
    # data-name ayuda al buscador
    $dirItems += "<li class='item dir' data-name='$([System.Uri]::EscapeDataString($d.Name.ToLower()))'><span class='badge b-dir'>DIR</span> <a href='$href'>$safe</a></li>"
  }

  # Archivos (orden por tipo y luego nombre)
  $files = Get-ChildItem -LiteralPath $dirPath -File |
    Where-Object {
      $_.Name -ne "index.html" -and
      $AllowedExt -contains $_.Extension.ToLower()
    } |
    Sort-Object `
      @{Expression = { $extOrder[$_.Extension.ToLower()] }}, `
      @{Expression = { $_.Name }}

  $fileItems = @()
  foreach ($f in $files) {
    $ext = $f.Extension.ToLower()
    $safeName = HtmlEncode $f.Name
    $href = Build-Url $relDir $f.Name
    $badge = Ext-Badge $ext
    $fileItems += "<li class='item file' data-name='$([System.Uri]::EscapeDataString($f.Name.ToLower()))'>$badge <a href='$href' target='_blank' rel='noopener'>$safeName</a></li>"
  }

  # Secciones
  $sections = @()
  if (($dirItems.Count -eq 0) -and ($fileItems.Count -eq 0)) {
    $sections += "<li><em>(Sin carpetas ni archivos)</em></li>"
  } else {
    if ($dirItems.Count -gt 0) {
      $sections += "<li class='section'><strong>Carpetas</strong><ul class='list'>"
      $sections += $dirItems
      $sections += "</ul></li>"
    }
    if ($fileItems.Count -gt 0) {
      $sections += "<li class='section'><strong>Archivos</strong><ul class='list'>"
      $sections += $fileItems
      $sections += "</ul></li>"
    }
  }

  # HTML
  $htmlLines = @()
  $htmlLines += "<!doctype html>"
  $htmlLines += "<html lang='es'>"
  $htmlLines += "<head>"
  $htmlLines += "  <meta charset='utf-8'/>"
  $htmlLines += "  <meta name='viewport' content='width=device-width, initial-scale=1'/>"
  $htmlLines += "  <title>$title</title>"
  $htmlLines += "  <style>"
  $htmlLines += "    body{font-family:system-ui,Segoe UI,Arial;max-width:980px;margin:24px auto;padding:0 12px;}"
  $htmlLines += "    .breadcrumb{font-size:14px;margin-bottom:10px;color:#555;}"
  $htmlLines += "    .uplink{margin-bottom:10px;}"
  $htmlLines += "    h1{font-size:22px;margin:10px 0 10px 0;}"
  $htmlLines += "    a{text-decoration:none;} a:hover{text-decoration:underline;}"
  $htmlLines += "    .tools{display:flex;gap:10px;align-items:center;margin:10px 0 14px 0;flex-wrap:wrap;}"
  $htmlLines += "    .search{padding:8px 10px;border:1px solid #ccc;border-radius:8px;min-width:260px;}"
  $htmlLines += "    .hint{color:#666;font-size:13px;}"
  $htmlLines += "    ul{line-height:1.7;padding-left:18px;}"
  $htmlLines += "    ul.list{padding-left:18px;margin-top:6px;}"
  $htmlLines += "    li.section{margin:10px 0;}"
  $htmlLines += "    li.item{margin:4px 0;}"
  $htmlLines += "    .badge{display:inline-block;font-size:11px;line-height:1;border-radius:6px;padding:4px 6px;margin-right:8px;border:1px solid #ddd;background:#f6f6f6;color:#333;min-width:44px;text-align:center;}"
  $htmlLines += "    .b-dir{background:#eef2ff;border-color:#d9ddff;}"
  $htmlLines += "    .b-html{background:#ecfeff;border-color:#cdeef2;}"
  $htmlLines += "    .b-pdf{background:#fff7ed;border-color:#f2dfc8;}"
  $htmlLines += "    .b-pptx{background:#fef2f2;border-color:#f3caca;}"
  $htmlLines += "    .b-docx{background:#eff6ff;border-color:#cfe0ff;}"
  $htmlLines += "    .b-xlsx{background:#ecfdf5;border-color:#c9f0dc;}"
  $htmlLines += "    .b-txt{background:#f5f5f5;border-color:#e1e1e1;}"
  $htmlLines += "  </style>"
  $htmlLines += "</head>"
  $htmlLines += "<body>"
  $htmlLines += "  <div class='breadcrumb'>$breadcrumbHtml</div>"
  if (-not [string]::IsNullOrWhiteSpace($upLinkHtml)) { $htmlLines += "  $upLinkHtml" }
  $htmlLines += "  <h1>$title</h1>"
  $htmlLines += "  <div class='tools'>"
  $htmlLines += "    <input id='q' class='search' type='search' placeholder='Buscar archivo o carpeta...' autocomplete='off' />"
  $htmlLines += "    <span class='hint'>Escribe para filtrar. Vaciar para ver todo.</span>"
  $htmlLines += "  </div>"
  $htmlLines += "  <ul>"
  $htmlLines += $sections
  $htmlLines += "  </ul>"

  # Mini buscador (JS)
  $htmlLines += "  <script>"
  $htmlLines += "    (function(){"
  $htmlLines += "      var input = document.getElementById('q');"
  $htmlLines += "      if(!input) return;"
  $htmlLines += "      var items = Array.prototype.slice.call(document.querySelectorAll('li.item'));"
  $htmlLines += "      function norm(s){ return (s||'').toLowerCase().trim(); }"
  $htmlLines += "      function apply(){"
  $htmlLines += "        var q = norm(input.value);"
  $htmlLines += "        items.forEach(function(li){"
  $htmlLines += "          var name = decodeURIComponent(li.getAttribute('data-name') || '');"
  $htmlLines += "          li.style.display = (q==='' || name.indexOf(q)>=0) ? '' : 'none';"
  $htmlLines += "        });"
  $htmlLines += "      }"
  $htmlLines += "      input.addEventListener('input', apply);"
  $htmlLines += "    })();"
  $htmlLines += "  </script>"

  $htmlLines += "</body>"
  $htmlLines += "</html>"

  $html = ($htmlLines -join "`n")
  $outFile = Join-Path $dirPath "index.html"

  # Escribir tal cual en UTF-8 sin BOM (y sin CRLF forzado)
  [System.IO.File]::WriteAllText($outFile, $html, (New-Object System.Text.UTF8Encoding($false)))
}

# Generar index en la raiz
Write-Index $RepoRoot ""

# Generar index en todas las carpetas
Get-ChildItem -LiteralPath $RepoRoot -Directory -Recurse -Force |
  Where-Object { $SkipDirs -notcontains $_.Name } |
  ForEach-Object {
    $rel = Get-RelPath $RepoRoot $_.FullName
    Write-Index $_.FullName $rel
  }

Write-Host "Index generados/actualizados." -ForegroundColor Green
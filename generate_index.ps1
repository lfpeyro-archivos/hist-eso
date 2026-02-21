param(
  [string]$RepoRoot = (Get-Location).Path
)

$AllowedExt = @(".pdf",".html",".docx",".pptx")
$SkipDirs   = @(".git",".github","node_modules")

$BaseUrlFile = Join-Path $RepoRoot "baseurl.txt"
if (-not (Test-Path -LiteralPath $BaseUrlFile)) { throw "Falta baseurl.txt en la raíz del repo." }
$BaseUrl = (Get-Content -LiteralPath $BaseUrlFile -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($BaseUrl)) { throw "baseurl.txt está vacío." }

function Escape-Segment([string]$s) { return [System.Uri]::EscapeDataString($s) }

function Build-Url([string]$relDir, [string]$fileName) {
  $relDir = ($relDir -replace "\\","/").Trim("/")
  if ([string]::IsNullOrWhiteSpace($relDir) -or $relDir -eq ".") {
    return "$BaseUrl/$(Escape-Segment $fileName)"
  }
  $segments = $relDir.Split("/") | ForEach-Object { Escape-Segment $_ }
  $escapedDir = ($segments -join "/")
  return "$BaseUrl/$escapedDir/$(Escape-Segment $fileName)"
}

function Write-Index([string]$dirPath, [string]$relDir) {
  $title = if ($relDir -and $relDir -ne ".") { ($relDir -replace "\\"," / ") } else { "Inicio" }

  $items = Get-ChildItem -LiteralPath $dirPath -File |
    Where-Object { $_.Name -ne "index.html" -and $AllowedExt -contains $_.Extension.ToLower() } |
    Sort-Object Name

  $listHtml = ""
  if ($items.Count -eq 0) {
    $listHtml = "<li><em>(Sin archivos)</em></li>"
  } else {
    foreach ($f in $items) {
      $href = Build-Url $relDir $f.Name
      $safeName = [System.Web.HttpUtility]::HtmlEncode($f.Name)
      $listHtml += "<li><a href='$href' target='_blank' rel='noopener'>$safeName</a></li>`n"
    }
  }

  $html = @"
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>$title</title>
  <style>
    body{font-family:system-ui,Segoe UI,Arial;max-width:980px;margin:24px auto;padding:0 12px;}
    h1{font-size:20px;margin:0 0 12px;}
    ul{line-height:1.7;padding-left:18px;}
    .muted{color:#666;font-size:13px;margin-bottom:12px;}
  </style>
</head>
<body>
  <h1>$title</h1>
  <div class="muted">Listado autogenerado</div>
  <ul>
    $listHtml
  </ul>
</body>
</html>
"@

  $outFile = Join-Path $dirPath "index.html"
  if (Test-Path -LiteralPath $outFile) {
    $old = Get-Content -LiteralPath $outFile -Raw
    if ($old -eq $html) { return }
  }
  Set-Content -LiteralPath $outFile -Value $html -Encoding UTF8
}

Write-Index $RepoRoot ""

Get-ChildItem -LiteralPath $RepoRoot -Directory -Recurse -Force |
  Where-Object { $SkipDirs -notcontains $_.Name } |
  ForEach-Object {
    $rel = [System.IO.Path]::GetRelativePath($RepoRoot, $_.FullName)
    Write-Index $_.FullName $rel
  }

Write-Host "Index generados/actualizados." -ForegroundColor Green
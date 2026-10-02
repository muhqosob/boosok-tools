# sync_to_sketchup.ps1
# Jalankan script ini setelah mengedit file di src/ agar perubahan masuk ke SketchUp.
#
# Mode dev: script ini membuat file penanda ".dev_mode" di folder plugin. Dengan penanda itu,
# plugin otomatis memantau perubahan dan me-reload dirinya sendiri (tanpa restart SketchUp):
#   - file .rb berubah           -> semua modul di-reload, dialog dibuka lagi di tool yang sama
#   - .html/.js/.css/.json berubah -> halaman dialog di-refresh
# Hanya file yang benar-benar berubah yang disalin, supaya tidak memicu reload sia-sia.
# (Restart SketchUp hanya perlu SEKALI untuk memuat dev_reload.rb pertama kali.)

$src = "c:\Users\FMMNH\Desktop\Boosok Tool\boosok-tools\src\boosok_tools"
$dst = "$env:APPDATA\SketchUp\SketchUp 2026\SketchUp\Plugins\boosok_tools"

if (-not (Test-Path $dst)) { Write-Host "ERROR: dst tidak ditemukan"; exit 1 }

# File yang dibuat/ditulis oleh plugin saat berjalan: jangan ditimpa dari src
$skip = @('session.js', 'strings.js', 'titlebar.log')

Write-Host "Syncing..." -ForegroundColor Cyan
$changed = 0
$same = 0
Get-ChildItem -Path $src -Recurse -File | ForEach-Object {
    if ($skip -contains $_.Name) { return }
    $rel = $_.FullName.Substring($src.Length + 1)
    $dest = Join-Path $dst $rel
    $dir = Split-Path $dest -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    if (Test-Path $dest) {
        $d = Get-Item $dest
        if ($d.Length -eq $_.Length -and $d.LastWriteTimeUtc -eq $_.LastWriteTimeUtc) { $same++; return }
    }
    Copy-Item $_.FullName $dest -Force
    Write-Host "  [OK] $rel"
    $changed++
}

# Penanda mode dev (aktifkan auto-reload di plugin)
$marker = Join-Path $dst ".dev_mode"
if (-not (Test-Path $marker)) {
    Set-Content -Path $marker -Value "auto-reload aktif. Hapus file ini untuk mematikan." -Encoding ASCII
    Write-Host "  [DEV] .dev_mode dibuat (auto-reload aktif setelah SketchUp di-restart sekali)" -ForegroundColor Yellow
}

Write-Host "Selesai! $changed file ter-update, $same tidak berubah." -ForegroundColor Green
if ($changed -gt 0) { Write-Host "Kalau SketchUp sedang terbuka, plugin akan reload otomatis dalam ~2 detik." -ForegroundColor DarkGray }

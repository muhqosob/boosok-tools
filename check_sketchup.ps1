# check_sketchup.ps1
# Jalankan di root repo sebelum membuat .rbz untuk di-upload ke Extension Signature Portal:
#   powershell -ExecutionPolicy Bypass -File .\check_sketchup.ps1
#
# 1) RuboCop dengan cop SketchUp (sama dengan pengecekan portal, lihat .rubocop.yml)
# 2) Pola yang TIDAK ditangkap RuboCop tapi merusak plugin setelah dienkripsi jadi .rbe:
#    require_relative / load / glob *.rb untuk file milik sendiri. Muat file lewat
#    BoosokTools.load_module atau Sketchup.require tanpa ekstensi.
# Exit code 0 = aman, 1 = ada masalah, 2 = RuboCop belum terpasang.

Set-Location $PSScriptRoot
$failed = $false

# File yang memang boleh memakai load (jalur source/dev, tidak jalan di paket terenkripsi)
$allowed = @('boosok_tools.rb', 'updater.rb', 'dev_reload.rb')

Write-Host "[1/2] RuboCop (cop SketchUp)..." -ForegroundColor Cyan
if (-not (Get-Command rubocop -ErrorAction SilentlyContinue)) {
    Write-Host "RuboCop belum terpasang. Lihat langkah setup di .rubocop.yml" -ForegroundColor Red
    exit 2
}
rubocop
if ($LASTEXITCODE -ne 0) { $failed = $true }

Write-Host ""
Write-Host "[2/2] Pola load yang rusak di paket terenkripsi..." -ForegroundColor Cyan
$patterns = @(
    '^\s*(require_relative|load)[\s(]',        # require_relative 'x' / load File.join(...)
    '\{\s*\|\w+\|\s*(require_relative|load)\b', # .each { |f| load f }
    '^\s*[^#\s].*Dir(\[|\.glob).*\.rb'          # Dir['*.rb'] di kode (bukan komentar)
)
$hits = @()
Get-ChildItem -Path (Join-Path $PSScriptRoot 'src') -Recurse -Filter *.rb |
    Where-Object { $allowed -notcontains $_.Name } |
    ForEach-Object {
        foreach ($p in $patterns) {
            $hits += Select-String -Path $_.FullName -Pattern $p -CaseSensitive
        }
    }
$hits = $hits | Sort-Object Path, LineNumber -Unique
if ($hits) {
    $failed = $true
    foreach ($h in $hits) {
        $rel = $h.Path.Substring($PSScriptRoot.Length + 1)
        Write-Host ("  {0}:{1}: {2}" -f $rel, $h.LineNumber, $h.Line.Trim()) -ForegroundColor Red
    }
    Write-Host "Ganti dengan BoosokTools.load_module('nama') atau Sketchup.require 'boosok_tools/nama'." -ForegroundColor Red
} else {
    Write-Host "Tidak ada pola berbahaya." -ForegroundColor Green
}

Write-Host ""
if ($failed) {
    Write-Host "GAGAL: perbaiki dulu sebelum upload ke portal." -ForegroundColor Red
    exit 1
}
Write-Host "LOLOS: aman untuk dibuat .rbz dan di-upload ke portal." -ForegroundColor Green
exit 0

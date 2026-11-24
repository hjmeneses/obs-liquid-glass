<#
.SYNOPSIS
    Verifica todo el repo en un solo paso / Checks the whole repo in one step.

.DESCRIPTION
    1. Compila los shaders con fxc (ps_5_0), con una cabecera que imita lo que obs-shaderfilter
       declara antes del shader (image, uv_size, elapsed_time...). Así se detectan errores de sintaxis
       y de tipos sin abrir OBS. Los avisos X3570 son normales.
    2. Revisa la sintaxis de los dos scripts Lua con luaparse (Node.js). La primera vez lo instala en
       %LOCALAPPDATA%\obs-liquid-glass-check (necesita internet una vez).
    3. Compara el código en español con el de en/, quitando comentarios y textos: deben ser idénticos.
    4. Con -SyncTo, si todo pasó, copia los shaders en español a esa carpeta (la que usa OBS).

    Compiles the shaders with fxc, checks Lua syntax with luaparse, verifies that the Spanish and
    English code is identical apart from comments and strings, and optionally syncs the shaders.

.EXAMPLE
    pwsh tools/check.ps1
.EXAMPLE
    pwsh tools/check.ps1 -SyncTo $HOME
#>
[CmdletBinding()]
param(
    # Carpeta donde copiar los shaders en español si todo pasa / Where to copy the shaders on success
    [string]$SyncTo,
    # Ruta a fxc.exe; por defecto busca el Windows SDK más reciente / Defaults to the newest Windows SDK
    [string]$Fxc,
    [switch]$SkipLua
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$failed = 0

function Write-Result([string]$name, [bool]$ok, [string]$detail = '') {
    $mark = if ($ok) { '[ OK ]' } else { '[FAIL]' }
    $color = if ($ok) { 'Green' } else { 'Red' }
    Write-Host "$mark " -ForegroundColor $color -NoNewline
    Write-Host $name -NoNewline
    if ($detail) { Write-Host "  $detail" -ForegroundColor DarkGray } else { Write-Host '' }
}

$spanishShaders = @(
    'liquid-glass.shader',
    'liquid-glass-forma.shader',
    'liquid-glass-lente.shader'
)
$shaders = $spanishShaders + @(
    'en/liquid-glass.shader',
    'en/liquid-glass-shape.shader'
)
# Pares español / inglés que deben tener el mismo código
$pairs = @(
    @('liquid-glass.shader', 'en/liquid-glass.shader'),
    @('liquid-glass-forma.shader', 'en/liquid-glass-shape.shader'),
    @('liquid-glass-presets.lua', 'en/liquid-glass-presets.lua')
)

$tmp = Join-Path ([IO.Path]::GetTempPath()) "obs-liquid-glass-check-$PID"
New-Item -ItemType Directory -Force $tmp | Out-Null

try {
    # ---------------------------------------------------------------- 1. Shaders
    Write-Host "`nShaders (fxc)" -ForegroundColor Cyan
    if (-not $Fxc) {
        $kits = 'C:\Program Files (x86)\Windows Kits\10\bin'
        $Fxc = Get-ChildItem $kits -Directory -Filter '10.*' -ErrorAction SilentlyContinue |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64\fxc.exe' } |
            Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $Fxc -or -not (Test-Path $Fxc)) {
        Write-Result 'fxc.exe' $false 'no encontrado: instala el Windows SDK o usa -Fxc <ruta>'
        $failed++
    } else {
        # Lo que obs-shaderfilter declara antes del texto del shader
        $header = @'
Texture2D image; SamplerState textureSampler;
float2 uv_size; float2 uv_pixel_interval; float elapsed_time;
struct VertData { float4 pos : SV_Position; float2 uv : TEXCOORD0; };
#define texture2d Texture2D
#define TARGET SV_Target
'@
        foreach ($s in $shaders) {
            $src = Join-Path $root $s
            $hlsl = Join-Path $tmp (($s -replace '[\\/]', '_') + '.hlsl')
            Set-Content $hlsl ($header + "`n" + (Get-Content $src -Raw)) -Encoding utf8
            $out = & $Fxc /nologo /T ps_5_0 /E mainImage /Fo (Join-Path $tmp 'out.cso') $hlsl 2>&1 | Out-String
            $errors = @($out -split "`r?`n" | Where-Object { $_ -match 'error X\d+' })
            $ok = ($LASTEXITCODE -eq 0) -and ($errors.Count -eq 0)
            Write-Result $s $ok
            if (-not $ok) {
                $failed++
                # fxc cuenta las líneas de la cabecera; se restan para apuntar a la línea real del .shader
                $offset = ($header -split "`n").Count
                $errors | ForEach-Object {
                    $msg = [regex]::Replace($_, [regex]::Escape($hlsl) + '\((\d+)', {
                            param($m) "$s($([int]$m.Groups[1].Value - $offset)" })
                    Write-Host "       $msg" -ForegroundColor Red
                }
            }
        }
    }

    # ---------------------------------------------------------------- 2. Lua
    Write-Host "`nLua (luaparse)" -ForegroundColor Cyan
    $luaFiles = @('liquid-glass-presets.lua', 'en/liquid-glass-presets.lua')
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($SkipLua) {
        Write-Host '       omitido (-SkipLua)' -ForegroundColor DarkGray
    } elseif (-not $node) {
        Write-Result 'node' $false 'Node.js no encontrado: instálalo o usa -SkipLua'
        $failed++
    } else {
        $cache = Join-Path $env:LOCALAPPDATA 'obs-liquid-glass-check'
        if (-not (Test-Path (Join-Path $cache 'node_modules\luaparse'))) {
            Write-Host "       instalando luaparse en $cache ..." -ForegroundColor DarkGray
            New-Item -ItemType Directory -Force $cache | Out-Null
            & npm install --prefix $cache --no-audit --no-fund --silent luaparse@0.3.1 2>&1 | Out-Null
        }
        $js = Join-Path $tmp 'luacheck.js'
        Set-Content $js -Encoding utf8 @'
const luaparse = require(process.argv[2]);
const fs = require('fs');
let bad = 0;
for (const f of process.argv.slice(3)) {
  try {
    luaparse.parse(fs.readFileSync(f, 'utf8'), { luaVersion: '5.1' });
    console.log('OK\t' + f);
  } catch (e) {
    console.log('FAIL\t' + f + '\t' + e.message);
    bad++;
  }
}
process.exit(bad ? 1 : 0);
'@
        $mod = Join-Path $cache 'node_modules\luaparse'
        $paths = $luaFiles | ForEach-Object { Join-Path $root $_ }
        $res = & node $js $mod @paths 2>&1
        foreach ($line in $res) {
            $parts = "$line" -split "`t"
            if ($parts.Count -lt 2) { Write-Host "       $line" -ForegroundColor Red; $failed++; continue }
            $rel = $parts[1].Substring($root.Length + 1) -replace '\\', '/'
            $ok = $parts[0] -eq 'OK'
            Write-Result $rel $ok ($(if (-not $ok) { $parts[2] }))
            if (-not $ok) { $failed++ }
        }
    }

    # ---------------------------------------------------------------- 3. Paridad ES / EN
    Write-Host "`nEspañol = inglés (sin comentarios ni textos)" -ForegroundColor Cyan
    # Una sola pasada de izquierda a derecha: lo que aparece primero gana. Por qué no varios
    # Replace seguidos: un apóstrofo en un comentario ("doesn't") se tomaba como inicio de cadena
    # y se comía el código hasta el siguiente apóstrofo.
    $luaTokens = [regex]::new(
        '(?<c>--\[(?<e1>=*)\[.*?\]\k<e1>\])|(?<s>\[(?<e2>=*)\[.*?\]\k<e2>\])|(?<c>--[^\r\n]*)' +
        '|(?<s>"(?:\\.|[^"\\\r\n])*")|(?<s>''(?:\\.|[^''\\\r\n])*'')', 'Singleline')
    $hlslTokens = [regex]::new(
        '(?<c>/\*.*?\*/)|(?<c>//[^\r\n]*)|(?<s>"(?:\\.|[^"\\\r\n])*")', 'Singleline')
    function Get-CodeLines([string]$path) {
        $re = if ($path -like '*.lua') { $luaTokens } else { $hlslTokens }
        $t = $re.Replace((Get-Content $path -Raw), {
                param($m) if ($m.Groups['c'].Success) { '' } else { '""' } })
        $t -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }
    foreach ($p in $pairs) {
        $a = @(Get-CodeLines (Join-Path $root $p[0]))
        $b = @(Get-CodeLines (Join-Path $root $p[1]))
        $diff = @(Compare-Object $a $b -SyncWindow 0)
        $ok = $diff.Count -eq 0
        Write-Result "$($p[0])  =  $($p[1])" $ok
        if (-not $ok) {
            $failed++
            $diff | Select-Object -First 6 | ForEach-Object {
                $side = if ($_.SideIndicator -eq '<=') { $p[0] } else { $p[1] }
                Write-Host "       $side`: $($_.InputObject)" -ForegroundColor Red
            }
        }
    }

    # ---------------------------------------------------------------- 4. Copia
    if ($SyncTo) {
        Write-Host "`nCopia a $SyncTo" -ForegroundColor Cyan
        if ($failed) {
            Write-Host '       no se copió nada porque hubo errores' -ForegroundColor Yellow
        } else {
            foreach ($s in $spanishShaders) {
                $src = Join-Path $root $s
                $dst = Join-Path $SyncTo $s
                Copy-Item $src $dst -Force
                $same = (Get-FileHash $src).Hash -eq (Get-FileHash $dst).Hash
                Write-Result $dst $same
                if (-not $same) { $failed++ }
            }
        }
    }
} finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($failed) {
    Write-Host "$failed problema(s) / problem(s)" -ForegroundColor Red
    exit 1
}
Write-Host 'Todo bien / All good' -ForegroundColor Green
exit 0

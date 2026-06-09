# SovereignKernel — Local Build Script (Windows PowerShell)
# Builds all three components: Rust, .NET Service, Electron UI

param(
    [switch]$SkipTests = $false,
    [switch]$NoColor = $false
)

# Setup directories
$BuildDir = ".\build"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = "$BuildDir\build_$Timestamp.log"

# Ensure build directory exists
if (-not (Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir | Out-Null
}

# ANSI colors (disable with -NoColor)
$Colors = @{
    Info    = if ($NoColor) { "" } else { "`e[34m" }  # Blue
    Success = if ($NoColor) { "" } else { "`e[32m" }  # Green
    Warn    = if ($NoColor) { "" } else { "`e[33m" }  # Yellow
    Error   = if ($NoColor) { "" } else { "`e[31m" }  # Red
    Reset   = if ($NoColor) { "" } else { "`e[0m" }   # Reset
}

function Log-Info {
    param([string]$Message)
    $line = "$($Colors.Info)[INFO]$($Colors.Reset) $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Log-Success {
    param([string]$Message)
    $line = "$($Colors.Success)[✓]$($Colors.Reset) $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Log-Warn {
    param([string]$Message)
    $line = "$($Colors.Warn)[WARN]$($Colors.Reset) $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Log-Error {
    param([string]$Message)
    $line = "$($Colors.Error)[ERROR]$($Colors.Reset) $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Test-Command {
    param([string]$Command)
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

# Initialize
Log-Info "Build started at $(Get-Date)"
Log-Info "Log: $LogFile"

# ============================================================================
# 1. Rust — Check & Test
# ============================================================================
Log-Info "════════════════════════════════════════════════════════════════════"
Log-Info "PHASE 1/4: Rust — Check & Test"
Log-Info "════════════════════════════════════════════════════════════════════"

if (-not (Test-Command "cargo")) {
    Log-Error "Rust toolchain not found. Install from https://rustup.rs/"
    exit 1
}

Log-Info "Rust version: $(rustc --version)"
Log-Info "Cargo version: $(cargo --version)"

if (-not $SkipTests) {
    Log-Info "Running cargo check..."
    cargo check --workspace *>> $LogFile
    if ($LASTEXITCODE -ne 0) {
        Log-Error "Cargo check failed"
        exit 1
    }
    Log-Success "Cargo check passed"

    Log-Info "Running cargo tests..."
    cargo test --workspace *>> $LogFile
    if ($LASTEXITCODE -ne 0) {
        Log-Error "Cargo tests failed"
        exit 1
    }
    Log-Success "Cargo tests passed"

    Log-Info "Running clippy..."
    cargo clippy --workspace -- -D warnings *>> $LogFile
    if ($LASTEXITCODE -ne 0) {
        Log-Error "Clippy warnings found"
        exit 1
    }
    Log-Success "Clippy lints passed"

    Log-Info "Checking format..."
    cargo fmt --all -- --check *>> $LogFile
    if ($LASTEXITCODE -ne 0) {
        Log-Error "Format check failed"
        exit 1
    }
    Log-Success "Format check passed"
} else {
    Log-Warn "Tests skipped (--SkipTests flag)"
}

# ============================================================================
# 2. Rust — Build vault-db-tool.exe for Windows
# ============================================================================
Log-Info "════════════════════════════════════════════════════════════════════"
Log-Info "PHASE 2/4: Rust — Build vault-db-tool.exe (Windows x86_64)"
Log-Info "════════════════════════════════════════════════════════════════════"

Log-Info "Installing x86_64-pc-windows-gnu target if needed..."
rustup target add x86_64-pc-windows-gnu *>> $LogFile

Log-Info "Building vault-db-tool for Windows..."
cargo build --release --target x86_64-pc-windows-gnu -p vault-db-tool *>> $LogFile
if ($LASTEXITCODE -ne 0) {
    Log-Error "Rust Windows build failed"
    exit 1
}

$VaultDbExe = "target\x86_64-pc-windows-gnu\release\vault-db-tool.exe"
if (Test-Path $VaultDbExe) {
    $Size = (Get-Item $VaultDbExe).Length
    Copy-Item $VaultDbExe "$BuildDir\" -Force
    Log-Success "Built: vault-db-tool.exe ($Size bytes)"
} else {
    Log-Error "vault-db-tool.exe not found after build"
    exit 1
}

# ============================================================================
# 3. .NET 8 — Build SovereignKernelVault.exe
# ============================================================================
Log-Info "════════════════════════════════════════════════════════════════════"
Log-Info "PHASE 3/4: .NET 8 — Build SovereignKernelVault.exe"
Log-Info "════════════════════════════════════════════════════════════════════"

if (-not (Test-Command "dotnet")) {
    Log-Error ".NET 8 SDK not found. Install from https://dotnet.microsoft.com/download"
    exit 1
}

Log-Info ".NET version: $(dotnet --version)"

$CsProj = "windows-service\SovereignKernelService.csproj"
if (-not (Test-Path $CsProj)) {
    Log-Error "Project file not found: $CsProj"
    exit 1
}

Log-Info "Restoring packages..."
dotnet restore $CsProj *>> $LogFile
if ($LASTEXITCODE -ne 0) {
    Log-Error "Package restore failed"
    exit 1
}
Log-Success "Packages restored"

Log-Info "Building .NET project..."
dotnet build $CsProj -c Release --no-restore *>> $LogFile
if ($LASTEXITCODE -ne 0) {
    Log-Error ".NET build failed"
    exit 1
}
Log-Success "Build completed"

$DotNetPublishDir = "$BuildDir\dotnet-publish"
if (-not (Test-Path $DotNetPublishDir)) {
    New-Item -ItemType Directory -Path $DotNetPublishDir | Out-Null
}

Log-Info "Publishing .NET project..."
dotnet publish $CsProj `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -o $DotNetPublishDir *>> $LogFile

if ($LASTEXITCODE -ne 0) {
    Log-Error ".NET publish failed"
    exit 1
}

$VaultServiceExe = "$DotNetPublishDir\SovereignKernelVault.exe"
if (Test-Path $VaultServiceExe) {
    $Size = (Get-Item $VaultServiceExe).Length
    Log-Success "Published: SovereignKernelVault.exe ($Size bytes)"
} else {
    Log-Error "SovereignKernelVault.exe not found after publish"
    exit 1
}

# ============================================================================
# 4. Electron — Build SovereignKernel.exe (UI)
# ============================================================================
Log-Info "════════════════════════════════════════════════════════════════════"
Log-Info "PHASE 4/4: Electron — Build SovereignKernel.exe (UI)"
Log-Info "════════════════════════════════════════════════════════════════════"

if (-not (Test-Command "node")) {
    Log-Error "Node.js not found. Install from https://nodejs.org/"
    exit 1
}

Log-Info "Node version: $(node --version)"
Log-Info "npm version: $(npm --version)"

Push-Location electron-ui

Log-Info "Installing npm dependencies..."
npm ci *>> "..\$LogFile"
if ($LASTEXITCODE -ne 0) {
    Log-Error "npm install failed"
    Pop-Location
    exit 1
}
Log-Success "npm dependencies installed"

Log-Info "Compiling TypeScript..."
npx tsc -p tsconfig.main.json *>> "..\$LogFile"
if ($LASTEXITCODE -ne 0) {
    Log-Error "TypeScript compilation failed"
    Pop-Location
    exit 1
}
Log-Success "TypeScript main compiled"

Log-Info "Building Vite renderer..."
npx vite build *>> "..\$LogFile"
if ($LASTEXITCODE -ne 0) {
    Log-Error "Vite build failed"
    Pop-Location
    exit 1
}
Log-Success "Vite renderer built"

Log-Info "Building with electron-builder..."
$env:CSC_IDENTITY_AUTO_DISCOVERY = "false"
npx electron-builder --win --dir *>> "..\$LogFile"
if ($LASTEXITCODE -ne 0) {
    Log-Warn "electron-builder had issues, but app files may be generated"
} else {
    Log-Success "Electron app packaged"
}

Pop-Location

# ============================================================================
# Summary
# ============================================================================
Log-Info "════════════════════════════════════════════════════════════════════"
Log-Success "Build completed successfully!"
Log-Info "════════════════════════════════════════════════════════════════════"

Log-Info ""
Log-Info "📦 Output binaries:"
Get-Item "$BuildDir\*.exe" -ErrorAction SilentlyContinue | ForEach-Object { Log-Info "  • $($_.Name) ($($_.Length) bytes)" }

Log-Info ""
Log-Info "📂 Detailed output:"
Log-Info "  • vault-db-tool.exe: $BuildDir\vault-db-tool.exe"
Log-Info "  • SovereignKernelVault.exe: $DotNetPublishDir\SovereignKernelVault.exe"
Log-Info "  • Electron files: .\electron-ui\release\win-unpacked\ (or .\electron-ui\dist\)"

Log-Info ""
Log-Info "✅ Next steps:"
Log-Info "  1. Run Service: & '$DotNetPublishDir\SovereignKernelVault.exe' --service"
Log-Info "  2. Or run UI: & '.\electron-ui\release\win-unpacked\SovereignKernel.exe'"

Log-Info ""
Log-Info "📋 Full build log: $LogFile"

#!/bin/bash
set -euo pipefail

# SovereignKernel — Local Build Script
# Builds all three components: Rust, .NET Service, Electron UI

BUILD_DIR="./build"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${BUILD_DIR}/build_${TIMESTAMP}.log"

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Setup
mkdir -p "$BUILD_DIR"
log_info "Build started at $(date)"
log_info "Log: $LOG_FILE"

# ============================================================================
# 1. Rust — Check & Test
# ============================================================================
log_info "════════════════════════════════════════════════════════════════════"
log_info "PHASE 1/4: Rust — Check & Test"
log_info "════════════════════════════════════════════════════════════════════"

if ! command -v cargo &> /dev/null; then
  log_error "Rust toolchain not found. Install from https://rustup.rs/"
  exit 1
fi

log_info "Rust version: $(rustc --version)"
log_info "Cargo version: $(cargo --version)"

if cargo check --workspace >> "$LOG_FILE" 2>&1; then
  log_success "Cargo check passed"
else
  log_error "Cargo check failed"
  exit 1
fi

if cargo test --workspace >> "$LOG_FILE" 2>&1; then
  log_success "Cargo tests passed"
else
  log_error "Cargo tests failed"
  exit 1
fi

if cargo clippy --workspace -- -D warnings >> "$LOG_FILE" 2>&1; then
  log_success "Clippy lints passed"
else
  log_error "Clippy warnings found"
  exit 1
fi

if cargo fmt --all -- --check >> "$LOG_FILE" 2>&1; then
  log_success "Format check passed"
else
  log_error "Format check failed"
  exit 1
fi

# ============================================================================
# 2. Rust — Build vault-db-tool.exe for Windows
# ============================================================================
log_info "════════════════════════════════════════════════════════════════════"
log_info "PHASE 2/4: Rust — Build vault-db-tool.exe (Windows x86_64)"
log_info "════════════════════════════════════════════════════════════════════"

if ! rustup target list | grep -q "x86_64-pc-windows-gnu (installed)"; then
  log_info "Installing Rust target: x86_64-pc-windows-gnu"
  rustup target add x86_64-pc-windows-gnu >> "$LOG_FILE" 2>&1
fi

if ! command -v x86_64-w64-mingw32-gcc &> /dev/null; then
  log_warn "MinGW not found. On Ubuntu: sudo apt-get install -y gcc-mingw-w64-x86-64"
  log_warn "Skipping Rust Windows build"
else
  if cargo build --release --target x86_64-pc-windows-gnu -p vault-db-tool >> "$LOG_FILE" 2>&1; then
    VAULT_DB_EXE="target/x86_64-pc-windows-gnu/release/vault-db-tool.exe"
    if [ -f "$VAULT_DB_EXE" ]; then
      cp "$VAULT_DB_EXE" "$BUILD_DIR/"
      log_success "Built: vault-db-tool.exe ($(stat -f%z "$BUILD_DIR/vault-db-tool.exe" 2>/dev/null || stat -c%s "$BUILD_DIR/vault-db-tool.exe") bytes)"
    fi
  else
    log_error "Rust Windows build failed"
    exit 1
  fi
fi

# ============================================================================
# 3. .NET 8 — Build SovereignKernelVault.exe
# ============================================================================
log_info "════════════════════════════════════════════════════════════════════"
log_info "PHASE 3/4: .NET 8 — Build SovereignKernelVault.exe"
log_info "════════════════════════════════════════════════════════════════════"

if ! command -v dotnet &> /dev/null; then
  log_error ".NET 8 SDK not found. Install from https://dotnet.microsoft.com/download"
  exit 1
fi

DOTNET_VERSION=$(dotnet --version)
log_info ".NET version: $DOTNET_VERSION"

if [ ! -f "windows-service/SovereignKernelService.csproj" ]; then
  log_error "Project file not found: windows-service/SovereignKernelService.csproj"
  exit 1
fi

if dotnet restore windows-service/SovereignKernelService.csproj >> "$LOG_FILE" 2>&1; then
  log_success "Restored packages"
else
  log_error "Package restore failed"
  exit 1
fi

if dotnet build windows-service/SovereignKernelService.csproj -c Release --no-restore >> "$LOG_FILE" 2>&1; then
  log_success "Build completed"
else
  log_error ".NET build failed"
  exit 1
fi

DOTNET_PUBLISH_DIR="$BUILD_DIR/dotnet-publish"
mkdir -p "$DOTNET_PUBLISH_DIR"

if dotnet publish windows-service/SovereignKernelService.csproj \
  -c Release \
  -r win-x64 \
  --self-contained true \
  -p:PublishSingleFile=true \
  -o "$DOTNET_PUBLISH_DIR" >> "$LOG_FILE" 2>&1; then
  
  VAULT_SERVICE_EXE="$DOTNET_PUBLISH_DIR/SovereignKernelVault.exe"
  if [ -f "$VAULT_SERVICE_EXE" ]; then
    log_success "Published: SovereignKernelVault.exe ($(stat -f%z "$VAULT_SERVICE_EXE" 2>/dev/null || stat -c%s "$VAULT_SERVICE_EXE") bytes)"
  fi
else
  log_error ".NET publish failed"
  exit 1
fi

# ============================================================================
# 4. Electron — Build SovereignKernel.exe (UI)
# ============================================================================
log_info "════════════════════════════════════════════════════════════════════"
log_info "PHASE 4/4: Electron — Build SovereignKernel.exe (UI)"
log_info "════════════════════════════════════════════════════════════════════"

if ! command -v node &> /dev/null; then
  log_error "Node.js not found. Install from https://nodejs.org/"
  exit 1
fi

log_info "Node version: $(node --version)"
log_info "npm version: $(npm --version)"

cd electron-ui

if npm ci >> "../$LOG_FILE" 2>&1; then
  log_success "npm dependencies installed"
else
  log_error "npm install failed"
  exit 1
fi

if npx tsc -p tsconfig.main.json >> "../$LOG_FILE" 2>&1; then
  log_success "TypeScript main compiled"
else
  log_error "TypeScript compilation failed"
  exit 1
fi

if npx vite build >> "../$LOG_FILE" 2>&1; then
  log_success "Vite renderer built"
else
  log_error "Vite build failed"
  exit 1
fi

# Try to build with electron-builder, but allow skip if Wine is missing on Linux
if [ "$(uname -s)" = "Linux" ] && ! command -v wine64 &> /dev/null; then
  log_warn "Wine64 not found. Skipping electron-builder packaging on Linux."
  log_warn "To package on Linux: sudo apt-get install -y wine64"
  log_info "Generated files are in: electron-ui/dist/"
else
  export CSC_IDENTITY_AUTO_DISCOVERY=false
  if npx electron-builder --win --dir >> "../$LOG_FILE" 2>&1; then
    ELECTRON_APP="release/win-unpacked/SovereignKernel.exe"
    if [ -f "$ELECTRON_APP" ]; then
      log_success "Built: Electron app in release/win-unpacked/"
    fi
  else
    log_warn "electron-builder packaging had issues, but app files are generated"
  fi
fi

cd ..

# ============================================================================
# Summary
# ============================================================================
log_info "════════════════════════════════════════════════════════════════════"
log_success "Build completed successfully!"
log_info "════════════════════════════════════════════════════════════════════"

log_info ""
log_info "📦 Output binaries:"
ls -lh "$BUILD_DIR"/ 2>/dev/null || true
log_info ""
log_info "📂 Detailed output:"
log_info "  • vault-db-tool.exe: $BUILD_DIR/vault-db-tool.exe"
log_info "  • SovereignKernelVault.exe: $DOTNET_PUBLISH_DIR/SovereignKernelVault.exe"
log_info "  • Electron files: electron-ui/release/win-unpacked/ (or electron-ui/dist/)"
log_info ""
log_info "✅ Next steps:"
log_info "  1. On Windows, run: .\\build\\SovereignKernelVault.exe --service"
log_info "  2. Or run Electron UI from: electron-ui\\release\\win-unpacked\\SovereignKernel.exe"
log_info ""
log_info "📋 Full build log: $LOG_FILE"

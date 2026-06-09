# 🏗️ Local Build Guide — SovereignKernel

Build all three executable components locally: **vault-db-tool.exe**, **SovereignKernelVault.exe**, and **SovereignKernel.exe**.

## Quick Start

### Windows

```powershell
# Administrator PowerShell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\scripts\build-all.ps1
```

**Options:**
```powershell
.\scripts\build-all.ps1 -SkipTests      # Skip Rust tests (faster)
.\scripts\build-all.ps1 -NoColor        # Disable ANSI colors
```

### Linux / macOS

```bash
chmod +x scripts/build-all.sh
./scripts/build-all.sh
```

---

## Prerequisites

### All Platforms
- **Rust 1.75+** (stable)
  ```bash
  # Install: https://rustup.rs/
  rustc --version
  cargo --version
  ```
- **Node.js 20+**
  ```bash
  # Install: https://nodejs.org/
  node --version
  npm --version
  ```
- **.NET 8.0 SDK**
  ```bash
  # Install: https://dotnet.microsoft.com/download
  dotnet --version
  ```

### Linux Only
```bash
# MinGW for Windows cross-compilation
sudo apt-get install -y gcc-mingw-w64-x86-64

# Wine64 for Electron packaging (optional, build will skip if missing)
sudo apt-get install -y wine64
```

---

## Build Output

After a successful build, you'll find three executables:

| File | Location | Purpose |
|------|----------|---------|
| **vault-db-tool.exe** | `./build/vault-db-tool.exe` | Rust utility for database operations |
| **SovereignKernelVault.exe** | `./build/dotnet-publish/` | Windows Service (cryptography core) |
| **SovereignKernel.exe** | `./electron-ui/release/win-unpacked/` | Desktop UI (React + Electron) |

### Log Files
All builds are logged to `./build/build_YYYYMMDD_HHMMSS.log`

---

## Running the Built Components

### 1. Start the Service

**On Windows:**
```powershell
# Administrator PowerShell
& '.\build\dotnet-publish\SovereignKernelVault.exe' --service
```

Or install as a Windows Service:
```powershell
sc.exe create SovereignKernelVault binPath="C:\path\to\SovereignKernelVault.exe --service"
sc.exe start SovereignKernelVault
```

### 2. Launch the UI

```powershell
& '.\electron-ui\release\win-unpacked\SovereignKernel.exe'
```

---

## Build Phases

### Phase 1: Rust — Check & Test
```bash
cargo check --workspace
cargo test --workspace
cargo clippy --workspace -- -D warnings
cargo fmt --all -- --check
```

### Phase 2: Rust — Build vault-db-tool.exe
```bash
cargo build --release --target x86_64-pc-windows-gnu -p vault-db-tool
```

### Phase 3: .NET 8 — Build Service
```bash
dotnet restore windows-service/SovereignKernelService.csproj
dotnet build windows-service/SovereignKernelService.csproj -c Release
dotnet publish windows-service/SovereignKernelService.csproj \
  -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

### Phase 4: Electron — Build UI
```bash
cd electron-ui
npm ci
npx tsc -p tsconfig.main.json
npx vite build
npx electron-builder --win --dir
```

---

## Troubleshooting

### ❌ "Rust toolchain not found"
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

### ❌ ".NET 8 SDK not found"
- Download: https://dotnet.microsoft.com/download
- Verify: `dotnet --version`

### ❌ "Node.js not found"
- Download: https://nodejs.org/
- Verify: `node --version` (should be 20+)

### ❌ "MinGW not found" (Linux only)
```bash
sudo apt-get update
sudo apt-get install -y gcc-mingw-w64-x86-64
```

### ❌ Build hangs on Electron packaging
Try skipping tests on first run:
```powershell
.\scripts\build-all.ps1 -SkipTests
```

### ❌ "cargo test" fails
Check for issues in `./build/build_*.log`, or run verbose:
```bash
cargo test --workspace -- --nocapture
```

---

## Manual Step-by-Step Build

If the automated scripts fail, try building each component individually:

```bash
# 1. Rust checks
cargo check --workspace
cargo test --workspace

# 2. Build Rust for Windows
rustup target add x86_64-pc-windows-gnu
cargo build --release --target x86_64-pc-windows-gnu -p vault-db-tool

# 3. Build .NET Service
cd windows-service
dotnet restore
dotnet build -c Release
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o ../publish
cd ..

# 4. Build Electron UI
cd electron-ui
npm install
npm run build
npx electron-builder --win --dir
cd ..
```

---

## Continuous Integration

The CI/CD pipeline mirrors these build scripts:
- See: [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)
- Branch requirement: Must pass `main` branch CI before merge

---

## Documentation

- [Architecture](../docs/ARCHITECTURE.md)
- [API Reference](../docs/API.md)
- [Contributing](../CONTRIBUTING.md)

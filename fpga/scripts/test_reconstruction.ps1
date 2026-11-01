param([string]$VivadoBin='C:\AMDDesignTools\2026.1\Vivado\bin')
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$work=Join-Path $repo '.audit_verification/repair_runs'
New-Item -ItemType Directory -Force $work | Out-Null
Push-Location $work
try {
  & "$VivadoBin/xvhdl.bat" "$repo/fpga/ip/fft_256_core/fft_256_core/sim/fft_256_core.vhd" "$repo/fpga/ip/ifft_256_core/ifft_256_core/sim/ifft_256_core.vhd"
  if($LASTEXITCODE -ne 0){throw 'Vendor model compilation failed'}
  $sources=@("$repo/fpga/rtl/pkg/auris_pkg.sv")
  $sources+=Get-ChildItem "$repo/fpga/rtl" -Recurse -Filter *.sv | Where-Object Name -ne auris_pkg.sv | ForEach-Object FullName
  # HEAD alone is insufficient while repairs are uncommitted. Fingerprint the
  # exact RTL, testbench and generated models used by this numerical run.
  $identityFiles=$sources + @(
    "$repo/fpga/sim/testbenches/tb_pipeline_reconstruction.sv",
    "$repo/fpga/ip/fft_256_core/fft_256_core/sim/fft_256_core.vhd",
    "$repo/fpga/ip/ifft_256_core/ifft_256_core/sim/ifft_256_core.vhd"
  )
  $identityFiles | ForEach-Object { Get-FileHash -Algorithm SHA256 -LiteralPath $_ } |
    Select-Object Path,Hash | ConvertTo-Json | Set-Content vendor_reconstruction_sources.json
  & "$VivadoBin/xvlog.bat" --sv @sources "$repo/fpga/sim/testbenches/tb_pipeline_reconstruction.sv" "$VivadoBin/../data/verilog/src/glbl.v"
  if($LASTEXITCODE -ne 0){throw 'RTL/testbench compilation failed'}
  & "$VivadoBin/xelab.bat" work.tb_pipeline_reconstruction work.glbl -L xfft_v9_1_16 -L unisims_ver -L secureip -L xpm -s vendor_reconstruction
  if($LASTEXITCODE -ne 0){throw 'Vendor reconstruction elaboration failed'}
  & "$VivadoBin/xsim.bat" vendor_reconstruction -runall -log vendor_reconstruction_run.log
  if($LASTEXITCODE -ne 0){throw 'Vendor reconstruction simulation failed'}
  $log=Get-Content vendor_reconstruction_run.log -Raw
  if($log -notmatch 'VENDOR_RECONSTRUCTION_PASS' -or $log -match 'Fatal:|Error:'){throw 'Missing successful reconstruction completion'}
} finally { Pop-Location }

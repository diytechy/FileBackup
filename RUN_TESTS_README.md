# Running the FileBackup Test Suite

## Quick Start

Simply run the batch file from the FileBackup folder:

```batch
cd C:\Projects\FileBackup
RunTests.bat
```

## What Happens

### 1. Pre-flight Checks
The batch file verifies:
- ✅ FileBackup.ps1 exists
- ✅ Reconstruct.ps1 exists
- ✅ Test-Backup.ps1 exists
- ✅ 7-Zip is installed (recommended for compression tests)

### 2. Dependency Installation Prompt
When the test harness runs, if K4os.Hash.xxHash is not installed, you'll see:

```
K4os.Hash.xxHash 1.0.8 is not installed.
Install it now via Install-Package K4os.Hash.xxHash -Version 1.0.8? (Y/N)
```

**Simply type `Y` and press Enter** — the script will:
- Download the package via NuGet
- Install to your local user profile
- Continue with tests automatically

**No admin rights needed** — installed per-user.

### 3. Test Execution
The harness runs **3 test suites** × **~10 tests each** = ~30 total tests:

**Test Suites:**
1. **MirrorMode** — Files stored in original folder structure
2. **ContentAddressed** — Files stored by hash+size with dedupe
3. **CompressedCA** — Content-addressed with 7-Zip compression

**Test Groups (per suite):**
- **BasicOps** — Create, modify, move, rename, delete, re-add
- **Reconstruction** — Restore from backup, handle compression, hash fallback
- **EdgeCases** — Empty source, spaces in filenames, deep nesting, special chars

### 4. Results
After the tests complete, you'll see:

```
===============================
TEST RESULTS
===============================

Summary:
  Passed: 28
  Failed: 0

Results exported: C:\Users\<YourUser>\AppData\Local\Temp\BackupTest_20260319_225307\TestResults_20260319_225650.csv
Test root (for inspection): C:\Users\<YourUser>\AppData\Local\Temp\BackupTest_20260319_225307
```

---

## Understanding the Output

### Console Output
Each test prints one of:
- `[OK] TestName` — Passed ✓
- `[FAIL] TestName : Error message` — Failed ✗

### CSV Results File
Located in the temp test folder, contains:
- **Suite** — Test mode (MirrorMode, ContentAddressed, CompressedCA)
- **Group** — Test category (BasicOps, Reconstruction, EdgeCases)
- **TestName** — Specific test (e.g., "InitialBackup_file1_exists")
- **Status** — PASS or FAIL
- **Detail** — Error message if failed
- **Timestamp** — When test ran

### Test Root Folder
All temporary files are in:
```
C:\Users\<YourUser>\AppData\Local\Temp\BackupTest_YYYYMMDD_HHMMSS\
```

You can inspect:
- `Source\` — Source files created for testing
- `Backup\` — Backup repository
- `Changes\` — Change folders created during backup runs
- `Recon\` — Reconstructed files (should match Source)

---

## Interpreting Results

### ✅ All Tests Pass
- New refactored code works correctly
- Decompression is functional
- Hash-based recovery works
- All edge cases handled

### ❌ Some Tests Fail
Check the CSV for:
- Which test failed
- Error message (usually descriptive)
- Which suite/group (helps narrow down)

**Common failures:**
- `Reconstruct.ps1 not found` — Verify file exists in same folder as FileBackup.ps1
- `7-Zip extraction failed` — Verify 7-Zip is installed at `C:\Program Files\7-Zip\7z.exe`
- `Drive X: is already in use` — Close any other programs using those drive letters, restart test

---

## Manual Validation (After Tests Pass)

### Test 1: Verify Decompression
The CompressedCA test mode exercises decompression. To manually verify:

1. Create a test file
2. Run FileBackup.ps1 with `CompressEnabled = $true`
3. Verify files in backup folder are `.7z` archives
4. Run `RECONSTRUCT.ps1` from backup folder
5. Verify reconstructed files are identical to originals:
   ```powershell
   (Get-FileHash .\original.txt).Hash -eq (Get-FileHash .\reconstructed.txt).Hash
   ```

### Test 2: Verify Hash Recovery
1. Make a backup
2. Manually edit the MANIFEST.csv in a change folder
3. Blank out a `DataPath` entry (leave RelativePath intact)
4. Run `RECONSTRUCT.ps1`
5. Verify the file is still recovered (via hash scan)

### Test 3: Verify Config Migration
1. Backup in MirrorMode (PreserveFolderTree=true)
2. Switch to ContentAddressed mode (PreserveFolderTree=false, CompressEnabled=true)
3. Run FileBackup.ps1 again
4. Verify:
   - Backup files are renamed to hash+size format
   - MANIFEST.csv shows StoredAsHashSize='Hash' and Compressed='Yes'
   - Reconstruction still works

---

## Troubleshooting

### "Drive X: is already in use"
Previous test failed before cleanup. Run:
```powershell
cmd /c "subst X: /d 2>nul"
cmd /c "subst Y: /d 2>nul"
cmd /c "subst Z: /d /d 2>nul"
cmd /c "subst W: /d 2>nul"
```
Then retry.

### "K4os.Hash.xxHash.dll not found in installed package"
The NuGet package may not have extracted properly. Try:
```powershell
Get-Package K4os.Hash.xxHash | Uninstall-Package -Force
# Then re-run RunTests.bat and answer Y to reinstall
```

### "7-Zip compression failed"
Verify 7-Zip is installed:
```powershell
Test-Path "C:\Program Files\7-Zip\7z.exe"
```
If not, install from https://www.7-zip.org/

### "RECONSTRUCT.ps1 not found"
Verify the file exists:
```powershell
Test-Path "C:\Projects\FileBackup\Reconstruct.ps1"
```
Both FileBackup.ps1 and Reconstruct.ps1 must be in the same folder.

---

## What Each Component Does

### FileBackup.ps1 (Main Script)
- Scans source folder
- Compares against backup via hash+size
- Copies new/modified files
- Moves deleted files to change folder
- Generates RECONSTRUCT.ps1 scripts

### Reconstruct.ps1 (Generated from Template)
- Aggregates change folder history
- Reconstructs original folder structure
- Decompresses .7z files if needed
- Falls back to hash scan if DataPath missing
- Logs all operations

### Test-Backup.ps1 (Test Harness)
- Creates virtual drives (X:/Y:/Z:/W:)
- Runs 3 backup modes
- Executes 10+ tests per mode
- Exports CSV results
- Cleans up after itself

### RunTests.bat (Launcher)
- Pre-flight validation
- Runs PowerShell harness
- Reports pass/fail
- Points to results file

---

## Expected Execution Time

- First run: **3-5 minutes** (includes NuGet package download)
- Subsequent runs: **1-2 minutes** (package already installed)

Time includes:
- Virtual drive creation/deletion
- Creating test files
- Running backups (3 runs per mode × 3 modes)
- Reconstructing files
- Exporting results

---

## Questions?

See `IMPLEMENTATION_SUMMARY.md` for detailed design information.

Check the test root folder for investigation:
```powershell
explorer "C:\Users\<YourUser>\AppData\Local\Temp\BackupTest_*"
```

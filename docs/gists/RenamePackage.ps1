# Usage:
# Run this script with the following parameters:
# -projectPath: The root path of your Android project
# -oldPackageName: The current package name to be changed
# -newPackageName: The new package name to set
#
# Example:
# .\RenamePackage.ps1 -projectPath "C:\Users\username\StudioProjects\rct" -oldPackageName "com.old.package" -newPackageName "com.new.package"

param (
    [string]$projectPath,
    [string]$oldPackageName,
    [string]$newPackageName
)

# --- VALIDATION ---
if (-Not (Test-Path $projectPath)) {
    Write-Host "Error: Project path not found at '$projectPath'"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($oldPackageName) -or [string]::IsNullOrWhiteSpace($newPackageName)) {
    Write-Host "Error: Old and new package names must be provided."
    exit 1
}

# --- DIRECTORY OPERATIONS ---
# Converts a package name like "com.example.app" to a path like "com\example\app"
function PackageNameToPath($packageName) {
    return $packageName.Replace('.', '\')
}

$oldPackagePath = PackageNameToPath $oldPackageName
$newPackagePath = PackageNameToPath $newPackageName

# Define source directories to check
$sourceRoots = @(
    (Join-Path $projectPath "app\src\main\java"),
    (Join-Path $projectPath "app\src\androidTest\java"),
    (Join-Path $projectPath "app\src\test\java")
)

foreach ($root in $sourceRoots) {
    $oldDir = Join-Path $root $oldPackagePath
    $newDir = Join-Path $root $newPackagePath

    if (Test-Path $oldDir) {
        # Ensure the new parent directory exists
        $newParentDir = Split-Path $newDir -Parent
        if (-Not (Test-Path $newParentDir)) {
            New-Item -ItemType Directory -Path $newParentDir -Force | Out-Null
        }
        
        # Move the directory
        Write-Host "Moving contents from '$oldDir' to '$newDir'..."
        Move-Item -Path $oldDir -Destination $newDir -Force
        
        # Clean up old empty parent directories
        $parent = Split-Path $oldDir -Parent
        while ($parent -ne $root -and (Get-ChildItem -Path $parent).Count -eq 0) {
            Write-Host "Removing empty directory '$parent'..."
            Remove-Item -Path $parent -Force
            $parent = Split-Path $parent -Parent
        }
    }
}

# --- FILE CONTENT REPLACEMENT ---
Write-Host "Updating package name references in files..."
$filesToUpdate = Get-ChildItem -Path $projectPath -Recurse -Include *.java, *.kt, *.xml, *.gradle, *.kts

foreach ($file in $filesToUpdate) {
    # Use -Raw to read the whole file at once for better performance
    $content = Get-Content -Path $file.FullName -Raw
    if ($content -match [regex]::Escape($oldPackageName)) {
        Write-Host "Updating file: $($file.FullName)"
        $newContent = $content -replace [regex]::Escape($oldPackageName), $newPackageName
        # Use -NoNewLine to prevent adding extra lines at the end of files
        Set-Content -Path $file.FullName -Value $newContent -Force -NoNewLine
    }
}

Write-Host "Script finished. Package name change from '$oldPackageName' to '$newPackageName' is complete."
Write-Host "Please perform a clean build and sync your project in Android Studio."

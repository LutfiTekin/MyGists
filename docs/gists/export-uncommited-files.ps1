$dest = "C:\Users\lutfi\Desktop\uncommited files"
New-Item -ItemType Directory -Path $dest -Force | Out-Null

git diff --name-only HEAD | ForEach-Object {
    $source = Join-Path (Get-Location) $_
    $destination = Join-Path $dest (Split-Path $_ -Leaf)
    Copy-Item $source $destination -Force
}
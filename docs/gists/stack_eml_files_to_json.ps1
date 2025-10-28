# Requires PowerShell 7+
# Install MimeKit: Install-Package MimeKit

Add-Type -Path "C:\Program Files\PackageManagement\NuGet\Packages\MimeKit.4.14.0\lib\netstandard2.0\MimeKit.dll"  # adjust path if needed

$emlFiles = Get-ChildItem -Path . -Filter *.eml
$result = @()

foreach ($file in $emlFiles) {
    try {
        $stream = [System.IO.File]::OpenRead($file.FullName)
        $message = [MimeKit.MimeMessage]::Load($stream)
        $stream.Close()

        # Get headers
        $from = ($message.From | ForEach-Object { $_.ToString() }) -join ", "
        $to = ($message.To | ForEach-Object { $_.ToString() }) -join ", "
        $subject = $message.Subject
        $date = $message.Date.UtcDateTime

        # Get body
        if ($message.TextBody) {
            $body = $message.TextBody
        } elseif ($message.HtmlBody) {
            $body = $message.HtmlBody -replace "<[^>]+>", "" -replace "&nbsp;", " "
        } else {
            $body = ""
        }

        $obj = [PSCustomObject]@{
            FileName = $file.Name
            From     = $from
            To       = $to
            Subject  = $subject
            Date     = $date
            Body     = $body.Trim()
        }

        $result += $obj
    } catch {
        Write-Warning "Failed to parse $($file.Name): $_"
    }
}

# Sort newest first
$result = $result | Sort-Object Date -Descending

# Save JSON
$result | ConvertTo-Json -Depth 3 | Set-Content -Path "emails_clean.json" -Encoding UTF8
Write-Host "✅ Parsed $($result.Count) emails into emails_clean.json"

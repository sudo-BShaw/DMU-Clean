# Shared setup for DMU Pester tests.
# Dot-sources Public and Private functions from the repo without requiring installation.

$repoRoot = Split-Path $PSScriptRoot -Parent
$publicDir  = Join-Path $repoRoot 'src\Public'
$privateDir = Join-Path $repoRoot 'src\Private'

foreach ($dir in @($privateDir, $publicDir)) {
    if (Test-Path $dir) {
        Get-ChildItem -Path $dir -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
            . $_.FullName
        }
    }
}

# Ensure key commands are visible to tests
$script:DMURepoRoot = $repoRoot
param(
  [switch]$UseLocalAdminSource
)

$ErrorActionPreference = 'Stop'
$coreRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$lockPath = Join-Path $coreRoot 'apps/core/mx-admin.lock.json'
$adminLock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
if ($adminLock.commit -notmatch '^[0-9a-f]{40}$') { throw 'Admin lock must contain a full commit SHA.' }
if ($adminLock.repository -notmatch '^https://github\.com/[^/]+/[^/]+\.git$') { throw 'Admin lock must contain a GitHub HTTPS Git URL.' }
$coreCommit = (git -C $coreRoot rev-parse HEAD).Trim()
$coreChanges = git -C $coreRoot status --porcelain -- dockerfile apps/core/package.json apps/core/mx-admin.lock.json
$sourceCommit = if ($coreChanges) { "$coreCommit-working-tree" } else { $coreCommit }
$adminRoot = Join-Path (Split-Path $coreRoot -Parent) 'mx-admin'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mx-space-build-" + [guid]::NewGuid().ToString('N'))
$coreContext = Join-Path $tempRoot 'core'
$adminContext = Join-Path $tempRoot 'admin'
$adminContextUri = $null

function Assert-PathWithinBuildTemp([string]$candidate) {
  $resolvedRoot = [System.IO.Path]::GetFullPath($tempRoot).TrimEnd('\') + '\'
  $resolvedCandidate = [System.IO.Path]::GetFullPath($candidate)
  if (-not $resolvedCandidate.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to remove a path outside the temporary build directory.'
  }
}

try {
  New-Item -ItemType Directory -Path $coreContext, $adminContext -Force | Out-Null
  git clone --quiet --shared --no-checkout $coreRoot $coreContext
  if ($LASTEXITCODE -ne 0) { throw 'Unable to create isolated Core build context.' }
  git -C $coreContext checkout --quiet HEAD
  if ($LASTEXITCODE -ne 0) { throw 'Unable to check out clean Core HEAD in build context.' }
  foreach ($relativePath in @('Dockerfile', 'apps/core/package.json', 'apps/core/mx-admin.lock.json')) {
    $destination = Join-Path $coreContext $relativePath
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $coreRoot $relativePath) -Destination $destination -Force
  }

  if ($UseLocalAdminSource) {
    git clone --quiet --shared --no-checkout $adminRoot $adminContext
    if ($LASTEXITCODE -ne 0) { throw 'Unable to create isolated Admin build context.' }
    git -C $adminContext checkout --quiet $adminLock.commit
    if ($LASTEXITCODE -ne 0) { throw 'Unable to check out the pinned Admin commit in build context.' }
    $adminContextUri = $adminContext
  } else {
    $adminContextUri = "$($adminLock.repository)#$($adminLock.commit)"
  }

  $coreGitMetadata = Join-Path $coreContext '.git'
  Assert-PathWithinBuildTemp $coreGitMetadata
  Remove-Item -LiteralPath $coreGitMetadata -Recurse -Force
  if ($UseLocalAdminSource) {
    $adminGitMetadata = Join-Path $adminContext '.git'
    Assert-PathWithinBuildTemp $adminGitMetadata
    Remove-Item -LiteralPath $adminGitMetadata -Recurse -Force
  }

  docker buildx build `
    --file (Join-Path $coreContext 'Dockerfile') `
    --build-context "admin-src=$adminContextUri" `
    --build-arg "ADMIN_COMMIT=$($adminLock.commit)" `
    --build-arg "SOURCE_COMMIT=$sourceCommit" `
    --tag 'cynthia174/mx-server:10.5.3-dev' `
    --load `
    $coreContext

  if ($LASTEXITCODE -ne 0) { throw 'Docker build failed.' }
} finally {
  if (Test-Path -LiteralPath $tempRoot) {
    $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
    $expectedParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
    if ((Split-Path $resolvedTempRoot -Parent) -ne $expectedParent -or
        (Split-Path $resolvedTempRoot -Leaf) -notmatch '^mx-space-build-[0-9a-f]{32}$') {
      throw 'Refusing to remove an unexpected build directory.'
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}

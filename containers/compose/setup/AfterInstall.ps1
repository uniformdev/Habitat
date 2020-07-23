param(
    [Parameter(Mandatory=$True)]
    $WebsiteRootPath,
    [Parameter(Mandatory=$False)]
    $SrcSourceFolderPath,
    [Parameter(Mandatory=$True)]
    $ScVariableName,
    [switch]
    $Force
)

Push-Location $PSScriptRoot
try {
    $WebConfig = "$WebsiteRootPath\web.config";
    $SitecoreKernel = "$WebsiteRootPath\bin\Sitecore.Kernel.dll";
    if (-not $Force) {
        if ((-not(Test-Path "$WebConfig")) -and (-not (Test-Path "$SitecoreKernel"))) {
            # try to fix if only Website was missed
            $WebsiteRootPath = "$WebsiteRootPath\Website"
        }
    
        $WebConfig = "$WebsiteRootPath\web.config";
        if (-not(Test-Path "$WebConfig")) {
            Write-Error "The WebsiteRootPath seem to be invalid, cannot find: $WebConfig"
            exit;
        }
    
        $SitecoreKernel = "$WebsiteRootPath\bin\Sitecore.Kernel.dll";
        if (-not (Test-Path "$SitecoreKernel")) {
            Write-Error "The WebsiteRootPath seem to be invalid, cannot find: $SitecoreKernel"
            exit;
        }
    } elseif (-not(Test-Path "$WebsiteRootPath")) {
        MKDIR $WebsiteRootPath
    }
    
    & .\_PublishProfiles.ps1 -WebsiteRootPath $WebsiteRootPath
    & .\_SourcePath.ps1 -WebsiteRootPath $WebsiteRootPath -SrcSourceFolderPath $SrcSourceFolderPath -ScVariableName $ScVariableName
} finally {
    Pop-Location
}

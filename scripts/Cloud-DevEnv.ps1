Param(
    [Parameter(Mandatory=$false)]
    [string] $version = "cloud",
    [Parameter(Mandatory=$true)]
    [string] $environmentName,
    [switch] $reuseEnvironment
)

$baseFolder = (Get-Item (Join-Path $PSScriptRoot "..")).FullName
. (Join-Path $PSScriptRoot "Read-Settings.ps1") -environment 'Local' -version $version
. (Join-Path $PSScriptRoot "Install-BcContainerHelper.ps1") -bcContainerHelperVersion $bcContainerHelperVersion -genericImageName $genericImageName

if (("$vaultNameForLocal" -eq "") -or !(Get-AzKeyVault -VaultName $vaultNameForLocal)) {
    throw "You need to setup a Key Vault for use with local pipelines"
}
Get-AzKeyVaultSecret -VaultName $vaultNameForLocal | ForEach-Object {
    Write-Host "Get Secret $($_.Name)Secret"
    Set-Variable -Name "$($_.Name)Secret" -Value (Get-AzKeyVaultSecret -VaultName $vaultNameForLocal -Name $_.Name -WarningAction SilentlyContinue)
}
$licenseFile = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($licenseFileSecret.SecretValue))
$insiderSasToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($insiderSasTokenSecret.SecretValue))
$credential = New-Object pscredential 'admin', $passwordSecret.SecretValue
$refreshToken = $BcSaasRefreshTokenSecret.SecretValue | Get-PlainText
$authContext = $null

if ($refreshToken -and $environmentName) {
    $authContext = New-BcAuthContext -refreshToken $refreshToken
    $existingEnvironment = Get-BcEnvironments -bcAuthContext $authContext | Where-Object { $_.Name -eq $environmentName }
    if ($existingEnvironment) {
        if ($existingEnvironment.type -ne "Sandbox") {
            throw "Environment $environmentName already exists and it is not a sandbox environment"
        }
        if (!$reuseEnvironment) {
            Remove-BcEnvironment -bcAuthContext $authContext -environment $environmentName
            $existingEnvironment = $null
        }
    }
    if ($existingEnvironment) {
        $countryCode = $existingEnvironment.CountryCode.ToLowerInvariant()
        $baseApp = Get-BcPublishedApps -bcAuthContext $authContext -environment $environmentName | Where-Object { $_.Name -eq "Base Application" }
    }
    else {
        $countryCode = $artifact.Split('/')[3]
        New-BcEnvironment -bcAuthContext $authContext -environment $environmentName -countryCode $countrycode -environmentType "Sandbox" | Out-Null
        do {
            Start-Sleep -Seconds 10
            $baseApp = Get-BcPublishedApps -bcAuthContext $authContext -environment $environmentName | Where-Object { $_.Name -eq "Base Application" }
        } while (!($baseApp))
        $baseapp | Out-Host
    }

    $artifact = Get-BCArtifactUrl `
        -country $countryCode `
        -version $baseApp.Version `
        -select Closest
    
    if ($artifact) {
        Write-Host "Using Artifacts: $artifact"
    }
    else {
        throw "No artifacts available"
    }
}

$allTestResults = "testresults*.xml"
$testResultsFile = Join-Path $baseFolder "TestResults.xml"
$testResultsFiles = Join-Path $baseFolder $allTestResults
if (Test-Path $testResultsFiles) {
    Remove-Item $testResultsFiles -Force
}

Run-AlPipeline `
    -pipelineName $pipelineName `
    -containerName $containerName `
    -imageName $imageName `
    -bcAuthContext $authContext `
    -environment $environmentName `
    -artifact $artifact.replace('{INSIDERSASTOKEN}',$insiderSasToken) `
    -memoryLimit $memoryLimit `
    -baseFolder $baseFolder `
    -licenseFile $licenseFile `
    -installApps $installApps `
    -installTestApps $installTestApps `
    -appFolders $appFolders `
    -testFolders $testFolders `
    -testResultsFile $testResultsFile `
    -testResultsFormat 'JUnit' `
    -installTestRunner:$installTestRunner `
    -installTestFramework:$installTestFramework `
    -installTestLibraries:$installTestLibraries `
    -installPerformanceToolkit:$installPerformanceToolkit `
    -credential $credential `
    -doNotRunTests `
    -useDevEndpoint `
    -updateLaunchJson "Cloud Sandbox" `

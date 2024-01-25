Function Connect-TOPdeskAPI {
    <#
    .SYNOPSIS
    Connect to the Topdesk API
    
    .DESCRIPTION
    Connect to the Topdesk API and generate a Token variable that can be used with your own Invoke-RestMethod commands '$topdeskAuthenticationHeader'
    All Functions within this Module already has this variable implemented.
    
    .PARAMETER Url
    Your Topdesk Url
    
    .PARAMETER LoginName
    The username of the account with the App Password

    .PARAMETER Secret
    App secret
    
    .PARAMETER LogToFile
    Connect to PSLoggingFunctions module, read more on GitHub, it create a Log folder in your directory if set to True
    
    .EXAMPLE
    Connect-TopdeskAPI -Url "https://topdesk.internal.local" -LoginName $TopdeskApplicationID -Secret $TopdeskAPISecret -LogToFile $False
    
    OUTPUT
    Topdesk Authenticated: True
    Topdesk URL = https://topdesk.internal.local
    Use Header Connection Variable = $topdeskAuthenticationHeader
    #>
    param(
        [parameter(mandatory)]
        $Url,
        [parameter(mandatory)]
        $LoginName,
        [parameter(mandatory)]
        $Secret,
        [parameter(mandatory)]
        [ValidateSet("True","False")]
        $LogToFile
    )

    $topdeskAuthenticationHeader = @{'Authorization' = "Basic $([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($LoginName):$($Secret)")))"}

    Write-Log -Message "Connecting to Topdesk API" -Active $LogToFile

    $testConnection = Invoke-RestMethod -Uri "$Url/tas/api/version" -ContentType "application/json" -Method GET -Headers $topdeskAuthenticationHeader
    $global:TopdeskAuthenticated = $false
    if ($testConnection){
        $global:topdeskAuthenticated = $true
        $global:topdeskUrl = $Url
        Write-Log -Message "Topdesk Authenticated: $TopdeskAuthenticated`nTopdesk URL = $TopdeskUrl" -Active $LogToFile
        Write-Host "Topdesk Authenticated: $TopdeskAuthenticated`nTopdesk URL = $TopdeskUrl`nUse Header Connection Variable ="'$topdeskAuthenticationHeader'
        $global:topdeskAuthenticationHeader = $topdeskAuthenticationHeader
        return ""
    }
    Write-Log -Message "Topdesk Authenticated: $TopdeskAuthenticated" -Active $LogToFile
    Write-Host "Topdesk Authenticated: $TopdeskAuthenticated"
    return $false
}

function Find-TopdeskConnection {
    if (!$topdeskAuthenticated){
        Write-Warning "Topdesk API is not authenticated, you need to run Connect-TOPdeskAPI and make sure you put in the correct credentials!"
        return $false
    }
    return $true
}

Function Get-TopdeskSuppliers {
    param(
        [parameter(mandatory)]
        [ValidateSet("true","false")]
        $LogToFile
    )
    if (Find-TopdeskConnection) {
        $Suppliers = Invoke-TryCatchLog -InfoLog "Getting all TOPdesk suppliers" -LogToFile $LogToFile -ScriptBlock {
            (Invoke-RestMethod -Uri "$topdeskUrl/tas/api/suppliers" -Method GET -Headers $topdeskAuthenticationHeader) | Select-Object name,id
        }
        return $Suppliers
    }
}

Function Get-TopdeskAssetDropdownOptions {
    param(
        [parameter(mandatory)]
        $DropdownName,
        [parameter(mandatory)]
        [ValidateSet("true","false")]
        $LogToFile
    )
    if (Find-TopdeskConnection) {
        $Dropdown = Invoke-TryCatchLog -InfoLog "Retrieving all Topdesk Assets available Dropdown Options: $DropdownName" -LogToFile $LogToFile -ScriptBlock { 
            (Invoke-RestMethod -Uri "$topdeskUrl/tas/api/assetmgmt/dropdowns/$($DropdownName)?field=name" -ContentType "application/json" -Method GET -Headers $topdeskAuthenticationHeader).results
        }
        return $Dropdown
    }
}

function Get-TopdeskAssets {
    <#
    .SYNOPSIS
    Retrieve all devices from TOPdesk asset registry
    
    .DESCRIPTION
    Retrieve all devices from TOPdesk asset registry and let the user choose if they want a HashTable object or just normal Powershell Object
    Also the ability to set which property to be the key in the hashtable.
    
    .PARAMETER Template
    Which template to return, for example Computer or Mobile phone

    .PARAMETER excludeArchived
    Does what is says, it excludes all archived assets

    .PARAMETER HashTableKey
    The $variable[keyvalue] - The key value that will be the filter
    
    .PARAMETER AsHashTable
    If the function should return a HashTable otherwise it will be normal powershell object.
    
    .PARAMETER LogToFile
    This parameter is connected to the Module PSLoggingFunctions mot information can be found on the GitHub.
    https://github.com/rakelord/PSLoggingFunctions
    
    .EXAMPLE
    Return a HashTable with the 'name' as Hash Key and create a log
    Get-TopdeskDevices -Templates ('Computer','Mobile phone') -excludeArchived -AsHashTable -HashTableKey "name" -LogToFile $True
    
    Return a Normal Powershell object and do not Log 
    Get-TopdeskDevices -LogToFile $False
    #>
    Param(
        [string]$Template,
        [switch]
        $excludeArchived,
        [parameter(mandatory)]
        [ValidateSet("True","False")]
        $LogToFile
    )

    $templateQuery = ""
    if ($Template){
        $templateQuery = "&templateName=$Template"
    }

    $archivedQuery = ""
    if ($excludeArchived){
        $archivedQuery = "&archived=false"
    }

    if (Find-TopdeskConnection) {
        $DevicesReturned = 0
        $AssetTable = @()

        Write-Log "Retrieving Topdesk Assets $($Template -join ',')" -Active $LogToFile

        # Retrieve the first list of objects, before we are able to filter the list based on the Last object (According to TOPdesks API documentation)
        $pagingUrl = "$($topdeskUrl)/tas/api/assetmgmt/assets?showAssignments&"+'fields=name,id'+$templateQuery+$archivedQuery
        $AssetTable += (Invoke-RestMethod -Headers $topdeskAuthenticationHeader -Uri $pagingUrl -UseBasicParsing -Method "GET" -ContentType "application/json").dataSet | Select-Object *,@{l='parameters';e={}}
        $Results = $AssetTable
        do {
            $pagingUrl = "$($topdeskUrl)/tas/api/assetmgmt/assets?showAssignments&"+'fields=name,id'+'&$filter=name gt '+"'$(($Results | Select-Object -Last 1).name)'"+$templateQuery+$archivedQuery
            $Results = (Invoke-RestMethod -Headers $topdeskAuthenticationHeader -Uri $pagingUrl -UseBasicParsing -Method "GET" -ContentType "application/json").dataSet | Select-Object *,@{l='parameters';e={}}
            $AssetTable += $Results
            $DevicesReturned += 50
            
            Clear-Host
            Write-Host "Retrieving All Topdesk Assets: $DevicesReturned$Loading"
            $Loading += "."
            if ($Loading.length -gt 7){$Loading = "."}
        } until (!($Results))

        $CompletedDevice = 0
        foreach ($Result in $AssetTable){
            $Data = (Invoke-RestMethod -Method GET -Uri "$($topdeskUrl)/tas/api/assetmgmt/assets/$($Result.unid)" -Headers $topdeskAuthenticationHeader -ContentType "application/json").data
            $Result.parameters += $Data
            
            $CompletedDevice += 1
            
            Clear-Host
            Write-Host "Adding in all Custom Parameters for each device - Completed: $CompletedDevice out of $($AssetTable.count)$Loading"
            $Loading += "."
            if ($Loading.length -gt 7){$Loading = "."}
        }

        Write-Host "Topdesk Assets Loaded: $($AssetTable.count)"

        return $AssetTable
    }
}
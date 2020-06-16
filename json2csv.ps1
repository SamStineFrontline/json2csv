Function Combine-Objects {
    <#
        .SYNOPSIS
        Combine two PowerShell Objects into one.

        .DESCRIPTION
        will combine two custom powershell objects in order to make one. This can be helpfull to add information to an already existing object. (this might make sence in all the cases through).


        .EXAMPLE

        Combine objects allow you to combine two seperate custom objects together in one.

        $Object1 = [PsCustomObject]@{"UserName"=$UserName;"FullName" = $FullName;"UPN"=$UPN}
        $Object2 = [PsCustomObject]@{"VorName"= $Vorname;"NachName" = $NachName}

        Combine-Object -Object1 $Object1 -Object2 $Object2

        Name                           Value
        ----                           -----
        UserName                       Vangust1
        FullName                       Stephane van Gulick
        UPN                            @PowerShellDistrict.com
        VorName                        Stephane
        NachName                       Van Gulick

        .EXAMPLE

        It is also possible to combine system objects (Which could not make sence sometimes though!).

        $User = Get-ADUser -identity vanGulick
        $Bios = Get-wmiObject -class win32_bios

        Combine-Objects -Object1 $bios -Object2 $User


        .NOTES
        -Author: Stephane van Gulick
        -Twitter : stephanevg
        -CreationDate: 10/28/2014
        -LastModifiedDate: 10/28/2014
        -Version: 1.0
        -History:

    .LINK
         http://www.powershellDistrict.com
    #>


    Param (
        [Parameter(mandatory=$true)]$Object1,
        [Parameter(mandatory=$true)]$Object2
    )

    [HashTable] $arguments = @{}

    foreach ( $Property in $Object1.psobject.Properties){
        $arguments += @{$Property.Name = $Property.value}

    }

    foreach ( $Property in $Object2.psobject.Properties){
        $arguments += @{ $Property.Name= $Property.value}

    }


    $Object3 = [Pscustomobject]$arguments


    return $Object3
}

Function GetTopLevelFieldsAsObject($item) {
    return [PSCustomObject]@{
        Timestamp = $item | Select-Object -ExpandProperty "@timestamp";
        Level = $item.level;
        Message = $item.message -replace ",", "";
    }
}

$script:allFields = @()

Function GetJsonFieldPropertiesAsObject($item, $topLevelItemName) {
    $properties = [PSCustomObject]@{}

    $item `
    | ForEach-Object {
        [bool] $propertyCreatedInThisCall = 0

        $_.PSObject.Properties | ForEach-Object {
            $propertyToAdd = [PSCustomObject]@{}
            $fieldName = "$($topLevelItemName).$($_.Name)"

            if ($_.TypeNameOfValue -eq "System.Management.Automation.PSCustomObject") {
                $propertyToAdd = GetJsonFieldPropertiesAsObject -item $_.Value -topLevelItemName $fieldName
            } else {
                $propertyToAdd = [PSCustomObject]@{
                    MemberType = $_.MemberType;
                    Name = $fieldName;
                    Value = $_.Value;
                }

                $propertyCreatedInThisCall = 1

                if (! $script:allFields.Contains($fieldName)) {
                    $script:allFields += $fieldName
                }
            }

            if ($propertyCreatedInThisCall){
                $properties | Add-Member -MemberType $propertyToAdd.MemberType -Name $propertyToAdd.Name  -Value $propertyToAdd.Value
            } elseif (! $null -eq $propertyToAdd.PSobject.Properties.Name) {
                $propertyToAdd.PSObject.Properties | ForEach-Object {
                    $properties | Add-Member -MemberType $_.MemberType -Name $_.Name  -Value $_.Value
                }
            }
        }
    }

    return $properties;
}

Function GetNestedFieldsAsObject($item) {
    $fields = $item | Select-Object -ExpandProperty fields

    $queryStringProperties = @{}
    $cookieProperties = @{}
    $securityBlockProperties = @{}
    $baseProperties = [PSCustomObject]@{}

    $fields.PSObject.Properties | ForEach-Object {
        $currentProperty = $_

        switch ($currentProperty.Name) {
            "QueryString" {
                $queryStringProperties =  GetJsonFieldPropertiesAsObject -item ($currentProperty | Select-Object -ExpandProperty Value) -topLevelItemName "QueryString";
                break;
            }
            "Cookies" {
                $cookieProperties = GetJsonFieldPropertiesAsObject -item ($currentProperty | Select-Object -ExpandProperty Value) -topLevelItemName "Cookies";
                break;
            }
            "SecurityBlock" {
                $securityBlockProperties = GetJsonFieldPropertiesAsObject -item ($currentProperty | Select-Object -ExpandProperty Value) -topLevelItemName "SecurityBlock";
                break;
            }
            Default {
                if (! $script:allFields.Contains($currentProperty.Name)) {
                    $script:allFields += $currentProperty.Name
                }

                $baseProperties | Add-Member -MemberType $currentProperty.MemberType -Name $currentProperty.Name  -Value $currentProperty.Value
            }
        }
    }

    $nestedProperties = Combine-Objects -Object1 $queryStringProperties -Object2 $cookieProperties

    if ($securityBlockProperties.PSObject.Properties.Name.Count -le 3) {
        $nestedProperties = Combine-Objects -Object1 [PSCustomObject]$nestedProperties -Object2 $securityBlockProperties
    }

    $combinedProperties = Combine-Objects -Object1 $baseProperties -Object2 $nestedProperties

    return $combinedProperties
}

Function GetJsonFromREST($resultsOffset, $resultsPerRequest) {
    $url = "http:/foo.com/bar"
    $body = Get-Content request.json
    $body = $body -replace '#resultsOffset', $resultsOffset
    $body = $body -replace '#resultsPerRequest', $resultsPerRequest
    $headers = @{"Content-Type" = "application/json"}

    Invoke-RestMethod -Method 'Post' -Uri $url -Headers $headers -Body $body -Outfile logs.json
}

$results = @()
$resultsOffset = 0
$resultsPerRequest = 10
[bool] $allResultsFound = 0

Do {
    GetJsonFromREST -resultsOffset $resultsOffset -resultsPerRequest $resultsPerRequest
    $hits = Get-Content logs.json `
        | ConvertFrom-Json `
        | Select-Object -ExpandProperty hits `
        | Select-Object -ExpandProperty hits

    if (! $hits -eq ""){
        $results += $hits `
        | Select-Object -ExpandProperty "_source"  `
        | ForEach-Object { Combine-Objects -Object1 (GetTopLevelFieldsAsObject -item $_) -Object2 (GetNestedFieldsAsObject -item $_) }
    } else {
        $allResultsFound = 1
    }

    $resultsOffset += $resultsPerRequest
} While ($resultsOffset -lt 30)

$script:allFields.ForEach(
    {
        if (! ($results[0].PSObject.Properties.Name -contains $_) ){
            $results[0] | Add-Member -MemberType NoteProperty -Name $_  -Value $null
        }
    }
)

$results | Export-Csv -Path .\logs.csv -NoTypeInformation


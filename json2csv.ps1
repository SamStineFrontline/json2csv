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

$script:allFieldNames = @()

Function GetJsonFieldPropertiesAsObject($item, $topLevelItemName) {
    $jsonAsObject = [PSCustomObject]@{}
    $properties = $item.PSObject.Properties

    foreach ($property in $properties){
        $propertyToAdd = [PSCustomObject]@{}
        $propertyName = "$($topLevelItemName).$($property.Name)"

        if ($topLevelItemName -eq ""){
            $propertyName = $property.Name
        }

        if ($property.TypeNameOfValue -eq "System.Management.Automation.PSCustomObject") {
            $propertyToAdd = GetJsonFieldPropertiesAsObject -item $property.Value -topLevelItemName $propertyName
        } else {
            $propertyToAdd = [PSCustomObject]@{
                MemberType = $property.MemberType;
                Name = $propertyName;
                Value = $property.Value;
            }
        }

        if ($null -eq $propertyToAdd.MemberType){
            $propertiesToAdd = $propertyToAdd.PSObject.Properties

            foreach ($propertyToAdd in $propertiesToAdd){
                $jsonAsObject | Add-Member -MemberType $property.MemberType -Name $propertyToAdd.Name  -Value $propertyToAdd.Value

                if (! ($script:allFieldNames -contains $propertyToAdd.Name)) {
                    $script:allFieldNames += $propertyToAdd.Name
                }

            }
        } else {
            $jsonAsObject | Add-Member -MemberType $propertyToAdd.MemberType -Name $propertyToAdd.Name  -Value $propertyToAdd.Value

            if (! ($script:allFieldNames -contains $propertyToAdd.Name)) {
                $script:allFieldNames += $propertyToAdd.Name
            }
        }
    }

    return $jsonAsObject;
}

Function GetJsonFromREST($resultsPerRequest, $minResultDateInclusive, $maxResultDateNonInclusive) {
    $url = "http:/foo.com/bar"
    $body = Get-Content request.json
    $body = $body -replace '#resultsPerRequest', $resultsPerRequest
    $body = $body -replace '#minResultDateInclusive', """$($minResultDateInclusive)"""
    $body = $body -replace '#maxResultDateNonInclusive', """$($maxResultDateNonInclusive)"""
    $headers = @{"Content-Type" = "application/json"}

    Invoke-RestMethod -Method 'Post' -Uri $url -Headers $headers -Body $body -Outfile logs.json
}

$results = @()
$resultsPerRequest = 10000
[bool] $resultsFound = 0
$minResultDateInclusive = Get-Date -Date "1970-01-01 00:00:00Z"
$maxResultDateNonInclusive = Get-Date -Date "1970-01-01 00:01:00Z"

Do {
    GetJsonFromREST -resultsPerRequest $resultsPerRequest -minResultDateInclusive ($minResultDateInclusive.ToUniversalTime().ToString("o")) -maxResultDateNonInclusive ($maxResultDateNonInclusive.ToUniversalTime().ToString("o"))
    $hits = Get-Content logs.json `
        | ConvertFrom-Json `
        | Select-Object -ExpandProperty hits `
        | Select-Object -ExpandProperty hits

    if (! $hits -eq ""){
        $resultsFound = 1

        $results += $hits `
        | Select-Object -ExpandProperty "_source"  `
        | ForEach-Object { Combine-Objects -Object1 (GetTopLevelFieldsAsObject -item $_) -Object2 (GetJsonFieldPropertiesAsObject -item ($_ | Select-Object -ExpandProperty fields) -topLevelItemName "") }

        $lastResult = $results[$results.Length - 1]
        $maxResultDateNonInclusive = (Get-Date -Date $lastResult.Timestamp).ToUniversalTime()
    } else {
        $resultsFound = 0
    }
} While ($resultsFound -and ($minResultDateInclusive -lt $maxResultDateNonInclusive))

$script:allFieldNames.ForEach(
    {
        if (! ($results[0].PSObject.Properties.Name -contains $_) ){
            $results[0] | Add-Member -MemberType NoteProperty -Name $_  -Value $null
        }
    }
)

$results | Export-Csv -Path .\logs.csv -NoTypeInformation
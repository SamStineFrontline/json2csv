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

Function GetJsonFieldPropertiesAsObject($item, $topLevelItemName) {
    $properties = [PSCustomObject]@{}

    $item `
    | ForEach-Object {
        [bool] $propertyCreatedInThisCall = 0
        
        $_.PSObject.Properties | ForEach-Object {
            $propertyToAdd = [PSCustomObject]@{}
            if ($_.Name -eq '$Value' -or $_.Name -eq '$Length'){
                $propertyToAdd = [PSCustomObject]@{
                    MemberType = $_.MemberType;
                    Name = "$($topLevelItemName).$($_.Name)";
                    Value = $_.Value;
                }

                $propertyCreatedInThisCall = 1
            } else {
                $propertyToAdd = GetJsonFieldPropertiesAsObject -item $_.Value -topLevelItemName "$($topLevelItemName).$($_.Name)"
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

Function GetNestedFieldPropertiesAsObject($item){
    $queryStringProperties = @{}
    $cookieProperties = @{}
    
    if (! $null -eq $item.QueryString){
        $queryStringProperties =GetJsonFieldPropertiesAsObject -item ($item | Select-Object -ExpandProperty QueryString) -topLevelItemName "QueryString"
    }

    if (! $null -eq $item.Cookies) {
        $cookieProperties = GetJsonFieldPropertiesAsObject -item ($item | Select-Object -ExpandProperty Cookies) -topLevelItemName "Cookies"
    }

    $properties = Combine-Objects -Object1 $queryStringProperties -Object2 $cookieProperties

    $item.PSObject.Properties | ForEach-Object {
        if (!($_.Name -eq "QueryString" -or $_.Name -eq "Cookies")) {
            $properties | Add-Member -MemberType $_.MemberType -Name $_.Name  -Value $_.Value
        }
    }

    return $properties
}

Function GetNestedFieldsAsObject($item) {
   return GetNestedFieldPropertiesAsObject -item ($item | Select-Object -ExpandProperty fields)
}

Function GetJsonFromREST() {
    $url = "http:/foo.com/bar"
    $body = Get-Content request.json
    $headers = @{"Content-Type" = "application/json"}

    Invoke-RestMethod -Method 'Post' -Uri $url -Headers $headers -Body $body -Outfile logs.json
}

GetJsonFromREST

Get-Content logs.json `
    | ConvertFrom-Json `
    | Select-Object -ExpandProperty hits `
    | Select-Object -ExpandProperty hits  `
    | Select-Object -ExpandProperty "_source"  `
    | ForEach-Object { Combine-Objects -Object1 (GetTopLevelFieldsAsObject -item $_) -Object2 (GetNestedFieldsAsObject -item $_) } `
    | ConvertTo-Csv -NoTypeInformation > logs.csv


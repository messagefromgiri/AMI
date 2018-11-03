<#
.SYNOPSIS
    Get a list of Azure VMs and their Status within a given resource group.

.DESCRIPTION
    The Get-AzureRmVMStatus helps to you get a list of Azure VMs and their
    status (PowerState) within a given resource group. You can supply a
    VM name filter if you want to enclose only specific VMs in the result.

.EXAMPLE
    Get-AzureRmVMStatus -ResourceGroupName 'myrg01'

.EXAMPLE
    Get-AzureRmVMStatus -ResourceGroupName 'myrg01' -Name '*desktop*'

.NOTES
    Author : Sesh
    Date   : 2018-10-25
#>


  [CmdletBinding()]
  param (
    #The name of a resouce group in your subscription
    [Parameter(Mandatory=$true)]
    [string]
    $ResourceGroupName,

    [Parameter(Mandatory=$true)]
    [string]
    $Subscription
    ,
    #VM name filter
    [Parameter()]
    [string]
    $Name = '*'
  )

$null = Login-AzureRmAccount 

$null = set-azurermcontext -subscription $Subscription

  Get-AzureRmVM -ResourceGroupName $ResourceGroupName |
    Get-AzureRmVM -Status |
    Select-Object -Property Name, Statuses |
    Where-Object {$_.Name -like $Name} |
    ForEach-Object {
      $VMName = $_.Name
      $_.Statuses |
        Where-Object {$_.Code -like 'PowerState/*'} |
        ForEach-Object {
          New-Object -TypeName psobject -Property @{
            Name   = $VMName
            Status = $_.DisplayStatus
          }
        }
      }

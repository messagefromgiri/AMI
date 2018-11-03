$null = Login-AzureRmAccount 

$null = set-azurermcontext -subscription PS-EXT-QA-CMPL-USE

$VMs = Get-AzureRmVM -ResourceGroupName "ASR-rg" 
    
    foreach($VM in $VMs)
    {
      $VMDetail = Get-AzureRmVM -ResourceGroupName "ASR-rg" -Name $VM.Name -Status
      
      foreach ($VMStatus in $VMDetail.Statuses)
      { 
          $VMStatusDetail = $VMStatus.DisplayStatus
      }
      Write-Output  ("VM Name: " + $VM.Name), "Status: $VMStatusDetail" `n
    }




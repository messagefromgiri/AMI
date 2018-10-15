# Define Mandatory Parameters


Param (
    [parameter(Mandatory="true")]
    [string]$ak,

    [parameter(Mandatory="true")]
    [string]$sak,

    [parameter(Mandatory="true")]
    [string]$region,

    [parameter(Mandatory="true")]
    [string]$csvpath

   )

    #set the aws credentials

    set-awscredential -AccessKey $ak -SecretKey $sak

    # Initialize AwS credentials with region

    Initialize-AWSDefaultConfiguration -region $region

    #define AWS parameters to start the instance

    $securitygroupid = "sg-0d69b7b2c9717b0a3"
    $subnetid = "subnet-51ec805d"
    $keyname = "asrkey"
    $instancetype = "t2.xlarge"


  # Define tags to identify the instances consistently for this task

$tag = @{Key = 'Name'; Value = 'ASR'}
$tagspec = new-object Amazon.EC2.Model.TagSpecification
$tagspec.ResourceType = "instance"
$tagspec.Tags.Add($tag1)

# Import the AMI ID's from the CSV file

$amicsv = Import-csv -path $csvpath

# Issue the command New-EC2Instance with relevant AMI ID's looping

foreach ($ami in $amicsv)

{

New-ec2instance -ImageId $ami.ID -mincount 1 -maxcount 1  -keyname $keyname -InstanceType $instancetype -SubnetId $subnetid  -SecurityGroupId $securitygroupid -TagSpecification $tagspec

}





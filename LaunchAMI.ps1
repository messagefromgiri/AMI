#aws ec2 describe-regions --output table

#$groupname = aws ec2 create-security-group --group-name asrdevenv-sg --vpc-id vpc-90321df4 --description "Security group for ASR environment"

#aws ec2 describe-security-groups --output table --group-name asrdevernv-sg

#aws ec2 create-key-pair --key-name asrdevenv-key --query 'KeyMaterial' --output text > C:\users\bhushanb\desktop\asrdevenv-key.pem

#csv file location
$amicsvpath = "amilist.csv"

#SubnetID from VPC
$subnetid = "subnet-f45a30c9"

#Securoty Group ID - already created - Need to discuss if we need another one
$securitygroupid = "sg-0d69b7b2c9717b0a3"

#instance size
$instancesize = "t2.micro"

$amicsv = Import-Csv -Path $amicsvpath

foreach ($ami in $amicsv)
{
    #default output will list instanceID
    aws ec2 run-instances --image-id $ami.imageid --subnet-id $subnetid --security-group-ids $securitygroupid --count 1 --instance-type $instancesize --key-name asrdevenv-key --query 'Instances[0].InstanceId'
}
This architecture implements secure and highly available object storage using Amazon S3 multi-tier lifecycle management with cross-region replication.

Storage Layer :  
 (1) Source bucket in us-east-1  
 (2) Destination bucket in us-west-2

Both bucket enabled with Versioning,KMS encryption. 
    Versioning → protects from accidental delete
    KMS → protects data at rest
    Bucket policy → blocks unencrypted uploads

For Encryption - Separate KMS key per region, 
Lifecycle - This reduces storage cost automatically based on object age, 
      Cross-Region Replication :
Replicates from us-east-1 to us-west-2, Uses IAM Role created by S3, Replicates Encrypted objects.
Monitoring & Alerting – Amazon CloudWatch

# Testing  :
To check file replication and encryption status
aws s3api head-object --bucket source-sclrbucket1 --key yourfile.txt --region us-east-1
# Check for default encryption is enabled
aws s3api get-bucket-encryption --bucket source-sclrbucket1
# Lists all the SNS topics in AWS account for the specified region.
aws sns list-topics --region us-east-1
# List all subscriptions for a specific SNS topic
aws sns list-subscriptions-by-topic --topic-arn arn:aws:sns:us-east-1:348375261644:sclr-replication-alerts --region us-east-1
# Upload without KMS
 aws s3 cp sourcefile2.txt s3://source-sclrbucket1/
upload failed: .\sourcefile2.txt to s3://source-sclrbucket1/sourcefile2.txt An error occurred (AccessDenied) when calling the PutObject operation: User: arn:aws:iam::348375261644:user/terraform is not authorized to perform: s3:PutObject on resource: "arn:aws:s3:::source-sclrbucket1/sourcefile2.txt" with an explicit deny in a resource-based policy
# Upload with KMS 
aws s3 cp sourcefile2.txt s3://source-sclrbucket1/ --sse aws:kms --sse-kms-key-id 2cc6fc85-4f8a-40e6-955d-afee4030f903
upload: .\sourcefile2.txt to s3://source-sclrbucket1/sourcefile2.txt
# To check the status and configuration of the CloudWatch alarm.
aws cloudwatch describe-alarms --alarm-names "sclr-replication-lag"

<img width="940" height="341" alt="image" src="https://github.com/user-attachments/assets/82531224-631f-4b10-aea5-7ba1488c591c" />

<img width="940" height="104" alt="image" src="https://github.com/user-attachments/assets/a1982e0c-8aa2-412c-8bb3-a65379ef1870" />
<img width="940" height="154" alt="image" src="https://github.com/user-attachments/assets/7a2ae38a-4f02-4e1d-af26-539868136420" />
<img width="940" height="311" alt="image" src="https://github.com/user-attachments/assets/516dfd1c-1b4f-4cbd-a538-166dfb973a59" />
<img width="940" height="414" alt="image" src="https://github.com/user-attachments/assets/948dd0fd-fad0-4229-9882-5c3f99daf6f4" />


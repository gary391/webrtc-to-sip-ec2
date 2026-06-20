# Cleanup

1. Run `sudo make native-stop` if retaining the instance briefly.
2. Delete the CloudFormation stack when testing is complete.
3. Confirm the EC2 instance terminated.
4. Confirm the Elastic IP was released.
5. Confirm no unattached EBS volume or unexpected snapshot remains.
6. Remove the Route 53 record if it is no longer needed.
7. Remove temporary deploy keys and local test credentials.
8. Check Billing/Cost Explorer for remaining resources and public IPv4 charges.

Do not delete the GitHub repository merely to clean up AWS. It is the source of
truth for reproducing or auditing the demo.

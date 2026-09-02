package main

import future.keywords.in

# 1. every taggable resource must carry a Project tag
deny contains msg if {
    r := input.resource_changes[_]
    r.change.after.tags_all
    not r.change.after.tags_all.Project
    msg := sprintf("%s is missing the Project tag", [r.address])
}

# 2. no security-group rule may allow 0.0.0.0/0 ingress unless it is the ALB
deny contains msg if {
    r := input.resource_changes[_]
    r.type == "aws_security_group"
    not contains(r.address, "alb")
    rule := r.change.after.ingress[_]
    "0.0.0.0/0" in rule.cidr_blocks
    msg := sprintf("%s allows public ingress and is not the ALB", [r.address])
}

# 3. RDS storage must be encrypted
deny contains msg if {
    r := input.resource_changes[_]
    r.type == "aws_db_instance"
    r.change.after.storage_encrypted != true
    msg := sprintf("%s: RDS storage is not encrypted", [r.address])
}

# 4. every S3 bucket needs a public-access block
deny contains msg if {
    r := input.resource_changes[_]
    r.type == "aws_s3_bucket"
    blocks := [b | b := input.resource_changes[_]; b.type == "aws_s3_bucket_public_access_block"]
    count(blocks) == 0
    msg := sprintf("%s has no aws_s3_bucket_public_access_block", [r.address])
}
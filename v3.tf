terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
  required_version = ">= 0.14.9"
}
provider "aws" {
  profile = "default"
  region  = "af-south-1"
}

//VPC
resource "aws_vpc" "mainvpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = "true"
  enable_dns_hostnames = "true"
}


//Subnets
resource "aws_subnet" "SubnetPublic" {
  vpc_id = "${aws_vpc.mainvpc.id}"
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = "true"
  availability_zone = "af-south-1a"
}

resource "aws_subnet" "SubnetPrivate" {
  vpc_id = "${aws_vpc.mainvpc.id}"
  cidr_block = "10.0.2.0/24"
  availability_zone = "af-south-1b"
}

resource "aws_subnet" "SubnetUnused" {
  vpc_id = "${aws_vpc.mainvpc.id}"
  cidr_block = "10.0.3.0/24"
  availability_zone = "af-south-1c"
}


//Gateway
resource "aws_internet_gateway" "MainGW" {
  vpc_id = "${aws_vpc.mainvpc.id}"
}


//Route
resource "aws_route_table" "MainRoute" {
  vpc_id = "${aws_vpc.mainvpc.id}"
  route {
        //associated subnet can reach everywhere
    cidr_block = "0.0.0.0/0"
        //CRT uses this IGW to reach internet
    gateway_id = "${aws_internet_gateway.MainGW.id}"
  }
}

resource "aws_route_table_association" "PubRouteAssoc"{
    subnet_id = "${aws_subnet.SubnetPublic.id}"
    route_table_id = "${aws_route_table.MainRoute.id}"
}


//Security Groups
resource "aws_security_group" "PubSubnetAccess" {
  vpc_id = "${aws_vpc.mainvpc.id}"

ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]
from_port = 80
    to_port = 80
    protocol = "tcp"
  }

ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]
from_port = 443
    to_port = 443
    protocol = "tcp"
  }



  egress {
   from_port = 0
   to_port = 0
   protocol = "-1"
   cidr_blocks = ["0.0.0.0/0"]
 }
}


//DNS
resource "aws_route53_zone" "private" {
  name = "testdns.com"

  vpc {
    vpc_id = "${aws_vpc.mainvpc.id}"
  }
}


//DB
resource "aws_db_instance" "default" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = var.dbsize
  name                 = var.dbname
  username             = var.dbuser 
  password             = var.dbpass
 
//  name                 = DbName
//  username             = DbUser 
//  password             = DbPass123s
  max_allocated_storage = var.dbspace
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
}


//Web Server
resource "aws_instance" "web1" {
  ami = "ami-0ff86122fd4ad7208"
  instance_type = var.instancesize


root_block_device {
    volume_size = var.blocksize
    volume_type = "gp2"
  }

  subnet_id = "${aws_subnet.SubnetPrivate.id}"
  vpc_security_group_ids = ["${aws_security_group.PubSubnetAccess.id}"]
  user_data = "${file("script.sh")}"
  iam_instance_profile  = aws_iam_instance_profile.web1.id
  }

resource "aws_iam_instance_profile" "web1" {
  name  = "web1_host_role"
  role  = aws_iam_role.ssm_role.id
}




data "aws_iam_policy_document" "assume_role" {
  statement {

    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type = "Service"
      identifiers = [
        "ec2.amazonaws.com"
      ]
    }
  }
}



//SSM
resource "aws_iam_role" "ssm_role" {
  name               = "SSM_role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}


resource "aws_iam_policy" "ssm_policy" {
  name        = "ssm-policy"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:DescribeAssociation",
                "ssm:GetDeployablePatchSnapshotForInstance",
                "ssm:GetDocument",
                "ssm:DescribeDocument",
                "ssm:GetManifest",
                "ssm:GetParameters",
                "ssm:ListAssociations",
                "ssm:ListInstanceAssociations",
                "ssm:PutInventory",
                "ssm:PutComplianceItems",
                "ssm:PutConfigurePackageResult",
                "ssm:UpdateAssociationStatus",
                "ssm:UpdateInstanceAssociationStatus",
                "ssm:UpdateInstanceInformation"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ssmmessages:CreateControlChannel",
                "ssmmessages:CreateDataChannel",
                "ssmmessages:OpenControlChannel",
                "ssmmessages:OpenDataChannel"
            ],
            "Resource": "*"
        }
        
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ssm_role" {
    role       = aws_iam_role.ssm_role.name
    policy_arn = aws_iam_policy.ssm_policy.arn
}




//Load Balancer
module "elb_http" {
  source  = "terraform-aws-modules/elb/aws"
  version = "~> 2.0"

  name = "pubELB"

  subnets         = ["${aws_subnet.SubnetPublic.id}", "${aws_subnet.SubnetPrivate.id}"]
  security_groups = ["${aws_security_group.PubSubnetAccess.id}"]
  internal        = false

  listener = [
    {
      instance_port     = 80
      instance_protocol = "HTTP"
      lb_port           = 80
      lb_protocol       = "HTTP"
    },
    {
      instance_port     = 443
      instance_protocol = "https"
      lb_port           = 443
      lb_protocol       = "https"
      ssl_certificate_id = "arn:aws:acm:af-south-1:507592092345:certificate/0218e2f7-60c5-4e28-ae67-ddd037213014"
    },
]

  health_check = {
    target              = "HTTP:80/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }
//
//  access_logs = {
//    bucket = "my-access-logs-bucket"
//  }

  // ELB attachments
  number_of_instances = 1
  instances           = ["${aws_instance.web1.id}"]

 }


//Output
output "ELB_dns_name" {
  description = "The DNS name of the ELB"
  value       = module.elb_http.this_elb_dns_name
}

output "DB_User" {
  description = "Database User"
  value       = var.dbuser
}

output "DB_Pass" {
  description = "Database Password"
  value       = var.dbpass
}

output "MySQL_URL" {
  description = "MySQL URL"
  value       = aws_db_instance.default.endpoint
}

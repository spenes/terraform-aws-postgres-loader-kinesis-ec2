locals {
  module_name    = "postgres-loader-kinesis-ec2"
  module_version = "0.1.1"

  app_name    = "snowplow-postgres-loader"
  app_version = "0.2.0"

  local_tags = {
    Name           = var.name
    app_name       = local.app_name
    app_version    = local.app_version
    module_name    = local.module_name
    module_version = local.module_version
  }

  tags = merge(
    var.tags,
    local.local_tags
  )

  cloudwatch_log_group_name = "/aws/ec2/${var.name}"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

module "telemetry" {
  source  = "snowplow-devops/telemetry/snowplow"
  version = "0.1.0"

  count = var.telemetry_enabled ? 1 : 0

  user_provided_id = var.user_provided_id
  cloud            = "AWS"
  region           = data.aws_region.current.name
  app_name         = local.app_name
  app_version      = local.app_version
  module_name      = local.module_name
  module_version   = local.module_version
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

# --- DynamoDB: KCL Table

resource "aws_dynamodb_table" "kcl" {
  name           = var.name
  hash_key       = "leaseKey"
  write_capacity = 1
  read_capacity  = 1

  attribute {
    name = "leaseKey"
    type = "S"
  }

  lifecycle {
    ignore_changes = [write_capacity, read_capacity]
  }

  tags = local.tags
}

module "kcl_autoscaling" {
  source  = "snowplow-devops/dynamodb-autoscaling/aws"
  version = "0.1.0"

  table_name = aws_dynamodb_table.kcl.id

  read_min_capacity  = var.kcl_read_min_capacity
  read_max_capacity  = var.kcl_read_max_capacity
  write_min_capacity = var.kcl_write_min_capacity
  write_max_capacity = var.kcl_write_max_capacity
}

# --- CloudWatch: Logging

resource "aws_cloudwatch_log_group" "log_group" {
  count = var.cloudwatch_logs_enabled ? 1 : 0

  name              = local.cloudwatch_log_group_name
  retention_in_days = var.cloudwatch_logs_retention_days

  tags = local.tags
}

# --- IAM: Roles & Permissions

resource "aws_iam_role" "iam_role" {
  name        = var.name
  description = "Allows the Postgres Loader nodes to access required services"
  tags        = local.tags

  assume_role_policy = <<EOF
{
  "Version" : "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": [ "ec2.amazonaws.com" ]},
      "Action": [ "sts:AssumeRole" ]
    }
  ]
}
EOF

  permissions_boundary = var.iam_permissions_boundary
}

resource "aws_iam_policy" "iam_policy" {
  name = var.name

  policy = <<EOF
{
  "Version" : "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kinesis:DescribeStream",
        "kinesis:DescribeStreamSummary",
        "kinesis:List*",
        "kinesis:Get*"
      ],
      "Resource": [
        "arn:aws:kinesis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stream/${var.in_stream_name}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:BatchWriteItem",
        "dynamodb:PutItem",
        "dynamodb:DescribeTable",
        "dynamodb:DeleteItem",
        "dynamodb:GetItem",
        "dynamodb:Scan",
        "dynamodb:UpdateItem"
      ],
      "Resource": [
        "${aws_dynamodb_table.kcl.arn}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:PutLogEvents",
        "logs:CreateLogStream",
        "logs:DescribeLogStreams"
      ],
      "Resource": [
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.cloudwatch_log_group_name}:*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "policy_attachment" {
  role       = aws_iam_role.iam_role.name
  policy_arn = aws_iam_policy.iam_policy.arn
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = var.name
  role = aws_iam_role.iam_role.name
}

# --- EC2: Security Group Rules

resource "aws_security_group" "sg" {
  name   = var.name
  vpc_id = var.vpc_id
  tags   = local.tags
}

resource "aws_security_group_rule" "ingress_tcp_22" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.ssh_ip_allowlist
  security_group_id = aws_security_group.sg.id
}

# Allows egress from the server to the RDS instance
resource "aws_security_group_rule" "egress_tcp_server_rds" {
  type                     = "egress"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = var.db_sg_id
  security_group_id        = aws_security_group.sg.id
}

resource "aws_security_group_rule" "egress_tcp_80" {
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg.id
}

resource "aws_security_group_rule" "egress_tcp_443" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg.id
}

# Needed for clock synchronization
resource "aws_security_group_rule" "egress_udp_123" {
  type              = "egress"
  from_port         = 123
  to_port           = 123
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg.id
}

# --- EC2: Security Group Rules for the RDS Instance

# Allows ingress from the webserver to the RDS Instance
resource "aws_security_group_rule" "rds_egress_tcp_webserver" {
  type                     = "ingress"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.sg.id
  security_group_id        = var.db_sg_id
}

# --- EC2: Auto-scaling group & Launch Configurations

locals {
  resolvers_raw = concat(var.default_iglu_resolvers, var.custom_iglu_resolvers)

  resolvers_open = [
    for resolver in local.resolvers_raw : merge(
      {
        name           = resolver["name"],
        priority       = resolver["priority"],
        vendorPrefixes = resolver["vendor_prefixes"],
        connection = {
          http = {
            uri = resolver["uri"]
          }
        }
      }
    ) if resolver["api_key"] == ""
  ]

  resolvers_closed = [
    for resolver in local.resolvers_raw : merge(
      {
        name           = resolver["name"],
        priority       = resolver["priority"],
        vendorPrefixes = resolver["vendor_prefixes"],
        connection = {
          http = {
            uri    = resolver["uri"]
            apikey = resolver["api_key"]
          }
        }
      }
    ) if resolver["api_key"] != ""
  ]

  resolvers = flatten([
    local.resolvers_open,
    local.resolvers_closed
  ])

  iglu_resolver = templatefile("${path.module}/templates/iglu_resolver.json.tmpl", { resolvers = jsonencode(local.resolvers) })

  config = templatefile("${path.module}/templates/config.json.tmpl", {
    app_name         = var.name
    in_stream_name   = var.in_stream_name
    region           = data.aws_region.current.name
    initial_position = var.initial_position
    db_host          = var.db_host
    db_port          = var.db_port
    db_name          = var.db_name
    db_username      = var.db_username
    db_password      = var.db_password
    schema_name      = var.schema_name
    purpose          = var.purpose
  })

  user_data = templatefile("${path.module}/templates/user-data.sh.tmpl", {
    config        = local.config
    iglu_resolver = local.iglu_resolver
    version       = local.app_version
    db_host       = var.db_host
    db_port       = var.db_port
    db_name       = var.db_name
    db_username   = var.db_username
    db_password   = var.db_password
    schema_name   = var.schema_name

    telemetry_script = join("", module.telemetry.*.amazon_linux_2_user_data)

    cloudwatch_logs_enabled   = var.cloudwatch_logs_enabled
    cloudwatch_log_group_name = local.cloudwatch_log_group_name
  })
}

resource "aws_launch_configuration" "lc" {
  name_prefix = "${var.name}-"

  image_id             = var.amazon_linux_2_ami_id == "" ? data.aws_ami.amazon_linux_2.id : var.amazon_linux_2_ami_id
  instance_type        = var.instance_type
  key_name             = var.ssh_key_name
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name
  security_groups      = [aws_security_group.sg.id]
  user_data            = local.user_data

  # Note: Required if deployed in a public subnet
  associate_public_ip_address = var.associate_public_ip_address

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "10"
    delete_on_termination = true
    encrypted             = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

module "tags" {
  source  = "snowplow-devops/tags/aws"
  version = "0.1.0"

  tags = local.tags
}

resource "aws_autoscaling_group" "asg" {
  name = var.name

  max_size = var.max_size
  min_size = var.min_size

  launch_configuration = aws_launch_configuration.lc.name

  health_check_grace_period = 300
  health_check_type         = "EC2"

  vpc_zone_identifier = var.subnet_ids

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 90
    }
    triggers = ["tag"]
  }

  tags = module.tags.asg_tags
}

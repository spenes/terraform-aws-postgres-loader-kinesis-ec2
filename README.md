[![Release][release-image]][release] [![CI][ci-image]][ci] [![License][license-image]][license] [![Registry][registry-image]][registry] [![Source][source-image]][source]

# terraform-aws-postgres-loader-kinesis-ec2

A Terraform module which deploys a Snowplow Postgres Loader application on AWS running on top of EC2.  If you want to use a custom AMI for this deployment you will need to ensure it is based on top of Amazon Linux 2.

_WARNING_: The current version of the Postgres Loader requires very high capacity for its backing DynamoDB KCL table - we would recommend avoiding using this application for high volume traffic.

## Telemetry

This module by default collects and forwards telemetry information to Snowplow to understand how our applications are being used.  No identifying information about your sub-account or account fingerprints are ever forwarded to us - it is very simple information about what modules and applications are deployed and active.

If you wish to subscribe to our mailing list for updates to these modules or security advisories please set the `user_provided_id` variable to include a valid email address which we can reach you at.

### How do I disable it?

To disable telemetry simply set variable `telemetry_enabled = false`.

### What are you collecting?

For details on what information is collected please see this module: https://github.com/snowplow-devops/terraform-snowplow-telemetry

## Usage

The Postgres Loader can load both your enriched and bad data into a Postgres database - by default we are using RDS as it affords a simple and cost effective way to get started.

To start loading "enriched" data into Postgres:

```hcl
module "enriched_stream" {
  source  = "snowplow-devops/kinesis-stream/aws"
  version = "0.1.0"

  name = "enriched-stream"
}

module "pipeline_rds" {
  source  = "snowplow-devops/rds/aws"
  version = "0.1.3"

  name        = "pipeline-rds"
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids
  db_name     = local.pipeline_db_name
  db_username = local.pipeline_db_username
  db_password = local.pipeline_db_password

  # Note: this exposes your data to the internet - take care to ensure your allowlist is strict enough
  #       or provide a way to access the database through the VPC instead
  publicly_accessible     = true
  additional_ip_allowlist = local.pipeline_ip_allowlist
}

module "postgres_loader_enriched" {
  source = "snowplow-devops/postgres-loader-kinesis-ec2/aws"

  name       = "postgres-loader-enriched-server"
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  in_stream_name = module.enriched_stream.name

  # Note: The purpose defines what the input data set should look like
  purpose = "ENRICHED_EVENTS"

  # Note: This schema is created automatically by the VM on launch
  schema_name = "atomic"

  ssh_key_name     = "your-key-name"
  ssh_ip_allowlist = ["0.0.0.0/0"]

  # Linking in the custom Iglu Server here
  custom_iglu_resolvers = [
    {
      name            = "Iglu Server"
      priority        = 0
      uri             = "http://your-iglu-server-endpoint/api"
      api_key         = var.iglu_super_api_key
      vendor_prefixes = []
    }
  ]

  db_sg_id    = module.pipeline_rds.sg_id
  db_host     = module.pipeline_rds.address
  db_port     = module.pipeline_rds.port
  db_name     = local.pipeline_db_name
  db_username = local.pipeline_db_username
  db_password = local.pipeline_db_password

  # Note: the postgres loader can be limited by KCL throughput - increasing this is crucial for anything over 30-40 RPS
  kcl_write_max_capacity = 50
}
```

To load the "bad" data instead:

```hcl
module "bad_1_stream" {
  source  = "snowplow-devops/kinesis-stream/aws"
  version = "0.1.0"

  name = "bad-1-stream"
}

module "postgres_loader_bad" {
  source = "snowplow-devops/postgres-loader-kinesis-ec2/aws"

  name       = "postgres-loader-bad-server"
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  in_stream_name = module.bad_1_stream.name

  # Note: The purpose defines what the input data set should look like
  purpose = "JSON"

  # Note: This schema is created automatically by the VM on launch
  schema_name = "atomic_bad"

  ssh_key_name     = "your-key-name"
  ssh_ip_allowlist = ["0.0.0.0/0"]

  # Linking in the custom Iglu Server here
  custom_iglu_resolvers = [
    {
      name            = "Iglu Server"
      priority        = 0
      uri             = "http://your-iglu-server-endpoint/api"
      api_key         = var.iglu_super_api_key
      vendor_prefixes = []
    }
  ]

  db_sg_id    = module.pipeline_rds.sg_id
  db_host     = module.pipeline_rds.address
  db_port     = module.pipeline_rds.port
  db_name     = local.pipeline_db_name
  db_username = local.pipeline_db_username
  db_password = local.pipeline_db_password

  # Note: the postgres loader can be limited by KCL throughput - increasing this is crucial for anything over 30-40 RPS
  kcl_write_max_capacity = 50
}
```

### Increasing RDS capacity

As you load data into the database it will start to fill up naturally!  To handle this seamlessly you can enabled auto-scaling for RDS by updating this module snippet as follows:

```hcl
module "pipeline_rds" {
  source  = "snowplow-devops/rds/aws"
  version = "0.1.3"

  # Note: Enables autoscaling storage to up to 100gb from the default 10gb
  max_allocated_storage = 100

  name        = "pipeline-rds"
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids
  db_name     = local.pipeline_db_name
  db_username = local.pipeline_db_username
  db_password = local.pipeline_db_password

  # Note: this exposes your data to the internet - take care to ensure your allowlist is strict enough
  #       or provide a way to access the database through the VPC instead
  publicly_accessible     = true
  additional_ip_allowlist = local.pipeline_ip_allowlist
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 0.15 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 3.25.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 3.25.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_kcl_autoscaling"></a> [kcl\_autoscaling](#module\_kcl\_autoscaling) | snowplow-devops/dynamodb-autoscaling/aws | 0.1.0 |
| <a name="module_tags"></a> [tags](#module\_tags) | snowplow-devops/tags/aws | 0.1.0 |
| <a name="module_telemetry"></a> [telemetry](#module\_telemetry) | snowplow-devops/telemetry/snowplow | 0.1.0 |

## Resources

| Name | Type |
|------|------|
| [aws_autoscaling_group.asg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_dynamodb_table.kcl](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_iam_instance_profile.instance_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_policy.iam_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.iam_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_launch_configuration.lc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_configuration) | resource |
| [aws_security_group.sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group_rule.egress_tcp_443](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.egress_tcp_80](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.egress_tcp_server_rds](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.egress_udp_123](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.ingress_tcp_22](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.rds_egress_tcp_webserver](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_ami.amazon_linux_2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_amazon_linux_2_ami_id"></a> [amazon\_linux\_2\_ami\_id](#input\_amazon\_linux\_2\_ami\_id) | The AMI ID to use which must be based of of Amazon Linux 2; by default the latest community version is used | `string` | `""` | no |
| <a name="input_associate_public_ip_address"></a> [associate\_public\_ip\_address](#input\_associate\_public\_ip\_address) | Whether to assign a public ip address to this instance | `bool` | `true` | no |
| <a name="input_custom_iglu_resolvers"></a> [custom\_iglu\_resolvers](#input\_custom\_iglu\_resolvers) | The custom Iglu Resolvers that will be used by Enrichment to resolve and validate events | <pre>list(object({<br>    name            = string<br>    priority        = number<br>    uri             = string<br>    api_key         = string<br>    vendor_prefixes = list(string)<br>  }))</pre> | `[]` | no |
| <a name="input_db_host"></a> [db\_host](#input\_db\_host) | The hostname of the database to connect to | `string` | n/a | yes |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | The name of the database to connect to | `string` | n/a | yes |
| <a name="input_db_password"></a> [db\_password](#input\_db\_password) | The password to use to connect to the database | `string` | n/a | yes |
| <a name="input_db_port"></a> [db\_port](#input\_db\_port) | The port the database is running on | `number` | n/a | yes |
| <a name="input_db_sg_id"></a> [db\_sg\_id](#input\_db\_sg\_id) | The ID of the RDS security group that sits downstream of the webserver | `string` | n/a | yes |
| <a name="input_db_username"></a> [db\_username](#input\_db\_username) | The username to use to connect to the database | `string` | n/a | yes |
| <a name="input_default_iglu_resolvers"></a> [default\_iglu\_resolvers](#input\_default\_iglu\_resolvers) | The default Iglu Resolvers that will be used by Enrichment to resolve and validate events | <pre>list(object({<br>    name            = string<br>    priority        = number<br>    uri             = string<br>    api_key         = string<br>    vendor_prefixes = list(string)<br>  }))</pre> | <pre>[<br>  {<br>    "api_key": "",<br>    "name": "Iglu Central",<br>    "priority": 10,<br>    "uri": "http://iglucentral.com",<br>    "vendor_prefixes": []<br>  },<br>  {<br>    "api_key": "",<br>    "name": "Iglu Central - Mirror 01",<br>    "priority": 20,<br>    "uri": "http://mirror01.iglucentral.com",<br>    "vendor_prefixes": []<br>  }<br>]</pre> | no |
| <a name="input_iam_permissions_boundary"></a> [iam\_permissions\_boundary](#input\_iam\_permissions\_boundary) | The permissions boundary ARN to set on IAM roles created | `string` | `""` | no |
| <a name="input_in_stream_name"></a> [in\_stream\_name](#input\_in\_stream\_name) | The name of the input kinesis stream that the Enricher will pull data from | `string` | n/a | yes |
| <a name="input_initial_position"></a> [initial\_position](#input\_initial\_position) | Where to start processing the input Kinesis Stream from (TRIM\_HORIZON or LATEST) | `string` | `"TRIM_HORIZON"` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | The instance type to use | `string` | `"t3.micro"` | no |
| <a name="input_kcl_read_max_capacity"></a> [kcl\_read\_max\_capacity](#input\_kcl\_read\_max\_capacity) | The maximum READ capacity for the KCL DynamoDB table | `number` | `10` | no |
| <a name="input_kcl_read_min_capacity"></a> [kcl\_read\_min\_capacity](#input\_kcl\_read\_min\_capacity) | The minimum READ capacity for the KCL DynamoDB table | `number` | `1` | no |
| <a name="input_kcl_write_max_capacity"></a> [kcl\_write\_max\_capacity](#input\_kcl\_write\_max\_capacity) | The maximum WRITE capacity for the KCL DynamoDB table | `number` | `10` | no |
| <a name="input_kcl_write_min_capacity"></a> [kcl\_write\_min\_capacity](#input\_kcl\_write\_min\_capacity) | The minimum WRITE capacity for the KCL DynamoDB table | `number` | `1` | no |
| <a name="input_max_size"></a> [max\_size](#input\_max\_size) | The maximum number of servers in this server-group | `number` | `2` | no |
| <a name="input_min_size"></a> [min\_size](#input\_min\_size) | The minimum number of servers in this server-group | `number` | `1` | no |
| <a name="input_name"></a> [name](#input\_name) | A name which will be pre-pended to the resources created | `string` | n/a | yes |
| <a name="input_purpose"></a> [purpose](#input\_purpose) | The type of data the loader will be pulling which can be one of ENRICHED\_EVENTS or JSON (Note: JSON can be used for loading bad rows) | `string` | n/a | yes |
| <a name="input_schema_name"></a> [schema\_name](#input\_schema\_name) | The database schema to load data into (e.g atomic \| atomic\_bad) | `string` | n/a | yes |
| <a name="input_ssh_ip_allowlist"></a> [ssh\_ip\_allowlist](#input\_ssh\_ip\_allowlist) | The list of CIDR ranges to allow SSH traffic from | `list(any)` | <pre>[<br>  "0.0.0.0/0"<br>]</pre> | no |
| <a name="input_ssh_key_name"></a> [ssh\_key\_name](#input\_ssh\_key\_name) | The name of the SSH key-pair to attach to all EC2 nodes deployed | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | The list of subnets to deploy the Postgres Loader across | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | The tags to append to this resource | `map(string)` | `{}` | no |
| <a name="input_telemetry_enabled"></a> [telemetry\_enabled](#input\_telemetry\_enabled) | Whether or not to send telemetry information back to Snowplow Analytics Ltd | `bool` | `true` | no |
| <a name="input_user_provided_id"></a> [user\_provided\_id](#input\_user\_provided\_id) | An optional unique identifier to identify the telemetry events emitted by this stack | `string` | `""` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The VPC to deploy the Postgres Loader within | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_asg_id"></a> [asg\_id](#output\_asg\_id) | ID of the ASG |
| <a name="output_asg_name"></a> [asg\_name](#output\_asg\_name) | Name of the ASG |
| <a name="output_sg_id"></a> [sg\_id](#output\_sg\_id) | ID of the security group attached to the Postgres Loader servers |

# Copyright and license

The Terraform AWS Postgres Loader on EC2 project is Copyright 2021-2021 Snowplow Analytics Ltd.

Licensed under the [Apache License, Version 2.0][license] (the "License");
you may not use this software except in compliance with the License.

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

[release]: https://github.com/snowplow-devops/terraform-aws-postgres-loader-kinesis-ec2/releases/latest
[release-image]: https://img.shields.io/github/v/release/snowplow-devops/terraform-aws-postgres-loader-kinesis-ec2

[ci]: https://github.com/snowplow-devops/terraform-aws-postgres-loader-kinesis-ec2/actions?query=workflow%3Aci
[ci-image]: https://github.com/snowplow-devops/terraform-aws-postgres-loader-kinesis-ec2/workflows/ci/badge.svg

[license]: https://www.apache.org/licenses/LICENSE-2.0
[license-image]: https://img.shields.io/badge/license-Apache--2-blue.svg?style=flat

[registry]: https://registry.terraform.io/modules/snowplow-devops/postgres-loader-kinesis-ec2/aws/latest
[registry-image]: https://img.shields.io/static/v1?label=Terraform&message=Registry&color=7B42BC&logo=terraform

[source]: https://github.com/snowplow-incubator/snowplow-postgres-loader
[source-image]: https://img.shields.io/static/v1?label=Snowplow&message=Postgres%20Loader&color=0E9BA4&logo=GitHub

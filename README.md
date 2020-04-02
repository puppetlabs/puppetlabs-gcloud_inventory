# gcloud_inventory

#### Table of Contents

1. [Description](#description)
2. [Requirements](#requirements)
3. [Usage](#usage)

## Description

This module includes a Bolt plugin to generate targets from Google Cloud compute engine instances.

## Requirements

- A service account with the `compute.instances.list` [permission](https://cloud.google.com/compute/docs/access/service-accounts#service_account_permissions)
- Compute engine instances with either the `compute` or `compute.readonly` [access scope](https://cloud.google.com/compute/docs/access/service-accounts#accesscopesiam)
- A [credentials file](https://cloud.google.com/iam/docs/creating-managing-service-account-keys#creating_service_account_keys)
  for the service account

## Usage

The plugin generates targets from a list of compute engine instances for a specific project
and zone. It supports the following fields:

| Option | Type | Description |
| ------ | ---- | ----------- |
| `credentials` | `String` | An absolute path to the service account credentials file. _Optional._ |
| `project` | `String` | The name of the project to lookup instances from. _Required_. |
| `target_mapping` | `Hash` | A hash of target attributes to populate with resource values. Must include either `name` or `uri`. _Required_. |
| `zone` | `String` | The name of the zone to lookup instances from. _Required_. |

### Credentials

The plugin supports loading a credentials file from a path specified in either the `credentials` option
or the `GOOGLE_APPLICATION_CREDENTIALS` environment variable. A path specified in the `credentials`
option will take precedence over a path specified in the `GOOGLE_APPLICATION_CREDENTIALS` environment
variable. If a credentials file is not specified, or the path does not point to a valid credentials
file, the plugin will error.

The credentials file must contain a JSON object with at least the following fields:

- `client_email`
- `private_key`
- `token_uri`

### Target mapping

The `target_mapping` field accepts a hash of target attributes to populate with 
[resource values](https://cloud.google.com/compute/docs/reference/rest/v1/instances/list#response-body).
The hash of target attributes is formatted similarly to a target specification in an 
[inventory file](https://puppet.com/docs/bolt/latest/inventory_file_v2.html#target-object). Resource
values are accessed using dot notation. For example, you can access an instance's public IP address
using `networkInterfaces.0.accessConfigs.0.natIP`.

### Example

```yaml
---
# inventory.yaml
group:
  - name: google
    targets:
      _plugin: gcloud_inventory
      project: my_project
      zone: us-west1-b
      credentials: ~/.google/credentials.json
      target_mapping:
        name: name
        uri: networkInterfaces.0.accessConfigs.0.natIP
        vars: labels
```

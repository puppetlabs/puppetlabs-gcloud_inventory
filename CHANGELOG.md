# Changelog

## Release 0.3.0

### New features

* **Provide credentials as parameters**
  ([#11](https://github.com/puppetlabs/puppetlabs-gcloud_inventory/pull/11))

  The `resolve_reference` task has new `client_email`, `token_uri`, and `private_key`
  parameters for authenticating with Google Cloud.

## Release 0.2.0

### New features

* **Bump maximum Puppet version to include 7.x** ([#10](https://github.com/puppetlabs/puppetlabs-gcloud_inventory/pull/10))

## Release 0.1.3

### Bug fixes

* **Add PDK as a gem dependency**

  PDK is now a gem dependency for the module release pipeline

## Release 0.1.2

### Bug fixes

* **Add missing dependencies to module metadata**
  ([#6](https://github.com/puppetlabs/puppetlabs-gcloud_inventory/pull/6))

  The module metadata now includes `ruby_plugin_helper` and `ruby_task_helper`
  as dependencies.

## Release 0.1.1

### Bug fixes

* **Set `resolve_reference` task to private**

  The `resolve_reference` task has been set to private so it no longer appears in UI lists.

## Release 0.1.0

This is the initial release.

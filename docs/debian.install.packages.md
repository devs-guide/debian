# debian.install.packages

`ansible/install.packages.yml` installs package groups defined in
`ansible/packages.yml`.

## Defaults

Enabled by default:

- `base`
- `time_sync`
- `security`
- `storage`
- `monitoring_benchmark`
- `networking`
- `hardware_info`
- `dev_tools`
- `archive_iso_tools`
- `performance_power`

Disabled by default:

- `desktop_rdp_optional`
- `apple_media_optional`
- `gpu_vendor_optional`
- `firmware`

## Override examples

Enable the optional desktop group:

```sh
ansible-playbook ansible/install.packages.yml \
  -e '{"package_group_overrides":{"desktop_rdp_optional":true}}'
```

Exclude one package globally:

```sh
ansible-playbook ansible/install.packages.yml \
  -e '{"exclude_packages":["mailutils"]}'
```

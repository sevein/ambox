# ambox config reference

This directory defines the layered configuration used by ambox at boot time.
The main config file is YAML and validated against the JSON Schema in the same
folder.

If you only need the quick start, see `hack/box/README.md`. This document is
the detailed reference for the configuration schema, including the processing
configuration options and how they map to Archivematica decisions.

## Example configuration

```yaml
# ambox config (YAML). Lines starting with # are comments.
version: v1

# Optional: override the SFTPGo host key.
sftpgo:
  # Absolute path, or a path relative to /var/lib/sftpgo inside the container.
  host_key: /etc/ambox/sftpgo_host_key

processing:
  configs:
    # Example 1: build on the default processing config and override a few
    # decisions for an "automated" profile.
    - name: automated
      extends: default
      config:
        virus_scanning: false
        normalize: do_not_normalize

    # Example 2: extend the automated base and tweak storage decisions.
    - name: demo
      extends: automated
      config:
        store_aip: true
        store_aip_location: default
        upload_dip: do_not_upload

    # Example 3: supply a full processingMCP.xml directly.
    - name: custom_xml
      source:
        type: file
        value: /etc/ambox/processingMCP.xml
```

## Where the config is read from

At container boot, ambox reads `/etc/ambox/config.yaml`. You can override the
path with the `AMBOX_CONFIG_FILE` environment variable. If no config file is
present, ambox proceeds without applying extra configuration (the schema
defaults and Archivematica defaults apply). The repository ships with
`hack/box/config/ambox.yaml` as a reference template; it is not loaded
automatically.

## Schema versioning

The root `version` field is required. Current schema versions:

- `v1`: current schema.

## Top-level structure

The root object accepts the following keys:

### `version` (required)

- Type: string.
- Allowed values: `v1`.
- Purpose: schema version for this config file.

### `sftpgo` (optional)

Overrides for the embedded SFTPGo service.

- Type: object.
- Properties:
  - `host_key` (string, optional)
    - Path to the SFTPGo private host key file (absolute, or relative to
      `/var/lib/sftpgo` inside the container).
    - The file must exist and be readable by the `archivematica` user at
      container startup, or the SFTP service will fail to boot.

Example:

```yaml
version: v1
sftpgo:
  host_key: /etc/ambox/sftpgo_host_key
```

### `processing` (optional)

Controls processing configuration XMLs generated at boot.

- Type: object.
- Properties:
  - `configs`: list of processing configuration definitions.
    - Type: array (max 10 items).
    - Default: empty list.

## Processing configuration overview

Processing configurations automate decision points in the Transfer and Ingest
workflows in Archivematica. In the dashboard UI, these are configured under
Administration > Processing configuration. ambox uses your YAML config to
generate `processingMCP.xml` files that mirror those choices.

For the canonical, user-facing descriptions of each decision point, see the
[Archivematica documentation].

[Archivematica documentation]: https://www.archivematica.org/en/docs/archivematica-latest/user-manual/administer/dashboard-admin/#dashboard-processing

### `processing.configs[]` (config items)

Each entry defines a single processing configuration file.

Required fields:

- `name` (string)
  - Name of the processing configuration.
  - Used as the file prefix: `<name>ProcessingMCP.xml`.
  - Pattern: `^[A-Za-z0-9_-]{1,80}$`.

Optional fields (mutually exclusive):

- `source` (object)
  - Directly supply a processingMCP XML file.
  - When `source` is provided, `extends` must not be set and `config` is not
    used.
- `config` (object)
  - Declarative set of decision points. When `config` is provided, `source`
    must not be set.

Optional base:

- `extends` (string)
  - Base bundled processing config to start from.
  - Allowed values: `default`, `automated`.
  - Only relevant when `config` is provided.

#### `source`

`source` is an object with:

- `type`: `"base64"` or `"file"`.
- `value`:
  - When `type` is `base64`, the base64-encoded XML string.
  - When `type` is `file`, an absolute path to the XML file.

Example:

```yaml
processing:
  configs:
    - name: automated
      source:
        type: file
        value: /etc/ambox/processingMCP.xml
```

#### `config`

`config` is a declarative mapping of processing decision points. Each field
corresponds to a dropdown in Archivematica's Processing configuration UI.

General rules:

- Most fields accept `true`/`false`/`null`. Use `null` to leave the decision to
  the dashboard at runtime.
- Some fields accept string enums (see below).
- If a value is `null`, ambox removes the preconfigured choice so the dashboard
  prompts the user.

Example (extend default + override a few decisions):

```yaml
processing:
  configs:
    - name: demo
      extends: default
      config:
        virus_scanning: false
        normalize: do_not_normalize
        store_aip: true
```

### Processing decision fields

Below are the supported keys under `processing.configs[].config`, with their
allowed values and meanings. For broader context and UI wording, see the
Archivematica processing configuration documentation linked above.

#### Transfer decisions

`virus_scanning` (boolean or null)
- `true`: scan for viruses.
- `false`: do not scan.
- `null`: prompt in the dashboard.

`assign_uuids_to_directories` (boolean or null)
- `true`: assign UUIDs to directories.
- `false`: do not assign.
- `null`: prompt in the dashboard.

`generate_transfer_structure` (boolean or null)
- `true`: generate a transfer structure report.
- `false`: do not generate.
- `null`: prompt in the dashboard.

`select_format_id_tool_transfer` (boolean or null)
- `true`: perform file format identification on transfer.
- `false`: skip file format identification.
- `null`: prompt in the dashboard.

`extract_packages` (boolean or null)
- `true`: extract package contents (e.g., zip).
- `false`: leave packages as-is.
- `null`: prompt in the dashboard.

`delete_packages` (boolean or null)
- `true`: delete extracted packages.
- `false`: keep extracted packages.
- `null`: prompt in the dashboard.

`policy_checks_originals` (boolean or null)
- `true`: run policy checks on originals.
- `false`: do not run policy checks.
- `null`: prompt in the dashboard.

`examine_contents` (boolean or null)
- `true`: run content examination (Bulk Extractor).
- `false`: skip content examination.
- `null`: prompt in the dashboard.

`create_sip` (boolean or null)
- `true`: create SIP(s).
- `null`: prompt in the dashboard.
- Note: some Archivematica UIs also offer a "send to backlog" option; ambox
  does not expose that choice in this schema.

#### Ingest decisions

`select_format_id_tool_ingest` (boolean or null)
- `true`: identify formats during ingest.
- `false`: reuse identification data from transfer.
- `null`: prompt in the dashboard.

`normalize` (string or null)
- `preservation_access`: normalize for preservation and access.
- `preservation`: normalize for preservation only.
- `access`: normalize for access only.
- `service_access`: normalize service (mezzanine) files for access.
- `manual`: normalize manually.
- `do_not_normalize`: do not normalize.
- `null`: prompt in the dashboard.

`normalize_transfer` (boolean or null)
- `true`: automatically approve normalization results.
- `false`: require manual review.
- `null`: prompt in the dashboard.

`normalize_thumbnail_mode` (string or null)
- `yes`: generate thumbnails; include default icons where needed.
- `yes_no_icons`: generate thumbnails only where explicit rules exist.
- `no`: do not generate thumbnails.
- `null`: prompt in the dashboard.

`policy_checks_preservation_derivatives` (boolean or null)
- `true`: run policy checks on preservation derivatives.
- `false`: do not run policy checks.
- `null`: prompt in the dashboard.

`policy_checks_access_derivatives` (boolean or null)
- `true`: run policy checks on access derivatives.
- `false`: do not run policy checks.
- `null`: prompt in the dashboard.

`bind_pids` (boolean or null)
- `true`: bind PIDs.
- `false`: do not bind PIDs.
- `null`: prompt in the dashboard.

`normative_structmap` (boolean or null)
- `true`: document empty directories in the structMap.
- `false`: do not document empty directories.
- `null`: prompt in the dashboard.

`reminder` (string or null)
- `continue`: skip metadata reminder and continue.
- `null`: prompt in the dashboard.

`transcribe_file` (boolean or null)
- `true`: run OCR transcription.
- `false`: do not run OCR.
- `null`: prompt in the dashboard.

`select_format_id_tool_submissiondocs` (boolean or null)
- `true`: identify formats for submission docs/metadata.
- `false`: skip identification for submission docs/metadata.
- `null`: prompt in the dashboard.

`compression_algo` (string or null)
- `7z_bzip2`: 7z using bzip2.
- `7z_lzma`: 7z using LZMA.
- `7z_none`: 7z without compression.
- `tar_gzip`: gzipped tar.
- `pbzip2`: parallel bzip2.
- `uncompressed`: no compression.
- `null`: prompt in the dashboard.

`compression_level` (integer or null)
- Allowed: `1`, `3`, `5`, `7`, `9`.
- Higher values mean smaller packages and longer compression times.
- `null`: prompt in the dashboard.

`store_aip` (boolean or null)
- `true`: store the AIP automatically.
- `false`: do not store the AIP.
- `null`: prompt in the dashboard.

`store_aip_location` (string or null)
- `default`: use the Storage Service default AIP location.
- `location:<uuid>`: specific Storage Service location UUID.
- `null`: prompt in the dashboard.

`upload_dip` (string or null)
- `atom`: upload to AtoM.
- `archivesspace`: upload to ArchivesSpace.
- `contentdm`: upload to CONTENTdm.
- `do_not_upload`: do not upload.
- `null`: prompt in the dashboard.

`store_dip` (boolean or null)
- `true`: store the DIP automatically.
- `false`: do not store the DIP.
- `null`: prompt in the dashboard.

`store_dip_location` (string or null)
- `default`: use the Storage Service default DIP location.
- `location:<uuid>`: specific Storage Service location UUID.
- `null`: prompt in the dashboard.

## Validation notes

- Unknown keys under `processing.configs[].config` are rejected by the schema.
- `processing.configs[].source` and `processing.configs[].config` are mutually
  exclusive.
- When using `source.type: file`, the path must be absolute.

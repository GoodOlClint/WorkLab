function Test-WorkLabProxmoxStorageFeature {
    <#
    .SYNOPSIS
        Probe a Proxmox storage's capability for a specific feature
        (snapshots, linked-clones, templates) before the framework attempts
        an operation that requires it.

    .DESCRIPTION
        Proxmox storage types vary widely in what features they support.
        Operations like Checkpoint-WorkLabProviderVm don't fail until you
        actually try them ("snapshot feature is not available"), which is
        late and unhelpful. This helper inspects the storage type and
        returns $true/$false so the caller can fast-fail with a teaching
        message pointing the operator at a compatible storage type.

        Capability matrix derived from the Proxmox VE docs
        (https://pve.proxmox.com/wiki/Storage); same table holds for 8.x
        and 9.x storage types:

          Type      | Snapshots | LinkedClone | Templates
          ----------|-----------|-------------|----------
          dir       | qcow2 only| qcow2 only  | yes
          nfs       | qcow2 only| qcow2 only  | yes
          cifs      | qcow2 only| qcow2 only  | yes
          lvm       | NO        | NO          | yes
          lvmthin   | YES       | YES         | yes
          iscsi     | NO        | NO          | NO
          iscsidirect| NO       | NO          | NO
          zfspool   | YES       | YES         | yes
          zfs       | YES       | YES         | yes
          rbd       | YES       | YES         | yes
          cephfs    | YES       | YES         | yes
          btrfs     | YES       | YES         | yes
          pbs       | n/a (backup target)

        For dir/nfs/cifs we err toward NO for snapshots/clone — the disk
        format (raw vs qcow2) decides at the volume level, not the storage,
        and we don't know which the VM will use until create time. If the
        framework grows qcow2-aware behavior, revisit.

    .PARAMETER Settings
        Resolved Proxmox context settings (from Resolve-WorkLabProxmoxContext).

    .PARAMETER Session
        Active PveSession.

    .PARAMETER Storage
        Storage name to probe (e.g. 'local-lvm', 'nas-iSCSI-lvm').

    .PARAMETER Feature
        Capability to test: 'Snapshot', 'Clone', 'Template'.

    .OUTPUTS
        pscustomobject: Storage, Type, Feature, Supported, Suggestion (when
        Supported is $false, lists storage type names known to support it).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Settings,
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Storage,
        [Parameter(Mandatory)][ValidateSet('Snapshot', 'Clone', 'Template')][string]$Feature
    )

    $store = Get-PveStorage -Session $Session -Storage $Storage -ErrorAction Stop |
        Select-Object -First 1
    if (-not $store) {
        throw "Proxmox storage '$Storage' not found. Use Get-PveStorage -Session <s> to list known storages."
    }
    $type = [string]$store.Type

    # Storage-type capability matrix. Keep tight: anything unlisted defaults
    # to "we don't know" -> assume unsupported and force the operator to
    # confirm or pick a known-good storage.
    $snapshotCapable = @('lvmthin', 'zfspool', 'zfs', 'rbd', 'cephfs', 'btrfs')
    $cloneCapable    = @('lvmthin', 'zfspool', 'zfs', 'rbd', 'cephfs', 'btrfs')
    $templateCapable = @('dir', 'nfs', 'cifs', 'lvm', 'lvmthin', 'zfspool', 'zfs',
                         'rbd', 'cephfs', 'btrfs')

    $supported = switch ($Feature) {
        'Snapshot' { $type -in $snapshotCapable; break }
        'Clone'    { $type -in $cloneCapable;    break }
        'Template' { $type -in $templateCapable; break }
    }

    $suggestion = switch ($Feature) {
        'Snapshot' { $snapshotCapable -join ', '; break }
        'Clone'    { $cloneCapable    -join ', '; break }
        'Template' { $templateCapable -join ', '; break }
    }

    [pscustomobject]@{
        Storage    = $Storage
        Type       = $type
        Feature    = $Feature
        Supported  = $supported
        Suggestion = if ($supported) { $null } else { $suggestion }
    }
}

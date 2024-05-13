# Restic Backup

This is a recurring job that backs up all folders tagged with `backup: true` in `inventory\groups.yml`

## Setup

Initialize the repo before scheduling regular backup jobs 

```bash
podman run --rm --hostname restic-host -ti \
    -e RESTIC_REPOSITORY=your_repository_url \
    -e RESTIC_PASSWORD=your_restic_password \
    restic/restic init
```
## Updates

`restic self-update`

## Remove unneeded files from backups

Remove `--dry-run` to make the proposed changes

```bash
restic rewrite \
  --exclude="*/cache/*" \
  --exclude="*/alloc/*" \
  --exclude="*/vfs/*" \
  --exclude="*/vfs-images/*" \
  --exclude="*/vfs-layers/*" \
  --dry-run
```
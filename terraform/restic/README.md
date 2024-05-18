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

## Troubleshooting

Set local variables used in `backup.sh` script. Keys can be read from `/etc/restic-env`, `RESTIC_PASSWORD` from `/etc/restic-password`, `RESTIC_REPOSITORY` and `HOSTNAME` are set in `variables.tf`

```bash
export AWS_ACCESS_KEY_ID=[key]
export AWS_SECRET_ACCESS_KEY=[secretkey]
export RESTIC_REPOSITORY="s3:[repo]"
export RESTIC_PASSWORD="password"
export HOSTNAME="octant-backup"
```
Run `terraform show terraform.tfstate` and copy the script contents to a file in the Occtant cluter (e.g. `/tmp/backup.sh`). Execute to debug.